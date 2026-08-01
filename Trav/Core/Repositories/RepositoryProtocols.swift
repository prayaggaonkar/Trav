import Foundation

/// Typed error for repository failures — replaces `preconditionFailure` crashes
/// when the Supabase client is missing, and gives the UI a friendly message.
enum RepositoryError: LocalizedError, Sendable {
    case backendUnavailable
    case notFound
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .backendUnavailable:
            return "Trav couldn't reach the server. Check your connection and try again."
        case .notFound:
            return "This content is no longer available."
        case .unauthorized:
            return "Sign in to continue."
        }
    }
}

/// Violations of the content model, surfaced to the user as copy.
///
/// The database raises the same set of conditions with `TRAV_*` prefixes; the
/// client checks them up front so users get feedback before a round trip.
enum ContentModelError: LocalizedError, Sendable, Equatable {
    case itineraryNeedsMoreStops(current: Int)
    case duplicateStop(name: String)
    case duplicateItinerary
    case invalidStop
    case ratingRequired
    case alreadyRated
    case tooManyPhotos(limit: Int)
    case spotsAreNotUserCreated

    var errorDescription: String? {
        switch self {
        case .itineraryNeedsMoreStops(let current):
            let noun = current == 1 ? "spot" : "spots"
            return "An itinerary needs at least 2 spots — you have \(current) \(noun)."
        case .duplicateStop(let name):
            return "\(name) is already in this itinerary. Every stop has to be a different spot."
        case .duplicateItinerary:
            return "Someone already published an itinerary with these spots in this order."
        case .invalidStop:
            return "Every stop needs a name and a location."
        case .ratingRequired:
            return "Add your rating to mark this complete."
        case .alreadyRated:
            return "You've already rated this experience."
        case .tooManyPhotos(let limit):
            return "You can attach up to \(limit) photos."
        case .spotsAreNotUserCreated:
            return "Spots come from our place catalog and can't be created by hand."
        }
    }

    /// Maps a Postgres error message from a `TRAV_*` raise back to a typed case.
    static func from(serverMessage message: String) -> ContentModelError? {
        if message.contains("TRAV_MIN_STOPS") { return .itineraryNeedsMoreStops(current: 1) }
        if message.contains("TRAV_DUPLICATE_ITINERARY") { return .duplicateItinerary }
        if message.contains("TRAV_DUPLICATE_STOP") { return .duplicateStop(name: "That spot") }
        if message.contains("TRAV_INVALID_STOP") || message.contains("TRAV_INVALID_SPOT") { return .invalidStop }
        if message.contains("TRAV_RATING_REQUIRED") { return .ratingRequired }
        if message.contains("TRAV_ALREADY_RATED") { return .alreadyRated }
        if message.contains("TRAV_PHOTO_LIMIT") { return .tooManyPhotos(limit: RatingDraft.maxPhotos) }
        return nil
    }
}

protocol CityRepository: Sendable {
    func fetchGlobeCities() async throws -> [City]
    func fetchCity(id: UUID) async throws -> City
    func fetchFeaturedExperience(cityID: UUID) async throws -> ExperienceSummary?
    func fetchTrendingCreators(cityID: UUID) async throws -> [Profile]
}

