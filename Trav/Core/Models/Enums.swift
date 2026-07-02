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
