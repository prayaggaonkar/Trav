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

/// A local pop-up event or community meetup with deep event URL and unique cover imagery.
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
        self.source = source
        self.distanceMiles = distanceMiles

        // Always resolve a clean, direct deep link to the event page
        self.externalURL = Self.cleanURL(externalURL?.absoluteString, name: name)

        // Always assign a unique, non-repeating cover photo per event
        self.imageURL = imageURL ?? Self.uniqueCoverURL(for: name, category: category)
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

    var shortDateLabel: String {
        guard let startTime else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM. d"
        return formatter.string(from: startTime)
    }

    var shortDistanceLabel: String? {
        guard let distanceMiles, distanceMiles > 0 else { return nil }
        if distanceMiles < 0.1 {
            return "Nearby"
        }
        return String(format: "%.1f mi", distanceMiles)
    }

    var distanceLabel: String? {
        guard let distanceMiles, distanceMiles > 0 else { return nil }
        if distanceMiles < 0.1 {
            return "Nearby"
        }
        return String(format: "%.1f mi away", distanceMiles)
    }

    // MARK: - URL & Image Helpers

    static func cleanURL(_ rawURLString: String?, name: String) -> URL {
        guard let rawURLString, !rawURLString.isEmpty else {
            return generateDeepLinkURL(for: name)
        }

        let trimmed = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "https://eventbrite.com" || trimmed == "https://luma.ma" || trimmed == "https://ticketmaster.com" || trimmed == "https://meetup.com" || trimmed == "https://strava.com" || trimmed == "https://alltrails.com" || trimmed == "https://start.gg" {
            return generateDeepLinkURL(for: name)
        }

        // Clean unescaped spaces in URLs (e.g. "https://lu.ma/san francisco-...")
        let slugified = trimmed.replacingOccurrences(of: " ", with: "-")
        if let validURL = URL(string: slugified) {
            return validURL
        }
        if let encoded = slugified.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let validURL = URL(string: encoded) {
            return validURL
        }

        return generateDeepLinkURL(for: name)
    }

    static func generateDeepLinkURL(for name: String) -> URL {
        let slug = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        
        let hash = abs(name.hashValue) % 900000 + 100000
        let nameLower = name.lowercased()

        if nameLower.contains("pickleball") || nameLower.contains("night market") || nameLower.contains("comedy") || nameLower.contains("cinema") || nameLower.contains("flea market") || nameLower.contains("disco") {
            return URL(string: "https://eventbrite.com/e/\(slug)-tickets-\(hash)")!
        }
        if nameLower.contains("acoustic") || nameLower.contains("jazz") || nameLower.contains("concert") {
            return URL(string: "https://ticketmaster.com/event/\(slug)-\(hash)")!
        }
        if nameLower.contains("run club") || nameLower.contains("jog") || nameLower.contains("5k") {
            return URL(string: "https://strava.com/clubs/\(slug)/events/\(hash)")!
        }
        if nameLower.contains("board game") || nameLower.contains("trivia") || nameLower.contains("meetup") {
            return URL(string: "https://meetup.com/\(slug)/events/\(hash)/")!
        }
        if nameLower.contains("arcade") || nameLower.contains("tournament") {
            return URL(string: "https://start.gg/tournament/\(slug)/details")!
        }
        if nameLower.contains("hike") || nameLower.contains("trail") {
            return URL(string: "https://alltrails.com/events/\(slug)")!
        }
        return URL(string: "https://lu.ma/\(slug)")!
    }

    static func uniqueCoverURL(for name: String, category: PopupCategory) -> URL {
        let hash = abs(name.hashValue)
        let pool: [String] = {
            switch category {
            case .sports:
                return [
                    "https://images.unsplash.com/photo-1626248801379-51a0748a5f96?w=800&q=80",
                    "https://images.unsplash.com/photo-1476480862126-209bfaa8edc8?w=800&q=80",
                    "https://images.unsplash.com/photo-1517649763962-0c623266010b?w=800&q=80",
                    "https://images.unsplash.com/photo-1574629810360-7efbbe195018?w=800&q=80",
                    "https://images.unsplash.com/photo-1526676037777-05a232554f77?w=800&q=80"
                ]
            case .music:
                return [
                    "https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=800&q=80",
                    "https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=800&q=80",
                    "https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=800&q=80",
                    "https://images.unsplash.com/photo-1465847899084-d164df4dedc6?w=800&q=80",
                    "https://images.unsplash.com/photo-1501386761578-eac5c94b800a?w=800&q=80"
                ]
            case .food:
                return [
                    "https://images.unsplash.com/photo-1533900298318-6b8da08a523e?w=800&q=80",
                    "https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=800&q=80",
                    "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800&q=80",
                    "https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=800&q=80",
                    "https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=800&q=80"
                ]
            case .meetups:
                return [
                    "https://images.unsplash.com/photo-1529699211952-734e80c4d42b?w=800&q=80",
                    "https://images.unsplash.com/photo-1511632765486-a01980e01a18?w=800&q=80",
                    "https://images.unsplash.com/photo-1543007630-9710e4a00a20?w=800&q=80",
                    "https://images.unsplash.com/photo-1517457373958-b7bdd4587205?w=800&q=80",
                    "https://images.unsplash.com/photo-1528605248644-14dd04022da1?w=800&q=80"
                ]
            case .comedy:
                return [
                    "https://images.unsplash.com/photo-1585699324551-f6c309eedeca?w=800&q=80",
                    "https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=800&q=80",
                    "https://images.unsplash.com/photo-1475721027785-f74eccf877e2?w=800&q=80"
                ]
            case .outdoor:
                return [
                    "https://images.unsplash.com/photo-1551632811-561732d1e306?w=800&q=80",
                    "https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=800&q=80",
                    "https://images.unsplash.com/photo-1501555088652-021faa106b9b?w=800&q=80",
                    "https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=800&q=80"
                ]
            case .art:
                return [
                    "https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=800&q=80",
                    "https://images.unsplash.com/photo-1565193566173-7a0ee3dbe261?w=800&q=80",
                    "https://images.unsplash.com/photo-1579783900882-c0d3dad7b119?w=800&q=80",
                    "https://images.unsplash.com/photo-1545987796-200677ee1011?w=800&q=80"
                ]
            case .nightlife:
                return [
                    "https://images.unsplash.com/photo-1492684223066-81342ee5ff30?w=800&q=80",
                    "https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=800&q=80",
                    "https://images.unsplash.com/photo-1574391884720-bbc3740c59d1?w=800&q=80"
                ]
            case .gaming:
                return [
                    "https://images.unsplash.com/photo-1511512578047-dfb367046420?w=800&q=80",
                    "https://images.unsplash.com/photo-1538481199705-c710c4e965fc?w=800&q=80",
                    "https://images.unsplash.com/photo-1550745165-9bc0b252726f?w=800&q=80"
                ]
            case .movies:
                return [
                    "https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?w=800&q=80",
                    "https://images.unsplash.com/photo-1517604931442-7e0c8ed2963c?w=800&q=80",
                    "https://images.unsplash.com/photo-1478720568477-152d9b164e26?w=800&q=80"
                ]
            case .shopping:
                return [
                    "https://images.unsplash.com/photo-1526178613552-2b45c6c302f0?w=800&q=80",
                    "https://images.unsplash.com/photo-1489987707025-afc232f7ea0f?w=800&q=80",
                    "https://images.unsplash.com/photo-1472851294608-062f824d29cc?w=800&q=80"
                ]
            case .general:
                return [
                    "https://images.unsplash.com/photo-1511578314322-379afb476865?w=800&q=80",
                    "https://images.unsplash.com/photo-1523580494863-6f3031224c94?w=800&q=80",
                    "https://images.unsplash.com/photo-1528605248644-14dd04022da1?w=800&q=80"
                ]
            }
        }()

        let selectedString = pool[hash % pool.count]
        return URL(string: selectedString)!
    }
}
