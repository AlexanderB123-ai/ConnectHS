import UIKit
import CoreImage
import os

actor ImagePipeline {

    static let shared = ImagePipeline()

    private let logger = Logger(subsystem: "com.connecths.app", category: "ImagePipeline")
    private let context = CIContext()

    /// JPEG-encode a captured photo at quality 0.8, downscaled so the long edge is ≤1080px.
    /// Returns nil if encoding fails (callers should treat that as a recoverable upload error).
    func encodeForUpload(_ image: UIImage) -> Data? {
        encode(image, maxLongEdge: 1080, quality: 0.8)
    }

    /// Decode raw image bytes, downscale, and re-encode as JPEG. Used by
    /// `WidgetSyncService` to produce 256×256 thumbs from already-uploaded
    /// post images — keeps the resize/encode logic in one place rather than
    /// duplicated across services.
    func encodeThumb(from data: Data, maxLongEdge: CGFloat, quality: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return encode(image, maxLongEdge: maxLongEdge, quality: quality)
    }

    func decode(_ data: Data) -> UIImage? {
        UIImage(data: data)
    }

    private func encode(_ image: UIImage, maxLongEdge: CGFloat, quality: CGFloat) -> Data? {
        // PRIVACY: re-encoding through `UIGraphicsImageRenderer` (in
        // `downscale`) + `UIImage.jpegData` strips EXIF — including GPS
        // coordinates baked in by Camera.app. We rely on this: the
        // closed-graph model is for friends, but a leaked image with
        // home-address EXIF would be a hard breach. Any future refactor
        // that switches to `CGImageDestination` with kCGImagePropertyExifDictionary
        // or to a metadata-preserving Core Image path MUST keep this
        // guarantee.
        let resized = downscale(image, maxLongEdge: maxLongEdge)
        return resized.jpegData(compressionQuality: quality)
    }

    private func downscale(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return image }

        let scale = maxLongEdge / longEdge
        let target = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
