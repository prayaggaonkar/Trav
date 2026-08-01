import SwiftUI
import UIKit
import CoreLocation

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
    static let tabBarBottom: CGFloat = 0
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
    static let tabBarAvatarSize: CGFloat = 24
    static let heroCityHeight: CGFloat = 380
    static let heroCityHeightMin: CGFloat = 280
    static let heroExperienceHeight: CGFloat = 414 // 360 * 1.15
    static let cardImageHeight: CGFloat = 140
    static let feedCardImageHeight: CGFloat = 140
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
    /// Small uppercase section kicker, pair with `.tracking(2.5)`.
    static func overline() -> Font { .system(size: 11, weight: .bold, design: .rounded) }
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

// Utility function to convert raw emojis or categories into professional SF Symbols
public func sfSymbolForEmojiOrCategory(_ value: String) -> String {
    let lower = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Check if it's already an SF Symbol (contains no emojis and has dot/alphabetic format)
    if lower.contains(".") || ["bag", "book", "tree", "eye", "map"].contains(lower) {
        return lower
    }
    
    // Check for raw emojis
    if lower.contains("☕") { return "cup.and.saucer.fill" }
    if lower.contains("🍻") || lower.contains("🍷") || lower.contains("🍺") || lower.contains("🍹") || lower.contains("🌙") { return "wineglass.fill" }
    if lower.contains("🌅") || lower.contains("🌄") || lower.contains("☀️") { return "sun.max.fill" }
    if lower.contains("🛍️") || lower.contains("🧥") || lower.contains("🛒") { return "bag.fill" }
    if lower.contains("🎨") || lower.contains("🖼️") || lower.contains("🎭") { return "paintpalette.fill" }
    if lower.contains("🍲") || lower.contains("🥞") || lower.contains("🍳") || lower.contains("🍽️") || lower.contains("🍕") || lower.contains("🍔") || lower.contains("🌮") { return "fork.knife" }
    if lower.contains("🥾") || lower.contains("🌳") || lower.contains("🌲") { return "figure.hiking" }
    if lower.contains("📚") { return "book.fill" }
    
    // Fallback to keyword-based category matching
    if lower.contains("bar") || lower.contains("pub") || lower.contains("drink") || lower.contains("lounge") || lower.contains("nightlife") {
        return "wineglass.fill"
    }
    if lower.contains("coffee") || lower.contains("cafe") || lower.contains("brew") || lower.contains("espresso") {
        return "cup.and.saucer.fill"
    }
    if lower.contains("shop") || lower.contains("store") || lower.contains("market") || lower.contains("vintage") {
        return "bag.fill"
    }
    if lower.contains("hike") || lower.contains("trail") || lower.contains("mountain") || lower.contains("climb") {
        return "figure.hiking"
    }
    if lower.contains("park") || lower.contains("garden") || lower.contains("lawn") || lower.contains("field") {
        return "tree.fill"
    }
    if lower.contains("view") || lower.contains("sunset") || lower.contains("scenic") || lower.contains("vista") {
        return "sun.max.fill"
    }
    if lower.contains("museum") || lower.contains("art") || lower.contains("gallery") {
        return "paintpalette.fill"
    }
    if lower.contains("book") || lower.contains("read") || lower.contains("library") {
        return "book.fill"
    }
    return "mappin.and.ellipse"
}

// MARK: - Route Travel Calculation (Walking vs Driving & Travel Time)

public struct RouteTravelInfo: Sendable, Equatable {
    public let walkingDistanceMeters: Double
    public let drivingDistanceMeters: Double
    public let walkingMinutes: Int
    public let drivingMinutes: Int

    public var totalDistanceMeters: Double {
        walkingDistanceMeters + drivingDistanceMeters
    }

    public var estimatedTravelTimeMinutes: Int {
        let total = walkingMinutes + drivingMinutes
        return total > 0 ? total : 0
    }

    /// True when every segment is driving (no walking).
    public var isDriving: Bool {
        drivingMinutes > 0 && walkingMinutes == 0
    }

    public var isMixed: Bool {
        walkingMinutes > 0 && drivingMinutes > 0
    }

    public var hasWalking: Bool { walkingMinutes > 0 }
    public var hasDriving: Bool { drivingMinutes > 0 }

    public var modeName: String {
        switch (hasWalking, hasDriving) {
        case (true, true): return "Walking & Driving"
        case (false, true): return "Driving"
        default: return "Walking"
        }
    }

    public var iconName: String {
        switch (hasWalking, hasDriving) {
        case (true, true): return "arrow.triangle.swap"
        case (false, true): return "car.fill"
        default: return "figure.walk"
        }
    }

    public var formattedTravelTime: String {
        Self.formatMinutes(max(1, estimatedTravelTimeMinutes))
    }

    public var timeAndModeLabel: String {
        switch (hasWalking, hasDriving) {
        case (true, true):
            return "\(Self.formatMinutes(walkingMinutes)) walk · \(Self.formatMinutes(drivingMinutes)) drive"
        case (false, true):
            return "\(Self.formatMinutes(max(1, drivingMinutes))) drive"
        default:
            return "\(Self.formatMinutes(max(1, walkingMinutes))) walk"
        }
    }

    public static func formatMinutes(_ mins: Int) -> String {
        let value = max(1, mins)
        if value >= 60 {
            let hours = value / 60
            let remainder = value % 60
            return remainder > 0 ? "\(hours)h \(remainder)m" : "\(hours)h"
        }
        return "\(value) min"
    }
}

public enum RouteTravelCalculator {
    /// Consecutive stops over this distance use driving; otherwise walking.
    public static let drivingThresholdMeters: Double = 1609.34 // 1 mile

    public static func isDrivingSegment(distanceMeters: Double) -> Bool {
        distanceMeters > drivingThresholdMeters
    }

    public static func segmentDistanceMeters(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> Double {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }

    public static func calculate(for coordinates: [CLLocationCoordinate2D]) -> RouteTravelInfo {
        guard coordinates.count >= 2 else {
            return RouteTravelInfo(
                walkingDistanceMeters: 0,
                drivingDistanceMeters: 0,
                walkingMinutes: 0,
                drivingMinutes: 0
            )
        }

        var walkingDistance: Double = 0
        var drivingDistance: Double = 0
        var walkingMinutesAcc: Double = 0
        var drivingMinutesAcc: Double = 0

        for i in 0..<(coordinates.count - 1) {
            let dist = segmentDistanceMeters(from: coordinates[i], to: coordinates[i + 1])
            if isDrivingSegment(distanceMeters: dist) {
                drivingDistance += dist
                // ~30 km/h (500 m/min) + short buffer for traffic/parking per hop
                drivingMinutesAcc += dist / 500.0 + 1.5
            } else {
                walkingDistance += dist
                // ~4.8 km/h (80 m/min)
                walkingMinutesAcc += dist / 80.0
            }
        }

        return RouteTravelInfo(
            walkingDistanceMeters: walkingDistance,
            drivingDistanceMeters: drivingDistance,
            walkingMinutes: Int(round(walkingMinutesAcc)),
            drivingMinutes: Int(round(drivingMinutesAcc))
        )
    }
}

