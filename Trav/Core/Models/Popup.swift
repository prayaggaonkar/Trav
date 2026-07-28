import Foundation
import SwiftUI

/// Categories of pop-up events and local meetups.
enum PopupCategory: String, Codable, Sendable, Hashable, CaseIterable {
    case sports
    case music
    case meetups
    case food
    case art
    case general

    var displayName: String {
        switch self {
        case .sports: return "Sports & Rec"
        case .music: return "Live Music"
        case .meetups: return "Social & Games"
        case .food: return "Food & Drink"
        case .art: return "Arts & Culture"
        case .general: return "Meetups & Popups"
        }
    }

    var emoji: String {
        switch self {
        case .sports: return "🏓"
        case .music: return "🎵"
        case .meetups: return "🍻"
        case .food: return "🌮"
        case .art: return "🎨"
        case .general: return "🎉"
        }
    }

    var badgeColor: Color {
        switch self {
        case .sports: return Color.green
        case .music: return Color.purple
        case .meetups: return Color.orange
        case .food: return Color.red
        case .art: return Color.pink
        case .general: return TravColors.accent
        }
    }
}

/// A local pop-up event or community meetup (sports tournaments, live concerts, markets, game nights, etc.).
struct Popup: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var address: String
    var city: String?
    var latitude: Double?
    var longitude: Double?
    var category: PopupCategory
    var description: String?
    var startTime: Date?
    var endTime: Date?
    var externalURL: URL?
    var imageURL: URL?
    var source: String?
    var distanceMiles: Double?

    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        city: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        category: PopupCategory = .general,
        description: String? = nil,
        startTime: Date? = nil,
        endTime: Date? = nil,
        externalURL: URL? = nil,
        imageURL: URL? = nil,
        source: String? = nil,
        distanceMiles: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.description = description
        self.startTime = startTime
        self.endTime = endTime
        self.externalURL = externalURL
        self.imageURL = imageURL
        self.source = source
        self.distanceMiles = distanceMiles
    }

    var isUpcomingSoon: Bool {
        guard let startTime else { return false }
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let threeDaysOut = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        return startTime >= startOfToday && startTime <= threeDaysOut
    }

    var startTimeLabel: String {
        guard let startTime else { return "Date/Time TBA" }
        if Calendar.current.isDateInToday(startTime) {
            return "Today at " + DateFormatter.localizedString(from: startTime, dateStyle: .none, timeStyle: .short)
        }
        if Calendar.current.isDateInTomorrow(startTime) {
            return "Tomorrow at " + DateFormatter.localizedString(from: startTime, dateStyle: .none, timeStyle: .short)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }

    var distanceLabel: String? {
        guard let distanceMiles, distanceMiles > 0 else { return nil }
        if distanceMiles < 0.1 {
            return "Nearby"
        }
        return String(format: "%.1f mi away", distanceMiles)
    }
}
