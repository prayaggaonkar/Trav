import Foundation

/// In-memory social graph used by mock repositories so saves/follows persist across screens.
actor MockSocialState {
    static let shared = MockSocialState()

    private var profiles: [UUID: Profile] = [:]
    private var follows: Set<FollowEdge> = []
    private var saves: Set<SaveEdge> = []
    private var likes: Set<SaveEdge> = []
    private var completions: [CompletionEdge] = []
    private var commentsStore: [Comment] = []
    private var blocks: Set<FollowEdge> = []
    private var notifications: [AppNotification] = []
    /// Extra summaries (e.g. bookmarked feed places) not present in MockData.experiences.
    private var bookmarkedSummaries: [UUID: ExperienceSummary] = [:]
    private var contactHashes: [UUID: Set<ContactHash>] = [:]
    private var didSeed = false

    struct FollowEdge: Hashable, Sendable {
        let followerID: UUID
        let followingID: UUID
    }

    struct SaveEdge: Hashable, Sendable {
        let userID: UUID
        let experienceID: UUID
    }

    struct CompletionEdge: Hashable, Sendable {
        let id: UUID
        let userID: UUID
        let experienceID: UUID
        let completedAt: Date
        let note: String?
    }

    func seedIfNeeded() {
        guard !didSeed else { return }
        didSeed = true

        for creator in MockData.creators {
            var profile = MockData.profile(for: creator)
            // Seed some follows among creators.
            profiles[profile.id] = profile
        }

        // Seed initial follows for demo user (maya follows jordan; jordan follows maya).
        _ = try? follow(followerID: MockData.creators[0].id, followingID: MockData.creators[1].id)
        _ = try? follow(followerID: MockData.creators[1].id, followingID: MockData.creators[0].id)
        // Additional mock creator follows for mutual path testing.
        _ = try? follow(followerID: MockData.creators[1].id, followingID: MockData.creators[3].id)
        _ = try? follow(followerID: MockData.creators[2].id, followingID: MockData.creators[3].id)
        if MockData.creators.count > 4 {
            _ = try? follow(followerID: MockData.creators[1].id, followingID: MockData.creators[4].id)
        }
        if MockData.creators.count > 5 {
            _ = try? follow(followerID: MockData.creators[2].id, followingID: MockData.creators[5].id)
        }

        // Seed a few contact-hash matches so "From your contacts" shows in mock.
        let sharedEmail = ContactSyncService.hashEmail("friend@trav.app")
        if let sharedEmail {
            contactHashes[MockData.creators[0].id] = [sharedEmail]
            contactHashes[MockData.creators[4].id, default: []].insert(sharedEmail)
        }
        let demoUser = MockData.creators[0].id
        saves.insert(SaveEdge(userID: demoUser, experienceID: MockData.experiences[1].id))
        saves.insert(SaveEdge(userID: demoUser, experienceID: MockData.experiences[3].id))
        completions.append(CompletionEdge(
            id: UUID(),
            userID: demoUser,
            experienceID: MockData.experiences[0].id,
            completedAt: Date().addingTimeInterval(-86400 * 3),
            note: nil
        ))
        completions.append(CompletionEdge(
            id: UUID(),
            userID: demoUser,
            experienceID: MockData.experiences[4].id,
            completedAt: Date().addingTimeInterval(-86400 * 10),
            note: nil
        ))

        // Seed inbox items for the demo user (maya).
        if let jordan = profiles[MockData.creators[1].id]?.summary,
           let sam = profiles[MockData.creators[2].id]?.summary {
            appendNotification(
                recipientID: demoUser,
                actor: jordan,
                type: .follow,
                referenceID: jordan.id,
                createdAt: Date().addingTimeInterval(-3600 * 2),
                isRead: false
            )
            appendNotification(
                recipientID: demoUser,
                actor: sam,
                type: .save,
                referenceID: MockData.experiences[0].id,
                createdAt: Date().addingTimeInterval(-3600 * 5),
                isRead: false
            )
            appendNotification(
                recipientID: demoUser,
                actor: jordan,
                type: .newExperience,
                referenceID: MockData.experiences[1].id,
                createdAt: Date().addingTimeInterval(-86400),
                isRead: true
            )
        }

        recalculateCounts()
    }

    func profile(username: String) throws -> Profile {
        seedIfNeeded()
        let key = username.lowercased()
        if let match = profiles.values.first(where: { $0.username.lowercased() == key }) {
            return match
        }
        throw RepositoryError.notFound
    }

    func profile(id: UUID) throws -> Profile {
        seedIfNeeded()
        if let match = profiles[id] { return match }
        throw RepositoryError.notFound
    }

    func upsert(_ profile: Profile) {
        seedIfNeeded()
        profiles[profile.id] = profile
    }

    func update(userID: UUID, update: ProfileUpdate) throws -> Profile {
        seedIfNeeded()
        guard var profile = profiles[userID] else { throw RepositoryError.notFound }

        if let displayName = update.displayName {
            profile.displayName = displayName
        }
        if let username = update.username {
            let normalized = UsernameValidator.normalize(username)
            if profiles.values.contains(where: { $0.id != userID && $0.username.lowercased() == normalized }) {
                throw RepositoryError.unauthorized
            }
            profile.username = normalized
        }
        if update.clearBio {
            profile.bio = nil
        } else if let bio = update.bio {
            profile.bio = bio
        }
        if update.clearHomeCity {
            profile.homeCityName = nil
            profile.onboardingLocation = nil
        } else if let homeCityName = update.homeCityName {
            profile.homeCityName = homeCityName
            profile.onboardingLocation = homeCityName
        }
        if update.clearAvatar {
            profile.avatarURL = nil
        } else if let avatarURL = update.avatarURL {
            profile.avatarURL = avatarURL
        }

        profiles[userID] = profile
        return profile
    }

    func isUsernameAvailable(_ username: String, excludingUserID: UUID?) -> UsernameAvailability {
        seedIfNeeded()
        let format = UsernameValidator.validateFormat(username)
        if case .invalid = format { return format }
        let normalized = UsernameValidator.normalize(username)
        if profiles.values.contains(where: { $0.id != excludingUserID && $0.username.lowercased() == normalized }) {
            return .unavailable(reason: "That username is taken.")
        }
        return .available
    }

    func follow(followerID: UUID, followingID: UUID) throws {
        seedIfNeeded()
        guard followerID != followingID else { return }
        let edge = FollowEdge(followerID: followerID, followingID: followingID)
        guard !follows.contains(edge) else { return }
        follows.insert(edge)
        recalculateCounts()
        if let actor = profiles[followerID]?.summary {
            appendNotification(
                recipientID: followingID,
                actor: actor,
                type: .follow,
                referenceID: followerID,
                createdAt: Date(),
                isRead: false
            )
        }
    }

    func unfollow(followerID: UUID, followingID: UUID) {
        seedIfNeeded()
        follows.remove(FollowEdge(followerID: followerID, followingID: followingID))
        recalculateCounts()
    }

    func isFollowing(followerID: UUID, followingID: UUID) -> Bool {
        seedIfNeeded()
        return follows.contains(FollowEdge(followerID: followerID, followingID: followingID))
    }

    func followers(of userID: UUID) -> [ProfileSummary] {
        seedIfNeeded()
        return follows
            .filter { $0.followingID == userID }
            .compactMap { profiles[$0.followerID]?.summary }
    }

    func following(of userID: UUID) -> [ProfileSummary] {
        seedIfNeeded()
        return follows
            .filter { $0.followerID == userID }
            .compactMap { profiles[$0.followingID]?.summary }
    }

    func followingIDs(of userID: UUID) -> Set<UUID> {
        seedIfNeeded()
        return Set(follows.filter { $0.followerID == userID }.map(\.followingID))
    }

    func syncContactHashes(_ hashes: [ContactHash]) {
        seedIfNeeded()
        // Mock sync is scoped to the demo signed-in user (maya).
        let demoUser = MockData.creators[0].id
        contactHashes[demoUser] = Set(hashes)
    }

    func suggestedUsers(limit: Int, for userID: UUID? = nil) -> [SuggestedUser] {
        seedIfNeeded()
        let viewerID = userID ?? MockData.creators[0].id
        let following = followingIDs(of: viewerID)
        let blocked = blockedIDs(of: viewerID)

        let myHashes = contactHashes[viewerID] ?? []
        var contactIDs = Set<UUID>()
        if !myHashes.isEmpty {
            for (otherID, hashes) in contactHashes where otherID != viewerID {
                if !hashes.isDisjoint(with: myHashes) {
                    contactIDs.insert(otherID)
                }
            }
        }

        var mutualMeta: [UUID: (count: Int, name: String)] = [:]
        for followEdge in follows where followEdge.followerID == viewerID {
            let friendID = followEdge.followingID
            let friendName = profiles[friendID]?.displayName ?? "Someone"
            for second in follows where second.followerID == friendID {
                let candidate = second.followingID
                guard candidate != viewerID,
                      !following.contains(candidate),
                      !blocked.contains(candidate) else { continue }
                if let existing = mutualMeta[candidate] {
                    mutualMeta[candidate] = (existing.count + 1, existing.name)
                } else {
                    mutualMeta[candidate] = (1, friendName)
                }
            }
        }

        var results: [SuggestedUser] = []
        var seen = Set<UUID>()

        func append(_ id: UUID, source: SuggestedUserSource) {
            guard id != viewerID,
                  !following.contains(id),
                  !blocked.contains(id),
                  seen.insert(id).inserted,
                  var profile = profiles[id] else { return }
            profile.isFollowing = false
            let mutual = mutualMeta[id]
            results.append(
                SuggestedUser(
                    profile: profile,
                    source: source,
                    mutualCount: mutual?.count ?? 0,
                    sampleMutualName: mutual?.name
                )
            )
        }

        for id in contactIDs.sorted(by: { (profiles[$0]?.followerCount ?? 0) > (profiles[$1]?.followerCount ?? 0) }) {
            append(id, source: .contact)
        }
        let mutualSorted = mutualMeta.keys.sorted {
            let lhs = mutualMeta[$0]!
            let rhs = mutualMeta[$1]!
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return (profiles[$0]?.followerCount ?? 0) > (profiles[$1]?.followerCount ?? 0)
        }
        for id in mutualSorted {
            append(id, source: .mutual)
        }
        let popular = profiles.values
            .filter { $0.id != viewerID && !following.contains($0.id) && !blocked.contains($0.id) }
            .sorted { $0.followerCount > $1.followerCount }
        for profile in popular {
            append(profile.id, source: .popular)
        }

        return Array(results.prefix(limit))
    }

    func savedIDs(of userID: UUID) -> Set<UUID> {
        seedIfNeeded()
        return Set(saves.filter { $0.userID == userID }.map(\.experienceID))
    }

    func completedIDs(of userID: UUID) -> Set<UUID> {
        seedIfNeeded()
        return Set(completions.filter { $0.userID == userID }.map(\.experienceID))
    }

    func toggleSave(userID: UUID, experienceID: UUID) -> Bool {
        seedIfNeeded()
        let edge = SaveEdge(userID: userID, experienceID: experienceID)
        if saves.contains(edge) {
            saves.remove(edge)
            return false
        }
        saves.insert(edge)
        if let ownerID = experienceOwnerID(experienceID),
           ownerID != userID,
           let actor = profiles[userID]?.summary {
            appendNotification(
                recipientID: ownerID,
                actor: actor,
                type: .save,
                referenceID: experienceID,
                createdAt: Date(),
                isRead: false
            )
        }
        return true
    }

    func toggleComplete(userID: UUID, experienceID: UUID) -> Bool {
        seedIfNeeded()
        if let index = completions.firstIndex(where: { $0.userID == userID && $0.experienceID == experienceID }) {
            completions.remove(at: index)
            recalculateCounts()
            return false
        }
        completions.append(CompletionEdge(
            id: UUID(),
            userID: userID,
            experienceID: experienceID,
            completedAt: Date(),
            note: nil
        ))
        recalculateCounts()
        notifyWatchlistExperience(actorID: userID, experienceID: experienceID)
        return true
    }

    func isSaved(userID: UUID, experienceID: UUID) -> Bool {
        seedIfNeeded()
        return saves.contains(SaveEdge(userID: userID, experienceID: experienceID))
    }

    func likedIDs(of userID: UUID) -> Set<UUID> {
        seedIfNeeded()
        return Set(likes.filter { $0.userID == userID }.map(\.experienceID))
    }

    func toggleLike(userID: UUID, experienceID: UUID) -> Bool {
        seedIfNeeded()
        let edge = SaveEdge(userID: userID, experienceID: experienceID)
        if likes.contains(edge) {
            likes.remove(edge)
            return false
        }
        likes.insert(edge)
        if let ownerID = experienceOwnerID(experienceID),
           ownerID != userID,
           let actor = profiles[userID]?.summary {
            appendNotification(
                recipientID: ownerID,
                actor: actor,
                type: .like,
                referenceID: experienceID,
                createdAt: Date(),
                isRead: false
            )
        }
        return true
    }

    func comments(experienceID: UUID, page: Int) -> Paginated<Comment> {
        seedIfNeeded()
        let all = commentsStore
            .filter { $0.experienceID == experienceID }
            .sorted { $0.createdAt > $1.createdAt }
        let size = CommentLimits.pageSize
        let start = page * size
        guard start < all.count else {
            return Paginated(items: [], page: page, hasMore: false)
        }
        let end = min(start + size, all.count)
        return Paginated(items: Array(all[start..<end]), page: page, hasMore: end < all.count)
    }

    func addComment(experienceID: UUID, authorID: UUID, body: String, parentID: UUID?) throws -> Comment {
        seedIfNeeded()
        guard let author = profiles[authorID]?.summary else {
            throw RepositoryError.notFound
        }
        let comment = Comment(
            id: UUID(),
            experienceID: experienceID,
            author: author,
            parentID: parentID,
            body: body,
            createdAt: Date()
        )
        commentsStore.append(comment)
        if let ownerID = experienceOwnerID(experienceID), ownerID != authorID {
            appendNotification(
                recipientID: ownerID,
                actor: author,
                type: .comment,
                referenceID: experienceID,
                createdAt: Date(),
                isRead: false
            )
        }
        return comment
    }

    func deleteComment(id: UUID) {
        seedIfNeeded()
        commentsStore.removeAll { $0.id == id }
    }

    func block(blockerID: UUID, blockedID: UUID) {
        seedIfNeeded()
        blocks.insert(FollowEdge(followerID: blockerID, followingID: blockedID))
        follows.remove(FollowEdge(followerID: blockerID, followingID: blockedID))
        follows.remove(FollowEdge(followerID: blockedID, followingID: blockerID))
        recalculateCounts()
    }

    func unblock(blockerID: UUID, blockedID: UUID) {
        seedIfNeeded()
        blocks.remove(FollowEdge(followerID: blockerID, followingID: blockedID))
    }

    func blockedIDs(of userID: UUID) -> Set<UUID> {
        seedIfNeeded()
        return Set(blocks.filter { $0.followerID == userID }.map(\.followingID))
    }

    func isCompleted(userID: UUID, experienceID: UUID) -> Bool {
        seedIfNeeded()
        return completions.contains { $0.userID == userID && $0.experienceID == experienceID }
    }

    func ensureExperienceExists(for summary: ExperienceSummary, ownerID: UUID) {
        seedIfNeeded()
        if MockData.experiences.contains(where: { $0.id == summary.id }) { return }
        if bookmarkedSummaries[summary.id] != nil { return }
        var copy = summary
        // Keep creator as the bookmarking user for mock ownership checks.
        copy.creator = ProfileSummary(
            id: ownerID,
            username: copy.creator.username,
            displayName: copy.creator.displayName,
            avatarURL: copy.creator.avatarURL,
            isVerified: copy.creator.isVerified
        )
        bookmarkedSummaries[summary.id] = copy
    }

    func savedExperiences(userID: UUID) -> [ExperienceSummary] {
        seedIfNeeded()
        let ids = savedIDs(of: userID)
        let fromMock = MockData.experiences.filter { ids.contains($0.id) }
        let fromBookmarks = ids.compactMap { bookmarkedSummaries[$0] }
        var seen = Set<UUID>()
        return (fromBookmarks + fromMock).filter { seen.insert($0.id).inserted }
    }

    func completedExperiences(userID: UUID) -> [CompletedExperienceItem] {
        seedIfNeeded()
        return completions
            .filter { $0.userID == userID }
            .sorted { $0.completedAt > $1.completedAt }
            .compactMap { edge in
                guard let experience = MockData.experiences.first(where: { $0.id == edge.experienceID }) else { return nil }
                return CompletedExperienceItem(
                    id: edge.id,
                    experience: experience,
                    completedAt: edge.completedAt,
                    note: edge.note
                )
            }
    }

    func createdExperiences(userID: UUID) -> [ExperienceSummary] {
        seedIfNeeded()
        return MockData.experiences.filter { $0.creator.id == userID }
    }

    /// Fan-out: notify everyone who follows `creatorID` about a new experience.
    func notifyNewExperience(creatorID: UUID, experienceID: UUID) {
        seedIfNeeded()
        guard let actor = profiles[creatorID]?.summary else { return }
        let recipients = follows
            .filter { $0.followingID == creatorID }
            .map(\.followerID)
        for recipientID in recipients where recipientID != creatorID {
            appendNotification(
                recipientID: recipientID,
                actor: actor,
                type: .newExperience,
                referenceID: experienceID,
                createdAt: Date(),
                isRead: false
            )
        }
    }

    /// Fan-out: notify everyone who follows `actorID` about a watchlisted experience.
    func notifyWatchlistExperience(actorID: UUID, experienceID: UUID) {
        seedIfNeeded()
        guard let actor = profiles[actorID]?.summary else { return }
        let recipients = follows
            .filter { $0.followingID == actorID }
            .map(\.followerID)
        for recipientID in recipients where recipientID != actorID {
            appendNotification(
                recipientID: recipientID,
                actor: actor,
                type: .watchlist,
                referenceID: experienceID,
                createdAt: Date(),
                isRead: false
            )
        }
    }

    func notifications(for userID: UUID, page: Int, pageSize: Int) -> Paginated<AppNotification> {
        seedIfNeeded()
        let sorted = notifications
            .filter { $0.userID == userID }
            .sorted { $0.createdAt > $1.createdAt }
        
        let items = sorted.map { item -> AppNotification in
            var copy = item
            if let refID = item.referenceID, item.type == .watchlist || item.type == .newExperience {
                copy.experienceTitle = MockData.experiences.first { $0.id == refID }?.title
            }
            return copy
        }
        
        let start = page * pageSize
        guard start < items.count else {
            return Paginated(items: [], page: page, hasMore: false)
        }
        let end = min(start + pageSize, items.count)
        return Paginated(items: Array(items[start..<end]), page: page, hasMore: end < items.count)
    }

    func unreadCount(for userID: UUID) -> Int {
        seedIfNeeded()
        return notifications.filter { $0.userID == userID && !$0.isRead }.count
    }

    func markRead(ids: [UUID]) {
        seedIfNeeded()
        let idSet = Set(ids)
        for index in notifications.indices where idSet.contains(notifications[index].id) {
            notifications[index].isRead = true
        }
    }

    func markAllRead(userID: UUID) {
        seedIfNeeded()
        for index in notifications.indices where notifications[index].userID == userID {
            notifications[index].isRead = true
        }
    }

    func deleteNotification(id: UUID) {
        seedIfNeeded()
        notifications.removeAll { $0.id == id }
    }

    private func experienceOwnerID(_ experienceID: UUID) -> UUID? {
        if let summary = MockData.experiences.first(where: { $0.id == experienceID }) {
            return summary.creator.id
        }
        return bookmarkedSummaries[experienceID]?.creator.id
    }

    private func appendNotification(
        recipientID: UUID,
        actor: ProfileSummary,
        type: AppNotificationType,
        referenceID: UUID?,
        createdAt: Date,
        isRead: Bool
    ) {
        guard recipientID != actor.id else { return }
        notifications.append(
            AppNotification(
                id: UUID(),
                userID: recipientID,
                actor: actor,
                type: type,
                referenceID: referenceID,
                isRead: isRead,
                createdAt: createdAt
            )
        )
    }

    private func recalculateCounts() {
        for id in profiles.keys {
            var profile = profiles[id]!
            profile.followerCount = follows.filter { $0.followingID == id }.count
            profile.followingCount = follows.filter { $0.followerID == id }.count
            profile.experienceCount = MockData.experiences.filter { $0.creator.id == id }.count
            profile.completionCount = completions.filter { $0.userID == id }.count
            profiles[id] = profile
        }
    }
}
