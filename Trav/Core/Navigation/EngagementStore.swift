import Foundation
import Observation
import UIKit

/// App-wide engagement + social graph state. Optimistic updates keep City, Experience,
/// Feed, and Profile screens in sync without a restart.
@Observable
@MainActor
final class EngagementStore {
    private(set) var savedExperienceIDs: Set<UUID> = []
    private(set) var completedExperienceIDs: Set<UUID> = []
    private(set) var likedExperienceIDs: Set<UUID> = []
    private(set) var followingUserIDs: Set<UUID> = []
    private(set) var unfollowedUserIDs: Set<UUID> = []
    private(set) var blockedUserIDs: Set<UUID> = []
    /// Latest known profiles keyed by id — refreshed after edits / follows.
    private(set) var profileCache: [UUID: Profile] = [:]
    private(set) var profileCacheByUsername: [String: Profile] = [:]
    /// Cached summaries for optimistic Profile Saved rendering before refetch completes.
    private(set) var savedSummaries: [UUID: ExperienceSummary] = [:]
    /// Bumped whenever lists or counts change so observing views can refresh.
    private(set) var revision: Int = 0
    /// Surfaces the last save error for debugging / lightweight UI.
    private(set) var lastSaveError: String?

    private(set) var bootstrappedUserID: UUID?
    private var inFlightSaveIDs: Set<UUID> = []
    private var inFlightCompleteIDs: Set<UUID> = []
    private var inFlightLikeIDs: Set<UUID> = []
    private var bootstrapTask: Task<Void, Never>?

    func reset() {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        savedExperienceIDs = []
        completedExperienceIDs = []
        likedExperienceIDs = []
        followingUserIDs = []
        unfollowedUserIDs = []
        blockedUserIDs = []
        profileCache = [:]
        profileCacheByUsername = [:]
        savedSummaries = [:]
        bootstrappedUserID = nil
        inFlightSaveIDs = []
        inFlightCompleteIDs = []
        inFlightLikeIDs = []
        lastSaveError = nil
        bump()
    }

    func hasExplicitlyUnfollowed(_ userID: UUID) -> Bool {
        unfollowedUserIDs.contains(userID)
    }

    func seedFollowingIDs(_ ids: [UUID]) {
        for id in ids {
            if !unfollowedUserIDs.contains(id) {
                followingUserIDs.insert(id)
            }
        }
        bump()
    }

    func seedSavedIDs(_ ids: [UUID]) {
        for id in ids {
            savedExperienceIDs.insert(id)
        }
        bump()
    }

    func refreshBootstrap(userID: UUID, using environment: AppEnvironment) async {
        bootstrappedUserID = nil
        await bootstrap(userID: userID, using: environment)
    }

    func bootstrap(userID: UUID, using environment: AppEnvironment) async {
        if bootstrappedUserID == userID { return }
        if let bootstrapTask {
            await bootstrapTask.value
            if bootstrappedUserID == userID { return }
        }

        let task = Task { @MainActor in
            do {
                async let saved = environment.engagementRepo.fetchSavedIDs(userID: userID)
                async let completed = environment.engagementRepo.fetchCompletedIDs(userID: userID)
                async let liked = environment.engagementRepo.fetchLikedIDs(userID: userID)
                async let following = environment.engagementRepo.fetchFollowingIDs(userID: userID)
                async let blocked = environment.engagementRepo.fetchBlockedIDs(userID: userID)
                let remoteSaved = try await saved
                let remoteCompleted = try await completed
                let remoteLiked = try await liked
                let remoteFollowing = try await following
                let remoteBlocked = try await blocked

                // Merge — never wipe optimistic toggles that happened during the fetch.
                savedExperienceIDs.formUnion(remoteSaved)
                completedExperienceIDs.formUnion(remoteCompleted)
                likedExperienceIDs.formUnion(remoteLiked)
                followingUserIDs.formUnion(remoteFollowing)
                blockedUserIDs = remoteBlocked
                bootstrappedUserID = userID
                bump()
            } catch {
                TravLog.engagement.error("bootstrap failed: \(error.localizedDescription, privacy: .public)")
                // Allow retry on next screen appear.
            }
        }
        bootstrapTask = task
        await task.value
        bootstrapTask = nil
    }

