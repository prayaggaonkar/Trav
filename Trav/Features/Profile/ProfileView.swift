import SwiftUI

struct ProfileView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(EngagementStore.self) private var engagement
    @Environment(\.dismiss) private var dismiss

    let username: String
    var showDismissButton: Bool = true

    @State private var viewModel: ProfileViewModel
    @State private var showEditProfile = false
    @State private var followListMode: FollowListMode?
    @State private var saveConfirmation = false
    @State private var showSettings = false

    private var tabs: [ProfileContentTab] {
        if isOwnProfile {
            return [.created, .saved, .completed]
        } else {
            return [.created, .completed]
        }
    }

    init(username: String, showDismissButton: Bool = true) {
        self.username = username
        self.showDismissButton = showDismissButton
        _viewModel = State(initialValue: ProfileViewModel(username: username))
    }

    private var isOwnProfile: Bool {
        session.currentUser?.username.lowercased() == username.lowercased()
            || session.currentUser?.id == viewModel.profile?.id
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .loading:
                    ProfileSkeleton()
                case .failed(let error):
                    ErrorStateView(message: error.localizedDescription) {
                        Task { await viewModel.load(using: environment) }
                    }
                case .loaded:
                    if let profile = viewModel.profile {
                        profileScroll(profile)
                    }
                }
            }
            .travScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showEditProfile) {
                if let profile = viewModel.profile {
                    EditProfileView(profile: profile) { updated in
                        viewModel.applyEditedProfile(
                            updated,
                            engagement: engagement,
                            session: session
                        )
                        saveConfirmation = true
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }
            .sheet(item: $followListMode) { mode in
                if let profile = viewModel.profile {
                    FollowListView(profile: profile, mode: mode)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheetView {
                    Task { await viewModel.signOut(using: environment) }
                }
                .presentationDetents([.height(240)])
                .presentationDragIndicator(.visible)
            }
            .overlay(alignment: .top) {
                if saveConfirmation {
                    Text("Profile updated")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(TravColors.primary)
                        .padding(.horizontal, TravSpacing.md)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.top, TravSpacing.sm)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .onAppear {
                            Task {
                                try? await Task.sleep(for: .seconds(1.6))
                                withAnimation(TravAnimation.quick) { saveConfirmation = false }
                            }
                        }
                }
            }
        }
        .task {
            await viewModel.load(using: environment)
            if let userID = session.currentUser?.id {
                await engagement.bootstrap(userID: userID, using: environment)
            }
        }
        .task(id: engagement.revision) {
            await viewModel.syncWithEngagement(engagement, environment: environment)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func profileScroll(_ profile: Profile) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                if isOwnProfile {
                    HStack {
                        Spacer(minLength: 0)
                        profileMenu
                    }
                    .padding(.horizontal, TravSpacing.screenHorizontal)
                    .padding(.top, TravSpacing.xs)
                }

                header(profile)
                    .padding(.horizontal, TravSpacing.screenHorizontal)
                    .padding(.top, isOwnProfile ? TravSpacing.sm : TravSpacing.md)
                    .travAppear()

                ProfileStatsRow(
                    profile: profile,
                    onFollowers: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        followListMode = .followers
                    },
                    onFollowing: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        followListMode = .following
                    },
                    onCreated: {
                        Task { await viewModel.selectTab(.created, using: environment) }
                    },
                    onCompleted: {
                        Task { await viewModel.selectTab(.completed, using: environment) }
                    }
                )
                .padding(.horizontal, TravSpacing.xs)
                .padding(.top, TravSpacing.lg)
                .travAppear(delay: 0.05)

                actionRow(profile)
                    .padding(.horizontal, TravSpacing.screenHorizontal)
                    .padding(.top, TravSpacing.md)
                    .travAppear(delay: 0.08)

                ProfileTabBar(
                    tabs: tabs,
                    selection: Binding(
                        get: { viewModel.selectedTab },
                        set: { newValue in
                            Task { await viewModel.selectTab(newValue, using: environment) }
                        }
                    ),
                    onSelect: { tab in
                        Task { await viewModel.selectTab(tab, using: environment) }
                    }
                )
                .padding(.top, TravSpacing.xl)
                .travAppear(delay: 0.1)

                tabContent
                    .padding(.bottom, TravSpacing.xxl + TravSpacing.lg)
            }
        }
        .refreshable {
            await viewModel.refresh(using: environment)
        }
    }

    @ViewBuilder
    private func header(_ profile: Profile) -> some View {
        VStack(spacing: TravSpacing.md) {
            AvatarView(url: profile.avatarURL, size: 88)

            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    Text(profile.displayName)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(TravColors.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if profile.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(TravColors.muted)
                    }
                }

                Text("@\(profile.username)")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(TravColors.muted)

                if let bio = profile.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(TravColors.primary.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                        .padding(.horizontal, TravSpacing.sm)
                }

                if let city = profile.homeCityLabel {
                    Text(city)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(TravColors.muted)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func actionRow(_ profile: Profile) -> some View {
        if isOwnProfile {
            HStack {
                Spacer(minLength: 0)
                ProfileEditButton(title: "Edit profile") {
                    showEditProfile = true
                }
                Spacer(minLength: 0)
            }
        } else {
            ProfileFollowButton(
                isFollowing: profile.isFollowing == true || engagement.isFollowing(profile.id),
                isLoading: viewModel.isFollowLoading
            ) {
                Task { await viewModel.toggleFollow(using: environment) }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        LazyVStack(spacing: 0) {
            switch viewModel.selectedTab {
            case .created:
                ProfileEmptyState(
                    title: "No experiences yet",
                    description: "Share your first experience with the community."
                )

            case .saved:
                if viewModel.saved.isEmpty {
                    ProfileEmptyState(
                        title: "Nothing saved",
                        description: "Save experiences to revisit them later."
                    )
                } else {
                    ForEach(Array(viewModel.saved.enumerated()), id: \.element.id) { index, experience in
                        savedExperienceRow(
                            experience: experience,
                            index: index,
                            isLast: experience.id == viewModel.saved.last?.id
                        )
                    }
                }

            case .completed:
                if viewModel.completed.isEmpty {
                    ProfileEmptyState(
                        title: "No completions yet",
                        description: "Complete your first experience to start building your journey."
                    )
                } else {
                    ForEach(Array(viewModel.completed.enumerated()), id: \.element.id) { index, item in
                        experienceRow(
                            experience: item.experience,
                            completedAt: item.completedAt,
                            index: index,
                            isLast: item.id == viewModel.completed.last?.id
                        )
                    }
                }
            }

            if viewModel.isLoadingMore {
                ProgressView()
                    .tint(TravColors.muted)
                    .padding(.vertical, TravSpacing.md)
            }
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .animation(TravAnimation.quick, value: viewModel.selectedTab)
        .animation(TravAnimation.quick, value: viewModel.saved.map(\.id))
    }

    @ViewBuilder
    private func experienceList(_ items: [ExperienceSummary]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, experience in
            experienceRow(
                experience: experience,
                completedAt: nil,
                index: index,
                isLast: experience.id == items.last?.id
            )
        }
    }

    @ViewBuilder
    private func savedExperienceRow(
        experience: ExperienceSummary,
        index: Int,
        isLast: Bool
    ) -> some View {
        Group {
            if isOwnProfile {
                SwipeToUnsaveRow(
                    onUnsave: {
                        Task { await viewModel.unsave(experience, using: environment) }
                    },
                    onOpen: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        router.openExperience(experience.id)
                    }
                ) {
                    ProfileExperienceCard(experience: experience)
                }
            } else {
                ProfileExperienceCard(experience: experience) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    router.openExperience(experience.id)
                }
            }
        }
        .travAppear(delay: Double(min(index, 5)) * 0.03)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(TravColors.border.opacity(0.4))
                    .frame(height: 0.5)
                    .padding(.leading, 72 + TravSpacing.md)
            }
        }
        .onAppear {
            if isLast {
                Task { await viewModel.loadMoreIfNeeded(using: environment) }
            }
        }
    }

    @ViewBuilder
    private func experienceRow(
        experience: ExperienceSummary,
        completedAt: Date?,
        index: Int,
        isLast: Bool
    ) -> some View {
        ProfileExperienceCard(experience: experience, completedAt: completedAt) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            router.openExperience(experience.id)
        }
        .travAppear(delay: Double(min(index, 5)) * 0.03)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(TravColors.border.opacity(0.4))
                    .frame(height: 0.5)
                    .padding(.leading, 72 + TravSpacing.md)
            }
        }
        .onAppear {
            if isLast {
                Task { await viewModel.loadMoreIfNeeded(using: environment) }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if showDismissButton {
            ToolbarItem(placement: .topBarLeading) {
                DismissButton {
                    if router.presentedRoute != nil {
                        router.dismiss()
                    } else {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var profileMenu: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(TravColors.primary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }
}

// MARK: - Settings Sheet

struct SettingsSheetView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let onSignOut: () -> Void

    var body: some View {
        VStack(spacing: TravSpacing.md) {
            // Header
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(TravColors.accent)
                Text("Settings")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(TravColors.primary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(TravColors.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .padding(.top, TravSpacing.lg)

            Divider()
                .background(TravColors.border.opacity(0.3))

            VStack(spacing: TravSpacing.sm) {
                // Toggle theme button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    environment.appearance.toggle()
                } label: {
                    HStack(spacing: TravSpacing.md) {
                        Image(systemName: environment.appearance.isLightMode ? "moon.fill" : "sun.max.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(TravColors.accent)
                            .frame(width: 32, height: 32)
                            .background(TravColors.surfaceElevated)
                            .clipShape(Circle())

                        Text(environment.appearance.isLightMode ? "Dark Mode" : "Light Mode")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(TravColors.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TravColors.muted)
                    }
                    .padding(.horizontal, TravSpacing.md)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(TravColors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(TravColors.border.opacity(0.4), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                // Sign out button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    dismiss()
                    onSignOut()
                } label: {
                    HStack(spacing: TravSpacing.md) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.red)
                            .frame(width: 32, height: 32)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Circle())

                        Text("Sign Out")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.red)

                        Spacer()
                    }
                    .padding(.horizontal, TravSpacing.md)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(TravColors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .padding(.top, TravSpacing.sm)

            Spacer()
        }
        .travScreenBackground()
    }
}
