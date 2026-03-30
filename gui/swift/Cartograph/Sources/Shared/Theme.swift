import SwiftUI

enum CartographTheme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
    }

    enum CodeColors {
        #if os(macOS)
        static let background = Color(nsColor: NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0))
        static let keyword = Color(nsColor: NSColor(red: 0.78, green: 0.46, blue: 0.82, alpha: 1.0))
        static let string = Color(nsColor: NSColor(red: 0.65, green: 0.82, blue: 0.46, alpha: 1.0))
        static let comment = Color(nsColor: NSColor(red: 0.45, green: 0.50, blue: 0.55, alpha: 1.0))
        static let function = Color(nsColor: NSColor(red: 0.46, green: 0.67, blue: 0.82, alpha: 1.0))
        static let type = Color(nsColor: NSColor(red: 0.82, green: 0.67, blue: 0.46, alpha: 1.0))
        static let text = Color(nsColor: NSColor(red: 0.80, green: 0.82, blue: 0.84, alpha: 1.0))
        #else
        static let background = Color(red: 0.12, green: 0.12, blue: 0.14)
        static let keyword = Color(red: 0.78, green: 0.46, blue: 0.82)
        static let string = Color(red: 0.65, green: 0.82, blue: 0.46)
        static let comment = Color(red: 0.45, green: 0.50, blue: 0.55)
        static let function = Color(red: 0.46, green: 0.67, blue: 0.82)
        static let type = Color(red: 0.82, green: 0.67, blue: 0.46)
        static let text = Color(red: 0.80, green: 0.82, blue: 0.84)
        #endif
        static let lineNumber = Color.secondary.opacity(0.6)
        static let highlight = Color.accentColor.opacity(0.15)
    }

    static let codeFont = Font.system(size: 13, design: .monospaced)
    static let codeFontSmall = Font.system(size: 11, design: .monospaced)
}
