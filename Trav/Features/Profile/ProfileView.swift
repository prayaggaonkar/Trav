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
            .toolbar(showDismissButton ? .automatic : .hidden, for: .navigationBar)
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
            .fullScreenCover(isPresented: $showSettings) {
                SettingsSheetView {
                    Task { await viewModel.signOut(using: environment) }
                }
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
        // Chrome lives in a top safeAreaInset so ScrollView / Map cards in any tab
        // cannot change its position or inject extra top inset.
        ScrollView {
            tabContent
                .id(viewModel.selectedTab)
                .padding(.bottom, TravSpacing.xxl + TravSpacing.lg)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            profileChrome(profile)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TravColors.surface)
                .navBarZoomable()
        }
        .trackScrollForNavBarZoom()
        .refreshable {
            await viewModel.refresh(using: environment)
        }
    }

    @ViewBuilder
    private func profileChrome(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            if isOwnProfile {
                HStack {
                    Spacer(minLength: 0)
                    profileMenu
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.top, TravSpacing.xs)
                .frame(height: 32, alignment: .center)
            }

            passportHeaderCard(profile)
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.top, isOwnProfile ? 0 : TravSpacing.xs)

            actionRow(profile)
                .padding(.horizontal, TravSpacing.screenHorizontal)

            if isOwnProfile, viewModel.isSuggestionsExpanded {
                SuggestedUsersSection(
                    users: viewModel.suggestedUsers,
                    isLoading: viewModel.isLoadingSuggestions,
                    contactsAuthorization: viewModel.contactsAuthorization,
                    onSelect: { suggestion in
                        router.openProfile(suggestion.profile.username)
                    },
                    onFollow: { suggestion in
                        Task { await viewModel.followSuggestion(suggestion, using: environment) }
                    },
                    onDismiss: { suggestion in
                        withAnimation(TravAnimation.quick) {
                            viewModel.dismissSuggestion(suggestion.id)
                        }
                    },
                    onSyncContacts: {
                        Task { await viewModel.requestContactsAccess(using: environment) }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
                .padding(.horizontal, TravSpacing.screenHorizontal)
            }

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
                    .saved: viewModel.saved.count,
                    .completed: viewModel.completed.count
                ],
                onSelect: { tab in
                    Task { await viewModel.selectTab(tab, using: environment) }
                }
            )
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .padding(.top, TravSpacing.xs)
            .padding(.bottom, TravSpacing.xs)
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(TravAnimation.enter, value: viewModel.isSuggestionsExpanded)
    }

    @ViewBuilder
    private func passportHeaderCard(_ profile: Profile) -> some View {
        VStack(spacing: TravSpacing.xs + 2) {
            // Avatar (Clean, no border ring)
            AvatarView(url: profile.avatarURL, size: 84)

            // Display Name, Verification Seal, and Username
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(profile.displayName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(TravColors.primary)
                        .lineLimit(1)

                    if profile.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(TravColors.accent)
                    }
                }

                Text("@\(profile.username)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(TravColors.muted)
            }

            // Location Pill
            if let city = profile.homeCityLabel {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TravColors.accent)
                    Text(city)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(TravColors.primary)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(TravColors.accentSoft)
                .clipShape(Capsule())
            }

            // Bio Block
            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(.system(size: 13.5, weight: .regular, design: .rounded))
                    .foregroundStyle(TravColors.primary.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, TravSpacing.xs)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Stat Metrics (Followers, Following, Rank)
            ProfileStatsRow(
                profile: profile,
                rankLabel: viewModel.creatorRankLabel,
                onFollowers: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    followListMode = .followers
                },
                onFollowing: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    followListMode = .following
                },
                onRankTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            )
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func actionRow(_ profile: Profile) -> some View {
        if isOwnProfile {
            HStack(spacing: TravSpacing.sm) {
                Button {
                    showEditProfile = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .bold))
                        Text("Edit profile")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(TravColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(TravColors.surfaceElevated)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(TravColors.border.opacity(0.5), lineWidth: 1)
                    )
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.97))

                ShareLink(item: URL(string: "https://trav.app/user/\(profile.username)")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .bold))
                        Text("Share")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(TravColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(TravColors.surfaceElevated)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(TravColors.border.opacity(0.5), lineWidth: 1)
                    )
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.97))

                Button {
                    Task {
                        await viewModel.toggleSuggestions(using: environment)
                    }
                } label: {
                    Image(systemName: viewModel.isSuggestionsExpanded ? "person.badge.plus.fill" : "person.badge.plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(viewModel.isSuggestionsExpanded ? TravColors.accent : TravColors.primary)
                        .frame(width: 38, height: 38)
                        .background(viewModel.isSuggestionsExpanded ? TravColors.accentSoft : TravColors.surfaceElevated)
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(viewModel.isSuggestionsExpanded ? TravColors.accent.opacity(0.4) : TravColors.border.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.96))
                .accessibilityLabel(viewModel.isSuggestionsExpanded ? "Hide suggested users" : "Find people to follow")
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
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .bold))
                        Text("Share profile")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(TravColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(TravColors.surfaceElevated)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(TravColors.border.opacity(0.5), lineWidth: 1)
                    )
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.97))
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
                            badgeText: isOwnProfile ? "Created by You" : "",
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
                        title: "Your watchlist is empty",
                        description: "Add experiences to your watchlist to start planning your journey."
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
    @State private var notifyFollows = UserDefaults.standard.object(forKey: "trav.settings.notifyFollows") as? Bool ?? true
    @State private var notifyReplies = UserDefaults.standard.object(forKey: "trav.settings.notifyReplies") as? Bool ?? true
    @State private var notifyLikes = UserDefaults.standard.object(forKey: "trav.settings.notifyLikes") as? Bool ?? true
    @State private var notifyUpdates = UserDefaults.standard.object(forKey: "trav.settings.notifyUpdates") as? Bool ?? true

    @State private var hapticsEnabled = UserDefaults.standard.bool(forKey: "trav.settings.hapticsEnabled")
    @State private var autoPlayMedia = UserDefaults.standard.bool(forKey: "trav.settings.autoPlayMedia")
    @State private var showBlockedUsers = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TravSpacing.lg) {
                    // MARK: - Notification Preferences Section
                    VStack(alignment: .leading, spacing: TravSpacing.xs) {
                        Text("NOTIFICATION PREFERENCES")
                            .font(TravTypography.overline())
                            .tracking(1.5)
                            .foregroundStyle(TravColors.muted)
                            .padding(.horizontal, TravSpacing.xs)

                        VStack(spacing: 0) {
                            ToggleRow(
                                isOn: $notificationsEnabled,
                                icon: "bell.fill",
                                iconColor: TravColors.accent,
                                title: "Push Notifications"
                            ) { newValue in
                                UserDefaults.standard.set(newValue, forKey: "trav.settings.notificationsEnabled")
                                Task {
                                    if newValue, let userID = environment.session.currentUser?.id {
                                        await PushNotificationService.shared.registerIfNeeded(
                                            userID: userID,
                                            using: environment
                                        )
                                    } else {
                                        await PushNotificationService.shared.unregister(using: environment)
                                    }
                                }
                            }

                            if notificationsEnabled {
                                Divider()
                                    .background(TravColors.border.opacity(0.2))
                                    .padding(.leading, 48)

                                ToggleSubRow(
                                    isOn: $notifyFollows,
                                    icon: "person.badge.plus.fill",
                                    iconColor: TravColors.accent,
                                    title: "New Followers",
                                    subtitle: "When someone starts following your profile"
                                ) { newValue in
                                    UserDefaults.standard.set(newValue, forKey: "trav.settings.notifyFollows")
                                }

                                Divider()
                                    .background(TravColors.border.opacity(0.2))
                                    .padding(.leading, 48)

                                ToggleSubRow(
                                    isOn: $notifyReplies,
                                    icon: "bubble.left.and.bubble.right.fill",
                                    iconColor: TravColors.accent,
                                    title: "Replies & Comments",
                                    subtitle: "When someone comments or replies on your posts"
                                ) { newValue in
                                    UserDefaults.standard.set(newValue, forKey: "trav.settings.notifyReplies")
                                }

                                Divider()
                                    .background(TravColors.border.opacity(0.2))
                                    .padding(.leading, 48)

                                ToggleSubRow(
                                    isOn: $notifyLikes,
                                    icon: "heart.fill",
                                    iconColor: TravColors.accent,
                                    title: "Likes & Saves",
                                    subtitle: "When someone likes or saves your experiences"
                                ) { newValue in
                                    UserDefaults.standard.set(newValue, forKey: "trav.settings.notifyLikes")
                                }

                                Divider()
                                    .background(TravColors.border.opacity(0.2))
                                    .padding(.leading, 48)

                                ToggleSubRow(
                                    isOn: $notifyUpdates,
                                    icon: "sparkles",
                                    iconColor: TravColors.accent,
                                    title: "Experience Updates",
                                    subtitle: "Activity on creators and routes you follow"
                                ) { newValue in
                                    UserDefaults.standard.set(newValue, forKey: "trav.settings.notifyUpdates")
                                }
                            }
                        }
                        .background(TravColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(TravColors.border.opacity(0.4), lineWidth: 1)
                        )
                    }

                    // MARK: - App Preferences
                    VStack(alignment: .leading, spacing: TravSpacing.xs) {
                        Text("APP PREFERENCES")
                            .font(TravTypography.overline())
                            .tracking(1.5)
                            .foregroundStyle(TravColors.muted)
                            .padding(.horizontal, TravSpacing.xs)

                        VStack(spacing: 0) {
                            ToggleRow(
                                isOn: Binding(
                                    get: { !environment.appearance.isLightMode },
                                    set: { isDark in
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        if isDark {
                                            environment.appearance.modeRaw = "dark"
                                        } else {
                                            environment.appearance.modeRaw = "light"
                                        }
                                    }
                                ),
                                icon: "moon.fill",
                                iconColor: TravColors.accent,
                                title: "Dark Mode"
                            ) { _ in }

                            Divider()
                                .background(TravColors.border.opacity(0.2))
                                .padding(.leading, 48)

                            ToggleRow(
                                isOn: $hapticsEnabled,
                                icon: "waveform",
                                iconColor: TravColors.accent,
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
                                iconColor: TravColors.accent,
                                title: "Auto-Play Media"
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
                    }

                    // MARK: - Privacy & Safety
                    VStack(alignment: .leading, spacing: TravSpacing.xs) {
                        Text("PRIVACY & SAFETY")
                            .font(TravTypography.overline())
                            .tracking(1.5)
                            .foregroundStyle(TravColors.muted)
                            .padding(.horizontal, TravSpacing.xs)

                        VStack(spacing: 0) {
                            Button {
                                showBlockedUsers = true
                            } label: {
                                HStack(spacing: TravSpacing.md) {
                                    Image(systemName: "hand.raised.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(TravColors.accent)
                                        .frame(width: 24, alignment: .center)

                                    Text("Blocked Users")
                                        .font(TravTypography.bodyMedium())
                                        .foregroundStyle(TravColors.primary)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(TravColors.muted)
                                }
                                .padding(.horizontal, TravSpacing.md)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                        .background(TravColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(TravColors.border.opacity(0.4), lineWidth: 1)
                        )
                    }

                    // MARK: - Account Actions
                    VStack(alignment: .leading, spacing: TravSpacing.xs) {
                        Text("ACCOUNT")
                            .font(TravTypography.overline())
                            .tracking(1.5)
                            .foregroundStyle(TravColors.muted)
                            .padding(.horizontal, TravSpacing.xs)

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            dismiss()
                            onSignOut()
                        } label: {
                            HStack(spacing: TravSpacing.md) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.red)
                                    .frame(width: 24, alignment: .center)

                                Text("Sign Out")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.red)

                                Spacer()
                            }
                            .padding(.horizontal, TravSpacing.md)
                            .padding(.vertical, 12)
                            .background(TravColors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.vertical, TravSpacing.lg)
            }
            .travScreenBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(TravTypography.titleMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(TravColors.accent)
                }
            }
            .sheet(isPresented: $showBlockedUsers) {
                BlockedUsersView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

private struct ToggleSubRow: View {
    @Binding var isOn: Bool
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: TravSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(TravColors.primary)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(TravColors.muted)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(TravColors.accent)
                .onChange(of: isOn) { _, newValue in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onChange(newValue)
                }
        }
        .padding(.horizontal, TravSpacing.md)
        .padding(.vertical, 10)
    }
}

// MARK: - Blocked users

struct BlockedUsersView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var blocked: [ProfileSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().tint(TravColors.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) {
                        Task { await load() }
                    }
                } else if blocked.isEmpty {
                    EmptyStateView(
                        icon: "hand.raised",
                        title: "No blocked users",
                        description: "People you block won't be able to interact with you on Trav."
                    )
                } else {
                    List {
                        ForEach(blocked) { profile in
                            HStack(spacing: TravSpacing.md) {
                                AvatarView(url: profile.avatarURL, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.displayName)
                                        .font(TravTypography.bodyMedium())
                                    Text("@\(profile.username)")
                                        .font(TravTypography.labelMedium())
                                        .foregroundStyle(TravColors.muted)
                                }
                                Spacer()
                                Button("Unblock") {
                                    Task { await unblock(profile) }
                                }
                                .font(TravTypography.labelMedium())
                                .foregroundStyle(TravColors.accent)
                            }
                            .listRowBackground(TravColors.surface)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .travScreenBackground()
            .navigationTitle("Blocked Users")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(TravColors.accent)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard let userID = environment.session.currentUser?.id else {
            blocked = []
            return
        }
        do {
            let ids = try await environment.engagementRepo.fetchBlockedIDs(userID: userID)
            var profiles: [ProfileSummary] = []
            for id in ids {
                if let profile = try? await environment.profiles.fetchProfile(id: id) {
                    profiles.append(profile.summary)
                }
            }
            blocked = profiles.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unblock(_ profile: ProfileSummary) async {
        guard let userID = environment.session.currentUser?.id else { return }
        do {
            try await environment.engagementRepo.unblock(blockerID: userID, blockedID: profile.id)
            blocked.removeAll { $0.id == profile.id }
        } catch {
            errorMessage = error.localizedDescription
        }
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 24, alignment: .center)

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
