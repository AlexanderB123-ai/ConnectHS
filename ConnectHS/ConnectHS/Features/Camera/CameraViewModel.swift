import Foundation
import SwiftUI
import AVFoundation
import UIKit
import os

@MainActor
@Observable
final class CameraViewModel {

    enum Mode: Sendable {
        case multiCam
        case sequential
    }

    enum State {
        case loading
        case permissionDenied
        case ready
        case capturing
        case previewing(front: UIImage, back: UIImage, frontData: Data, backData: Data)
        case uploading
        case success
        case failed(CameraError)
    }

    enum FrontCorner: String, Codable, Sendable {
        case topLeft, topRight, bottomLeft, bottomRight

        static let storageKey = "ch.cameraInsetCorner"
    }

    private(set) var state: State = .loading
    private(set) var mode: Mode = .multiCam
    var caption: String = "" {
        didSet { if caption.count > 140 { caption = String(caption.prefix(140)) } }
    }
    var frontCorner: FrontCorner {
        didSet { UserDefaults.standard.set(frontCorner.rawValue, forKey: FrontCorner.storageKey) }
    }

    let dualSession: DualCameraSession?
    let sequentialSession: SequentialCameraSession?

    /// Held outside the state enum so an upload that fails mid-flight can be
    /// retried without forcing the user to recapture. Cleared on retake or
    /// reset; only valid while `state` is `.previewing`, `.uploading`, or
    /// `.failed` after an upload attempt.
    private var pendingFrontData: Data?
    private var pendingBackData: Data?

    private let postService = PostService()
    private let logger = Logger(subsystem: "com.connecths.app", category: "CameraVM")

    init() {
        if DualCameraSession.isSupported {
            self.mode = .multiCam
            self.dualSession = DualCameraSession()
            self.sequentialSession = nil
        } else {
            self.mode = .sequential
            self.dualSession = nil
            self.sequentialSession = SequentialCameraSession()
        }

        let saved = UserDefaults.standard.string(forKey: FrontCorner.storageKey)
            .flatMap(FrontCorner.init(rawValue:))
        self.frontCorner = saved ?? .topRight
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            await configure()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { await configure() } else { state = .permissionDenied }
        case .denied, .restricted:
            state = .permissionDenied
        @unknown default:
            state = .permissionDenied
        }
    }

    private func configure() async {
        do {
            switch mode {
            case .multiCam:
                try await dualSession?.configure()
                dualSession?.start()
            case .sequential:
                try await sequentialSession?.configure()
                sequentialSession?.start()
            }
            state = .ready
        } catch {
            logger.error("Camera configure failed: \(error.localizedDescription)")
            state = .failed(.noCameraAvailable)
        }
    }

    func teardown() {
        dualSession?.stop()
        sequentialSession?.stop()
    }

    // MARK: - Capture

    func capture() async {
        guard case .ready = state else { return }
        state = .capturing

        do {
            let pair: (front: Data, back: Data)
            switch mode {
            case .multiCam:
                guard let dualSession else { throw CameraError.noCameraAvailable }
                pair = try await dualSession.capture()
            case .sequential:
                guard let sequentialSession else { throw CameraError.noCameraAvailable }
                pair = try await sequentialSession.capture()
            }

            guard let frontImage = UIImage(data: pair.front),
                  let backImage = UIImage(data: pair.back) else {
                throw CameraError.captureFailed
            }
            pendingFrontData = pair.front
            pendingBackData = pair.back
            state = .previewing(front: frontImage, back: backImage, frontData: pair.front, backData: pair.back)
        } catch {
            logger.error("Capture failed: \(error.localizedDescription)")
            state = .failed(.captureFailed)
        }
    }

    func retake() {
        state = .ready
        caption = ""
        pendingFrontData = nil
        pendingBackData = nil
    }

    // MARK: - Post

    func post(group: FriendGroup, user: AppUser) async {
        // Accept either an in-progress preview OR a previously-failed upload
        // attempt — `pendingFrontData/BackData` survives the .uploading →
        // .failed transition so the user can retry without recapturing.
        let frontData: Data
        let backData: Data
        switch state {
        case .previewing(_, _, let f, let b):
            frontData = f
            backData = b
        case .failed:
            guard let f = pendingFrontData, let b = pendingBackData else { return }
            frontData = f
            backData = b
        default:
            return
        }
        state = .uploading

        let postId = UUID()
        let pipeline = ImagePipeline.shared
        do {
            guard let frontImage = UIImage(data: frontData),
                  let backImage = UIImage(data: backData) else {
                throw CameraError.encodeFailed
            }
            async let frontEncoded = pipeline.encodeForUpload(frontImage)
            async let backEncoded = pipeline.encodeForUpload(backImage)
            guard let frontJpeg = await frontEncoded, let backJpeg = await backEncoded else {
                throw CameraError.encodeFailed
            }

            try await postService.uploadMoment(
                postId: postId,
                groupId: group.id,
                frontJpeg: frontJpeg,
                backJpeg: backJpeg,
                caption: caption.isEmpty ? nil : caption
            )

            // Hand the freshly-encoded JPEGs to the widget so we don't pay the
            // download round-trip for our own post. Client-side fields like
            // viewCount/reactionSummary start empty — they'll resolve on the
            // next feed reload, but the widget thumb only cares about images.
            let trimmedCaption = caption.isEmpty ? nil : caption
            let frontPath = "\(postId.uuidString)/front.jpg"
            let backPath = "\(postId.uuidString)/back.jpg"
            let feedPost = FeedPost(
                postId: postId,
                authorId: user.id,
                authorName: user.displayName,
                authorAvatar: user.avatarUrl,
                frontImagePath: frontPath,
                backImagePath: backPath,
                caption: trimmedCaption,
                postedAt: Date(),
                isLate: false,
                viewCount: 0,
                reactionSummary: nil
            )
            await WidgetSyncService.shared.refresh(
                ownPost: feedPost,
                group: group,
                frontJpeg: frontJpeg,
                backJpeg: backJpeg
            )

            pendingFrontData = nil
            pendingBackData = nil
            state = .success
        } catch {
            logger.error("Upload failed: \(error.localizedDescription)")
            if let err = error as? CameraError {
                state = .failed(err)
            } else {
                let message = (error as NSError).localizedDescription.lowercased()
                if message.contains("idx_posts_one_per_day") || message.contains("duplicate key") {
                    state = .failed(.alreadyPostedToday)
                } else {
                    state = .failed(.uploadFailed)
                }
            }
        }
    }

    // MARK: - Reset on dismiss

    func reset() {
        caption = ""
        state = .ready
    }
}
