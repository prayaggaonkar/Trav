import Foundation

enum CostLevel: String, Codable, Sendable, CaseIterable {
    case free
    case budget
    case moderate
    case premium

    var displayName: String {
        switch self {
        case .free: "Free"
        case .budget: "$"
        case .moderate: "$$"
        case .premium: "$$$"
        }
    }
}

/// The only two shapes an experience can take.
///
/// A `spot` is one real-world place, synced from our place provider and never
/// authored by a user. An `itinerary` is a curated journey over 2+ distinct
/// spots, authored by a user or by Trav.
enum ExperienceKind: String, Codable, Sendable, CaseIterable, Hashable {
    case spot
    case itinerary

    var displayName: String {
        switch self {
        case .spot: "Spot"
        case .itinerary: "Itinerary"
        }
    }

    var pluralDisplayName: String {
        switch self {
        case .spot: "Spots"
        case .itinerary: "Itineraries"
        }
    }

    var symbolName: String {
        switch self {
        case .spot: "mappin.circle.fill"
        case .itinerary: "map.fill"
        }
    }

    /// Minimum number of distinct stops required to publish.
    var minimumStops: Int {
        switch self {
        case .spot: 1
        case .itinerary: 2
        }
    }

    /// Spots come from the place provider; users may only author itineraries.
    var isUserAuthorable: Bool { self == .itinerary }

    /// Falls back to stop count for rows written before kinds existed.
    static func inferred(stopCount: Int) -> ExperienceKind {
        stopCount > 1 ? .itinerary : .spot
    }
}

enum TransportMode: String, Codable, Sendable {
    case walking
    case driving
    case transit
    case mixed

    var symbolName: String {
        switch self {
        case .walking: "figure.walk"
        case .driving: "car.fill"
        case .transit: "tram.fill"
        case .mixed: "arrow.triangle.swap"
        }
    }
}

enum MediaType: String, Codable, Sendable {
    case photo
    case video
}

enum AuthPhase: Equatable, Sendable {
    case loading
    case unauthenticated
    case onboarding
    case authenticated
}

struct Paginated<T: Sendable>: Sendable {
    var items: [T]
    var page: Int
    var hasMore: Bool
}
