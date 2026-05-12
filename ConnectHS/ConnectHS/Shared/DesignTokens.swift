import SwiftUI

// MARK: - Colors

extension Color {
    static let chCream = Color(hex: 0xFBF7F0)
    static let chPeach = Color(hex: 0xF5C8A8)
    static let chInk = Color(hex: 0x1A1A1A)
    static let chInkSoft = Color(hex: 0x4A4A4A)
    static let chTether = Color(hex: 0xE5734D)
    static let chSuccess = Color(hex: 0x6DA77F)
    static let chWarning = Color(hex: 0xE0A33D)
    static let chError = Color(hex: 0xC45656)
}

extension ShapeStyle where Self == Color {
    static var chCream: Color { Color.chCream }
    static var chPeach: Color { Color.chPeach }
    static var chInk: Color { Color.chInk }
    static var chInkSoft: Color { Color.chInkSoft }
    static var chTether: Color { Color.chTether }
    static var chSuccess: Color { Color.chSuccess }
    static var chWarning: Color { Color.chWarning }
    static var chError: Color { Color.chError }
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Typography

extension Font {
    static let chDisplay = Font.system(.largeTitle, design: .rounded, weight: .semibold)
    static let chHeadline = Font.system(.headline, design: .rounded, weight: .semibold)
    static let chBody = Font.system(.body, design: .default)
    static let chCaption = Font.system(.caption, design: .default)
    static let chMicro = Font.system(.caption2, design: .default)
}

// MARK: - Spacing

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Corner Radius

enum CornerRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let full: CGFloat = 9999
}
