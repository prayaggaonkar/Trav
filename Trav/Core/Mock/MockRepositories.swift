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

    func fetchCityStats(for city: City) async -> City {
        let matches = MockData.experiences.filter { exp in
            exp.cityID == city.id || (exp.cityName != nil && exp.cityName?.localizedCaseInsensitiveCompare(city.name) == .orderedSame)
        }
        let expCount = matches.count
        let creatorsCount = Set(matches.map { $0.creator.id }).count
        var updated = city
        updated.experienceCount = expCount
        updated.creatorCount = creatorsCount
        return updated
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
        if let cachedAppleMapsExp = AppleMapsVibeService.shared.cachedExperience(for: id) {
            return cachedAppleMapsExp
        }
        guard let summary = MockData.experiences.first(where: { $0.id == id }) else {
            throw RepositoryError.notFound
        }
        return MockData.fullExperience(for: summary)
    }

    func fetchCityFeed(cityID: UUID, page: Int) async throws -> Paginated<ExperienceSummary> {
        let items = MockData.experiences.filter { $0.cityID == cityID }
        return Paginated(items: items, page: page, hasMore: false)
    }

    func fetchHomeFeed(page: Int) async throws -> Paginated<ExperienceSummary> {
        try await Task.sleep(for: .milliseconds(180))
        return Paginated(items: page == 0 ? MockData.experiences : [], page: page, hasMore: false)
    }

    func fetchPlacesFeed(page: Int) async throws -> Paginated<ExperienceSummary> {
        Paginated(items: [], page: page, hasMore: false)
    }

    func fetchPopups(
        latitude: Double? = nil,
        longitude: Double? = nil,
        city: String? = nil
    ) async throws -> [Popup] {
        let targetCity = city ?? "Berkeley, CA"
        let cityShort = targetCity.components(separatedBy: ",").first ?? "Local"
        let now = Date()
        let todayEvening = Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: now)
        let tomorrowAfternoon = Calendar.current.date(byAdding: .day, value: 1, to: now).flatMap {
            Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: $0)
        }
        let day2Evening = Calendar.current.date(byAdding: .day, value: 2, to: now).flatMap {
            Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: $0)
        }
        let day3Morning = Calendar.current.date(byAdding: .day, value: 3, to: now).flatMap {
            Calendar.current.date(bySettingHour: 10, minute: 30, second: 0, of: $0)
        }

        return [
            Popup(
                name: "\(cityShort) Pickleball Open & Social",
                address: "Community Courts, \(targetCity)",
                city: targetCity,
                latitude: (latitude ?? 37.8715) + 0.005,
                longitude: (longitude ?? -122.2730) - 0.003,
                category: .sports,
                description: "Doubles tournament open to all skill levels! Grab a paddle, bring friends, and enjoy post-game refreshments.",
                startTime: tomorrowAfternoon,
                externalURL: URL(string: "https://eventbrite.com"),
                imageURL: URL(string: "https://images.unsplash.com/photo-1626248801379-51a0748a5f96?w=800&q=80"),
                source: "community",
                distanceMiles: 1.2
            ),
            Popup(
                name: "Sunset Live Acoustic Sessions",
                address: "Amphitheater Plaza, \(targetCity)",
                city: targetCity,
                latitude: (latitude ?? 37.8715) - 0.004,
                longitude: (longitude ?? -122.2730) + 0.006,
                category: .music,
                description: "Outdoor acoustic concert featuring regional indie bands, food trucks, and sunset views.",
                startTime: todayEvening,
                externalURL: URL(string: "https://ticketmaster.com"),
                imageURL: URL(string: "https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=800&q=80"),
                source: "ticketmaster",
                distanceMiles: 0.8
            ),
            Popup(
                name: "\(cityShort) Night Market & Street Food Rally",
                address: "Main St Promenade, \(targetCity)",
                city: targetCity,
                latitude: (latitude ?? 37.8715) + 0.002,
                longitude: (longitude ?? -122.2730) + 0.002,
                category: .food,
                description: "Over 20 local food trucks, craft boba, live DJ sets, and night market vendors.",
                startTime: day2Evening,
                externalURL: URL(string: "https://eventbrite.com"),
                imageURL: URL(string: "https://images.unsplash.com/photo-1533900298318-6b8da08a523e?w=800&q=80"),
                source: "eventbrite",
                distanceMiles: 2.1
            ),
            Popup(
                name: "Board Games, Craft Beer & Trivia Night",
                address: "Corner Taproom, \(targetCity)",
                city: targetCity,
                latitude: (latitude ?? 37.8715) - 0.008,
                longitude: (longitude ?? -122.2730) - 0.004,
                category: .meetups,
                description: "Bring friends or play solo! Hundreds of board games, team trivia with prizes, and local brews on tap.",
                startTime: day2Evening,
                externalURL: URL(string: "https://meetup.com"),
                imageURL: URL(string: "https://images.unsplash.com/photo-1529699211952-734e80c4d42b?w=800&q=80"),
                source: "meetup",
                distanceMiles: 1.5
            ),
            Popup(
                name: "\(cityShort) Morning Run Club & Coffee Social",
                address: "Town Square Fountain, \(targetCity)",
                city: targetCity,
                latitude: (latitude ?? 37.8715) + 0.010,
                longitude: (longitude ?? -122.2730) - 0.007,
                category: .sports,
                description: "Easy 3-mile casual jog followed by complimentary pour-over coffee and pastries with the crew.",
                startTime: day3Morning,
                externalURL: URL(string: "https://strava.com"),
                imageURL: URL(string: "https://images.unsplash.com/photo-1476480862126-209bfaa8edc8?w=800&q=80"),
                source: "community",
                distanceMiles: 3.0
            )
        ]
    }

    @discardableResult
    func publishExperience(_ draft: ExperienceDraft) async throws -> UUID {
        try draft.validateForPublishing()
        if await MockSocialState.shared.itineraryExists(stopKeys: draft.stopIdentityKeys) {
            throw ContentModelError.duplicateItinerary
        }
        try await Task.sleep(for: .milliseconds(500))
        let id = UUID()
        await MockSocialState.shared.registerItinerary(id: id, stopKeys: draft.stopIdentityKeys)
        await MockSocialState.shared.notifyNewExperience(creatorID: draft.creatorID, experienceID: id)
        return id
    }

    func updateExperience(id: UUID, draft: ExperienceDraft) async throws {
        try draft.validateForPublishing()
        try await Task.sleep(for: .milliseconds(300))
        NotificationCenter.default.post(name: Notification.Name("ExperienceUpdatedNotification"), object: nil)
        NotificationCenter.default.post(name: Notification.Name("ExperiencePublishedNotification"), object: nil)
    }

    func deleteExperience(id: UUID) async throws {
        try await Task.sleep(for: .milliseconds(300))
        NotificationCenter.default.post(name: Notification.Name("ExperienceDeletedNotification"), object: nil)
        NotificationCenter.default.post(name: Notification.Name("ExperiencePublishedNotification"), object: nil)
    }

    @discardableResult
    func syncSpot(_ request: SpotSyncRequest) async throws -> UUID {
        StableUUID.from(request.placeID ?? request.identityKey)
    }

    func fetchPersonalizedFeed(_ request: FeedRequest) async throws -> Paginated<ExperienceSummary> {
        try await Task.sleep(for: .milliseconds(180))
        guard request.page == 0 else {
            return Paginated(items: [], page: request.page, hasMore: false)
        }

        var items = MockData.experiences
        if let cityID = request.cityID {
            items = items.filter { $0.cityID == cityID }
        }
        if let kind = request.kind {
            items = items.filter { $0.kind == kind }
        }

        // A rough stand-in for the database engine: quality, then social proof.
        let ranked = items.sorted { lhs, rhs in
            let lScore = (lhs.ratingSummary.displayScore ?? 0) * 2
                + Double(lhs.completionCount) * 0.5 + Double(lhs.saveCount) * 0.2
            let rScore = (rhs.ratingSummary.displayScore ?? 0) * 2
                + Double(rhs.completionCount) * 0.5 + Double(rhs.saveCount) * 0.2
            return lScore > rScore
        }
        return Paginated(items: ranked, page: request.page, hasMore: false)
    }

    func searchExperiences(query: String, kind: ExperienceKind?, limit: Int) async throws -> [ExperienceSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count >= 2 else { return [] }
        var items = MockData.experiences.filter { $0.title.lowercased().contains(trimmed) }
        if let kind {
            items = items.filter { $0.kind == kind }
        }
        return Array(items.prefix(limit))
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

    func fetchLeaderboardEntries(cityID: UUID?, cityName: String?) async throws -> [LeaderboardEntry] {
        try await Task.sleep(for: .milliseconds(120))
        var entries = MockLeaderboardData.entries
        if let cityID {
            entries = entries.filter { $0.cityID == cityID }
        } else if let cityName, !cityName.isEmpty, cityName != LocationOption.allLocations.name {
            let lower = cityName.lowercased().components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? cityName.lowercased()
            entries = entries.filter { entry in
                guard let cName = entry.cityName?.lowercased() else { return false }
                return cName.contains(lower) || lower.contains(cName.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? lower)
            }
        }
        return entries
    }

    func fetchHeatStreakEntries(cityID: UUID?, cityName: String?) async throws -> [HeatStreakEntry] {
        try await Task.sleep(for: .milliseconds(120))
        return MockHeatStreakData.entries
    }

    func fetchImpactLeaderboard(cityID: UUID?, cityName: String?) async throws -> [ImpactEntry] {
        try await Task.sleep(for: .milliseconds(120))
        return MockImpactData.entries
    }

    func fetchMainLeaderboard(cityID: UUID?, cityName: String?) async throws -> [MainLeaderboardEntry] {
        try await Task.sleep(for: .milliseconds(120))
        return MockMainLeaderboardData.entries
    }

    func observeExperiencesInsert() -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.onTermination = { _ in }
        }
    }
}

