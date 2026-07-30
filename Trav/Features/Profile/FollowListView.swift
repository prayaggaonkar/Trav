import SwiftUI

enum FollowListMode: String, Identifiable {
    case followers
    case following

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followers: "Followers"
        case .following: "Following"
        }
    }
}

struct FollowListView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(EngagementStore.self) private var engagement
    @Environment(\.dismiss) private var dismiss

    let profile: Profile
    let mode: FollowListMode

    @State private var users: [ProfileSummary] = []
    @State private var query = ""
    @State private var page = 0
    @State private var hasMore = true
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var error: Error?
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedUsernameForProfile: String?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        // No NavigationStack here — it was adding a large empty chrome gap under the sheet grabber.
        VStack(spacing: 0) {
            followListTopBar

            followListSearchBar
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.top, TravSpacing.md)
                .padding(.bottom, TravSpacing.xs)

            Group {
                if isLoading && users.isEmpty {
                    SkeletonRankingsList()
                } else if let error, users.isEmpty {
                    ErrorStateView(message: error.localizedDescription) {
                        Task { await reload(reset: true) }
                    }
                } else if filteredUsers.isEmpty {
                    EmptyStateView(
                        icon: mode == .followers ? "person.2" : "person.badge.plus",
                        title: query.isEmpty
                            ? (mode == .followers ? "No followers yet" : "Not following anyone")
                            : "No matches",
                        description: query.isEmpty
                            ? (mode == .followers
                                ? "When people follow \(profile.displayName), they’ll show up here."
                                : "Follow travelers to build your circle.")
                            : "Try a different name or username."
                    )
                } else {
                    List {
                        ForEach(filteredUsers) { user in
                            let isFollowingUser: Bool? = {
                                guard let currentUserID = session.currentUser?.id else { return nil }
                                if currentUserID == user.id { return nil }
                                if mode == .following && profile.id == currentUserID {
                                    return engagement.isFollowing(user.id) || !engagement.hasExplicitlyUnfollowed(user.id)
                                }
                                return engagement.isFollowing(user.id)
                            }()

                            ProfileUserRow(
                                user: user,
                                isFollowing: isFollowingUser,
                                onTap: {
                                    selectedUsernameForProfile = user.username
                                },
                                onFollowToggle: session.currentUser?.id == user.id ? nil : {
                                    Task { await toggleFollow(user, isCurrentlyFollowing: isFollowingUser) }
                                }
                            )
                            .listRowBackground(TravColors.surface)
                            .listRowSeparatorTint(TravColors.border.opacity(0.5))
                            .onAppear {
                                if user.id == filteredUsers.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                        }

                        if isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .listRowBackground(TravColors.surface)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .travScreenBackground()
        .onChange(of: query) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                await reload(reset: true)
            }
        }
        .sheet(item: Binding(
            get: { selectedUsernameForProfile.map { ProfileSheetItem(username: $0) } },
            set: { selectedUsernameForProfile = $0?.username }
        )) { item in
            ProfileView(username: item.username, showDismissButton: true)
        }
        .task { await reload(reset: true) }
        .task(id: engagement.revision) { await reload(reset: true) }
    }

    private var followListTopBar: some View {
        HStack {
            Spacer()
            Text(mode.title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(TravColors.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.top, TravSpacing.md)
        .padding(.bottom, TravSpacing.xs)
    }

    private var followListSearchBar: some View {
        HStack(spacing: TravSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TravColors.muted)
                .accessibilityHidden(true)

            TextField("Search \(mode.title.lowercased())", text: $query)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(TravColors.primary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)

            if !query.isEmpty {
                Button {
                    withAnimation(TravAnimation.quick) {
                        query = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(TravColors.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, TravSpacing.md)
        .frame(height: 44)
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                .stroke(TravColors.border.opacity(0.55), lineWidth: 1)
        }
    }

    private var filteredUsers: [ProfileSummary] {
        users.filter { !engagement.isBlocked($0.id) }
    }

    private func reload(reset: Bool) async {
        if reset {
            isLoading = users.isEmpty
            page = 0
            hasMore = true
        }
        defer { isLoading = false }

        do {
            let result: Paginated<ProfileSummary>
            switch mode {
            case .followers:
                result = try await environment.profiles.fetchFollowers(
                    userID: profile.id,
                    query: query.isEmpty ? nil : query,
                    page: page
                )
            case .following:
                result = try await environment.profiles.fetchFollowing(
                    userID: profile.id,
                    query: query.isEmpty ? nil : query,
                    page: page
                )
            }
            if mode == .following && profile.id == session.currentUser?.id {
                engagement.seedFollowingIDs(result.items.map(\.id))
            }
            let visible = result.items.filter { !engagement.isBlocked($0.id) }
            users = reset ? visible : users + visible
            hasMore = result.hasMore
            error = nil

            if query.isEmpty && page == 0 {
                let totalCount = visible.count
                if var cached = engagement.cachedProfile(username: profile.username) ?? (profile.id == session.currentUser?.id ? session.currentUser : nil) {
                    if mode == .followers {
                        cached.followerCount = totalCount
                    } else {
                        cached.followingCount = totalCount
                    }
                    engagement.cache(cached)
                    if session.currentUser?.id == cached.id {
                        session.currentUser = cached
                    }
                }
            }
        } catch {
            self.error = error
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        page += 1
        await reload(reset: false)
    }

    private func toggleFollow(_ user: ProfileSummary, isCurrentlyFollowing: Bool?) async {
        let target = engagement.cachedProfile(username: user.username) ?? Profile(
            id: user.id,
            username: user.username,
            displayName: user.displayName,
            bio: nil,
            avatarURL: user.avatarURL,
            homeCityID: nil,
            homeCityName: nil,
            followerCount: 0,
            followingCount: 0,
            experienceCount: 0,
            completionCount: 0,
            isVerified: user.isVerified,
            selectedVibes: nil,
            onboardingLocation: nil,
            isFollowing: isCurrentlyFollowing ?? engagement.isFollowing(user.id)
        )
        _ = await engagement.toggleFollow(target: target, isCurrentlyFollowing: isCurrentlyFollowing, using: environment)
    }
}

private struct ProfileSheetItem: Identifiable {
    let username: String
    var id: String { username }
}
