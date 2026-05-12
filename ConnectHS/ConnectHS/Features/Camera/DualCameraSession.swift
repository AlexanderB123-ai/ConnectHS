import AVFoundation
import UIKit
import os

/// True simultaneous front + back capture using `AVCaptureMultiCamSession`.
/// Requires A12+ (iPhone XS / XR / 11 and newer).
final class DualCameraSession: NSObject, @unchecked Sendable {

    let session = AVCaptureMultiCamSession()

    private let queue = DispatchQueue(label: "com.connecths.camera.dual", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.connecths.app", category: "DualCamera")

    private var backInput: AVCaptureDeviceInput?
    private var frontInput: AVCaptureDeviceInput?
    private let backOutput = AVCapturePhotoOutput()
    private let frontOutput = AVCapturePhotoOutput()

    private(set) var backPreviewLayer: AVCaptureVideoPreviewLayer?
    private(set) var frontPreviewLayer: AVCaptureVideoPreviewLayer?

    private var pendingDelegates: [PhotoCaptureDelegate] = []

    static var isSupported: Bool { AVCaptureMultiCamSession.isMultiCamSupported }

    // MARK: - Configuration

    func configure() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else { return }
                do {
                    try self.configureLocked()
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func configureLocked() throws {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            throw CameraError.noCameraAvailable
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw CameraError.noCameraAvailable
        }

        let backIn = try AVCaptureDeviceInput(device: back)
        let frontIn = try AVCaptureDeviceInput(device: front)

        guard session.canAddInput(backIn), session.canAddInput(frontIn) else {
            throw CameraError.noCameraAvailable
        }
        session.addInputWithNoConnections(backIn)
        session.addInputWithNoConnections(frontIn)
        self.backInput = backIn
        self.frontInput = frontIn

        guard session.canAddOutput(backOutput), session.canAddOutput(frontOutput) else {
            throw CameraError.noCameraAvailable
        }
        session.addOutputWithNoConnections(backOutput)
        session.addOutputWithNoConnections(frontOutput)

        let backPort = backIn.ports(for: .video, sourceDeviceType: back.deviceType, sourceDevicePosition: .back).first
        let frontPort = frontIn.ports(for: .video, sourceDeviceType: front.deviceType, sourceDevicePosition: .front).first

        guard let backPort, let frontPort else {
            throw CameraError.noCameraAvailable
        }

        let backConnection = AVCaptureConnection(inputPorts: [backPort], output: backOutput)
        let frontConnection = AVCaptureConnection(inputPorts: [frontPort], output: frontOutput)

        guard session.canAddConnection(backConnection), session.canAddConnection(frontConnection) else {
            throw CameraError.noCameraAvailable
        }
        session.addConnection(backConnection)
        session.addConnection(frontConnection)

        backOutput.maxPhotoQualityPrioritization = .balanced
        frontOutput.maxPhotoQualityPrioritization = .balanced

        // Build preview layers and connect them while the session is still in
        // configuration. Doing this during configure() keeps SwiftUI body re-renders
        // from accidentally adding new connections each tick.
        if let layer = makePreviewLayer(input: backInput, position: .back) {
            backPreviewLayer = layer
        }
        if let layer = makePreviewLayer(input: frontInput, position: .front) {
            frontPreviewLayer = layer
        }
    }

    private func makePreviewLayer(input: AVCaptureDeviceInput?, position: AVCaptureDevice.Position) -> AVCaptureVideoPreviewLayer? {
        guard let input,
              let port = input.ports(for: .video, sourceDeviceType: input.device.deviceType, sourceDevicePosition: position).first else {
            return nil
        }
        let layer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        layer.videoGravity = .resizeAspectFill
        let connection = AVCaptureConnection(inputPort: port, videoPreviewLayer: layer)
        guard session.canAddConnection(connection) else { return nil }
        session.addConnection(connection)
        return layer
    }

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: - Capture

    /// Triggers both photo outputs back-to-back on the session queue.
    /// AVF doesn't guarantee identical timestamps, but in practice the gap is <30ms on supported hardware.
    func capture() async throws -> (front: Data, back: Data) {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Data, Data), Error>) in
            queue.async { [weak self] in
                guard let self else { return }

                let backDelegate = PhotoCaptureDelegate()
                let frontDelegate = PhotoCaptureDelegate()
                self.pendingDelegates.append(backDelegate)
                self.pendingDelegates.append(frontDelegate)

                let backSettings = AVCapturePhotoSettings()
                let frontSettings = AVCapturePhotoSettings()
                backSettings.flashMode = .off
                frontSettings.flashMode = .off

                self.backOutput.capturePhoto(with: backSettings, delegate: backDelegate)
                self.frontOutput.capturePhoto(with: frontSettings, delegate: frontDelegate)

                Task {
                    do {
                        async let back = backDelegate.awaitData()
                        async let front = frontDelegate.awaitData()
                        let pair = try await (front: front, back: back)
                        await self.dropDelegates([backDelegate, frontDelegate])
                        cont.resume(returning: pair)
                    } catch {
                        await self.dropDelegates([backDelegate, frontDelegate])
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func dropDelegates(_ delegates: [PhotoCaptureDelegate]) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingDelegates.removeAll { d in delegates.contains(where: { $0 === d }) }
        }
    }
}

// MARK: - Photo capture delegate

nonisolated final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {

    private var continuation: CheckedContinuation<Data, Error>?

    func awaitData() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            continuation?.resume(throwing: CameraError.captureFailed)
            continuation = nil
            return
        }
        continuation?.resume(returning: data)
        continuation = nil
    }
}
