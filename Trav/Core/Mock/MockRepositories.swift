import Foundation

struct MockCityRepository: CityRepository {
    func fetchGlobeCities() async throws -> [City] {
        return MockData.cities
    }

    func fetchCity(id: UUID) async throws -> City {
        guard let city = MockData.cities.first(where: { $0.id == id }) else {
            throw RepositoryError.notFound
        }
        return city
    }

    func fetchFeaturedExperience(cityID: UUID) async throws -> ExperienceSummary? {
        MockData.experiences.first { $0.cityID == cityID }
    }

    func fetchTrendingCreators(cityID: UUID) async throws -> [Profile] {
        MockData.trendingCreators(for: cityID)
    }
}

struct MockExperienceRepository: ExperienceRepository {
    func fetchExperience(id: UUID) async throws -> Experience {
        guard let summary = MockData.experiences.first(where: { $0.id == id }) else {
            throw RepositoryError.notFound
        }
        return MockData.fullExperience(for: summary)
    }

    func fetchCityFeed(cityID: UUID, page: Int) async throws -> Paginated<ExperienceSummary> {
        let items = MockData.experiences.filter { $0.cityID == cityID }
        return Paginated(items: items, page: page, hasMore: false)
    }

    func publishExperience(
        title: String,
        description: String,
        cityID: UUID,
        creatorID: UUID,
        stops: [StopPreview],
        rating: RadarRating?,
        imageData: Data?
    ) async throws {
        print("--- MockExperienceRepository.publishExperience called (using Mock Backend) with rating: \(String(describing: rating)) ---")
        try await Task.sleep(for: .milliseconds(500))
        await MockSocialState.shared.notifyNewExperience(creatorID: creatorID, experienceID: UUID())
    }

    func fetchUserExperiences(cityID: UUID, userID: UUID) async throws -> [ExperienceSummary] {
        MockData.experiences.filter { $0.cityID == cityID && $0.creator.id == userID }
    }

    func fetchRankedExperiences(
        cityID: UUID?,
        creatorID: UUID?,
        axis: RankingAxis,
        page: Int
    ) async throws -> Paginated<ExperienceSummary> {
        try await Task.sleep(for: .milliseconds(180))
        var items = MockData.experiences
        if let cityID {
            items = items.filter { $0.cityID == cityID }
        }
        if let creatorID {
            items = items.filter { $0.creator.id == creatorID }
        }
        let sorted = RankingScore.sortedExperiences(items, axis: axis)
        return RankingScore.paginate(sorted, page: page)
    }

    func fetchRankedCreators(
        cityID: UUID?,
        axis: RankingAxis,
        page: Int
    ) async throws -> Paginated<RankedCreator> {
        try await Task.sleep(for: .milliseconds(180))
        var items = MockData.experiences
        if let cityID {
            items = items.filter { $0.cityID == cityID }
        }
        let ranked = RankingScore.rankedCreators(from: items, axis: axis)
        return RankingScore.paginate(ranked, page: page)
    }
}

struct MockAuthRepository: AuthRepository {
    func signIn(email: String, password: String) async throws -> Profile {
        let profile = try await MockSocialState.shared.profile(id: MockData.creators[0].id)
        return profile
    }

    func signUp(email: String, password: String) async throws {}

    func signOut() async throws {}

    func resetPassword(email: String) async throws {}

    func signInWithGoogle() async throws -> Profile {
        try await signIn(email: "demo@trav.app", password: "")
    }

    func saveOnboardingData(userID: UUID, vibes: [String], location: String?) async throws -> Profile {
        var profile = try await MockSocialState.shared.profile(id: userID)
        profile.selectedVibes = vibes
        profile.onboardingLocation = location
        profile.homeCityName = location
        await MockSocialState.shared.upsert(profile)
        return profile
    }

    func authStateChanges() -> AsyncStream<Profile?> {
        AsyncStream { continuation in
            continuation.yield(nil)
            continuation.finish()
        }
    }
}

struct MockProfileRepository: ProfileRepository {
    func fetchProfile(username: String) async throws -> Profile {
        try await Task.sleep(for: .milliseconds(180))
        return try await MockSocialState.shared.profile(username: username)
    }

    func fetchProfile(id: UUID) async throws -> Profile {
        try await Task.sleep(for: .milliseconds(120))
        return try await MockSocialState.shared.profile(id: id)
    }

    func updateProfile(userID: UUID, update: ProfileUpdate) async throws -> Profile {
        try await Task.sleep(for: .milliseconds(250))
        return try await MockSocialState.shared.update(userID: userID, update: update)
    }

    func checkUsernameAvailability(_ username: String, excludingUserID: UUID?) async throws -> UsernameAvailability {
        try await Task.sleep(for: .milliseconds(200))
        return await MockSocialState.shared.isUsernameAvailable(username, excludingUserID: excludingUserID)
    }

    func uploadAvatar(userID: UUID, imageData: Data) async throws -> URL {
        try await Task.sleep(for: .milliseconds(300))
        // Mock: pretend we uploaded and return a deterministic placeholder.
        return URL(string: "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400&h=400&fit=crop")!
    }

