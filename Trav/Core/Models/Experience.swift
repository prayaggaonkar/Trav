import Foundation

struct StopMedia: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var mediaType: MediaType
    var url: URL
    var thumbnailURL: URL?
    var orderIndex: Int
}

struct Stop: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var orderIndex: Int
    var name: String
    var description: String
    var creatorNotes: String?
    var latitude: Double
    var longitude: Double
    var placeID: String?
    var recommendedTime: String?
    var durationMinutes: Int
    var emoji: String?
    var media: [StopMedia]
}

struct RouteSegment: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var fromStopID: UUID
    var toStopID: UUID
    var distanceMeters: Int
    var durationSeconds: Int
    var polyline: String
    var transportMode: TransportMode
}

struct ExperienceSummary: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var cityID: UUID
    var title: String
    var coverImageURL: URL?
    var creator: ProfileSummary
    var durationMinutes: Int
    var costLevel: CostLevel
    var saveCount: Int
    var completionCount: Int
    var stops: [StopPreview]
}

struct StopPreview: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var emoji: String?
}

struct Experience: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var cityID: UUID
    var creator: ProfileSummary
    var title: String
    var description: String
    var coverImageURL: URL?
    var durationMinutes: Int
    var costLevel: CostLevel
    var estimatedCostUSD: Decimal?
    var transportMode: TransportMode
    var totalDistanceMeters: Int
    var saveCount: Int
    var likeCount: Int
    var completionCount: Int
    var commentCount: Int
    var isPublished: Bool
    var publishedAt: Date?
    var stops: [Stop]
    var routeSegments: [RouteSegment]
}
