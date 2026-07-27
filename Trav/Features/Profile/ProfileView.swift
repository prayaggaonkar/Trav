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
    @State private var showCreateExperience = false

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
                .presentationDetents([.height(440)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showCreateExperience) {
                CreateExperienceView()
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
            VStack(alignment: .leading, spacing: 0) {
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
                    .padding(.top, isOwnProfile ? TravSpacing.xs : TravSpacing.sm)
                    .travAppear()

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
                    counts: [
                        .created: max(profile.experienceCount, viewModel.created.count),
                        .saved: viewModel.saved.count
                    ],
                    onSelect: { tab in
                        Task { await viewModel.selectTab(tab, using: environment) }
                    }
                )
                .padding(.top, TravSpacing.lg)
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
        VStack(alignment: .leading, spacing: TravSpacing.md) {
            // Top Row: Large avatar on left, Display Name & Stats on right
            HStack(alignment: .center, spacing: TravSpacing.lg) {
                AvatarView(url: profile.avatarURL, size: 84)

                VStack(alignment: .leading, spacing: TravSpacing.xs + 2) {
                    HStack(spacing: 4) {
                        Text(profile.displayName)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(TravColors.primary)
                            .lineLimit(1)
                        if profile.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(TravColors.accent)
                        }
                    }

                    ProfileStatsRow(
                        profile: profile,
                        createdCount: max(profile.experienceCount, viewModel.created.count),
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
                        }
                    )
                }
            }

            // Bio & Location Chip below avatar
            VStack(alignment: .leading, spacing: 8) {
                if let bio = profile.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(TravColors.primary.opacity(0.9))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let city = profile.homeCityLabel {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 11))
                            .foregroundStyle(TravColors.accent)
                        Text(city)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(TravColors.primary)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(TravColors.surfaceElevated)
                    .clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private func actionRow(_ profile: Profile) -> some View {
        if isOwnProfile {
            HStack(spacing: TravSpacing.sm) {
                Button {
                    showEditProfile = true
                } label: {
                    Text("Edit profile")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(TravColors.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(TravColors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.98))

                ShareLink(item: URL(string: "https://trav.app/user/\(profile.username)")!) {
                    Text("Share profile")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(TravColors.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(TravColors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.98))

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(TravColors.primary)
                        .frame(width: 38, height: 38)
                        .background(TravColors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.98))
            }
        } else {
            HStack(spacing: TravSpacing.sm) {
                ProfileFollowButton(
                    isFollowing: profile.isFollowing == true || engagement.isFollowing(profile.id),
                    isLoading: viewModel.isFollowLoading
                ) {
                    Task { await viewModel.toggleFollow(using: environment) }
                }

                ShareLink(item: URL(string: "https://trav.app/user/\(profile.username)")!) {
                    Text("Share profile")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(TravColors.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(TravColors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.98))
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        LazyVStack(spacing: TravSpacing.md) {
            switch viewModel.selectedTab {
            case .created:
                if viewModel.created.isEmpty {
                    ProfileEmptyState(
                        title: "No experiences yet",
                        description: "Share your first experience with the community."
                    )
                } else {
                    ForEach(Array(viewModel.created.enumerated()), id: \.element.id) { index, experience in
                        experienceRow(
                            experience: experience,
                            badgeText: isOwnProfile ? "Created by Me" : "",
                            index: index,
                            isLast: experience.id == viewModel.created.last?.id
                        )
                    }
                }

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
                        let badgeText = "Completed"
                        experienceRow(
                            experience: item.experience,
                            badgeText: badgeText,
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
        .padding(.top, TravSpacing.md)
        .animation(TravAnimation.quick, value: viewModel.selectedTab)
        .animation(TravAnimation.quick, value: viewModel.created.map(\.id))
        .animation(TravAnimation.quick, value: viewModel.saved.map(\.id))
        .animation(TravAnimation.quick, value: viewModel.completed.map(\.id))
    }

    @ViewBuilder
    private func experienceList(_ items: [ExperienceSummary]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, experience in
            experienceRow(
                experience: experience,
                badgeText: "",
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
                    ExperienceCard(
                        experience: experience,
                        badgeText: "Saved",
                        isSaved: true,
                        onTap: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            router.openExperience(experience.id)
                        },
                        onCreatorTap: {
                            router.openProfile(experience.creator.username)
                        },
                        onSave: {
                            Task { await viewModel.unsave(experience, using: environment) }
                        }
                    )
                }
            } else {
                ExperienceCard(
                    experience: experience,
                    badgeText: "Saved",
                    isSaved: engagement.isSaved(experience.id),
                    onTap: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        router.openExperience(experience.id)
                    },
                    onCreatorTap: {
                        router.openProfile(experience.creator.username)
                    },
                    onSave: {
                        Task {
                            await engagement.toggleSave(
                                experienceID: experience.id,
                                summary: experience,
                                using: environment
                            )
                        }
                    }
                )
            }
        }
        .travAppear(delay: Double(min(index, 5)) * 0.03)
        .onAppear {
            if isLast {
                Task { await viewModel.loadMoreIfNeeded(using: environment) }
            }
        }
    }

    @ViewBuilder
    private func experienceRow(
        experience: ExperienceSummary,
        badgeText: String,
        index: Int,
        isLast: Bool
    ) -> some View {
        ExperienceCard(
            experience: experience,
            badgeText: badgeText,
            isSaved: engagement.isSaved(experience.id),
            onTap: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                router.openExperience(experience.id)
            },
            onCreatorTap: {
                router.openProfile(experience.creator.username)
            },
            onSave: {
                Task {
                    await engagement.toggleSave(
                        experienceID: experience.id,
                        summary: experience,
                        using: environment
                    )
                }
            }
        )
        .travAppear(delay: Double(min(index, 5)) * 0.03)
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

    @State private var notificationsEnabled = UserDefaults.standard.bool(forKey: "trav.settings.notificationsEnabled")
    @State private var hapticsEnabled = UserDefaults.standard.bool(forKey: "trav.settings.hapticsEnabled")
    @State private var autoPlayMedia = UserDefaults.standard.bool(forKey: "trav.settings.autoPlayMedia")

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

            VStack(spacing: TravSpacing.md) {
                // Grouped preference box
                VStack(spacing: 0) {
                    ToggleRow(
                        isOn: $notificationsEnabled,
                        icon: "bell.fill",
                        iconColor: Color.blue,
                        title: "Notifications"
                    ) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "trav.settings.notificationsEnabled")
                    }

                    Divider()
                        .background(TravColors.border.opacity(0.2))
                        .padding(.leading, 48)

                    ToggleRow(
                        isOn: $hapticsEnabled,
                        icon: "waveform",
                        iconColor: Color.orange,
                        title: "Haptic Feedback"
                    ) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "trav.settings.hapticsEnabled")
                    }

                    Divider()
                        .background(TravColors.border.opacity(0.2))
                        .padding(.leading, 48)

                    ToggleRow(
                        isOn: $autoPlayMedia,
                        icon: "play.circle.fill",
                        iconColor: Color.green,
                        title: "Auto-Play Experiences"
                    ) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "trav.settings.autoPlayMedia")
                    }
                }
                .background(TravColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(TravColors.border.opacity(0.4), lineWidth: 1)
                )

                // Actions Box
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
            }
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .padding(.top, TravSpacing.sm)

            Spacer()
        }
        .travScreenBackground()
    }
}

struct ToggleRow: View {
    @Binding var isOn: Bool
    let icon: String
    let iconColor: Color
    let title: String
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: TravSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.12))
                .clipShape(Circle())

            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(TravColors.primary)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(TravColors.accent)
                .onChange(of: isOn) { _, newValue in
                    onChange(newValue)
                }
        }
        .padding(.horizontal, TravSpacing.md)
        .padding(.vertical, 10)
    }
}
