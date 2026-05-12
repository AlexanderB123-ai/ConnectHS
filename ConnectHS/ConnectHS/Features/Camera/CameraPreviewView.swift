import SwiftUI
import AVFoundation
import UIKit

/// UIKit host for `AVCaptureVideoPreviewLayer`. The only place we use UIKit per CLAUDE.md.
struct CameraPreviewView: UIViewRepresentable {

    let layer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer = layer
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        uiView.previewLayer = layer
    }

    final class PreviewHostView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                if let previewLayer {
                    previewLayer.frame = bounds
                    layer.addSublayer(previewLayer)
                }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}
