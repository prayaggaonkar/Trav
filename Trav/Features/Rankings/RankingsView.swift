import SwiftUI

struct RankingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(AppearanceStore.self) private var appearance

    @State private var viewModel = RankingsViewModel()
    @State private var isSearchFocused = false

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            modeTabBar
            axisChips
            content
        }
        .travScreenBackground()
        .task {
            await viewModel.bootstrap(using: environment)
        }
        .onChange(of: viewModel.mode) { _, _ in
            Task { await viewModel.reload(using: environment) }
        }
        .onChange(of: viewModel.axis) { _, _ in
            Task { await viewModel.reload(using: environment) }
        }
        .onChange(of: viewModel.selectedCity?.id) { _, _ in
            Task { await viewModel.reload(using: environment) }
        }
    }

    private var header: some View {
        HStack {
            Text("Rankings")
                .font(TravTypography.displayMedium())
                .foregroundStyle(TravColors.primary)
            Spacer()
            Image(systemName: "crown.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(TravColors.accent)
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.top, TravSpacing.md)
        .padding(.bottom, TravSpacing.sm)
    }

    /// Profile-style underline tabs for Experiences / Creators.
    private var modeTabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(RankingMode.allCases) { mode in
                    Button {
                        withAnimation(TravAnimation.tab) {
                            viewModel.mode = mode
                            viewModel.clearCreator()
                        }
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 14, weight: viewModel.mode == mode ? .semibold : .regular, design: .rounded))
                            .foregroundStyle(viewModel.mode == mode ? TravColors.primary : TravColors.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, TravSpacing.sm)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(TravColors.border.opacity(0.55))
                    .frame(height: 0.5)

                GeometryReader { geo in
                    let tabs = RankingMode.allCases
                    let width = geo.size.width / CGFloat(tabs.count)
                    let index = tabs.firstIndex(of: viewModel.mode) ?? 0
                    Rectangle()
                        .fill(TravColors.primary)
                        .frame(width: width * 0.45, height: 1.5)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .offset(x: width * CGFloat(index) + width * 0.275)
                        .animation(TravAnimation.tab, value: viewModel.mode)
                }
                .frame(height: 1.5)
            }
            .frame(height: 1.5)
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.bottom, TravSpacing.sm)
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            FeedSearchBar(
                text: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.searchText = $0 }
                ),
                placeholder: "Search spots, cities, creators...",
                isFocused: $isSearchFocused,
                isLightMode: appearance.isLightMode,
                cityToken: viewModel.selectedCity,
                userToken: nil,
                onClearCity: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.clearCity()
                    }
                }
            )
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .padding(.vertical, TravSpacing.xs)

            if isSearchFocused && !viewModel.matchingCities.isEmpty {
                citySuggestionsOverlay
                    .padding(.horizontal, TravSpacing.screenHorizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.bottom, TravSpacing.xs)
    }

    private var citySuggestionsOverlay: some View {
        VStack(alignment: .leading, spacing: TravSpacing.xs) {
            Text("CITIES")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(
                    appearance.isLightMode ? Color.black.opacity(0.55) : Color.white.opacity(0.6)
                )
                .padding(.horizontal, TravSpacing.xs)

            VStack(spacing: 6) {
                ForEach(viewModel.matchingCities.prefix(5)) { city in
                    Button {
                        viewModel.selectCity(city)
                        isSearchFocused = false
                    } label: {
                        HStack(spacing: TravSpacing.sm) {
                            ZStack {
                                Circle()
                                    .fill(TravColors.accent.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(TravColors.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(city.name)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(appearance.isLightMode ? Color.black : Color.white)
                                Text(city.locationLabel)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(TravColors.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(TravColors.muted.opacity(0.6))
                        }
                        .padding(.horizontal, TravSpacing.sm)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: TravRadius.sm, style: .continuous)
                                .fill(
                                    appearance.isLightMode
                                        ? Color.white.opacity(0.85)
                                        : Color.white.opacity(0.08)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(TravSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, appearance.isLightMode ? .light : .dark)
        )
        .overlay {
            RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                .stroke(
                    appearance.isLightMode ? Color.black.opacity(0.1) : Color.white.opacity(0.12),
                    lineWidth: 1
                )
        }
        .padding(.vertical, TravSpacing.xs)
    }

    private var axisChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TravSpacing.sm) {
                ForEach(RankingAxis.allCases) { axis in
                    SelectionChip(
                        title: axis.title,
                        isSelected: viewModel.axis == axis
                    ) {
                        viewModel.axis = axis
                    }
                }
            }
            .padding(.horizontal, TravSpacing.screenHorizontal)
        }
        .padding(.bottom, TravSpacing.sm)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle, .loading:
            ProgressView()
                .tint(TravColors.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ErrorStateView(message: error.localizedDescription) {
                Task { await viewModel.reload(using: environment) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            EmptyStateView(
                icon: "crown",
                title: emptyTitle,
                description: emptyDescription
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            listContent
        }
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                switch viewModel.mode {
                case .experiences:
                    ForEach(Array(viewModel.experiences.enumerated()), id: \.element.id) { index, experience in
                        RankedExperienceRow(
                            rank: index + 1,
                            experience: experience,
                            axis: viewModel.axis,
                            onTap: { router.openExperience(experience.id) },
                            onCreatorTap: { router.openProfile(experience.creator.username) }
                        )
                        if index < viewModel.experiences.count - 1 {
                            Divider()
                                .overlay(TravColors.border.opacity(0.45))
                                .padding(.leading, TravSpacing.screenHorizontal + 28 + TravSpacing.md)
                        }
                    }
                case .creators:
                    let creators = viewModel.creators
                    ForEach(Array(creators.enumerated()), id: \.element.id) { index, creator in
                        RankedCreatorRow(
                            rank: index + 1,
                            creator: creator,
                            onTap: { router.openProfile(creator.profile.username) }
                        )
                        if index < creators.count - 1 {
                            Divider()
                                .overlay(TravColors.border.opacity(0.45))
                                .padding(.leading, TravSpacing.screenHorizontal + 28 + TravSpacing.md)
                        }
                    }
                }
            }
            .padding(.bottom, TravSpacing.tabBarBottom + 80)
        }
        .refreshable {
            await viewModel.reload(using: environment)
        }
    }

    private var emptyTitle: String {
        if viewModel.selectedCity != nil {
            return "No rankings match"
        }
        return viewModel.mode == .experiences ? "No experiences yet" : "No creators yet"
    }

    private var emptyDescription: String {
        if viewModel.selectedCity != nil {
            return "Try clearing the city filter or picking a different axis."
        }
        return "Publish an experience to see it show up here. Ratings push posts higher in the list."
    }
}
