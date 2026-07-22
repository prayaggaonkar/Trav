import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class ProfileViewModel {
    enum Phase {
        case loading
        case loaded
        case failed(Error)
    }

    let username: String

    private(set) var phase: Phase = .loading
    private(set) var profile: Profile?
    var selectedTab: ProfileContentTab = .created

    private(set) var created: [ExperienceSummary] = []
    private(set) var saved: [ExperienceSummary] = []
    private(set) var completed: [CompletedExperienceItem] = []

    private(set) var createdPage = 0
    private(set) var savedPage = 0
    private(set) var completedPage = 0
    private(set) var createdHasMore = true
    private(set) var savedHasMore = true
    private(set) var completedHasMore = true

    private(set) var isLoadingMore = false
    private(set) var isRefreshing = false
    private(set) var isFollowLoading = false
    private(set) var isSigningOut = false

    private var loadedTabs: Set<ProfileContentTab> = []
    private var lastEngagementRevision: Int = -1

    init(username: String) {
        self.username = username
    }

    func load(using environment: AppEnvironment) async {
        phase = .loading
        do {
            var fetched = try await environment.profiles.fetchProfile(username: username)
            if let viewerID = environment.session.currentUser?.id, viewerID != fetched.id {
                fetched.isFollowing = try await environment.profiles.isFollowing(
                    followerID: viewerID,
                    followingID: fetched.id
                )
            }
            profile = fetched
            environment.engagement.cache(fetched)
            phase = .loaded
            loadedTabs = []
            await loadTab(selectedTab, using: environment, reset: true)
        } catch {
            phase = .failed(error)
        }
    }

    func refresh(using environment: AppEnvironment) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            var fetched = try await environment.profiles.fetchProfile(username: username)
            if let viewerID = environment.session.currentUser?.id, viewerID != fetched.id {
                if environment.engagement.isFollowing(fetched.id) {
                    fetched.isFollowing = true
                } else {
                    fetched.isFollowing = try await environment.profiles.isFollowing(
                        followerID: viewerID,
                        followingID: fetched.id
                    )
                }
            }
            profile = fetched
            environment.engagement.cache(fetched)
            loadedTabs = []
            await loadTab(selectedTab, using: environment, reset: true)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } catch {
            // Keep existing content on refresh failure.
        }
    }

    func selectTab(_ tab: ProfileContentTab, using environment: AppEnvironment) async {
        guard selectedTab != tab else { return }
        selectedTab = tab
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if !loadedTabs.contains(tab) {
            await loadTab(tab, using: environment, reset: true)
        }
    }

    func loadMoreIfNeeded(using environment: AppEnvironment) async {
        guard !isLoadingMore else { return }
        switch selectedTab {
        case .created where createdHasMore:
            await loadTab(.created, using: environment, reset: false)
        case .saved where savedHasMore:
            await loadTab(.saved, using: environment, reset: false)
        case .completed where completedHasMore:
            await loadTab(.completed, using: environment, reset: false)
        default:
            break
        }
    }

    /// Reacts to EngagementStore changes (save/unsave/complete/follow elsewhere).
    func syncWithEngagement(_ store: EngagementStore, environment: AppEnvironment) async {
        guard lastEngagementRevision != store.revision else { return }
        lastEngagementRevision = store.revision

        if let cached = store.cachedProfile(username: username) {
            var merged = cached
            if let existing = profile {
                merged.isFollowing = store.isFollowing(cached.id) ? true : existing.isFollowing
            } else {
                merged.isFollowing = store.isFollowing(cached.id)
            }
            profile = merged
        }

        // Own-profile saved/completed tabs should reflect engagement immediately.
        guard let profile, environment.session.currentUser?.id == profile.id else { return }

        if loadedTabs.contains(.saved) {
            await loadTab(.saved, using: environment, reset: true)
        }
        if loadedTabs.contains(.completed) {
            await loadTab(.completed, using: environment, reset: true)
        }
    }

    func toggleFollow(using environment: AppEnvironment) async {
        guard var profile else { return }
        guard !isFollowLoading else { return }
        isFollowLoading = true
        defer { isFollowLoading = false }

        let nowFollowing = await environment.engagement.toggleFollow(target: profile, using: environment)
        profile.isFollowing = nowFollowing
        if let cached = environment.engagement.cachedProfile(username: username) {
            self.profile = cached
        } else {
            self.profile = profile
        }
    }

    func signOut(using environment: AppEnvironment) async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        try? await environment.auth.signOut()
        environment.session.currentUser = nil
        environment.session.phase = .unauthenticated
        environment.engagement.reset()
    }

    func applyEditedProfile(_ updated: Profile, engagement: EngagementStore, session: SessionStore) {
        profile = updated
        engagement.applyUpdatedProfile(updated, session: session)
    }

    // MARK: - Private

    private func loadTab(_ tab: ProfileContentTab, using environment: AppEnvironment, reset: Bool) async {
        guard let profile else { return }
        isLoadingMore = !reset
        defer { isLoadingMore = false }

        do {
            switch tab {
            case .created:
                let page = reset ? 0 : createdPage + 1
                let result = try await environment.profiles.fetchCreatedExperiences(userID: profile.id, page: page)
                created = reset ? result.items : created + result.items
                createdPage = page
                createdHasMore = result.hasMore
            case .saved:
                let page = reset ? 0 : savedPage + 1
                let result = try await environment.profiles.fetchSavedExperiences(userID: profile.id, page: page)
                // Filter through engagement store for instant unsaves on own profile.
                let items: [ExperienceSummary]
                if environment.session.currentUser?.id == profile.id {
                    items = result.items.filter { environment.engagement.isSaved($0.id) || reset == false }
                    // Prefer store as source of truth after first page.
                    if reset {
                        saved = result.items.filter { environment.engagement.isSaved($0.id) || environment.engagement.savedExperienceIDs.isEmpty }
                        if !environment.engagement.savedExperienceIDs.isEmpty {
                            saved = result.items.filter { environment.engagement.isSaved($0.id) }
                        } else {
                            saved = result.items
                        }
                    } else {
                        saved += items
                    }
                } else {
                    saved = reset ? result.items : saved + result.items
                }
                savedPage = page
                savedHasMore = result.hasMore
            case .completed:
                let page = reset ? 0 : completedPage + 1
                let result = try await environment.profiles.fetchCompletedExperiences(userID: profile.id, page: page)
                if environment.session.currentUser?.id == profile.id, !environment.engagement.completedExperienceIDs.isEmpty, reset {
                    completed = result.items.filter { environment.engagement.isCompleted($0.experience.id) }
                } else {
                    completed = reset ? result.items : completed + result.items
                }
                completedPage = page
                completedHasMore = result.hasMore
            }
            loadedTabs.insert(tab)
        } catch {
            // Leave existing tab content; surface via empty/error at screen level if initial load.
        }
    }
}
