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
    private(set) var followingUserIDs: Set<UUID> = []
    /// Latest known profiles keyed by id — refreshed after edits / follows.
    private(set) var profileCache: [UUID: Profile] = [:]
    private(set) var profileCacheByUsername: [String: Profile] = [:]
    /// Cached summaries for optimistic Profile Saved rendering before refetch completes.
    private(set) var savedSummaries: [UUID: ExperienceSummary] = [:]
    /// Bumped whenever lists or counts change so observing views can refresh.
    private(set) var revision: Int = 0
    /// Surfaces the last save error for debugging / lightweight UI.
    private(set) var lastSaveError: String?

    private var bootstrappedUserID: UUID?
    private var inFlightSaveIDs: Set<UUID> = []
    private var bootstrapTask: Task<Void, Never>?

    func reset() {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        savedExperienceIDs = []
        completedExperienceIDs = []
        followingUserIDs = []
        profileCache = [:]
        profileCacheByUsername = [:]
        savedSummaries = [:]
        bootstrappedUserID = nil
        inFlightSaveIDs = []
        lastSaveError = nil
        bump()
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
                async let following = environment.engagementRepo.fetchFollowingIDs(userID: userID)
                let remoteSaved = try await saved
                let remoteCompleted = try await completed
                let remoteFollowing = try await following

                // Merge — never wipe optimistic toggles that happened during the fetch.
                savedExperienceIDs.formUnion(remoteSaved)
                completedExperienceIDs.formUnion(remoteCompleted)
                followingUserIDs.formUnion(remoteFollowing)
                bootstrappedUserID = userID
                bump()
            } catch {
                print("EngagementStore.bootstrap failed: \(error)")
                // Allow retry on next screen appear.
            }
        }
        bootstrapTask = task
        await task.value
        bootstrapTask = nil
    }

    func cache(_ profile: Profile) {
        profileCache[profile.id] = profile
        profileCacheByUsername[profile.username.lowercased()] = profile
        bump()
    }

    func cachedProfile(username: String) -> Profile? {
        profileCacheByUsername[username.lowercased()]
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

    func isFollowing(_ userID: UUID) -> Bool {
        followingUserIDs.contains(userID)
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
            print("EngagementStore.toggleSave error: \(error)")
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
            let nowCompleted = try await environment.engagementRepo.toggleComplete(
                userID: userID,
                experienceID: experienceID
            )
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
    func toggleFollow(target: Profile, using environment: AppEnvironment) async -> Bool {
        guard let followerID = environment.session.currentUser?.id else {
            environment.router.presentAuth()
            return false
        }
        guard followerID != target.id else { return false }

        let wasFollowing = followingUserIDs.contains(target.id)
        var updatedTarget = target

        if wasFollowing {
            followingUserIDs.remove(target.id)
            updatedTarget.followerCount = max(0, updatedTarget.followerCount - 1)
            updatedTarget.isFollowing = false
            if var me = environment.session.currentUser {
                me.followingCount = max(0, me.followingCount - 1)
                environment.session.currentUser = me
                cache(me)
            }
        } else {
            followingUserIDs.insert(target.id)
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
    }
}
