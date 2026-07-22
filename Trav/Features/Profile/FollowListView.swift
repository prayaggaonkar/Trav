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

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && users.isEmpty {
                    ProgressView()
                        .tint(TravColors.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, users.isEmpty {
                    ErrorStateView(message: error.localizedDescription) {
                        Task { await reload(reset: true) }
                    }
                } else if filteredUsers.isEmpty {
                    EmptyStateView(
                        icon: mode == .followers ? "person.2" : "person.badge.plus",
                        title: mode == .followers ? "No followers yet" : "Not following anyone",
                        description: mode == .followers
                            ? "When people follow \(profile.displayName), they’ll show up here."
                            : "Follow travelers to build your circle."
                    )
                } else {
                    List {
                        ForEach(filteredUsers) { user in
                            let isFollowingUser: Bool? = {
                                guard let currentUserID = session.currentUser?.id else { return nil }
                                if currentUserID == user.id { return nil }
                                if mode == .following && profile.id == currentUserID {
                                    // In own following list, if not explicitly unfollowed in session, default to true
                                    return engagement.isFollowing(user.id) || !engagement.hasExplicitlyUnfollowed(user.id)
                                }
                                return engagement.isFollowing(user.id)
                            }()

                            ProfileUserRow(
                                user: user,
                                isFollowing: isFollowingUser,
                                onTap: {
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                        router.openProfile(user.username)
                                    }
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
            .travScreenBackground()
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search \(mode.title.lowercased())")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: query) { _, _ in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(280))
                    guard !Task.isCancelled else { return }
                    await reload(reset: true)
                }
            }
        }
        .task { await reload(reset: true) }
    }

    private var filteredUsers: [ProfileSummary] { users }

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
            users = reset ? result.items : users + result.items
            hasMore = result.hasMore
            error = nil
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
        let stub = Profile(
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
        _ = await engagement.toggleFollow(target: stub, isCurrentlyFollowing: isCurrentlyFollowing, using: environment)
    }
}
