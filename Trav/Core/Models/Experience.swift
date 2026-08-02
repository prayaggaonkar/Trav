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

/// A user shown in the "completed by" facepile on feed cards.
struct CompletionUser: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let name: String
    let avatarImage: String
}

struct ExperienceSummary: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var kind: ExperienceKind
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
    /// The creator's own radar scores, stored as JSON in DB.
    var rating: RadarRating? = nil
    /// Database-computed aggregates across every rating of this experience.
    var ratingSummary: RatingSummary = .empty
    /// Optional display label when city is stored as text (Supabase simplified schema).
    var cityName: String? = nil
    var completedBy: [CompletionUser] = []
    /// Canonical place identity, present on spots synced from the provider.
    var spotKey: String? = nil
    var category: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil

    var isSpot: Bool { kind == .spot }
    var isItinerary: Bool { kind == .itinerary }

    var isTravOwned: Bool {
        ExperienceInsert.isTravOwned(
            creatorID: creator.id,
            username: creator.username,
            displayName: creator.displayName
        )
    }

    /// True only if this is a real multi-stop itinerary created by a user.
    var isRealUserItinerary: Bool {
        kind == .itinerary && !isTravOwned
    }

    /// Destinations are Trav-owned, so any rating is community validation.
    /// Itineraries need a non-creator rating before the score is social proof.
    var showsCommunityValidatedScore: Bool {
        if ratingSummary.hasCommunityValidation || ratingSummary.communityRatingCount > 0 {
            return true
        }
        if isSpot && ratingSummary.ratingCount > 0 {
            return true
        }
        return false
    }

    var coverImageURL: URL? {
        imageURLs.first
    }

    /// Radar to render, preferring the community average once it exists.
    var displayRadar: RadarRating? {
        ratingSummary.displayRadar(creatorRadar: rating)
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
        kind: ExperienceKind? = nil,
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
        ratingSummary: RatingSummary = .empty,
        cityName: String? = nil,
        completedBy: [CompletionUser] = [],
        spotKey: String? = nil,
        category: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.kind = kind ?? .inferred(stopCount: stops.count)
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
        self.ratingSummary = ratingSummary
        self.cityName = cityName
        self.completedBy = completedBy
        self.spotKey = spotKey
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
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
    var kind: ExperienceKind
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
    /// The creator's own radar scores, stored as JSON in DB.
    var rating: RadarRating? = nil
    /// Database-computed aggregates across every rating of this experience.
    var ratingSummary: RatingSummary = .empty
    var spotKey: String? = nil
    var category: String? = nil
    var cityName: String? = nil

    var isSpot: Bool { kind == .spot }
    var isItinerary: Bool { kind == .itinerary }

    var isTravOwned: Bool {
        ExperienceInsert.isTravOwned(
            creatorID: creator.id,
            username: creator.username,
            displayName: creator.displayName
        )
    }

    /// True only if this is a real multi-stop itinerary created by a user.
    var isRealUserItinerary: Bool {
        kind == .itinerary && !isTravOwned
    }

    var showsCommunityValidatedScore: Bool {
        if ratingSummary.hasCommunityValidation || ratingSummary.communityRatingCount > 0 {
            return true
        }
        if isSpot && ratingSummary.ratingCount > 0 {
            return true
        }
        return false
    }

    var coverImageURL: URL? {
        imageURLs.first
    }

    /// Radar to render, preferring the community average once it exists.
    var displayRadar: RadarRating? {
        ratingSummary.displayRadar(creatorRadar: rating)
    }

    init(
        id: UUID,
        kind: ExperienceKind? = nil,
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
        rating: RadarRating? = nil,
        ratingSummary: RatingSummary = .empty,
        spotKey: String? = nil,
        category: String? = nil,
        cityName: String? = nil
    ) {
        self.id = id
        self.kind = kind ?? .inferred(stopCount: stops.count)
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
        self.ratingSummary = ratingSummary
        self.spotKey = spotKey
        self.category = category
        self.cityName = cityName
    }
}

extension Experience {
    /// Feed-card projection of a full experience.
    var summary: ExperienceSummary {
        ExperienceSummary(
            id: id,
            kind: kind,
            cityID: cityID,
            title: title,
            imageURLs: imageURLs,
            creator: creator,
            durationMinutes: durationMinutes,
            costLevel: costLevel,
            estimatedCostUSD: estimatedCostUSD,
            saveCount: saveCount,
            likeCount: likeCount,
            completionCount: completionCount,
            stops: stops.map {
                StopPreview(
                    id: $0.id,
                    name: $0.name,
                    emoji: $0.emoji,
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            },
            rating: rating,
            ratingSummary: ratingSummary,
            cityName: cityName,
            spotKey: spotKey,
            category: category
        )
    }
}
