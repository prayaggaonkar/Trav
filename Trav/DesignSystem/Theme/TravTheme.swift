import SwiftUI

enum TravColors {
    static let primary = Color(red: 0.04, green: 0.04, blue: 0.043)
    static let accent = Color(red: 1.0, green: 0.36, blue: 0.21)
    static let accentSoft = accent.opacity(0.12)
    static let surface = Color.white
    static let surfaceElevated = Color(red: 0.97, green: 0.97, blue: 0.973)
    static let border = Color(red: 0.91, green: 0.91, blue: 0.918)
    static let success = Color(red: 0.13, green: 0.77, blue: 0.37)
    static let muted = Color(red: 0.42, green: 0.42, blue: 0.44)
    static let globeBackground = Color(red: 0.02, green: 0.02, blue: 0.05)
}

enum TravSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let hero: CGFloat = 64
    static let screenHorizontal: CGFloat = 20
}

enum TravRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum TravTypography {
    static func displayLarge() -> Font { .system(size: 34, weight: .bold, design: .default) }
    static func displayMedium() -> Font { .system(size: 28, weight: .bold, design: .default) }
    static func titleLarge() -> Font { .system(size: 22, weight: .semibold, design: .default) }
    static func titleMedium() -> Font { .system(size: 17, weight: .semibold, design: .default) }
    static func bodyLarge() -> Font { .system(size: 17, weight: .regular, design: .default) }
    static func bodyMedium() -> Font { .system(size: 15, weight: .regular, design: .default) }
    static func labelMedium() -> Font { .system(size: 13, weight: .medium, design: .default) }
    static func caption() -> Font { .system(size: 12, weight: .regular, design: .default) }
}