    func fetchFollowers(userID: UUID, query: String?, page: Int) async throws -> Paginated<ProfileSummary> {
        try await Task.sleep(for: .milliseconds(150))
        var items = await MockSocialState.shared.followers(of: userID)
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = query.lowercased()
            items = items.filter {
                $0.username.lowercased().contains(q) || $0.displayName.lowercased().contains(q)
            }
        }
        return paginate(items, page: page)
    }

    func fetchFollowing(userID: UUID, query: String?, page: Int) async throws -> Paginated<ProfileSummary> {
        try await Task.sleep(for: .milliseconds(150))
        var items = await MockSocialState.shared.following(of: userID)
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = query.lowercased()
            items = items.filter {
                $0.username.lowercased().contains(q) || $0.displayName.lowercased().contains(q)
            }
        }
        return paginate(items, page: page)
    }

    func searchUsers(query: String) async throws -> [ProfileSummary] {
        try await Task.sleep(for: .milliseconds(120))
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return MockData.creators.compactMap { creator in
            let profile = MockData.profile(for: creator)
            if profile.username.lowercased().contains(q) || profile.displayName.lowercased().contains(q) {
                return profile.summary
            }
            return nil
        }
    }

    func isFollowing(followerID: UUID, followingID: UUID) async throws -> Bool {
        await MockSocialState.shared.isFollowing(followerID: followerID, followingID: followingID)
    }

    func follow(followerID: UUID, followingID: UUID) async throws {
        try await MockSocialState.shared.follow(followerID: followerID, followingID: followingID)
    }

    func unfollow(followerID: UUID, followingID: UUID) async throws {
        await MockSocialState.shared.unfollow(followerID: followerID, followingID: followingID)
    }

    func fetchCreatedExperiences(userID: UUID, page: Int) async throws -> Paginated<ExperienceSummary> {
        try await Task.sleep(for: .milliseconds(160))
        let items = await MockSocialState.shared.createdExperiences(userID: userID).map { summary in
            var copy = summary
            copy.cityName = MockData.cities.first(where: { $0.id == summary.cityID })?.name
            return copy
        }
        return paginate(items, page: page)
    }

    func fetchSavedExperiences(userID: UUID, page: Int) async throws -> Paginated<ExperienceSummary> {
        try await Task.sleep(for: .milliseconds(160))
        let items = await MockSocialState.shared.savedExperiences(userID: userID).map { summary in
            var copy = summary
            copy.cityName = MockData.cities.first(where: { $0.id == summary.cityID })?.name
            return copy
        }
        return paginate(items, page: page)
    }

    func fetchCompletedExperiences(userID: UUID, page: Int) async throws -> Paginated<CompletedExperienceItem> {
        try await Task.sleep(for: .milliseconds(160))
        let items = await MockSocialState.shared.completedExperiences(userID: userID).map { item in
            var copy = item
            var experience = copy.experience
            experience.cityName = MockData.cities.first(where: { $0.id == experience.cityID })?.name
            copy.experience = experience
            return copy
        }
        return paginate(items, page: page)
    }

    private func paginate<T: Sendable>(_ items: [T], page: Int) -> Paginated<T> {
        let size = ProfileLimits.pageSize
        let start = page * size
        guard start < items.count else {
            return Paginated(items: [], page: page, hasMore: false)
        }
        let end = min(start + size, items.count)
        let slice = Array(items[start..<end])
        return Paginated(items: slice, page: page, hasMore: end < items.count)
    }
}

struct MockEngagementRepository: EngagementRepository {
    func fetchSavedIDs(userID: UUID) async throws -> Set<UUID> {
        await MockSocialState.shared.savedIDs(of: userID)
    }

    func fetchCompletedIDs(userID: UUID) async throws -> Set<UUID> {
        await MockSocialState.shared.completedIDs(of: userID)
    }

    func fetchFollowingIDs(userID: UUID) async throws -> Set<UUID> {
        await MockSocialState.shared.followingIDs(of: userID)
    }

    func isSaved(userID: UUID, experienceID: UUID) async throws -> Bool {
        await MockSocialState.shared.isSaved(userID: userID, experienceID: experienceID)
    }

    func isCompleted(userID: UUID, experienceID: UUID) async throws -> Bool {
        await MockSocialState.shared.isCompleted(userID: userID, experienceID: experienceID)
    }

    func toggleSave(userID: UUID, experienceID: UUID) async throws -> Bool {
        await MockSocialState.shared.toggleSave(userID: userID, experienceID: experienceID)
    }

    func unsave(userID: UUID, experienceID: UUID) async throws {
        if await MockSocialState.shared.isSaved(userID: userID, experienceID: experienceID) {
            _ = await MockSocialState.shared.toggleSave(userID: userID, experienceID: experienceID)
        }
    }

    func toggleComplete(userID: UUID, experienceID: UUID) async throws -> Bool {
        await MockSocialState.shared.toggleComplete(userID: userID, experienceID: experienceID)
    }

    func ensureExperienceExists(for summary: ExperienceSummary, ownerID: UUID) async throws {
        await MockSocialState.shared.ensureExperienceExists(for: summary, ownerID: ownerID)
    }
}

struct MockNotificationRepository: NotificationRepository {
    private static let pageSize = 30

    func fetchNotifications(userID: UUID, page: Int) async throws -> Paginated<AppNotification> {
        try await Task.sleep(for: .milliseconds(120))
        return await MockSocialState.shared.notifications(for: userID, page: page, pageSize: Self.pageSize)
    }

    func unreadCount(userID: UUID) async throws -> Int {
        await MockSocialState.shared.unreadCount(for: userID)
    }

    func markRead(ids: [UUID]) async throws {
        await MockSocialState.shared.markRead(ids: ids)
    }

    func markAllRead(userID: UUID) async throws {
        await MockSocialState.shared.markAllRead(userID: userID)
    }

    func observeInserts(userID: UUID) -> AsyncStream<AppNotification> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

enum RepositoryError: LocalizedError {
    case notFound
    case unauthorized
    case network

    var errorDescription: String? {
        switch self {
        case .notFound: "Content not found."
        case .unauthorized: "Please sign in to continue."
        case .network: "Check your connection and try again."
        }
    }
}
