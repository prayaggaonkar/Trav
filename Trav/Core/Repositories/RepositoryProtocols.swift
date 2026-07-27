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
    /// Upcoming local pop-up events.
    func fetchPopups() async throws -> [Popup]
    func publishExperience(_ draft: ExperienceDraft) async throws
    func fetchUserExperiences(cityID: UUID, userID: UUID) async throws -> [ExperienceSummary]
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

/// Everything needed to publish a new experience.
struct ExperienceDraft: Sendable {
    var title: String
    var description: String
    var city: City
    var creatorID: UUID
    var stops: [Stop]
    var rating: RadarRating?
    var imagesData: [Data]
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
    /// Returns the new completed state after toggle.
    func toggleComplete(userID: UUID, experienceID: UUID, note: String?, photosData: [Data]) async throws -> Bool
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

protocol NotificationRepository: Sendable {
    func fetchNotifications(userID: UUID, page: Int) async throws -> Paginated<AppNotification>
    func unreadCount(userID: UUID) async throws -> Int
    func markRead(ids: [UUID]) async throws
    func markAllRead(userID: UUID) async throws
    /// Emits newly inserted notifications for `userID` (Realtime). Empty stream when unsupported.
    func observeInserts(userID: UUID) -> AsyncStream<AppNotification>
    /// Registers an APNs device token for push delivery.
    func registerDeviceToken(_ token: String, userID: UUID) async throws
    func unregisterDeviceToken(_ token: String) async throws
}