    func cache(_ profile: Profile) {
        let isStub = profile.bio == nil && profile.homeCityName == nil && profile.experienceCount == 0 && profile.followerCount == 0 && profile.followingCount == 0

        if var existing = profileCache[profile.id] {
            if isStub {
                let oldFollowing = existing.isFollowing ?? followingUserIDs.contains(profile.id)
                let newFollowing = profile.isFollowing ?? followingUserIDs.contains(profile.id)
                if oldFollowing != newFollowing {
                    if newFollowing {
                        existing.followerCount += 1
                    } else {
                        existing.followerCount = max(0, existing.followerCount - 1)
                    }
                }
                existing.isFollowing = newFollowing
            } else {
                var updated = profile
                if updated.isFollowing == nil {
                    updated.isFollowing = existing.isFollowing ?? followingUserIDs.contains(profile.id)
                }
                existing = updated
            }
            profileCache[profile.id] = existing
            profileCacheByUsername[existing.username.lowercased()] = existing
        } else if !isStub {
            var full = profile
            if full.isFollowing == nil {
                full.isFollowing = followingUserIDs.contains(profile.id)
            }
            profileCache[profile.id] = full
            profileCacheByUsername[full.username.lowercased()] = full
        }
        bump()
    }

    func cachedProfile(username: String) -> Profile? {
        profileCacheByUsername[username.lowercased()]
    }

    /// Increments the logged-in user's follower count and triggers real-time UI updates when a follow notification arrives.
    func handleFollowNotification(notification: AppNotification, using environment: AppEnvironment) {
        guard let currentUserID = environment.session.currentUser?.id,
              notification.userID == currentUserID,
              notification.type == .follow else { return }

        if var me = environment.session.currentUser {
            me.followerCount += 1
            environment.session.currentUser = me
            cache(me)
        } else if var cached = profileCache[currentUserID] {
            cached.followerCount += 1
            cache(cached)
        } else {
            bump()
        }
    }

    /// Decrements the logged-in user's follower count and triggers real-time UI updates when someone unfollows.
    func handleUnfollowEvent(followerID: UUID, followingID: UUID, using environment: AppEnvironment) {
        guard let currentUserID = environment.session.currentUser?.id,
              followingID == currentUserID else { return }

        if var me = environment.session.currentUser {
            me.followerCount = max(0, me.followerCount - 1)
            environment.session.currentUser = me
            cache(me)
        } else if var cached = profileCache[currentUserID] {
            cached.followerCount = max(0, cached.followerCount - 1)
            cache(cached)
        } else {
            bump()
        }
    }

    func cachedSummary(for experienceID: UUID) -> ExperienceSummary? {
        savedSummaries[experienceID]
    }

    func isSaved(_ experienceID: UUID) -> Bool {
        savedExperienceIDs.contains(experienceID)
    }

    func isCompleted(_ experienceID: UUID) -> Bool {
        completedExperienceIDs.contains(experienceID)
    }

    func isLiked(_ experienceID: UUID) -> Bool {
        likedExperienceIDs.contains(experienceID)
    }

    func isFollowing(_ userID: UUID) -> Bool {
        followingUserIDs.contains(userID)
    }

    func isBlocked(_ userID: UUID) -> Bool {
        blockedUserIDs.contains(userID)
    }

