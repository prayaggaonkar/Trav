import Foundation
import Observation
import UIKit

/// App-wide engagement + social graph state. Optimistic updates keep City, Experience,
/// and Profile screens in sync without a restart.
@Observable
@MainActor
final class EngagementStore {
    private(set) var savedExperienceIDs: Set<UUID> = []
    private(set) var completedExperienceIDs: Set<UUID> = []
    private(set) var followingUserIDs: Set<UUID> = []
    private(set) var unfollowedUserIDs: Set<UUID> = []
    /// Latest known profiles keyed by id — refreshed after edits / follows.
    private(set) var profileCache: [UUID: Profile] = [:]
    private(set) var profileCacheByUsername: [String: Profile] = [:]
    /// Bumped whenever lists or counts change so observing views can refresh.
    private(set) var revision: Int = 0

    private var bootstrappedUserID: UUID?

    func reset() {
        savedExperienceIDs = []
        completedExperienceIDs = []
        followingUserIDs = []
        unfollowedUserIDs = []
        profileCache = [:]
        profileCacheByUsername = [:]
        bootstrappedUserID = nil
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

    func bootstrap(userID: UUID, using environment: AppEnvironment) async {
        if bootstrappedUserID == userID { return }
        bootstrappedUserID = userID
        do {
            async let saved = environment.engagementRepo.fetchSavedIDs(userID: userID)
            async let completed = environment.engagementRepo.fetchCompletedIDs(userID: userID)
            async let following = environment.engagementRepo.fetchFollowingIDs(userID: userID)
            savedExperienceIDs = try await saved
            completedExperienceIDs = try await completed
            followingUserIDs = try await following
            bump()
        } catch {
            // Keep empty sets; screens can still operate with per-action fetches.
        }
    }

    func cache(_ profile: Profile) {
        profileCache[profile.id] = profile
        profileCacheByUsername[profile.username.lowercased()] = profile
        bump()
    }

    func cachedProfile(username: String) -> Profile? {
        profileCacheByUsername[username.lowercased()]
    }

    func isSaved(_ experienceID: UUID) -> Bool {
        savedExperienceIDs.contains(experienceID)
    }

    func isCompleted(_ experienceID: UUID) -> Bool {
        completedExperienceIDs.contains(experienceID)
    }

    func isFollowing(_ userID: UUID) -> Bool {
        followingUserIDs.contains(userID)
    }

    @discardableResult
    func toggleSave(experienceID: UUID, using environment: AppEnvironment) async -> Bool {
        guard let userID = environment.session.currentUser?.id else {
            environment.router.presentAuth()
            return false
        }

        let wasSaved = savedExperienceIDs.contains(experienceID)
        if wasSaved {
            savedExperienceIDs.remove(experienceID)
        } else {
            savedExperienceIDs.insert(experienceID)
        }
        bump()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        do {
            let nowSaved = try await environment.engagementRepo.toggleSave(userID: userID, experienceID: experienceID)
            if nowSaved {
                savedExperienceIDs.insert(experienceID)
            } else {
                savedExperienceIDs.remove(experienceID)
            }
            bump()
            return nowSaved
        } catch {
            if wasSaved {
                savedExperienceIDs.insert(experienceID)
            } else {
                savedExperienceIDs.remove(experienceID)
            }
            bump()
            return wasSaved
        }
    }

    @discardableResult
    func toggleComplete(experienceID: UUID, using environment: AppEnvironment) async -> Bool {
        guard let userID = environment.session.currentUser?.id else {
            environment.router.presentAuth()
            return false
        }

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
            let nowCompleted = try await environment.engagementRepo.toggleComplete(userID: userID, experienceID: experienceID)
            if nowCompleted {
                completedExperienceIDs.insert(experienceID)
            } else {
                completedExperienceIDs.remove(experienceID)
            }
            bump()
            return nowCompleted
        } catch {
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
        var updatedTarget = target

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
            // Revert optimistic update
            if wasFollowing {
                followingUserIDs.insert(target.id)
            } else {
                followingUserIDs.remove(target.id)
            }
            cache(target)
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

    private func bump() {
        revision &+= 1
    }
}
