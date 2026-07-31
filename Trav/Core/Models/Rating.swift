import Foundation

/// A user's rating of a Spot or an Itinerary.
///
/// Ratings are the only way to complete an experience: submitting one marks the
/// experience completed, folds into its averages, and adds it to the author's
/// Completed tab. There is exactly one rating per user per experience.
struct Rating: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var experienceID: UUID
    var author: ProfileSummary
    /// Hexagon axis scores exactly as captured by the rating control.
    var radar: RadarRating
    var overallScore: Double
    var review: String?
    var photoURLs: [URL]
    var createdAt: Date
    var updatedAt: Date

    var hasReview: Bool {
        guard let review else { return false }
        return !review.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        id: UUID,
        experienceID: UUID,
        author: ProfileSummary,
        radar: RadarRating,
        overallScore: Double,
        review: String? = nil,
        photoURLs: [URL] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.experienceID = experienceID
        self.author = author
        self.radar = radar
        self.overallScore = overallScore
        self.review = review
        self.photoURLs = photoURLs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Everything a user submits when rating an experience.
struct RatingDraft: Sendable {
    var experienceID: UUID
    var radar: RadarRating
    var review: String?
    var photosData: [Data]

    static let maxPhotos = 3

    init(experienceID: UUID, radar: RadarRating, review: String? = nil, photosData: [Data] = []) {
        self.experienceID = experienceID
        self.radar = radar
        self.review = review
        self.photosData = Array(photosData.prefix(Self.maxPhotos))
    }
}

/// Aggregate rating state for an experience, computed by the database.
///
/// The distinction between `creatorScore` and the community average drives how
/// the UI presents trust: a creator rating alone is not social proof.
struct RatingSummary: Codable, Sendable, Hashable {
    /// Mean across every rating, including the creator's own.
    var averageScore: Double?
    var ratingCount: Int
    /// Mean across everyone except the creator.
    var communityAverageScore: Double?
    var communityRatingCount: Int
    /// The creator's own score, when they rated their itinerary.
    var creatorScore: Double?
    /// Per-axis community mean, for the hexagon chart.
    var communityRadar: RadarRating?

    static let empty = RatingSummary(
        averageScore: nil,
        ratingCount: 0,
        communityAverageScore: nil,
        communityRatingCount: 0,
        creatorScore: nil,
        communityRadar: nil
    )

    /// True once anyone other than the creator has rated — the point at which a
    /// score becomes genuine public validation.
    var hasCommunityValidation: Bool {
        communityRatingCount > 0 && communityAverageScore != nil
    }

    /// Score to lead with: community when it exists, otherwise the creator's.
    var displayScore: Double? {
        if hasCommunityValidation { return communityAverageScore }
        return creatorScore ?? averageScore
    }

    var displayCount: Int {
        hasCommunityValidation ? communityRatingCount : ratingCount
    }

    /// The radar to draw: averaged community axes when available.
    func displayRadar(creatorRadar: RadarRating?) -> RadarRating? {
        if hasCommunityValidation, let communityRadar, !communityRadar.scores.isEmpty {
            return communityRadar
        }
        return creatorRadar
    }

    var isCreatorOnly: Bool {
        !hasCommunityValidation && (creatorScore != nil || ratingCount > 0)
    }

    var caption: String {
        if hasCommunityValidation {
            let noun = communityRatingCount == 1 ? "rating" : "ratings"
            return "\(communityRatingCount) community \(noun)"
        }
        if creatorScore != nil || ratingCount > 0 {
            return "Creator rating · no community ratings yet"
        }
        return "Not rated yet"
    }

    init(
        averageScore: Double? = nil,
        ratingCount: Int = 0,
        communityAverageScore: Double? = nil,
        communityRatingCount: Int = 0,
        creatorScore: Double? = nil,
        communityRadar: RadarRating? = nil
    ) {
        self.averageScore = averageScore
        self.ratingCount = ratingCount
        self.communityAverageScore = communityAverageScore
        self.communityRatingCount = communityRatingCount
        self.creatorScore = creatorScore
        self.communityRadar = communityRadar
    }
}
