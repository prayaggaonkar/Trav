import Foundation

/// Codable helper struct to seamlessly decode both single string and array string Supabase columns.
struct StringOrArray: Codable, Sendable {
    let values: [String]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Prefer `[String?]` so rows like `[null]` (bad uploads) don't fail the feed.
        if let array = try? container.decode([String?].self) {
            self.values = array.compactMap { $0 }
        } else if let array = try? container.decode([String].self) {
            self.values = array
        } else if let single = try? container.decode(String.self) {
            self.values = [single]
        } else {
            self.values = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

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

struct WatchlistUser: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let name: String
    let avatarImage: String
}

struct ExperienceSummary: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var cityID: UUID
    var title: String
    var imageURLs: [URL]
    var creator: ProfileSummary
    var durationMinutes: Int
    var costLevel: CostLevel
    var estimatedCostUSD: Decimal?
    var saveCount: Int
    var likeCount: Int
    var completionCount: Int
    var stops: [StopPreview]
    /// Multi-dimensional radar rating data stored as JSON in DB.
    var rating: RadarRating? = nil
    /// Optional display label when city is stored as text (Supabase simplified schema).
    var cityName: String? = nil
    var watchlistedBy: [WatchlistUser] = []

    var coverImageURL: URL? {
        imageURLs.first
    }

    var costLabel: String {
        if let estimatedCostUSD {
            let dollars = NSDecimalNumber(decimal: estimatedCostUSD).intValue
            return dollars == 0 ? "Free" : "$\(dollars)"
        }
        return costLevel.displayName
    }

    var displayCityName: String {
        if let cityName, !cityName.isEmpty { return cityName }
        return "Unknown"
    }

    init(
        id: UUID,
        cityID: UUID,
        title: String,
        imageURLs: [URL] = [],
        coverImageURL: URL? = nil,
        creator: ProfileSummary,
        durationMinutes: Int,
        costLevel: CostLevel,
        estimatedCostUSD: Decimal? = nil,
        saveCount: Int = 0,
        likeCount: Int = 0,
        completionCount: Int = 0,
        stops: [StopPreview] = [],
        rating: RadarRating? = nil,
        cityName: String? = nil,
        watchlistedBy: [WatchlistUser] = []
    ) {
        self.id = id
        self.cityID = cityID
        self.title = title
        if !imageURLs.isEmpty {
            self.imageURLs = imageURLs
        } else if let coverImageURL {
            self.imageURLs = [coverImageURL]
        } else {
            self.imageURLs = []
        }
        self.creator = creator
        self.durationMinutes = durationMinutes
        self.costLevel = costLevel
        self.estimatedCostUSD = estimatedCostUSD
        self.saveCount = saveCount
        self.likeCount = likeCount
        self.completionCount = completionCount
        self.stops = stops
        self.rating = rating
        self.cityName = cityName
        self.watchlistedBy = watchlistedBy
    }
}

struct StopPreview: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var emoji: String?
    var latitude: Double? = nil
    var longitude: Double? = nil
}

struct Experience: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var cityID: UUID
    var creator: ProfileSummary
    var title: String
    var description: String
    var imageURLs: [URL]
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
    /// Multi-dimensional radar rating data stored as JSON in DB.
    var rating: RadarRating? = nil

    var coverImageURL: URL? {
        imageURLs.first
    }

    init(
        id: UUID,
        cityID: UUID,
        creator: ProfileSummary,
        title: String,
        description: String = "",
        imageURLs: [URL] = [],
        coverImageURL: URL? = nil,
        durationMinutes: Int,
        costLevel: CostLevel,
        estimatedCostUSD: Decimal? = nil,
        transportMode: TransportMode = .walking,
        totalDistanceMeters: Int = 0,
        saveCount: Int = 0,
        likeCount: Int = 0,
        completionCount: Int = 0,
        commentCount: Int = 0,
        isPublished: Bool = true,
        publishedAt: Date? = nil,
        stops: [Stop] = [],
        routeSegments: [RouteSegment] = [],
        rating: RadarRating? = nil
    ) {
        self.id = id
        self.cityID = cityID
        self.creator = creator
        self.title = title
        self.description = description
        if !imageURLs.isEmpty {
            self.imageURLs = imageURLs
        } else if let coverImageURL {
            self.imageURLs = [coverImageURL]
        } else {
            self.imageURLs = []
        }
        self.durationMinutes = durationMinutes
        self.costLevel = costLevel
        self.estimatedCostUSD = estimatedCostUSD
        self.transportMode = transportMode
        self.totalDistanceMeters = totalDistanceMeters
        self.saveCount = saveCount
        self.likeCount = likeCount
        self.completionCount = completionCount
        self.commentCount = commentCount
        self.isPublished = isPublished
        self.publishedAt = publishedAt
        self.stops = stops
        self.routeSegments = routeSegments
        self.rating = rating
    }
}
