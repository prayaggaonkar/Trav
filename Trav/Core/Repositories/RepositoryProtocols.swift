import Foundation

protocol CityRepository: Sendable {
    func fetchGlobeCities() async throws -> [City]
    func fetchCity(id: UUID) async throws -> City
    func fetchFeaturedExperience(cityID: UUID) async throws -> ExperienceSummary?
    func fetchTrendingCreators(cityID: UUID) async throws -> [Profile]
}

protocol ExperienceRepository: Sendable {
    func fetchExperience(id: UUID) async throws -> Experience
    func fetchCityFeed(cityID: UUID, page: Int) async throws -> Paginated<ExperienceSummary>
    func publishExperience(title: String, description: String, cityID: UUID, creatorID: UUID, stops: [StopPreview], rating: RadarRating?, imageData: Data?) async throws
    func fetchUserExperiences(cityID: UUID, userID: UUID) async throws -> [ExperienceSummary]
}

protocol AuthRepository: Sendable {
    func signIn(email: String, password: String) async throws -> Profile
    func signUp(email: String, password: String) async throws
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
    func fetchFollowingIDs(userID: UUID) async throws -> Set<UUID>
    func isSaved(userID: UUID, experienceID: UUID) async throws -> Bool
    func isCompleted(userID: UUID, experienceID: UUID) async throws -> Bool
    /// Returns the new saved state after toggle.
    func toggleSave(userID: UUID, experienceID: UUID) async throws -> Bool
    /// Always removes the bookmark for this user (no-op if already unsaved).
    func unsave(userID: UUID, experienceID: UUID) async throws
    /// Returns the new completed state after toggle.
    func toggleComplete(userID: UUID, experienceID: UUID) async throws -> Bool
    /// Ensures an `experiences` row exists for `summary.id` so `experience_saves` FK succeeds
    /// (used when bookmarking feed places that are not already published experiences).
    func ensureExperienceExists(for summary: ExperienceSummary, ownerID: UUID) async throws
}

protocol NotificationRepository: Sendable {
    func fetchNotifications(userID: UUID, page: Int) async throws -> Paginated<AppNotification>
    func unreadCount(userID: UUID) async throws -> Int
    func markRead(ids: [UUID]) async throws
    func markAllRead(userID: UUID) async throws
    /// Emits newly inserted notifications for `userID` (Realtime). Empty stream when unsupported.
    func observeInserts(userID: UUID) -> AsyncStream<AppNotification>
}
