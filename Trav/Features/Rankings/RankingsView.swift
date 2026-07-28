import SwiftUI

struct RankingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(AppearanceStore.self) private var appearance

    @State private var viewModel = RankingsViewModel()
    @State private var showMemberScopeSheet = false
    @State private var showLocationSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            topTabBar
            subHeader
            filterPillsRow
            content
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

    // MARK: - Top Tab Bar ("Experiences" only, matching app theme)

    private var topTabBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Experiences")
                    .font(TravTypography.titleMedium())
                    .foregroundStyle(TravColors.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                            .fill(TravColors.surfaceElevated)
                            .shadow(color: Color.black.opacity(0.08), radius: 3, y: 1)
                    )
                Spacer()
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                    .fill(appearance.isLightMode ? Color(red: 0.94, green: 0.94, blue: 0.96) : Color.white.opacity(0.08))
            )
            Spacer()
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.bottom, 12)
    }

    // MARK: - Subheader Description

    private var subHeader: some View {
        Text("Number of experiences created")
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

            // Location Filter Pill (Dublin, CA / All Locations / etc.)
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

    // MARK: - Main Content List

    @ViewBuilder
    private var content: some View {
        let entries = viewModel.filteredEntries

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