protocol ExperienceRepository: Sendable {
    func fetchExperience(id: UUID) async throws -> Experience
    func fetchCityFeed(cityID: UUID, page: Int) async throws -> Paginated<ExperienceSummary>
    /// Global home feed: newest published experiences across all cities.
    func fetchHomeFeed(page: Int) async throws -> Paginated<ExperienceSummary>
    /// Curated places from the ingestion pipeline, mapped to feed summaries.
    func fetchPlacesFeed(page: Int) async throws -> Paginated<ExperienceSummary>
    /// Upcoming local pop-up events tailored to user's location.
    func fetchPopups(latitude: Double?, longitude: Double?, city: String?) async throws -> [Popup]
    /// Publishes a user-authored itinerary. Throws `ContentModelError` when the
    /// draft has fewer than 2 distinct spots or duplicates an existing journey.
    @discardableResult
    func publishExperience(_ draft: ExperienceDraft) async throws -> UUID
    /// Idempotently resolves a provider place to its canonical Spot, creating it
    /// on first sight. Spots are never authored by users, so this is the only
    /// way one enters the catalog.
    @discardableResult
    func syncSpot(_ request: SpotSyncRequest) async throws -> UUID
    /// Personalized ranking: the feed's primary source.
    func fetchPersonalizedFeed(_ request: FeedRequest) async throws -> Paginated<ExperienceSummary>
    /// Title search across spots and itineraries, used when rating something
    /// the user did not arrive from.
    func searchExperiences(query: String, kind: ExperienceKind?, limit: Int) async throws -> [ExperienceSummary]
    func fetchUserExperiences(cityID: UUID, userID: UUID) async throws -> [ExperienceSummary]
    /// Leaders sorted by total published experience count.
    func fetchLeaderboardEntries(cityID: UUID?, cityName: String?) async throws -> [LeaderboardEntry]
    /// Active streak leaders fetched from Supabase.
    func fetchHeatStreakEntries(cityID: UUID?, cityName: String?) async throws -> [HeatStreakEntry]
    /// Impact leaders ranked by total completions + saves across all published experiences.
    func fetchImpactLeaderboard(cityID: UUID?, cityName: String?) async throws -> [ImpactEntry]
    /// Main leaderboard ranked by total score: Total Score = (Impact * 5) + (Experiences * 25) + (Streak Days * 15) + (Streak Posts * 5).
    func fetchMainLeaderboard(cityID: UUID?, cityName: String?) async throws -> [MainLeaderboardEntry]
    /// Observe real-time insertion of new published experiences.
    func observeExperiencesInsert() -> AsyncStream<Void>
    /// Ranked experiences with a real rating. Unrated experiences are excluded.
    func fetchRankedExperiences(
        cityID: UUID?,
        creatorID: UUID?,
        axis: RankingAxis,
        page: Int
    ) async throws -> Paginated<ExperienceSummary>
    /// Creators ranked by mean score of their rated experiences (min 1).
    func fetchRankedCreators(
        cityID: UUID?,
        axis: RankingAxis,
        page: Int
    ) async throws -> Paginated<RankedCreator>
}

/// Everything needed to publish a new itinerary.
///
/// Only itineraries are user-authored, so publishing always enforces the
/// itinerary invariants: at least 2 stops, each a distinct spot.
struct ExperienceDraft: Sendable {
    var title: String
    var description: String
    var city: City
    var creatorID: UUID
    var stops: [Stop]
    var rating: RadarRating?
    var imagesData: [Data]

    /// Stops collapsed to their canonical place identity, preserving order.
    var stopIdentityKeys: [String] {
        stops
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { SpotIdentity.key(placeID: $0.placeID, name: $0.name, latitude: $0.latitude, longitude: $0.longitude) }
    }

    var distinctStopCount: Int {
        Set(stopIdentityKeys).count
    }

    /// Throws the first content-model violation, so the UI can block publishing
    /// before a round trip.
    func validateForPublishing() throws {
        for stop in stops where stop.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ContentModelError.invalidStop
        }

        var seen: Set<String> = []
        for stop in stops.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            let key = SpotIdentity.key(
                placeID: stop.placeID,
                name: stop.name,
                latitude: stop.latitude,
                longitude: stop.longitude
            )
            if seen.contains(key) {
                throw ContentModelError.duplicateStop(name: stop.name)
            }
            seen.insert(key)
        }

        if seen.count < ExperienceKind.itinerary.minimumStops {
            throw ContentModelError.itineraryNeedsMoreStops(current: seen.count)
        }
    }
}

/// A provider place being promoted into the canonical Spot catalog.
struct SpotSyncRequest: Sendable {
    var placeID: String?
    var name: String
    var description: String
    var cityName: String
    var cityID: UUID?
    var latitude: Double?
    var longitude: Double?
    var imageURLs: [URL]
    var category: String?
    var emoji: String?

