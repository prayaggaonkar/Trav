import Foundation
import SwiftUI

/// Expanded categories of pop-up events, social activities, and community meetups.
enum PopupCategory: String, Codable, Sendable, Hashable, CaseIterable {
    case sports
    case music
    case food
    case meetups
    case comedy
    case outdoor
    case art
    case nightlife
    case gaming
    case movies
    case shopping
    case general

    var displayName: String {
        switch self {
        case .sports: return "Sports & Rec"
        case .music: return "Concerts & Live Music"
        case .food: return "Food & Drink"
        case .meetups: return "Social & Games"
        case .comedy: return "Comedy & Improv"
        case .outdoor: return "Outdoor & Hiking"
        case .art: return "Arts & Crafts"
        case .nightlife: return "Nightlife & Parties"
        case .gaming: return "Gaming & Esports"
        case .movies: return "Movies & Screenings"
        case .shopping: return "Markets & Vintage"
        case .general: return "Local Happenings"
        }
    }

    var emoji: String {
        switch self {
        case .sports: return "🏓"
        case .music: return "🎵"
        case .food: return "🌮"
        case .meetups: return "🍻"
        case .comedy: return "🎙️"
        case .outdoor: return "🌲"
        case .art: return "🎨"
        case .nightlife: return "💃"
        case .gaming: return "🎮"
        case .movies: return "🍿"
        case .shopping: return "🛍️"
        case .general: return "🎉"
        }
    }

    var badgeColor: Color {
        switch self {
        case .sports: return Color.green
        case .music: return Color.purple
        case .food: return Color.orange
        case .meetups: return Color.blue
        case .comedy: return Color.yellow
        case .outdoor: return Color.teal
        case .art: return Color.pink
        case .nightlife: return Color.indigo
        case .gaming: return Color.mint
        case .movies: return Color.red
        case .shopping: return Color.brown
        case .general: return TravColors.accent
        }
    }
}

/// A local pop-up event or community meetup (pickleball tournaments, live concerts, markets, game nights, etc.).
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
        let sevenDaysOut = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        return startTime >= startOfToday && startTime <= sevenDaysOut
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
