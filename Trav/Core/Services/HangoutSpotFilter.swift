import Foundation
import MapKit
import CoreLocation
import SwiftUI

/// Hangout / travel destination categories shown and searchable in Trav.
/// Grocery stores, utilities, and broad admin areas are intentionally excluded.
enum SpotCategory: String, CaseIterable, Codable, Sendable {
    case foodAndDrink = "Food & Drink"
    case entertainment = "Entertainment"
    case arts = "Arts"
    case nature = "Nature"
    case landmarks = "Landmarks"
    case shopping = "Shopping"
    case sportsAndRecreation = "Sports & Recreation"
    case wellness = "Wellness"
    case family = "Family"
    case adventure = "Adventure"
    case nightlife = "Nightlife"
    case events = "Events"

    var emoji: String {
        switch self {
        case .foodAndDrink: return "🍽️"
        case .entertainment: return "🎮"
        case .arts: return "🎨"
        case .nature: return "🥾"
        case .landmarks: return "🏛"
        case .shopping: return "🛍️"
        case .sportsAndRecreation: return "🎾"
        case .wellness: return "🧘"
        case .family: return "🦁"
        case .adventure: return "🪂"
        case .nightlife: return "🍸"
        case .events: return "🎪"
        }
    }

    var badgeColor: Color {
        switch self {
        case .foodAndDrink: return Color(red: 0.95, green: 0.45, blue: 0.25)
        case .entertainment: return Color(red: 0.55, green: 0.35, blue: 0.95)
        case .arts: return Color(red: 0.85, green: 0.35, blue: 0.55)
        case .nature: return Color(red: 0.1, green: 0.75, blue: 0.45)
        case .landmarks: return Color(red: 0.95, green: 0.65, blue: 0.1)
        case .shopping: return Color(red: 0.2, green: 0.55, blue: 0.95)
        case .sportsAndRecreation: return Color(red: 0.15, green: 0.7, blue: 0.85)
        case .wellness: return Color(red: 0.45, green: 0.75, blue: 0.55)
        case .family: return Color(red: 0.95, green: 0.55, blue: 0.2)
        case .adventure: return Color(red: 0.9, green: 0.3, blue: 0.35)
        case .nightlife: return Color(red: 0.45, green: 0.25, blue: 0.75)
        case .events: return Color(red: 0.95, green: 0.4, blue: 0.55)
        }
    }

    /// Backward-compatible inference used by call sites that only have strings.
    static func infer(title: String, subtitle: String) -> SpotCategory {
        HangoutSpotFilter.category(title: title, subtitle: subtitle)
    }

    /// Maps legacy stored category strings onto the current taxonomy.
    init?(legacyRawValue value: String) {
        if let exact = SpotCategory(rawValue: value) {
            self = exact
            return
        }
        switch value {
        case "Arts & Culture": self = .arts
        case "Nature & Outdoors": self = .nature
        case "Landmarks & Sightseeing": self = .landmarks
        case "Family Attractions": self = .family
        case "Events & Festivals": self = .events
        case "Public Spaces": self = .landmarks
        case "Unique Attractions": self = .entertainment
        default: return nil
        }
    }
}

/// Shared eligibility rules for MapKit places that can appear in spot search / rating.
enum HangoutSpotFilter {

    // MARK: - MapKit POI allow / deny

