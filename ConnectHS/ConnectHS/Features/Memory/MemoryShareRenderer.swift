import UIKit
import os

/// Builds a 1080×1920 portrait share image for a memory: blurred back-camera
/// background, full back as foreground, front-camera inset top-right, and a
/// "X year ago today · made on connecths" footer. Returns nil if either image
/// can't be downloaded — the caller should disable the share affordance in
/// that case rather than render half a card.
enum MemoryShareRenderer {

    private static let logger = Logger(subsystem: "com.connecths.app", category: "MemoryShare")
    private static let canvas = CGSize(width: 1080, height: 1920)

    static func render(memory: MemoryPost) async -> UIImage? {
        async let back = fetch(path: memory.backImagePath)
        async let front = fetch(path: memory.frontImagePath)
        guard let backImage = await back, let frontImage = await front else {
            logger.error("Share render aborted: image fetch returned nil")
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)

        return renderer.image { ctx in
            // Cream backdrop in case the back image has transparency or fails to fill.
            UIColor(red: 0xFB / 255.0, green: 0xF7 / 255.0, blue: 0xF0 / 255.0, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: canvas))

            drawAspectFill(image: backImage, in: CGRect(origin: .zero, size: canvas))

            // Front inset — top-right, 28pt margin, 320×426 (3:4)
            let insetSize = CGSize(width: 320, height: 426)
            let insetRect = CGRect(
                x: canvas.width - insetSize.width - 56,
                y: 96,
                width: insetSize.width,
                height: insetSize.height
            )
            let insetPath = UIBezierPath(roundedRect: insetRect, cornerRadius: 36)
            ctx.cgContext.saveGState()
            insetPath.addClip()
            drawAspectFill(image: frontImage, in: insetRect)
            ctx.cgContext.restoreGState()
            UIColor.white.withAlphaComponent(0.85).setStroke()
            insetPath.lineWidth = 6
            insetPath.stroke()

            // Footer text on a black gradient so it's readable against any photo.
            drawFooter(memory: memory, in: ctx.cgContext)
        }
    }

    // MARK: - Helpers

    private static func fetch(path: String) async -> UIImage? {
        do {
            let url = try await SignedURLCache.shared.url(for: path)
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            logger.error("Image fetch for \(path, privacy: .public) failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func drawAspectFill(image: UIImage, in rect: CGRect) {
        let imageRatio = image.size.width / image.size.height
        let rectRatio = rect.width / rect.height
        var drawRect = rect
        if imageRatio > rectRatio {
            // Image wider than rect — scale to height, crop sides.
            let scaledWidth = rect.height * imageRatio
            drawRect = CGRect(
                x: rect.minX - (scaledWidth - rect.width) / 2,
                y: rect.minY,
                width: scaledWidth,
                height: rect.height
            )
        } else {
            // Image taller — scale to width, crop top/bottom.
            let scaledHeight = rect.width / imageRatio
            drawRect = CGRect(
                x: rect.minX,
                y: rect.minY - (scaledHeight - rect.height) / 2,
                width: rect.width,
                height: scaledHeight
            )
        }
        image.draw(in: drawRect)
    }

    private static func drawFooter(memory: MemoryPost, in ctx: CGContext) {
        let footerHeight: CGFloat = 360
        let footerRect = CGRect(
            x: 0,
            y: canvas.height - footerHeight,
            width: canvas.width,
            height: footerHeight
        )
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.78).cgColor
            ] as CFArray,
            locations: [0.0, 1.0]
        ) {
            ctx.saveGState()
            ctx.addRect(footerRect)
            ctx.clip()
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: footerRect.minY),
                end: CGPoint(x: 0, y: footerRect.maxY),
                options: []
            )
            ctx.restoreGState()
        }

        let yearsLine: String = {
            if memory.yearsAgo == 1 {
                return String(localized: "memory.years.one")
            }
            return String(localized: "memory.years.many \(memory.yearsAgo)")
        }()
        let attribution = String(localized: "memory.share.attribution")
        let captionLine = memory.caption?.trimmingCharacters(in: .whitespacesAndNewlines)

        let yearsAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 64, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        let captionAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 44, weight: .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(0.92)
        ]
        let attribAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 32, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.65)
        ]

        let baseX: CGFloat = 80
        var cursorY = canvas.height - 64 - 40 // attribution baseline first, drawing bottom-up

        (attribution as NSString).draw(at: CGPoint(x: baseX, y: cursorY), withAttributes: attribAttrs)
        cursorY -= 24

        if let captionLine, !captionLine.isEmpty {
            cursorY -= 56
            (captionLine as NSString).draw(at: CGPoint(x: baseX, y: cursorY), withAttributes: captionAttrs)
        }

        cursorY -= 84
        (yearsLine as NSString).draw(at: CGPoint(x: baseX, y: cursorY), withAttributes: yearsAttrs)
    }
}