    /// Optimistic like toggle. Returns the resolved liked state.
    @discardableResult
    func toggleLike(
        experienceID: UUID,
        summary: ExperienceSummary? = nil,
        using environment: AppEnvironment
    ) async -> Bool {
        guard let userID = environment.session.currentUser?.id else {
            environment.router.presentAuth()
            return false
        }
        guard !inFlightLikeIDs.contains(experienceID) else {
            return likedExperienceIDs.contains(experienceID)
        }
        inFlightLikeIDs.insert(experienceID)
        defer { inFlightLikeIDs.remove(experienceID) }

        let wasLiked = likedExperienceIDs.contains(experienceID)
        if wasLiked {
            likedExperienceIDs.remove(experienceID)
        } else {
            likedExperienceIDs.insert(experienceID)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        bump()

        do {
            if !wasLiked, let summary {
                try await environment.engagementRepo.ensureExperienceExists(for: summary, ownerID: userID)
            }
            let nowLiked = try await environment.engagementRepo.toggleLike(userID: userID, experienceID: experienceID)
            if nowLiked {
                likedExperienceIDs.insert(experienceID)
            } else {
                likedExperienceIDs.remove(experienceID)
            }
            bump()
            return nowLiked
        } catch {
            TravLog.engagement.error("toggleLike failed: \(error.localizedDescription, privacy: .public)")
            if wasLiked {
                likedExperienceIDs.insert(experienceID)
            } else {
                likedExperienceIDs.remove(experienceID)
            }
            bump()
            return wasLiked
        }
    }

    /// Blocks a user and removes them from local social state.
    func block(userID targetID: UUID, using environment: AppEnvironment) async -> Bool {
        guard let userID = environment.session.currentUser?.id, userID != targetID else { return false }
        blockedUserIDs.insert(targetID)
        followingUserIDs.remove(targetID)
        bump()
        do {
            try await environment.engagementRepo.block(blockerID: userID, blockedID: targetID)
            return true
        } catch {
            blockedUserIDs.remove(targetID)
            bump()
            return false
        }
    }

    func unblock(userID targetID: UUID, using environment: AppEnvironment) async {
        guard let userID = environment.session.currentUser?.id else { return }
        blockedUserIDs.remove(targetID)
        bump()
        try? await environment.engagementRepo.unblock(blockerID: userID, blockedID: targetID)
    }

    @discardableResult
    func toggleSave(
        experienceID: UUID,
        summary: ExperienceSummary? = nil,
        using environment: AppEnvironment
    ) async -> Bool {
        guard let userID = environment.session.currentUser?.id else {
            environment.router.presentAuth()
            return false
        }
        // Prevent double-taps / stacked Tasks from immediately undoing a save.
        guard !inFlightSaveIDs.contains(experienceID) else {
            return savedExperienceIDs.contains(experienceID)
        }
        inFlightSaveIDs.insert(experienceID)
        defer { inFlightSaveIDs.remove(experienceID) }

        let wasSaved = savedExperienceIDs.contains(experienceID)
        applyLocalSaveState(experienceID: experienceID, saved: !wasSaved, summary: summary)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        do {
            if !wasSaved, let summary {
                try await environment.engagementRepo.ensureExperienceExists(for: summary, ownerID: userID)
            }
            let nowSaved = try await environment.engagementRepo.toggleSave(
                userID: userID,
                experienceID: experienceID
            )
            applyLocalSaveState(experienceID: experienceID, saved: nowSaved, summary: summary)
            lastSaveError = nil
            return nowSaved
        } catch {
            // Keep the optimistic bookmark visible — legacy dual-write / retry paths may
            // still have persisted. Only revert when the server explicitly reports the
            // opposite state on a follow-up read.
            TravLog.engagement.error("toggleSave failed: \(error.localizedDescription, privacy: .public)")
            lastSaveError = error.localizedDescription

            if let confirmed = try? await environment.engagementRepo.isSaved(
                userID: userID,
                experienceID: experienceID
            ) {
                applyLocalSaveState(experienceID: experienceID, saved: confirmed, summary: summary)
                return confirmed
            }

            // Soft-fail: trust optimistic local state so the UI does not flash unsaved.
            return !wasSaved
        }
    }

    /// Always removes a bookmark (used by Profile Saved swipe-to-unsave).
    func unsave(experienceID: UUID, using environment: AppEnvironment) async {
        guard let userID = environment.session.currentUser?.id else {
            environment.router.presentAuth()
            return
        }
        guard !inFlightSaveIDs.contains(experienceID) else { return }
        inFlightSaveIDs.insert(experienceID)
        defer { inFlightSaveIDs.remove(experienceID) }

        applyLocalSaveState(experienceID: experienceID, saved: false, summary: nil)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        do {
            try await environment.engagementRepo.unsave(userID: userID, experienceID: experienceID)
            lastSaveError = nil
        } catch {
            TravLog.engagement.error("unsave failed: \(error.localizedDescription, privacy: .public)")
            lastSaveError = error.localizedDescription
            // Keep local unsaved — swipe already removed from the list.
        }
    }

    @discardableResult
    func toggleComplete(
        experienceID: UUID,
        summary: ExperienceSummary? = nil,
        note: String? = nil,
        photosData: [Data] = [],
        using environment: AppEnvironment
    ) async -> Bool {
        guard let userID = environment.session.currentUser?.id else {
            environment.router.presentAuth()
            return false
        }
        // Prevent double-taps from desyncing local and remote completion state.
        guard !inFlightCompleteIDs.contains(experienceID) else {
            return completedExperienceIDs.contains(experienceID)
        }
        inFlightCompleteIDs.insert(experienceID)
        defer { inFlightCompleteIDs.remove(experienceID) }

        let wasCompleted = completedExperienceIDs.contains(experienceID)
        if wasCompleted {
            completedExperienceIDs.remove(experienceID)
            if var user = environment.session.currentUser {
                user.completionCount = max(0, user.completionCount - 1)
                environment.session.currentUser = user
                cache(user)
            }
        } else {
            completedExperienceIDs.insert(experienceID)
            if var user = environment.session.currentUser {
                user.completionCount += 1
                environment.session.currentUser = user
                cache(user)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        bump()

        do {
            if !wasCompleted, let summary {
                try await environment.engagementRepo.ensureExperienceExists(for: summary, ownerID: userID)
            }
            let nowCompleted = try await environment.engagementRepo.toggleComplete(
                userID: userID,
                experienceID: experienceID,
                note: note,
                photosData: photosData
            )
            if nowCompleted {
                completedExperienceIDs.insert(experienceID)
            } else {
                completedExperienceIDs.remove(experienceID)
            }
            bump()
            return nowCompleted
        } catch {
            TravLog.engagement.error("toggleComplete failed: \(error.localizedDescription, privacy: .public)")
            if wasCompleted {
                completedExperienceIDs.insert(experienceID)
            } else {
                completedExperienceIDs.remove(experienceID)
            }
            bump()
            return wasCompleted
        }
    }

    @discardableResult
    func toggleFollow(target: Profile, isCurrentlyFollowing: Bool? = nil, using environment: AppEnvironment) async -> Bool {
        guard let followerID = environment.session.currentUser?.id else {
            environment.router.presentAuth()
            return false
        }
        guard followerID != target.id else { return false }

        let wasFollowing = isCurrentlyFollowing ?? (followingUserIDs.contains(target.id) || (target.isFollowing ?? false))
        var updatedTarget = profileCache[target.id] ?? target

        if wasFollowing {
            followingUserIDs.remove(target.id)
            unfollowedUserIDs.insert(target.id)
            updatedTarget.followerCount = max(0, updatedTarget.followerCount - 1)
            updatedTarget.isFollowing = false
            if var me = environment.session.currentUser {
                me.followingCount = max(0, me.followingCount - 1)
                environment.session.currentUser = me
                cache(me)
            }
        } else {
            followingUserIDs.insert(target.id)
            unfollowedUserIDs.remove(target.id)
            updatedTarget.followerCount += 1
            updatedTarget.isFollowing = true
            if var me = environment.session.currentUser {
                me.followingCount += 1
                environment.session.currentUser = me
                cache(me)
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        cache(updatedTarget)
        bump()

        do {
            if wasFollowing {
                try await environment.profiles.unfollow(followerID: followerID, followingID: target.id)
            } else {
                try await environment.profiles.follow(followerID: followerID, followingID: target.id)
            }
            return !wasFollowing
        } catch {
            // Roll back every optimistic mutation from above, including the
            // explicit-unfollow marker and both sides' counters.
            if wasFollowing {
                followingUserIDs.insert(target.id)
                unfollowedUserIDs.remove(target.id)
                updatedTarget.followerCount += 1
                updatedTarget.isFollowing = true
                if var me = environment.session.currentUser {
                    me.followingCount += 1
                    environment.session.currentUser = me
                    cache(me)
                }
            } else {
                followingUserIDs.remove(target.id)
                unfollowedUserIDs.insert(target.id)
                updatedTarget.followerCount = max(0, updatedTarget.followerCount - 1)
                updatedTarget.isFollowing = false
                if var me = environment.session.currentUser {
                    me.followingCount = max(0, me.followingCount - 1)
                    environment.session.currentUser = me
                    cache(me)
                }
            }
            cache(updatedTarget)
            bump()
            return wasFollowing
        }
    }

    func applyUpdatedProfile(_ profile: Profile, session: SessionStore) {
        cache(profile)
        if session.currentUser?.id == profile.id {
            session.currentUser = profile
        }
        bump()
    }

    private func applyLocalSaveState(
        experienceID: UUID,
        saved: Bool,
        summary: ExperienceSummary?
    ) {
        if saved {
            savedExperienceIDs.insert(experienceID)
            if let summary {
                savedSummaries[experienceID] = summary
            }
        } else {
            savedExperienceIDs.remove(experienceID)
            savedSummaries.removeValue(forKey: experienceID)
        }
        bump()
    }

    private func bump() {
        revision &+= 1
        NotificationCenter.default.post(name: Notification.Name("ExperienceSavedNotification"), object: nil)
    }
}
