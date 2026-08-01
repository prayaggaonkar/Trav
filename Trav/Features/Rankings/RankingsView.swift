import SwiftUI

enum RankingsTab: String, CaseIterable, Identifiable, Sendable {
    case main = "Main"
    case experiences = "Experiences"
    case streaks = "Streaks"
    case impact = "Impact"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .main: return "trophy.fill"
        case .experiences: return "map.fill"
        case .streaks: return "flame.fill"
        case .impact: return "bookmark.fill"
        }
    }
}

struct RankingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(AppearanceStore.self) private var appearance
    @Environment(EngagementStore.self) private var engagement

    @State private var viewModel = RankingsViewModel()
    @State private var selectedTab: RankingsTab = .main
    @State private var showCombinedFilterSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            topTabBar
            subHeader
            filterPillsRow

            switch selectedTab {
            case .main:
                MainLeaderboardView(
                    memberScope: viewModel.memberScope,
                    selectedLocation: viewModel.selectedLocation
                )
            case .experiences:
                content
            case .streaks:
                TrendingLeaderboardView(
                    memberScope: viewModel.memberScope,
                    selectedLocation: viewModel.selectedLocation
                )
            case .impact:
                ImpactLeaderboardView(
                    memberScope: viewModel.memberScope,
                    selectedLocation: viewModel.selectedLocation
                )
            }
        }
        .travScreenBackground()
        .task {
            await viewModel.bootstrap(using: environment)
            for await _ in environment.experiences.observeExperiencesInsert() {
                await viewModel.reload(using: environment)
            }
        }
        .task(id: engagement.revision) {
            await viewModel.reload(using: environment)
        }
        .task(id: router.experienceCatalogRevision) {
            await viewModel.reload(using: environment)
        }
        .onChange(of: selectedTab) { _, _ in
            Task {
                await viewModel.reload(using: environment)
            }
        }
        .fullScreenCover(isPresented: $showCombinedFilterSheet) {
            CombinedFilterModalSheet(
                availableLocations: viewModel.availableLocations,
                selectedScope: viewModel.memberScope,
                selectedLocation: viewModel.selectedLocation,
                onApply: { scope, location in
                    viewModel.selectMemberScope(scope)
                    viewModel.selectLocation(location)
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ExperiencePublishedNotification"))) { _ in
            Task { await viewModel.reload(using: environment) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ExperienceSavedNotification"))) { _ in
            Task { await viewModel.reload(using: environment) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ExperienceUnsavedNotification"))) { _ in
            Task { await viewModel.reload(using: environment) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ExperienceCompletedNotification"))) { _ in
            Task { await viewModel.reload(using: environment) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UserProfileUpdatedNotification"))) { _ in
            Task { await viewModel.reload(using: environment) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FollowStateChangedNotification"))) { _ in
            Task { await viewModel.reload(using: environment) }
        }
    }

    // MARK: - Header Title

    private var header: some View {
        HStack {
            Text("Rankings")
                .font(TravTypography.displayLarge())
                .foregroundStyle(TravColors.primary)
            Spacer()
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.top, TravSpacing.md)
        .padding(.bottom, TravSpacing.sm)
    }

    // MARK: - Top Tab Bar ("Main", "Experiences", "Streaks", and "Impact" - Icons Removed)

    private var topTabBar: some View {
        HStack(spacing: 3) {
            ForEach(RankingsTab.allCases) { tab in
                Button {
                    withAnimation(TravAnimation.quick) {
                        selectedTab = tab
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: selectedTab == tab ? .bold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(selectedTab == tab ? TravColors.accent : TravColors.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            Group {
                                if selectedTab == tab {
                                    RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                        .fill(TravColors.surfaceElevated)
                                        .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                .fill(appearance.isLightMode ? Color(red: 0.93, green: 0.93, blue: 0.95) : Color.white.opacity(0.08))
        )
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.bottom, 10)
    }

    // MARK: - Subheader Description

    private var subHeader: some View {
        let text: String = {
            switch selectedTab {
            case .main:
                return "Ranked by total score combining impact, experiences, and streaks"
            case .experiences:
                return "Number of experiences created"
            case .streaks:
                return "Active consecutive daily posting streaks"
            case .impact:
                return "Ranked by total completions and saves across all published experiences"
            }
        }()

        return Text(text)
            .font(TravTypography.bodyMedium())
            .foregroundStyle(TravColors.muted)
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .padding(.bottom, 10)
    }

    // MARK: - Combined Filter Pill (Renamed to "Filter Rankings", Icon Removed)

    private var filterPillsRow: some View {
        HStack {
            Button {
                showCombinedFilterSheet = true
            } label: {
                HStack(spacing: 6) {
                    Text("Filter Rankings")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(TravColors.primary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(TravColors.muted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(TravColors.surfaceElevated)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(TravColors.border.opacity(0.4), lineWidth: 1)
                )
            }
            .buttonStyle(TravPressButtonStyle(scale: 0.96))

            Spacer()
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.bottom, 12)
    }

    // MARK: - Main Content List (Experiences Tab)

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            SkeletonRankingsList()
        } else {
            let entries = viewModel.filteredEntries(
                followingIDs: engagement.followingUserIDs,
                currentUserID: environment.session.currentUser?.id
            )

            ScrollView {
                if entries.isEmpty {
                    EmptyStateView(
                        icon: "map",
                        title: "No members found",
                        description: "No members match the selected filters. Try choosing a different location or member scope."
                    )
                    .padding(.top, 40)
                } else {
                    VStack(spacing: 0) {
                        if entries.count >= 3 {
                            RankingsPodiumView<LeaderboardEntry>(
                                topThree: Array(entries.prefix(3)),
                                displayName: { $0.displayName },
                                username: { $0.username },
                                avatarURL: { $0.avatarURL },
                                metricValue: { "\($0.experienceCount)" },
                                metricIcon: "map.fill",
                                onTap: { router.openProfile($0.username) }
                            )
                        }

                        let listEntries = entries.count >= 3 ? Array(entries.dropFirst(3)) : entries
                        let startIndex = entries.count >= 3 ? 4 : 1

                        if !listEntries.isEmpty {
                            RankingsListView<LeaderboardEntry>(
                                items: listEntries,
                                startIndex: startIndex,
                                displayName: { $0.displayName },
                                username: { $0.username },
                                avatarURL: { $0.avatarURL },
                                metricValue: { "\($0.experienceCount)" },
                                metricIcon: "map.fill",
                                onTap: { router.openProfile($0.username) }
                            )
                        }
                    }
                    .padding(.bottom, TravSpacing.tabBarBottom + 40)
                }
            }
            .refreshable {
                await viewModel.reload(using: environment)
            }
        }
    }
}
