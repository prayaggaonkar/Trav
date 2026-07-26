import SwiftUI

struct RankingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(AppearanceStore.self) private var appearance

    @State private var viewModel = RankingsViewModel()
    @State private var isSearchFocused = false
    @State private var userSearchResults: [ProfileSummary] = []
    @State private var isSearchingUsers = false
    @State private var userSearchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            modePicker
            filterBar
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
        .onChange(of: viewModel.selectedCreator?.id) { _, _ in
            Task { await viewModel.reload(using: environment) }
        }
        .onChange(of: viewModel.searchText) { _, newValue in
            scheduleUserSearch(for: newValue)
            viewModel.applyCreatorSearchFilter()
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

    private var modePicker: some View {
        HStack(spacing: TravSpacing.sm) {
            ForEach(RankingMode.allCases) { mode in
                SelectionChip(
                    title: mode.title,
                    isSelected: viewModel.mode == mode
                ) {
                    withAnimation(TravAnimation.quick) {
                        viewModel.mode = mode
                        if mode == .creators {
                            viewModel.clearCreator()
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.bottom, TravSpacing.sm)
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: TravSpacing.xs) {
            FeedSearchBar(
                text: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.searchText = $0 }
                ),
                placeholder: viewModel.mode == .experiences
                    ? "Filter by city or creator..."
                    : "Filter by city or search creators...",
                isFocused: $isSearchFocused,
                isLightMode: appearance.isLightMode,
                cityToken: viewModel.selectedCity,
                userToken: viewModel.mode == .experiences ? viewModel.selectedCreator : nil,
                onClearCity: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.clearCity()
                    }
                },
                onClearUser: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.clearCreator()
                    }
                }
            )
            .padding(.horizontal, TravSpacing.screenHorizontal)

            if isSearchFocused && showsSuggestions {
                suggestionsOverlay
                    .padding(.horizontal, TravSpacing.screenHorizontal)
            }
        }
        .padding(.bottom, TravSpacing.sm)
    }

    private var showsSuggestions: Bool {
        !viewModel.matchingCities.isEmpty
            || isSearchingUsers
            || (!userSearchResults.isEmpty && viewModel.mode == .experiences)
    }

    private var suggestionsOverlay: some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            if !viewModel.matchingCities.isEmpty {
                suggestionSection(title: "CITIES") {
                    ForEach(viewModel.matchingCities.prefix(5)) { city in
                        Button {
                            viewModel.selectCity(city)
                            isSearchFocused = false
                        } label: {
                            suggestionRow(
                                title: city.name,
                                subtitle: city.locationLabel,
                                systemImage: "mappin.circle.fill"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if viewModel.mode == .experiences, isSearchingUsers || !userSearchResults.isEmpty {
                suggestionSection(title: "CREATORS") {
                    if isSearchingUsers && userSearchResults.isEmpty {
                        ProgressView()
                            .tint(TravColors.muted)
                            .padding(.vertical, TravSpacing.sm)
                    }
                    ForEach(userSearchResults.prefix(5)) { user in
                        Button {
                            viewModel.selectCreator(user)
                            isSearchFocused = false
                        } label: {
                            HStack(spacing: TravSpacing.sm) {
                                AvatarView(url: user.avatarURL, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(TravColors.primary)
                                    Text("@\(user.username)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(TravColors.muted)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, TravSpacing.sm)
                            .padding(.vertical, 8)
                            .background(TravColors.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func suggestionSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: TravSpacing.xs) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(TravColors.muted)
                .padding(.horizontal, TravSpacing.xs)
            content()
        }
    }

    private func suggestionRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: TravSpacing.sm) {
            ZStack {
                Circle()
                    .fill(TravColors.accent.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(TravColors.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(TravColors.primary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TravColors.muted)
            }
            Spacer()
        }
        .padding(.horizontal, TravSpacing.sm)
        .padding(.vertical, 8)
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
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
                    let creators = viewModel.displayedCreators
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
        if viewModel.selectedCity != nil || viewModel.selectedCreator != nil {
            return "No rankings match"
        }
        return viewModel.mode == .experiences ? "No experiences yet" : "No creators yet"
    }

    private var emptyDescription: String {
        if viewModel.selectedCity != nil || viewModel.selectedCreator != nil {
            return "Try clearing a filter or picking a different axis."
        }
        return "Publish an experience to see it show up here. Ratings push posts higher in the list."
    }

    private func scheduleUserSearch(for query: String) {
        userSearchTask?.cancel()
        guard viewModel.mode == .experiences else {
            userSearchResults = []
            isSearchingUsers = false
            return
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            userSearchResults = []
            isSearchingUsers = false
            return
        }
        isSearchingUsers = true
        userSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            let results = (try? await environment.profiles.searchUsers(query: trimmed)) ?? []
            guard !Task.isCancelled else { return }
            userSearchResults = results
            isSearchingUsers = false
        }
    }
}