struct MockAuthRepository: AuthRepository {
    func signIn(email: String, password: String) async throws -> Profile {
        let profile = try await MockSocialState.shared.profile(id: MockData.creators[0].id)
        return profile
    }

    @discardableResult
    func signUp(email: String, password: String) async throws -> Profile? {
        try await signIn(email: email, password: password)
    }

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

    func syncContactHashes(_ hashes: [ContactHash]) async throws {
        try await Task.sleep(for: .milliseconds(80))
        await MockSocialState.shared.syncContactHashes(hashes)
    }

    func fetchSuggestedUsers(limit: Int) async throws -> [SuggestedUser] {
        try await Task.sleep(for: .milliseconds(160))
        return await MockSocialState.shared.suggestedUsers(limit: limit)
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

    func removeCompletion(userID: UUID, experienceID: UUID) async throws {
        await MockSocialState.shared.removeRating(userID: userID, experienceID: experienceID)
    }

    func fetchLikedIDs(userID: UUID) async throws -> Set<UUID> {
        await MockSocialState.shared.likedIDs(of: userID)
    }

    func toggleLike(userID: UUID, experienceID: UUID) async throws -> Bool {
        await MockSocialState.shared.toggleLike(userID: userID, experienceID: experienceID)
    }

    func ensureExperienceExists(for summary: ExperienceSummary, ownerID: UUID) async throws {
        await MockSocialState.shared.ensureExperienceExists(for: summary, ownerID: ownerID)
    }

    func fetchComments(experienceID: UUID, page: Int) async throws -> Paginated<Comment> {
        try await Task.sleep(for: .milliseconds(150))
        return await MockSocialState.shared.comments(experienceID: experienceID, page: page)
    }

    func addComment(experienceID: UUID, authorID: UUID, body: String, parentID: UUID?) async throws -> Comment {
        try await MockSocialState.shared.addComment(
            experienceID: experienceID,
            authorID: authorID,
            body: body,
            parentID: parentID
        )
    }

    func deleteComment(id: UUID) async throws {
        await MockSocialState.shared.deleteComment(id: id)
    }

    func report(target: ReportTarget, reporterID: UUID, reason: ReportReason, details: String?) async throws {
        try await Task.sleep(for: .milliseconds(200))
    }

    func block(blockerID: UUID, blockedID: UUID) async throws {
        await MockSocialState.shared.block(blockerID: blockerID, blockedID: blockedID)
    }

    func unblock(blockerID: UUID, blockedID: UUID) async throws {
        await MockSocialState.shared.unblock(blockerID: blockerID, blockedID: blockedID)
    }

    func fetchBlockedIDs(userID: UUID) async throws -> Set<UUID> {
        await MockSocialState.shared.blockedIDs(of: userID)
    }
}

struct MockRatingRepository: RatingRepository {
    @discardableResult
    func submitRating(_ draft: RatingDraft, userID: UUID) async throws -> Rating {
        guard !draft.radar.scores.isEmpty else { throw ContentModelError.ratingRequired }
        guard draft.photosData.count <= RatingDraft.maxPhotos else {
            throw ContentModelError.tooManyPhotos(limit: RatingDraft.maxPhotos)
        }
        if await MockSocialState.shared.rating(userID: userID, experienceID: draft.experienceID) != nil {
            throw ContentModelError.alreadyRated
        }
        try await Task.sleep(for: .milliseconds(320))
        return await MockSocialState.shared.submitRating(draft, userID: userID)
    }

    func fetchMyRating(userID: UUID, experienceID: UUID) async throws -> Rating? {
        await MockSocialState.shared.rating(userID: userID, experienceID: experienceID)
    }

    func fetchRatings(experienceID: UUID, page: Int) async throws -> Paginated<Rating> {
        try await Task.sleep(for: .milliseconds(140))
        return await MockSocialState.shared.ratings(experienceID: experienceID, page: page)
    }

    func fetchRatingSummary(experienceID: UUID) async throws -> RatingSummary {
        await MockSocialState.shared.ratingSummary(experienceID: experienceID)
    }

    func deleteRating(userID: UUID, experienceID: UUID) async throws {
        await MockSocialState.shared.removeRating(userID: userID, experienceID: experienceID)
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

    func deleteNotification(id: UUID) async throws {
        await MockSocialState.shared.deleteNotification(id: id)
    }

    func observeInserts(userID: UUID) -> AsyncStream<AppNotification> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func registerDeviceToken(_ token: String, userID: UUID) async throws {}

    func unregisterDeviceToken(_ token: String) async throws {}
}

