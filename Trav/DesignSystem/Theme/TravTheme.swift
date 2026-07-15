import SwiftUI
import UIKit

enum TravColors {
    static let primary = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor.white : UIColor(red: 0.04, green: 0.04, blue: 0.043, alpha: 1.0)
    })
    static let accent = Color(red: 0.63, green: 0.28, blue: 1.0) // Space Electric Purple
    static let accentSoft = accent.opacity(0.14)
    static let surface = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor.black : UIColor.white
    })
    static let surfaceElevated = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(red: 0.11, green: 0.11, blue: 0.14, alpha: 1.0) : UIColor(red: 0.97, green: 0.97, blue: 0.973, alpha: 1.0)
    })
    static let border = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(red: 0.18, green: 0.18, blue: 0.21, alpha: 1.0) : UIColor(red: 0.91, green: 0.91, blue: 0.918, alpha: 1.0)
    })
    static let success = Color(red: 0.13, green: 0.77, blue: 0.37)
    static let error = Color(red: 0.94, green: 0.27, blue: 0.27)
    static let muted = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(red: 0.58, green: 0.58, blue: 0.61, alpha: 1.0) : UIColor(red: 0.42, green: 0.42, blue: 0.44, alpha: 1.0)
    })
    static let globeBackground = Color(red: 0.01, green: 0.01, blue: 0.03)
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
    static let tabBarBottom: CGFloat = 8
    /// Extra inset so card shadows stay inside the screen.
    static let cardShadowGutter: CGFloat = 4
}

enum TravRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum TravLayout {
    static let buttonHeight: CGFloat = 52
    static let minTouchTarget: CGFloat = 44
    static let tabBarIconSize: CGFloat = 22
    static let heroCityHeight: CGFloat = 380
    static let heroCityHeightMin: CGFloat = 280
    static let heroExperienceHeight: CGFloat = 360
    static let cardImageHeight: CGFloat = 220
    static let feedCardImageHeight: CGFloat = 220
    static let featuredCardHeight: CGFloat = 280
    static let citySearchHeight: CGFloat = 48
    static let creatorCardWidth: CGFloat = 96
    static let glassIconSize: CGFloat = 32
    static let sectionSpacing: CGFloat = TravSpacing.lg
    static let cardContentSpacing: CGFloat = TravSpacing.xs
}

enum TravIcon {
    static let sm: CGFloat = 14
    static let md: CGFloat = 20
    static let lg: CGFloat = 28
    static let xl: CGFloat = 56
}

enum TravShadow {
    static func card() -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(0.08), 10, 4)
    }

    static func elevated() -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(0.25), 20, 10)
    }
}

enum TravAnimation {
    static let quick = Animation.easeOut(duration: 0.18)
    static let press = Animation.easeOut(duration: 0.15)
    static let enter = Animation.spring(duration: 0.45, bounce: 0.18)
    static let tab = Animation.spring(duration: 0.32, bounce: 0.12)
    static let modal = Animation.spring(duration: 0.42, bounce: 0.14)
}

enum TravTypography {
    static func displayLarge() -> Font { .system(size: 34, weight: .bold, design: .rounded) }
    static func displayMedium() -> Font { .system(size: 28, weight: .bold, design: .rounded) }
    static func titleLarge() -> Font { .system(size: 22, weight: .semibold, design: .rounded) }
    static func titleMedium() -> Font { .system(size: 17, weight: .semibold, design: .rounded) }
    static func bodyLarge() -> Font { .system(size: 17, weight: .regular, design: .rounded) }
    static func bodyMedium() -> Font { .system(size: 15, weight: .regular, design: .rounded) }
    static func labelMedium() -> Font { .system(size: 13, weight: .medium, design: .rounded) }
    static func caption() -> Font { .system(size: 12, weight: .regular, design: .rounded) }
    static func tabLabel() -> Font { .system(size: 10, weight: .medium, design: .rounded) }
}

enum TravFormatters {
    static func duration(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder > 0 ? "\(hours)h \(remainder)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    static func distance(_ meters: Int) -> String {
        meters >= 1000 ? String(format: "%.1f km", Double(meters) / 1000) : "\(meters) m"
    }

    static func count(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1000 {
            let value = Double(count) / 1000
            return value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fk", value)
                : String(format: "%.1fk", value)
        }
        return "\(count)"
    }

    static func groupedCount(_ count: Int) -> String {
        count.formatted(.number.grouping(.automatic))
    }
}
