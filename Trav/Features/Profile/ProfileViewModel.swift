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

    var isSuggestionsExpanded = false
    private(set) var suggestedUsers: [SuggestedUser] = []
    private(set) var isLoadingSuggestions = false
    private(set) var contactsAuthorization: ContactAuthorizationStatus = ContactSyncService.authorizationStatus
    private var dismissedSuggestionIDs: Set<UUID> = []
    private var hasLoadedSuggestions = false

    private var loadedTabs: Set<ProfileContentTab> = []
    private var lastEngagementRevision: Int = -1

    init(username: String) {
        self.username = username
    }

    private(set) var calculatedRank: Int? = nil
    private(set) var isRankLoading: Bool = true
    private(set) var isFollowCountsLoading: Bool = true

    var creatorRankLabel: String {
        if let rank = calculatedRank {
            return "#\(rank)"
        }
        return "—"
    }

    private func updateCreatorRank(using environment: AppEnvironment) async {
        isRankLoading = true
        defer { isRankLoading = false }

        // Users without any created experiences should not have a rank.
        let userCount = max(profile?.experienceCount ?? 0, created.count)
        guard userCount > 0 else {
            calculatedRank = nil
            return
        }

        do {
            let mainEntries = try await environment.experiences.fetchMainLeaderboard(cityID: nil, cityName: nil)
            let validEntries = mainEntries.filter { $0.experienceCount > 0 }
            if let match = validEntries.firstIndex(where: {
                $0.id == profile?.id || $0.username.lowercased() == username.lowercased()
            }) {
                calculatedRank = validEntries[match].rank
            } else {
                let rankPos = (validEntries.firstIndex(where: { $0.experienceCount <= userCount }) ?? validEntries.count) + 1
                calculatedRank = rankPos
            }
        } catch {
            calculatedRank = nil
        }
    }

    func load(using environment: AppEnvironment) async {
        if profile == nil {
            phase = .loading
        }
        if (profile?.followerCount ?? 0) > 0 || (profile?.followingCount ?? 0) > 0 {
            isFollowCountsLoading = true
        }
        defer { isFollowCountsLoading = false }
        do {
            var fetched = try await environment.profiles.fetchProfile(username: username)
            if let followersPage = try? await environment.profiles.fetchFollowers(userID: fetched.id, query: nil, page: 0) {
                fetched.followerCount = followersPage.items.count
            }
            if let followingPage = try? await environment.profiles.fetchFollowing(userID: fetched.id, query: nil, page: 0) {
                fetched.followingCount = followingPage.items.count
            }

            if let viewerID = environment.session.currentUser?.id, viewerID != fetched.id {
                fetched.isFollowing = try await environment.profiles.isFollowing(
                    followerID: viewerID,
                    followingID: fetched.id
                )
            } else if environment.session.currentUser?.id == fetched.id {
                environment.session.currentUser = fetched
            }
            profile = fetched
            environment.engagement.cache(fetched)
            phase = .loaded
            if loadedTabs.isEmpty {
                await loadTab(selectedTab, using: environment, reset: true)
            }
            await updateCreatorRank(using: environment)
        } catch {
            if profile == nil {
                phase = .failed(error)
            }
        }
    }

    func refresh(using environment: AppEnvironment) async {
        isRefreshing = true
        if (profile?.followerCount ?? 0) > 0 || (profile?.followingCount ?? 0) > 0 {
            isFollowCountsLoading = true
        }
        defer {
            isRefreshing = false
            isFollowCountsLoading = false
        }
        do {
            var fetched = try await environment.profiles.fetchProfile(username: username)
            if let followersPage = try? await environment.profiles.fetchFollowers(userID: fetched.id, query: nil, page: 0) {
                fetched.followerCount = followersPage.items.count
            }
            if let followingPage = try? await environment.profiles.fetchFollowing(userID: fetched.id, query: nil, page: 0) {
                fetched.followingCount = followingPage.items.count
            }

            if let viewerID = environment.session.currentUser?.id, viewerID != fetched.id {
                if environment.engagement.isFollowing(fetched.id) {
                    fetched.isFollowing = true
                } else {
                    fetched.isFollowing = try await environment.profiles.isFollowing(
                        followerID: viewerID,
                        followingID: fetched.id
                    )
                }
            } else if environment.session.currentUser?.id == fetched.id {
                environment.session.currentUser = fetched
            }
            profile = fetched
            environment.engagement.cache(fetched)
            loadedTabs = []
            await loadTab(selectedTab, using: environment, reset: true)
            await updateCreatorRank(using: environment)
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

        if var current = profile {
            if let cached = store.cachedProfile(username: username) {
                current.followerCount = cached.followerCount
                current.followingCount = cached.followingCount
                current.experienceCount = max(current.experienceCount, cached.experienceCount)
                if let bio = cached.bio { current.bio = bio }
                if let avatar = cached.avatarURL { current.avatarURL = avatar }
                if let city = cached.homeCityName { current.homeCityName = city }
                if let isFollowing = cached.isFollowing { current.isFollowing = isFollowing }
            }
            current.isFollowing = store.isFollowing(current.id)
            if environment.session.currentUser?.id == current.id, let me = environment.session.currentUser {
                current.followingCount = me.followingCount
                current.followerCount = me.followerCount
                current.experienceCount = max(current.experienceCount, me.experienceCount)
            }
            current.experienceCount = max(current.experienceCount, created.count)
            profile = current
        } else if let cached = store.cachedProfile(username: username) {
            var merged = cached
            merged.isFollowing = store.isFollowing(cached.id)
            profile = merged
        }

        // Own-profile saved/completed tabs should reflect engagement immediately.
        guard let profile, environment.session.currentUser?.id == profile.id else { return }

        if loadedTabs.contains(.saved) || selectedTab == .saved {
            await loadTab(.saved, using: environment, reset: true)
        } else {
            // Force a fresh fetch the next time Saved is opened.
            loadedTabs.remove(.saved)
        }
        if loadedTabs.contains(.completed) || selectedTab == .completed {
            await loadTab(.completed, using: environment, reset: true)
        } else {
            loadedTabs.remove(.completed)
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

    /// Swipe-to-unsave from the Saved tab (own profile only).
    func unsave(_ experience: ExperienceSummary, using environment: AppEnvironment) async {
        guard let profile, environment.session.currentUser?.id == profile.id else { return }
        saved.removeAll { $0.id == experience.id }
        await environment.engagement.unsave(experienceID: experience.id, using: environment)
    }

    // MARK: - Suggested users

    func toggleSuggestions(using environment: AppEnvironment) async {
        let opening = !isSuggestionsExpanded
        isSuggestionsExpanded = opening
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if opening {
            await loadSuggestions(using: environment, force: !hasLoadedSuggestions)
        }
    }

    func loadSuggestions(using environment: AppEnvironment, force: Bool = false) async {
        guard environment.session.currentUser != nil else { return }
        if isLoadingSuggestions { return }
        if hasLoadedSuggestions && !force && !suggestedUsers.isEmpty { return }

        isLoadingSuggestions = true
        defer { isLoadingSuggestions = false }

        contactsAuthorization = ContactSyncService.authorizationStatus

        if contactsAuthorization == .notDetermined {
            let granted = await ContactSyncService.requestAccess()
            contactsAuthorization = ContactSyncService.authorizationStatus
            if granted {
                await syncAndFetchSuggestions(using: environment)
                return
            }
        }

        if contactsAuthorization == .authorized {
            await syncAndFetchSuggestions(using: environment)
        } else {
            await fetchSuggestionsOnly(using: environment)
        }
    }

    func requestContactsAccess(using environment: AppEnvironment) async {
        contactsAuthorization = ContactSyncService.authorizationStatus
        if contactsAuthorization == .denied || contactsAuthorization == .restricted {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            return
        }
        let granted = await ContactSyncService.requestAccess()
        contactsAuthorization = ContactSyncService.authorizationStatus
        if granted {
            await syncAndFetchSuggestions(using: environment)
        } else {
            await fetchSuggestionsOnly(using: environment)
        }
    }

    func dismissSuggestion(_ userID: UUID) {
        dismissedSuggestionIDs.insert(userID)
        suggestedUsers.removeAll { $0.id == userID }
    }

    func followSuggestion(_ suggestion: SuggestedUser, using environment: AppEnvironment) async {
        _ = await environment.engagement.toggleFollow(
            target: suggestion.profile,
            isCurrentlyFollowing: false,
            using: environment
        )
        dismissSuggestion(suggestion.id)
    }

    // MARK: - Private

    private func syncAndFetchSuggestions(using environment: AppEnvironment) async {
        do {
            let hashes = try ContactSyncService.fetchContactHashes()
            try await environment.profiles.syncContactHashes(hashes)
        } catch {
            // Still load mutuals/popular if contact sync fails.
        }
        await fetchSuggestionsOnly(using: environment)
    }

    private func fetchSuggestionsOnly(using environment: AppEnvironment) async {
        do {
            let fetched = try await environment.profiles.fetchSuggestedUsers(limit: 20)
            suggestedUsers = fetched.filter {
                !dismissedSuggestionIDs.contains($0.id) && !environment.engagement.isBlocked($0.id)
            }
            hasLoadedSuggestions = true
        } catch {
            if suggestedUsers.isEmpty {
                suggestedUsers = []
            }
            hasLoadedSuggestions = true
        }
    }

    private func loadTab(_ tab: ProfileContentTab, using environment: AppEnvironment, reset: Bool) async {
        guard let profile else { return }
        isLoadingMore = !reset
        defer { isLoadingMore = false }

        do {
            switch tab {
            case .created:
                let page = reset ? 0 : createdPage + 1
                let result = try await environment.profiles.fetchCreatedExperiences(userID: profile.id, page: page)
                // Spots are catalogue places owned by Trav — never user "posts".
                let itineraries = result.items.filter(\.isItinerary)
                created = reset ? itineraries : created + itineraries
                createdPage = page
                createdHasMore = result.hasMore
                if var p = self.profile {
                    p.experienceCount = max(p.experienceCount, created.count)
                    self.profile = p
                }
            case .saved:
                guard environment.session.currentUser?.id == profile.id else {
                    saved = []
                    savedHasMore = false
                    return
                }
                let page = reset ? 0 : savedPage + 1
                let result = try await environment.profiles.fetchSavedExperiences(userID: profile.id, page: page)
                var items = result.items

                if environment.session.currentUser?.id == profile.id {
                    let store = environment.engagement
                    if store.bootstrappedUserID == profile.id {
                        items = items.filter { store.isSaved($0.id) }
                    }
                    let present = Set(items.map(\.id))
                    let optimistic = store.savedExperienceIDs
                        .subtracting(present)
                        .compactMap { store.cachedSummary(for: $0) }

                    if reset {
                        saved = optimistic + items
                    } else {
                        var seen = Set(saved.map(\.id))
                        for item in optimistic + items where seen.insert(item.id).inserted {
                            saved.append(item)
                        }
                    }
                } else if reset {
                    saved = items
                } else {
                    saved += items
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
                if var p = self.profile {
                    p.completionCount = max(p.completionCount, completed.count)
                    self.profile = p
                }
            }
            loadedTabs.insert(tab)
        } catch {
            // Leave existing tab content; surface via empty/error at screen level if initial load.
        }
    }
}
