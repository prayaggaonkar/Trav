import SwiftUI

enum RankingsTab: String, CaseIterable, Identifiable, Sendable {
    case main = "Main"
    case experiences = "Experiences"
    case streaks = "Streaks"
    case impact = "Impact"

    var id: String { rawValue }
}

struct RankingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(AppearanceStore.self) private var appearance
    @Environment(EngagementStore.self) private var engagement

    @State private var viewModel = RankingsViewModel()
    @State private var selectedTab: RankingsTab = .main
    @State private var showMemberScopeSheet = false
    @State private var showLocationSheet = false

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
        }
        .sheet(isPresented: $showMemberScopeSheet) {
            MemberFilterModalSheet(
                selectedScope: viewModel.memberScope,
                onSelect: { scope in
                    viewModel.selectMemberScope(scope)
                }
            )
        }
        .sheet(isPresented: $showLocationSheet) {
            LocationFilterModalSheet(
                availableLocations: viewModel.availableLocations,
                selectedLocation: viewModel.selectedLocation,
                onSelect: { location in
                    viewModel.selectLocation(location)
                }
            )
        }
    }

    // MARK: - Header Title (Matching App Typography)

    private var header: some View {
        HStack {
            Text("Rankings")
                .font(TravTypography.displayLarge())
                .foregroundStyle(TravColors.primary)
            Spacer()
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.top, TravSpacing.md)
        .padding(.bottom, TravSpacing.md)
    }

    // MARK: - Top Tab Bar ("Main", "Experiences", "Streaks", and "Impact")

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
                        .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(selectedTab == tab ? TravColors.primary : TravColors.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if selectedTab == tab {
                                    RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                        .fill(TravColors.surfaceElevated)
                                        .shadow(color: Color.black.opacity(0.08), radius: 3, y: 1)
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
                .fill(appearance.isLightMode ? Color(red: 0.94, green: 0.94, blue: 0.96) : Color.white.opacity(0.08))
        )
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.bottom, 12)
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
            .padding(.bottom, TravSpacing.md)
    }

    // MARK: - Filter Pills Row (Member Scope & Location)

    private var filterPillsRow: some View {
        HStack(spacing: 12) {
            // Member Scope Pill (All Members / Friends)
            FilterPillButton(
                title: viewModel.memberScope.title
            ) {
                showMemberScopeSheet = true
            }

            // Location Filter Pill (Worldwide / Dublin, CA / etc.)
            FilterPillButton(
                title: viewModel.selectedLocation.name
            ) {
                showLocationSheet = true
            }

            Spacer()
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.bottom, TravSpacing.md)
    }

    // MARK: - Main Content List (Experiences Tab)

    @ViewBuilder
    private var content: some View {
        let entries = viewModel.filteredEntries(
            followingIDs: engagement.followingUserIDs,
            currentUserID: environment.session.currentUser?.id
        )

        if entries.isEmpty {
            EmptyStateView(
                icon: "crown",
                title: "No members found",
                description: "No members match the selected filters. Try choosing a different location or member scope."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        LeaderboardUserRow(
                            rank: index + 1,
                            entry: entry,
                            onTap: {
                                router.openProfile(entry.username)
                            }
                        )
                    }
                }
                .padding(.bottom, TravSpacing.tabBarBottom + 40)
            }
            .refreshable {
                await viewModel.reload(using: environment)
            }
        }
    }
}