    /// Categories that map to hangout & travel spots.
    static var allowedPOICategories: Set<MKPointOfInterestCategory> {
        var cats: Set<MKPointOfInterestCategory> = [
            // Food & Drink
            .restaurant, .cafe, .bakery, .brewery, .winery,
            // Entertainment / Arts / Nightlife
            .nightlife, .theater, .movieTheater,
            // Nature
            .park, .nationalPark, .beach, .campground, .marina,
            // Shopping (grocers filtered via keywords / foodMarket deny)
            .store,
            // Sports & Recreation / Wellness-adjacent
            .stadium, .fitnessCenter,
            // Family / Entertainment
            .zoo, .aquarium, .amusementPark,
            // Arts / Landmarks (campuses → Landmarks)
            .museum, .library, .university
        ]

        if #available(iOS 18.0, *) {
            cats.formUnion([
                .bowling, .miniGolf, .goKart, .musicVenue, .distillery,
                .hiking, .landmark, .nationalMonument, .castle, .fortress,
                .golf, .tennis, .skating, .skatePark, .rockClimbing,
                .baseball, .basketball, .soccer, .volleyball, .swimming, .skiing,
                .spa, .kayaking, .surfing, .fishing,
                .fairground, .conventionCenter, .planetarium, .rvPark
            ])
        }
        return cats
    }

    /// Utility / errand POIs that are never hangout destinations.
    static var excludedPOICategories: Set<MKPointOfInterestCategory> {
        var cats: Set<MKPointOfInterestCategory> = [
            .foodMarket, .pharmacy, .gasStation, .bank, .atm,
            .hospital, .parking, .laundry, .postOffice, .school,
            .fireStation, .police, .restroom, .carRental,
            .airport, .publicTransport, .hotel, .evCharger
        ]
        if #available(iOS 18.0, *) {
            cats.formUnion([.mailbox, .animalService, .automotiveRepair])
        }
        return cats
    }

    /// Inclusive filter for `MKLocalSearch.Request` / completers.
    static var pointOfInterestFilter: MKPointOfInterestFilter {
        MKPointOfInterestFilter(including: Array(allowedPOICategories))
    }

    // MARK: - Keyword lists

    private static let excludedKeywords: [String] = [
        "grocery", "supermarket", "food market",
        "safeway", "whole foods", "trader joe", "costco", "walmart", "target",
        "aldi", "kroger", "publix", "ralphs", "vons", "food lion", "wegmans",
        "cvs", "walgreens", "rite aid", "7-eleven", "7 eleven", "convenience store",
        "dollar store", "dollar tree", "family dollar",
        "gas station", "parking garage", "parking lot", "car wash",
        "hospital", "urgent care", "clinic", "pharmacy",
        "post office", "laundromat", "dry cleaner", "self storage",
        "elementary school", "middle school", "high school", "police station",
        "fire station", "dmv", "auto repair", "oil change"
    ]

    /// Positive signals used when MapKit omits `pointOfInterestCategory`.
    private static let hangoutKeywords: [String] = [
        "restaurant", "cafe", "café", "coffee", "bakery", "dessert", "boba",
        "bar", "brewery", "winery", "rooftop", "food truck", "bistro", "eatery",
        "arcade", "escape room", "laser tag", "bowling", "mini golf", "karaoke",
        "billiard", "pool hall", "axe throwing", "go-kart", "go kart", "casino",
        "theater", "theatre", "cinema", "movie", "theme park", "ferris",
        "museum", "gallery", "comedy", "concert", "opera", "exhibit", "public art",
        "studio tour",
        "park", "beach", "lake", "river", "trail", "hike", "hiking", "waterfall",
        "forest", "garden", "campground", "hot spring", "nature", "preserve",
        "lookout", "overlook", "vista", "summit",
        "landmark", "monument", "viewpoint", "observation", "historic", "scenic",
        "waterfront", "downtown", "plaza", "campus", "boardwalk", "pier",
        "promenade", "fountain", "observatory", "planetarium", "famous building",
        "factory tour",
        "mall", "shopping", "market", "bazaar", "outlet", "boutique", "vintage",
        "bookstore", "farmers market", "flea market",
        "climbing", "skating", "rink", "golf", "pickleball", "tennis",
        "stadium", "recreation", "sports complex",
        "spa", "sauna", "yoga", "meditation", "wellness", "retreat",
        "zoo", "aquarium", "playground", "trampoline", "petting zoo", "children's museum",
        "zipline", "zip line", "skydiving", "boating", "kayak", "rafting",
        "horseback", "atv", "scuba", "surf",
        "nightclub", "lounge", "live music", "jazz", "speakeasy", "club",
        "festival", "fairground", "carnival", "holiday market", "pop-up", "popup"
    ]

    private static let broadAreaKeywords: [String] = [
        "county", "parish", "borough", "province", "prefecture",
        "state of", "republic of", "kingdom of", "commonwealth of",
        "united states", "united kingdom"
    ]

    // MARK: - Public API

    /// Whether a MapKit item is a specific hangout/travel spot (not grocery, not a country/state/county).
    static func isEligibleSpot(_ item: MKMapItem) -> Bool {
        guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return false
        }

        if isBroadGeographicEntity(item) {
            return false
        }

        let haystack = "\(name) \(item.placemark.title ?? "")".lowercased()
        if excludedKeywords.contains(where: { haystack.contains($0) }) {
            return false
        }

        if let poi = item.pointOfInterestCategory {
            if excludedPOICategories.contains(poi) { return false }
            return allowedPOICategories.contains(poi)
        }

        // No POI category — only keep if text clearly matches a hangout type.
        return hangoutKeywords.contains(where: { haystack.contains($0) })
    }

    /// Countries, states, counties, and bare city names are not rateable spots.
    static func isBroadGeographicEntity(_ item: MKMapItem) -> Bool {
        let placemark = item.placemark
        let name = (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return true }

        // Specific allowed POI types are never broad admin areas.
        if let poi = item.pointOfInterestCategory, allowedPOICategories.contains(poi) {
            return false
        }

        let lower = name.lowercased()

        if let country = placemark.country, lower == country.lowercased() { return true }
        if let area = placemark.administrativeArea, lower == area.lowercased() { return true }
        if let sub = placemark.subAdministrativeArea, lower == sub.lowercased() { return true }

        // Bare locality with no street / POI is a city, not a spot.
        if let locality = placemark.locality,
           lower == locality.lowercased(),
           placemark.thoroughfare == nil,
           item.pointOfInterestCategory == nil {
            return true
        }

        if broadAreaKeywords.contains(where: {
            lower == $0 || lower.hasSuffix(" \($0)") || lower.contains(" \($0) ")
        }) {
            return true
        }

        if lower.hasSuffix(" county") || lower.hasSuffix(" parish") || lower.hasSuffix(" province") {
            return true
        }

        return false
    }

    /// Fast text-only check for completer rows that lack a map item.
    static func isEligibleText(title: String, subtitle: String) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }

        let haystack = "\(trimmedTitle) \(subtitle)".lowercased()

        if excludedKeywords.contains(where: { haystack.contains($0) }) {
            return false
        }
        if trimmedTitle.lowercased().hasSuffix(" county")
            || trimmedTitle.lowercased().hasSuffix(" parish")
            || trimmedTitle.lowercased().hasSuffix(" province") {
            return false
        }
        if looksLikeBareLocality(title: trimmedTitle, subtitle: subtitle) {
            return false
        }
        if hangoutKeywords.contains(where: { haystack.contains($0) }) {
            return true
        }

        // Completer subtitles often include the POI type ("Café", "Museum", …).
        let subtitleLower = subtitle.lowercased()
        let poiHints = [
            "restaurant", "cafe", "café", "bakery", "bar", "museum", "park",
            "gallery", "theater", "theatre", "nightlife", "attraction", "shop",
            "store", "market", "brewery", "winery", "zoo", "aquarium", "spa",
            "stadium", "trail", "beach", "landmark", "viewpoint"
        ]
        return poiHints.contains(where: { subtitleLower.contains($0) })
    }

    /// Infer a Trav display category from a MapKit item.
    static func category(for item: MKMapItem) -> SpotCategory {
        if let poi = item.pointOfInterestCategory {
            return category(forPOI: poi, text: "\(item.name ?? "") \(item.placemark.title ?? "")")
        }
        return category(fromText: "\(item.name ?? "") \(item.placemark.title ?? "")")
    }

    static func category(title: String, subtitle: String) -> SpotCategory {
        category(fromText: "\(title) \(subtitle)")
    }

    // MARK: - Internals

    private static func looksLikeBareLocality(title: String, subtitle: String) -> Bool {
        let s = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }
        let lowerSubtitle = s.lowercased()
        let adminOnly = lowerSubtitle.contains("united states")
            || lowerSubtitle.contains("united kingdom")
            || lowerSubtitle.range(of: #"^[A-Z]{2}(,|$)"#, options: .regularExpression) != nil
        let hasStreetHint = s.contains(where: { $0.isNumber })
            || lowerSubtitle.contains("street")
            || lowerSubtitle.contains("avenue")
            || lowerSubtitle.contains("road")
            || lowerSubtitle.contains("blvd")
        return adminOnly && !hasStreetHint && title.count < 40
    }

    private static func category(forPOI poi: MKPointOfInterestCategory, text: String) -> SpotCategory {
        let textCategory = category(fromText: text)

        switch poi {
        case .restaurant, .cafe, .bakery:
            return .foodAndDrink
        case .brewery, .winery, .nightlife:
            if textCategory == .nightlife { return .nightlife }
            return poi == .nightlife ? .nightlife : .foodAndDrink
        case .theater, .movieTheater:
            return textCategory == .nightlife ? .nightlife : .entertainment
        case .museum, .library:
            return .arts
        case .park, .nationalPark, .beach, .campground:
            return .nature
        case .marina:
            return textCategory == .adventure ? .adventure : .nature
        case .store:
            return .shopping
        case .stadium, .fitnessCenter:
            return textCategory == .wellness ? .wellness : .sportsAndRecreation
        case .zoo, .aquarium:
            return .family
        case .amusementPark:
            // Former Unique Attractions → Entertainment / Family
            return textCategory == .family ? .family : .entertainment
        case .university:
            // Former Public Spaces (campuses) → Landmarks
            return .landmarks
        default:
            break
        }

        if #available(iOS 18.0, *) {
            switch poi {
            case .bowling, .miniGolf, .goKart:
                return .entertainment
            case .musicVenue, .distillery:
                return .nightlife
            case .hiking:
                return .nature
            case .landmark, .nationalMonument, .castle, .fortress:
                return .landmarks
            case .golf, .tennis, .skating, .skatePark, .rockClimbing,
                 .baseball, .basketball, .soccer, .volleyball, .swimming, .skiing:
                return .sportsAndRecreation
            case .spa:
                return .wellness
            case .kayaking, .surfing, .fishing:
                return .adventure
            case .fairground, .conventionCenter:
                return .events
            case .planetarium:
                // Former Unique Attractions → Landmarks
                return .landmarks
            case .rvPark:
                return .nature
            default:
                break
            }
        }

        return textCategory
    }

    private static func category(fromText text: String) -> SpotCategory {
        let t = text.lowercased()

        if matches(t, ["nightclub", "speakeasy", "lounge", "live music", "jazz bar", "nightlife", "club "]) {
            return .nightlife
        }
        if matches(t, ["restaurant", "cafe", "café", "coffee", "bakery", "dessert", "boba", "brewery", "winery", "food truck", "bar ", " pub"]) {
            return .foodAndDrink
        }
        if matches(t, ["theme park", "ferris", "arcade", "escape room", "laser tag", "bowling", "mini golf", "karaoke", "billiard", "axe throwing", "go-kart", "go kart", "casino", "theater", "theatre", "cinema"]) {
            return .entertainment
        }
        if matches(t, ["public art", "studio tour", "museum", "gallery", "comedy", "concert", "opera", "exhibit"]) {
            return .arts
        }
        if matches(t, ["zipline", "zip line", "skydiving", "kayak", "rafting", "horseback", "scuba", "atv", "boating"]) {
            return .adventure
        }
        if matches(t, ["spa", "sauna", "yoga", "meditation", "wellness"]) {
            return .wellness
        }
        if matches(t, ["zoo", "aquarium", "playground", "trampoline", "petting zoo", "children"]) {
            return .family
        }
        if matches(t, ["festival", "carnival", "fairground", "holiday market", "pop-up", "popup"]) {
            return .events
        }
        if matches(t, ["mall", "shopping", "boutique", "outlet", "flea market", "farmers market", "bookstore", "vintage"]) {
            return .shopping
        }
        if matches(t, ["climbing", "skating", "rink", "golf", "pickleball", "tennis", "stadium", "recreation"]) {
            return .sportsAndRecreation
        }
        // Former Public Spaces + Unique Attractions (observatory / famous buildings / factory tours)
        // → Landmarks, plus classic sightseeing terms
        if matches(t, [
            "plaza", "campus", "boardwalk", "pier", "promenade", "fountain",
            "observatory", "planetarium", "factory tour", "famous building",
            "landmark", "monument", "viewpoint", "observation", "historic", "scenic", "waterfront"
        ]) {
            return .landmarks
        }
        if matches(t, ["park", "beach", "lake", "trail", "hike", "hiking", "waterfall", "garden", "campground", "hot spring", "forest", "nature", "lookout", "overlook"]) {
            return .nature
        }
        return .landmarks
    }

    private static func matches(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
