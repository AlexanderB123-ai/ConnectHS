import AVFoundation
import UIKit
import os

/// Fallback for devices without `AVCaptureMultiCamSession` support: capture back, swap to front, capture again.
/// Gap target ≤500ms; in practice closer to 200–400ms depending on device.
final class SequentialCameraSession: NSObject, @unchecked Sendable {

    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "com.connecths.camera.seq", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.connecths.app", category: "SeqCamera")

    private var currentInput: AVCaptureDeviceInput?
    private let output = AVCapturePhotoOutput()
    private var pendingDelegates: [PhotoCaptureDelegate] = []
    /// See DualCameraSession.captureTask — same rationale: cancel the
    /// in-flight delegate-await Task on stop() so the dismissed-mid-capture
    /// path doesn't leave orphaned work waiting on AVF.
    private var captureTask: Task<Void, Never>?
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    func configure() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else { return }
                do {
                    try self.configureLocked(initial: .back)
                    let layer = AVCaptureVideoPreviewLayer(session: self.session)
                    layer.videoGravity = .resizeAspectFill
                    self.previewLayer = layer
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func configureLocked(initial position: AVCaptureDevice.Position) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraError.noCameraAvailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.noCameraAvailable }
        session.addInput(input)
        currentInput = input

        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        output.maxPhotoQualityPrioritization = .balanced
    }

    private func swap(to position: AVCaptureDevice.Position) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if let currentInput {
            session.removeInput(currentInput)
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraError.noCameraAvailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.noCameraAvailable }
        session.addInput(input)
        currentInput = input
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.captureTask?.cancel()
            self.captureTask = nil
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func capture() async throws -> (front: Data, back: Data) {
        let backData = try await captureCurrent(position: .back)
        try queueSwap(to: .front)
        let frontData = try await captureCurrent(position: .front)
        return (front: frontData, back: backData)
    }

    private func captureCurrent(position: AVCaptureDevice.Position) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            queue.async { [weak self] in
                guard let self else { return }
                let delegate = PhotoCaptureDelegate()
                self.pendingDelegates.append(delegate)
                let settings = AVCapturePhotoSettings()
                settings.flashMode = .off
                self.output.capturePhoto(with: settings, delegate: delegate)
                self.captureTask?.cancel()
                self.captureTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        let data = try await delegate.awaitData()
                        await self.dropDelegate(delegate)
                        if Task.isCancelled {
                            cont.resume(throwing: CancellationError())
                        } else {
                            cont.resume(returning: data)
                        }
                    } catch {
                        await self.dropDelegate(delegate)
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func queueSwap(to position: AVCaptureDevice.Position) throws {
        var swapError: Error?
        queue.sync { [weak self] in
            guard let self else { return }
            do { try self.swap(to: position) } catch { swapError = error }
        }
        if let swapError { throw swapError }
    }

    private func dropDelegate(_ delegate: PhotoCaptureDelegate) {
        queue.async { [weak self] in
            self?.pendingDelegates.removeAll { $0 === delegate }
        }
    }
}
