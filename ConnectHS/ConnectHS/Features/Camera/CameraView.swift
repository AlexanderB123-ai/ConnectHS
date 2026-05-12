import SwiftUI
import AVFoundation

struct CameraView: View {

    let group: FriendGroup
    let user: AppUser
    let onDismiss: () -> Void

    @State private var viewModel = CameraViewModel()
    @State private var insetDragOffset: CGSize = .zero
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.state {
            case .loading:
                liveCaptureUI
                loadingOverlay
            case .ready, .capturing:
                liveCaptureUI
            case .permissionDenied:
                CameraPermissionView(onDismiss: closeFlow)
            case .previewing(let front, let back, _, _):
                CapturePreviewView(
                    front: front,
                    back: back,
                    caption: $viewModel.caption,
                    onRetake: { viewModel.retake() },
                    onPost: { Task { await viewModel.post(group: group, user: user) } }
                )
            case .uploading:
                uploadingOverlay
            case .success:
                Color.clear.onAppear {
                    Task {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        closeFlow()
                    }
                }
            case .failed(let err):
                failureOverlay(err)
            }
        }
        .task { await viewModel.bootstrap() }
        .onDisappear { viewModel.teardown() }
    }

    // MARK: - Live capture UI

    private var liveCaptureUI: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                backPreview
                    .ignoresSafeArea()

                frontInset(in: proxy.size)

                topBar

                VStack {
                    Spacer()
                    shutter
                        .padding(.bottom, Spacing.xl)
                }

                if viewModel.mode == .sequential {
                    sequentialIndicator
                        .padding(.top, Spacing.xl + Spacing.lg)
                        .padding(.leading, Spacing.md)
                }
            }
        }
    }

    @ViewBuilder
    private var backPreview: some View {
        if let layer = viewModel.dualSession?.backPreviewLayer
                    ?? viewModel.sequentialSession?.previewLayer {
            CameraPreviewView(layer: layer)
        } else {
            Color.black
        }
    }

    @ViewBuilder
    private func frontInset(in size: CGSize) -> some View {
        if viewModel.mode == .multiCam,
           let layer = viewModel.dualSession?.frontPreviewLayer {
            CameraPreviewView(layer: layer)
                .frame(width: 120, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(Color.white.opacity(0.6), lineWidth: 2)
                )
                .position(insetPosition(in: size))
                .offset(insetDragOffset)
                .gesture(insetDrag(in: size))
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: viewModel.frontCorner)
        }
    }

    private func insetPosition(in size: CGSize) -> CGPoint {
        let m: CGFloat = Spacing.lg + 60
        switch viewModel.frontCorner {
        case .topLeft:     return CGPoint(x: m, y: m + Spacing.xl)
        case .topRight:    return CGPoint(x: size.width - m, y: m + Spacing.xl)
        case .bottomLeft:  return CGPoint(x: m, y: size.height - m - Spacing.xxl)
        case .bottomRight: return CGPoint(x: size.width - m, y: size.height - m - Spacing.xxl)
        }
    }

    private func insetDrag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                insetDragOffset = value.translation
            }
            .onEnded { value in
                // Final touch location = current corner anchor + drag translation.
                // Snap to the quadrant the drop landed in, then animate the
                // offset back to zero so the inset glides to the new anchor.
                let anchor = insetPosition(in: size)
                let final = CGPoint(
                    x: anchor.x + value.translation.width,
                    y: anchor.y + value.translation.height
                )
                let isTop = final.y < size.height / 2
                let isLeft = final.x < size.width / 2
                let target: CameraViewModel.FrontCorner = switch (isTop, isLeft) {
                case (true, true):   .topLeft
                case (true, false):  .topRight
                case (false, true):  .bottomLeft
                case (false, false): .bottomRight
                }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    viewModel.frontCorner = target
                    insetDragOffset = .zero
                }
            }
    }

    private var topBar: some View {
        HStack {
            Button { closeFlow() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.black.opacity(0.4)))
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.lg)
    }

    private var shutter: some View {
        Button {
            Task { await viewModel.capture() }
        } label: {
            ZStack {
                Circle().fill(.white).frame(width: 76, height: 76)
                Circle().stroke(.white, lineWidth: 4).frame(width: 90, height: 90)
                if case .capturing = viewModel.state {
                    ProgressView().tint(.chTether)
                }
            }
        }
        .disabled({
            if case .capturing = viewModel.state { return true }
            if case .ready = viewModel.state { return false }
            return true
        }())
        .accessibilityLabel(Text("camera.shutter.label"))
        .accessibilityHint(Text("camera.shutter.hint"))
    }

    private var sequentialIndicator: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "info.circle.fill")
            Text("camera.sequentialIndicator")
                .font(.chMicro)
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Capsule().fill(.black.opacity(0.4)))
    }

    // MARK: - Upload / failure

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: Spacing.sm) {
                ProgressView().tint(.white).scaleEffect(1.4)
                Text("camera.loading")
                    .font(.chCaption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var uploadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: Spacing.md) {
                ProgressView().tint(.white).scaleEffect(1.5)
                Text("camera.uploading").foregroundStyle(.white).font(.chHeadline)
            }
        }
    }

    private func failureOverlay(_ err: CameraError) -> some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: Spacing.md) {
                Text(err.errorDescription ?? String(localized: "camera.error.generic"))
                    .foregroundStyle(.white)
                    .font(.chHeadline)
                HStack(spacing: Spacing.md) {
                    Button { closeFlow() } label: {
                        Text("camera.failure.close")
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    if isRetryableUploadFailure(err) {
                        Button {
                            Task { await viewModel.post(group: group, user: user) }
                        } label: {
                            Text("camera.failure.retryUpload")
                        }
                        .foregroundStyle(.chTether)
                        .font(.chHeadline)
                    } else {
                        Button { viewModel.reset() } label: {
                            Text("camera.failure.retry")
                        }
                        .foregroundStyle(.chTether)
                        .font(.chHeadline)
                    }
                }
            }
            .padding(Spacing.lg)
        }
    }

    /// Upload-side failures (network, encode, generic upload error) can be
    /// retried against the same captured bytes. Capture-side failures must
    /// recapture, and "already posted today" can't be retried at all — the
    /// X close affordance is the only recovery for those.
    private func isRetryableUploadFailure(_ err: CameraError) -> Bool {
        switch err {
        case .uploadFailed, .encodeFailed:
            return true
        case .captureFailed, .noCameraAvailable, .permissionDenied,
             .alreadyPostedToday, .noActiveGroup:
            return false
        }
    }

    private func closeFlow() {
        viewModel.teardown()
        onDismiss()
        dismiss()
    }
}

#Preview {
    CameraView(
        group: FriendGroup(
            id: UUID(),
            name: "the boys",
            emoji: "🌊",
            createdBy: UUID(),
            memberLimit: 25,
            createdAt: Date(),
            updatedAt: Date()
        ),
        user: AppUser(
            id: UUID(),
            displayName: "Alex",
            authMethod: .phone,
            timezone: "America/New_York",
            isAgeVerified: true,
            isBlocked: false,
            createdAt: Date(),
            updatedAt: Date()
        ),
        onDismiss: {}
    )
}