    init(
        placeID: String? = nil,
        name: String,
        description: String = "",
        cityName: String = "",
        cityID: UUID? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        imageURLs: [URL] = [],
        category: String? = nil,
        emoji: String? = nil
    ) {
        self.placeID = placeID
        self.name = name
        self.description = description
        self.cityName = cityName
        self.cityID = cityID
        self.latitude = latitude
        self.longitude = longitude
        self.imageURLs = imageURLs
        self.category = category
        self.emoji = emoji
    }

    init(summary: ExperienceSummary) {
        let stop = summary.stops.first
        self.init(
            placeID: nil,
            name: summary.title,
            description: "",
            cityName: summary.cityName ?? "",
            cityID: summary.cityID,
            latitude: summary.latitude ?? stop?.latitude,
            longitude: summary.longitude ?? stop?.longitude,
            imageURLs: summary.imageURLs,
            category: summary.category,
            emoji: stop?.emoji
        )
    }

    var identityKey: String {
        SpotIdentity.key(placeID: placeID, name: name, latitude: latitude ?? 0, longitude: longitude ?? 0)
    }
}

/// Mirrors `public.spot_identity_key` in Postgres so the client and database
/// agree on when two places are the same spot.
enum SpotIdentity {
    static func key(placeID: String?, name: String, latitude: Double, longitude: Double) -> String {
        if let placeID, !placeID.trimmingCharacters(in: .whitespaces).isEmpty {
            return "place:" + placeID.trimmingCharacters(in: .whitespaces).lowercased()
        }
        let slug = name
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
        return String(format: "geo:%@:%.4f:%.4f", slug, latitude, longitude)
    }
}

/// Inputs to the weighted recommendation engine.
struct FeedRequest: Sendable {
    var userID: UUID?
    var latitude: Double?
    var longitude: Double?
    var cityID: UUID?
    var kind: ExperienceKind?
    var page: Int
    var pageSize: Int

    init(
        userID: UUID? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        cityID: UUID? = nil,
        kind: ExperienceKind? = nil,
        page: Int = 0,
        pageSize: Int = 20
    ) {
        self.userID = userID
        self.latitude = latitude
        self.longitude = longitude
        self.cityID = cityID
        self.kind = kind
        self.page = page
        self.pageSize = pageSize
    }
}

protocol AuthRepository: Sendable {
    func signIn(email: String, password: String) async throws -> Profile
    /// Returns the profile when Supabase issues a session immediately;
    /// `nil` when email confirmation is required before sign-in completes.
    @discardableResult
    func signUp(email: String, password: String) async throws -> Profile?
    func signOut() async throws
    func resetPassword(email: String) async throws
    func signInWithGoogle() async throws -> Profile
    func saveOnboardingData(userID: UUID, vibes: [String], location: String?) async throws -> Profile

    /// Emits the signed-in profile whenever the auth session changes, starting with the
    /// current session (or `nil`) as soon as the stream is created. Used to restore and
    /// keep `SessionStore` in sync across app launches, sign-outs, and token refreshes.
    func authStateChanges() -> AsyncStream<Profile?>
}

protocol ProfileRepository: Sendable {
    func fetchProfile(username: String) async throws -> Profile
    func fetchProfile(id: UUID) async throws -> Profile
    func updateProfile(userID: UUID, update: ProfileUpdate) async throws -> Profile
    func checkUsernameAvailability(_ username: String, excludingUserID: UUID?) async throws -> UsernameAvailability
    func uploadAvatar(userID: UUID, imageData: Data) async throws -> URL
    func fetchFollowers(userID: UUID, query: String?, page: Int) async throws -> Paginated<ProfileSummary>
    func fetchFollowing(userID: UUID, query: String?, page: Int) async throws -> Paginated<ProfileSummary>
    func searchUsers(query: String) async throws -> [ProfileSummary]
    func isFollowing(followerID: UUID, followingID: UUID) async throws -> Bool
    func follow(followerID: UUID, followingID: UUID) async throws
    func unfollow(followerID: UUID, followingID: UUID) async throws
    func syncContactHashes(_ hashes: [ContactHash]) async throws
    func fetchSuggestedUsers(limit: Int) async throws -> [SuggestedUser]
    func fetchCreatedExperiences(userID: UUID, page: Int) async throws -> Paginated<ExperienceSummary>
    func fetchSavedExperiences(userID: UUID, page: Int) async throws -> Paginated<ExperienceSummary>
    func fetchCompletedExperiences(userID: UUID, page: Int) async throws -> Paginated<CompletedExperienceItem>
}

protocol EngagementRepository: Sendable {
    func fetchSavedIDs(userID: UUID) async throws -> Set<UUID>
    func fetchCompletedIDs(userID: UUID) async throws -> Set<UUID>
    func fetchLikedIDs(userID: UUID) async throws -> Set<UUID>
    func fetchFollowingIDs(userID: UUID) async throws -> Set<UUID>
    func isSaved(userID: UUID, experienceID: UUID) async throws -> Bool
    func isCompleted(userID: UUID, experienceID: UUID) async throws -> Bool
    /// Returns the new saved state after toggle.
    func toggleSave(userID: UUID, experienceID: UUID) async throws -> Bool
    /// Always removes the bookmark for this user (no-op if already unsaved).
    func unsave(userID: UUID, experienceID: UUID) async throws
    /// Removes a completion by deleting the underlying rating. Completion is a
    /// consequence of rating, so it cannot be toggled on its own — use
    /// `RatingRepository.submitRating` to complete an experience.
    func removeCompletion(userID: UUID, experienceID: UUID) async throws
    /// Returns the new liked state after toggle.
    func toggleLike(userID: UUID, experienceID: UUID) async throws -> Bool
    /// Ensures an `experiences` row exists for `summary.id` so save/completion FKs
    /// succeed when bookmarking feed places. The shadow row is unpublished
    /// (`is_published = false`) so it never appears in feeds or profiles.
    func ensureExperienceExists(for summary: ExperienceSummary, ownerID: UUID) async throws

    // Comments
    func fetchComments(experienceID: UUID, page: Int) async throws -> Paginated<Comment>
    func addComment(experienceID: UUID, authorID: UUID, body: String, parentID: UUID?) async throws -> Comment
    func deleteComment(id: UUID) async throws

    // Moderation
    func report(target: ReportTarget, reporterID: UUID, reason: ReportReason, details: String?) async throws
    func block(blockerID: UUID, blockedID: UUID) async throws
    func unblock(blockerID: UUID, blockedID: UUID) async throws
    func fetchBlockedIDs(userID: UUID) async throws -> Set<UUID>
}

/// Ratings are a first-class entity with their own read/write surface.
protocol RatingRepository: Sendable {
    /// Creates or replaces this user's rating, which also marks the experience
    /// complete. Returns the persisted rating.
    @discardableResult
    func submitRating(_ draft: RatingDraft, userID: UUID) async throws -> Rating
    /// This user's rating of an experience, if they have rated it.
    func fetchMyRating(userID: UUID, experienceID: UUID) async throws -> Rating?
    /// Every rating on an experience, newest first.
    func fetchRatings(experienceID: UUID, page: Int) async throws -> Paginated<Rating>
    /// Database-computed aggregates for an experience.
    func fetchRatingSummary(experienceID: UUID) async throws -> RatingSummary
    /// Deleting a rating also removes the completion.
    func deleteRating(userID: UUID, experienceID: UUID) async throws
}

protocol NotificationRepository: Sendable {
    func fetchNotifications(userID: UUID, page: Int) async throws -> Paginated<AppNotification>
    func unreadCount(userID: UUID) async throws -> Int
    func markRead(ids: [UUID]) async throws
    func markAllRead(userID: UUID) async throws
    /// Permanently removes a notification owned by the current user.
    func deleteNotification(id: UUID) async throws
    /// Emits newly inserted notifications for `userID` (Realtime). Empty stream when unsupported.
    func observeInserts(userID: UUID) -> AsyncStream<AppNotification>
    /// Registers an APNs device token for push delivery.
    func registerDeviceToken(_ token: String, userID: UUID) async throws
    func unregisterDeviceToken(_ token: String) async throws
}
