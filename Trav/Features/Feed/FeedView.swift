import SwiftUI
import UniformTypeIdentifiers

enum FeedFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case itineraries = "Itineraries"
    case singleSpots = "Single Spots"
    case saved = "Saved"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .itineraries: return "map"
        case .singleSpots: return "pin"
        case .saved: return "bookmark.fill"
        }
    }
}

struct QuickPlannerDropDelegate: DropDelegate {
    @Binding var draftStops: [StopPreview]
    @Binding var draftCityName: String?
    let feedItems: [ExperienceSummary]

    func performDrop(info: DropInfo) -> Bool {
        guard let itemProvider = info.itemProviders(for: [.text]).first else { return false }

        itemProvider.loadItem(forTypeIdentifier: "public.text", options: nil) { textData, _ in
            guard let data = textData as? Data,
                  let idString = String(data: data, encoding: .utf8),
                  let experienceUUID = UUID(uuidString: idString) else {
                return
            }

            if let matched = feedItems.first(where: { $0.id == experienceUUID }) {
                DispatchQueue.main.async {
                    let stop = StopPreview(
                        id: UUID(),
                        name: matched.title,
                        emoji: matched.stops.first?.emoji ?? "📍"
                    )
                    draftStops.append(stop)
                    if draftCityName == nil {
                        draftCityName = matched.cityName
                    }
                }
            }
        }
        return true
    }
}

struct FeedView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppearanceStore.self) private var appearance
    @Environment(EngagementStore.self) private var engagement

    /// When false (Feed tab hidden), city/user/keyword tags are cleared.
    /// Stays true while an experience/profile cover is presented over Feed.
    var isActive: Bool = true

    @State private var viewModel = FeedViewModel()
    @State private var selectedFilter: FeedFilter = .all
    @State private var selectedPopup: Popup?
    @State private var shareItem: ShareItem?

    // Search
    @State private var searchText = ""
    @State private var isSearchFocused = false
    @State private var catalogCities: [City] = []
    @State private var userSearchResults: [ProfileSummary] = []
    @State private var userSearchTask: Task<Void, Never>?
    @State private var isSearchingUsers = false

    // Spot Search & Rating
    @State private var spotSearchController = SpotSearchController()
    @State private var cityLocator = CurrentCityLocator()
    @State private var selectedSpotDetail: SpotSuggestion? = nil

    // Quick Planner state
    @State private var draftStops: [StopPreview] = []
    @State private var draftCityName: String?
    @State private var itineraryTitle: String = ""
    @State private var isSavingItinerary = false
    @State private var plannerError: String?

    private var showSearchSuggestions: Bool {
        isSearchFocused && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            TravColors.surface
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, TravSpacing.screenHorizontal)
                    .padding(.top, TravSpacing.sm)

                // Filters + feed; search results sit flush under the bar and cover the chips.
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        filterChips
                        feedBody
                    }

                    if showSearchSuggestions {
                        searchSuggestionsOverlay
                            .padding(.horizontal, TravSpacing.screenHorizontal)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .zIndex(10)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            quickPlannerPanel
        }
        .tabBarBackdrop(feedTabBarBackdrop)
        .travShareSheet(item: $shareItem)
        .sheet(item: $selectedPopup) { popup in
            PopupDetailSheet(popup: popup)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(TravRadius.xl)
        }
        .sheet(item: $selectedSpotDetail) { spot in
            SpotDetailSheet(spot: spot)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(TravRadius.xl)
        }
        .alert("Couldn't Save Route", isPresented: Binding(
            get: { plannerError != nil },
            set: { if !$0 { plannerError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(plannerError ?? "")
        }
        .task {
            if let userID = session.currentUser?.id {
                await engagement.bootstrap(userID: userID, using: environment)
            }
            catalogCities = (try? await environment.cities.fetchGlobeCities()) ?? []
            let userCoord = await cityLocator.requestLocationCoordinate()
            let cityLabel = router.selectedFeedCity?.name
            await viewModel.loadIfNeeded(
                using: environment,
                latitude: userCoord?.latitude,
                longitude: userCoord?.longitude,
                city: cityLabel
            )
        }
        .onChange(of: searchText) { _, newValue in
            router.feedKeyword = newValue
            spotSearchController.query = newValue
            scheduleUserSearch(for: newValue)
        }
        .onChange(of: router.feedNavigationToken) { _, _ in
            searchText = router.feedKeyword
            isSearchFocused = false
            userSearchResults = []
            spotSearchController.clear()
        }
        .onChange(of: isActive) { _, active in
            // Leaving Feed for another tab clears tags; opening an experience keeps them.
            guard !active else { return }
            router.clearFeedSearch()
            searchText = ""
            isSearchFocused = false
            userSearchResults = []
            userSearchTask?.cancel()
            isSearchingUsers = false
            spotSearchController.clear()
        }
        .onDisappear {
            userSearchTask?.cancel()
        }
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TravSpacing.xs) {
                ForEach(FeedFilter.allCases) { filter in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedFilter = filter
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.iconName)
                                .font(.system(size: 12, weight: .bold))
                            Text(filter.rawValue)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, TravSpacing.md)
                        .padding(.vertical, TravSpacing.xs)
                        .background(
                            Capsule()
                                .fill(selectedFilter == filter ? TravColors.accent : TravColors.surfaceElevated)
                        )
                        .foregroundStyle(selectedFilter == filter ? Color.white : TravColors.primary)
                        .overlay(
                            Capsule()
                                .stroke(TravColors.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filter: \(filter.rawValue)")
                }
            }
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .padding(.vertical, TravSpacing.xs)
        }
    }

    // MARK: - Feed body

    @ViewBuilder
    private var feedBody: some View {
        switch viewModel.phase {
        case .idle, .loading:
            Spacer()
            ProgressView()
                .tint(TravColors.accent)
            Spacer()
        case let .failed(message):
            Spacer()
            EmptyStateView(
                icon: "wifi.exclamationmark",
                title: "Couldn't Load Feed",
                description: message,
                actionTitle: "Try Again"
            ) {
                Task { await viewModel.load(using: environment) }
            }
            Spacer()
        case .loaded:
            if filteredFeed.isEmpty && visiblePopups.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: emptyStateTitle,
                    description: emptyStateDescription
                )
                Spacer()
            } else {
                feedScrollView
            }
        }
    }

    private var feedScrollView: some View {
        ScrollView {
            // 40% tighter gap between Happening Soon and Experiences (16 → ~10).
            VStack(spacing: 10) {
                if !visiblePopups.isEmpty && selectedFilter == .all {
                    popupCarousel
                }

                HStack {
                    Text("Experiences")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(TravColors.primary)
                    Spacer()
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.top, visiblePopups.isEmpty || selectedFilter != .all ? TravSpacing.xs : 0)
                .padding(.bottom, 4)

                LazyVStack(spacing: 12) {
                    ForEach(filteredFeed) { experience in
                        ExperienceCard(
                            experience: experience,
                            badgeText: ownExperienceBadge(for: experience),
                            isSaved: engagement.isSaved(experience.id),
                            isLiked: engagement.isLiked(experience.id),
                            connectedLayout: false,
                            onTap: {
                                router.presentedRoute = .experience(experience.id)
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
                            },
                            onLike: {
                                Task {
                                    await engagement.toggleLike(
                                        experienceID: experience.id,
                                        summary: experience,
                                        using: environment
                                    )
                                }
                            },
                            onShare: {
                                shareItem = ShareItem(
                                    message: "Check out \"\(experience.title)\" on Trav",
                                    url: TravLinks.experience(experience.id)
                                )
                            }
                        )
                        .onDrag {
                            NSItemProvider(object: experience.id.uuidString as NSString)
                        }
                        .onAppear {
                            if experience.id == filteredFeed.last?.id {
                                Task { await viewModel.loadMore(using: environment) }
                            }
                        }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .tint(TravColors.accent)
                            .padding(.vertical, TravSpacing.md)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, TravSpacing.sm)
            .padding(.bottom, draftStops.isEmpty ? TravSpacing.tabBarBottom + 20 : TravSpacing.tabBarBottom + 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await viewModel.load(using: environment)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 8).onChanged { _ in
                if isSearchFocused {
                    isSearchFocused = false
                }
            }
        )
    }

    // MARK: - Popups carousel

    private var popupCarousel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Happening Soon")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(TravColors.primary)
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.top, TravSpacing.xs)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(visiblePopups) { popup in
                        Button {
                            selectedPopup = popup
                        } label: {
                            PopupStoryCard(popup: popup)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(popup.name), \(popup.startTimeLabel)")
                    }
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
            }
        }
        .padding(.bottom, TravSpacing.xxs)
    }

    private func ownExperienceBadge(for experience: ExperienceSummary) -> String {
        guard let currentID = session.currentUser?.id,
              experience.creator.id == currentID else {
            return ""
        }
        return "Created by You"
    }

    private var visiblePopups: [Popup] {
        let keyword = router.feedKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return viewModel.popups }
        return viewModel.popups.filter {
            $0.name.localizedCaseInsensitiveContains(keyword)
                || $0.address.localizedCaseInsensitiveContains(keyword)
        }
    }

    // MARK: - Quick Planner

    @ViewBuilder
    private var quickPlannerPanel: some View {
        VStack {
            Spacer()

            if !draftStops.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("QUICK PLANNER")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(2.0)
                                .foregroundStyle(TravColors.accent)

                            Text(plannerSubtitle)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(TravColors.primary)
                        }

                        Spacer()

                        Button {
                            withAnimation(.spring()) {
                                draftStops.removeAll()
                                draftCityName = nil
                                itineraryTitle = ""
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(TravColors.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear planner")
                    }
                    .padding(.horizontal, TravSpacing.screenHorizontal)
                    .padding(.vertical, TravSpacing.sm)

                    Divider()
                        .background(TravColors.border)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(draftStops.enumerated()), id: \.offset) { index, stop in
                                HStack(spacing: 6) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(5)
                                        .background(TravColors.accent)
                                        .clipShape(Circle())
                                        .foregroundStyle(.white)

                                    Image(systemName: sfSymbolForEmojiOrCategory(stop.emoji ?? ""))
                                        .font(.system(size: 11))
                                        .foregroundStyle(TravColors.accent)
                                    Text(stop.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(TravColors.primary)

                                    Button {
                                        draftStops.remove(at: index)
                                        if draftStops.isEmpty {
                                            draftCityName = nil
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.red.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove \(stop.name)")
                                }
                                .padding(.horizontal, TravSpacing.sm)
                                .padding(.vertical, 6)
                                .background(TravColors.surfaceElevated)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(TravColors.border, lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                        .padding(.vertical, TravSpacing.sm)
                    }

                    HStack(spacing: TravSpacing.sm) {
                        TextField("", text: $itineraryTitle, prompt: Text("Itinerary Name...").foregroundColor(TravColors.muted))
                            .padding(.horizontal, TravSpacing.md)
                            .padding(.vertical, 8)
                            .background(TravColors.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                            .foregroundStyle(TravColors.primary)
                            .tint(TravColors.accent)

                        Button {
                            Task { await saveDraftItinerary() }
                        } label: {
                            HStack {
                                if isSavingItinerary {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Save Route")
                                }
                            }
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .padding(.horizontal, TravSpacing.md)
                            .padding(.vertical, 10)
                            .background(TravColors.accent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                        }
                        .disabled(isSavingItinerary)
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, TravSpacing.screenHorizontal)
                    .padding(.bottom, TravSpacing.sm + 10)
                }
                .background(TravColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                        .stroke(TravColors.border, lineWidth: 1)
                )
                .padding(.horizontal, TravSpacing.sm)
                .padding(.bottom, TravSpacing.tabBarBottom + 5)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onDrop(of: [.text], delegate: QuickPlannerDropDelegate(
                    draftStops: $draftStops,
                    draftCityName: $draftCityName,
                    feedItems: viewModel.items
                ))
            }
        }
    }

    private var plannerSubtitle: String {
        if let draftCityName {
            return "\(draftStops.count) stops in \(draftCityName)"
        }
        return "\(draftStops.count) stops selected"
    }

    private func saveDraftItinerary() async {
        guard let currentUser = session.currentUser else {
            router.presentAuth()
            return
        }
        guard !draftStops.isEmpty else { return }

        isSavingItinerary = true
        defer { isSavingItinerary = false }

        do {
            try await viewModel.saveQuickItinerary(
                title: itineraryTitle,
                stops: draftStops,
                cityName: draftCityName ?? router.selectedFeedCity?.name,
                creatorID: currentUser.id,
                using: environment
            )
            withAnimation(.spring()) {
                draftStops.removeAll()
                draftCityName = nil
                itineraryTitle = ""
            }
        } catch {
            plannerError = error.localizedDescription
        }
    }

    // MARK: - Filtering

    private var filteredFeed: [ExperienceSummary] {
        var items = viewModel.items

        if let city = router.selectedFeedCity {
            items = items.filter { experienceMatchesCity($0, city: city) }
        }

        if let user = router.selectedFeedUser {
            items = items.filter { experienceMatchesUser($0, user: user) }
        }

        let keyword = router.feedKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            items = items.filter { experienceMatchesKeyword($0, query: keyword) }
        }

        switch selectedFilter {
        case .all:
            break
        case .itineraries:
            items = items.filter { $0.stops.count > 1 }
        case .singleSpots:
            items = items.filter { $0.stops.count <= 1 }
        case .saved:
            items = items.filter { engagement.isSaved($0.id) }
        }

        return items
    }

    private func experienceMatchesCity(_ experience: ExperienceSummary, city: City) -> Bool {
        if experience.cityID == city.id { return true }
        let expCity = (experience.cityName ?? experience.displayCityName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let target = city.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !expCity.isEmpty, expCity != "unknown" else { return false }
        return expCity == target || expCity.contains(target) || target.contains(expCity)
    }

    private func experienceMatchesKeyword(_ experience: ExperienceSummary, query: String) -> Bool {
        experience.title.localizedCaseInsensitiveContains(query)
            || experience.creator.displayName.localizedCaseInsensitiveContains(query)
            || experience.creator.username.localizedCaseInsensitiveContains(query)
            || experience.stops.contains { $0.name.localizedCaseInsensitiveContains(query) }
            || (experience.cityName?.localizedCaseInsensitiveContains(query) ?? false)
            || experience.displayCityName.localizedCaseInsensitiveContains(query)
    }

    private func experienceMatchesUser(_ experience: ExperienceSummary, user: ProfileSummary) -> Bool {
        experience.creator.id == user.id
            || experience.creator.username.caseInsensitiveCompare(user.username) == .orderedSame
    }

    // MARK: - Empty states

    private var emptyStateTitle: String {
        let keyword = router.feedKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            return "No results for \"\(keyword)\""
        }
        if let user = router.selectedFeedUser, let city = router.selectedFeedCity {
            return "No posts by @\(user.username) in \(city.name)"
        }
        if let user = router.selectedFeedUser {
            return "No posts by @\(user.username)"
        }
        if let city = router.selectedFeedCity {
            return "No experiences in \(city.name)"
        }
        return "No Matching Spots"
    }

    private var emptyStateDescription: String {
        if router.selectedFeedCity != nil
            || router.selectedFeedUser != nil
            || !router.feedKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try another city or person from the suggestions, clear a tag, or search a different keyword."
        }
        return "Places, itineraries, and local events will show up here. Pull to refresh, or create your first experience."
    }

    private var feedTabBarBackdrop: TabBarBackdrop {
        appearance.isLightMode ? .light : .dark
    }

    // MARK: - Search

    private var matchingCities: [City] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return catalogCities.filter { city in
            city.name.localizedCaseInsensitiveContains(trimmed)
                || city.countryName.localizedCaseInsensitiveContains(trimmed)
                || city.locationLabel.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func scheduleUserSearch(for query: String) {
        userSearchTask?.cancel()
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

    private func selectFeedCity(_ city: City) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        router.selectedFeedCity = city
        searchText = ""
        router.feedKeyword = ""
        userSearchResults = []
        // Keep focus so the user can keep adding keywords / another token.
        isSearchFocused = true
    }

    private func selectFeedUser(_ user: ProfileSummary) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        router.selectedFeedUser = user
        searchText = ""
        router.feedKeyword = ""
        userSearchResults = []
        isSearchFocused = true
    }

    private var headerView: some View {
        FeedSearchBar(
            text: $searchText,
            placeholder: "Search spots, cities, creators...",
            isFocused: $isSearchFocused,
            isLightMode: appearance.isLightMode,
            cityToken: router.selectedFeedCity,
            userToken: router.selectedFeedUser,
            onClearCity: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    router.clearFeedCity()
                }
            },
            onClearUser: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    router.clearFeedUser()
                }
            }
        )
        .padding(.vertical, TravSpacing.xs)
    }

    private var searchSuggestionsOverlay: some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            if spotSearchController.isSearching || !spotSearchController.spots.isEmpty {
                VStack(alignment: .leading, spacing: TravSpacing.xs) {
                    Text("SPOTS")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(Color.white.opacity(0.55))
                        .padding(.horizontal, TravSpacing.xs)

                    if spotSearchController.isSearching && spotSearchController.spots.isEmpty {
                        ProgressView()
                            .tint(.white)
                            .padding(.vertical, TravSpacing.sm)
                    }

                    VStack(spacing: 6) {
                        ForEach(spotSearchController.spots) { spot in
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                selectedSpotDetail = spot
                            } label: {
                                HStack(spacing: TravSpacing.sm) {
                                    ZStack {
                                        Circle()
                                            .fill(spot.category.badgeColor.opacity(0.18))
                                            .frame(width: 32, height: 32)
                                        Text(spot.category.emoji)
                                            .font(.system(size: 16))
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(spot.title)
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.white)

                                            Text(spot.category.rawValue)
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .foregroundStyle(spot.category.badgeColor)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(spot.category.badgeColor.opacity(0.18))
                                                .clipShape(Capsule())
                                        }

                                        Text(spot.displayLocation)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Color.white.opacity(0.5))
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    HStack(spacing: 4) {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Rate")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                    }
                                    .foregroundStyle(TravColors.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(TravColors.accent.opacity(0.18)))
                                }
                                .padding(.horizontal, TravSpacing.sm)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !matchingCities.isEmpty {
                VStack(alignment: .leading, spacing: TravSpacing.xs) {
                    Text("CITIES")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(TravColors.muted)
                        .padding(.horizontal, TravSpacing.xs)

                    VStack(spacing: 6) {
                        ForEach(matchingCities.prefix(5)) { city in
                            Button {
                                selectFeedCity(city)
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
                                            .foregroundStyle(TravColors.primary)
                                        Text(city.locationLabel)
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

            if isSearchingUsers || !userSearchResults.isEmpty {
                VStack(alignment: .leading, spacing: TravSpacing.xs) {
                    Text("PEOPLE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(TravColors.muted)
                        .padding(.horizontal, TravSpacing.xs)

                    if isSearchingUsers && userSearchResults.isEmpty {
                        ProgressView()
                            .tint(TravColors.accent)
                            .padding(.vertical, TravSpacing.sm)
                    }

                    VStack(spacing: 6) {
                        ForEach(userSearchResults.prefix(5)) { user in
                            Button {
                                selectFeedUser(user)
                            } label: {
                                HStack(spacing: TravSpacing.sm) {
                                    if let avatarURL = user.avatarURL {
                                        RemoteImage(url: avatarURL, height: 32, cornerRadius: 16)
                                            .frame(width: 32, height: 32)
                                    } else {
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.system(size: 32))
                                            .foregroundStyle(TravColors.accent.opacity(0.8))
                                    }
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

            if spotSearchController.spots.isEmpty && matchingCities.isEmpty && userSearchResults.isEmpty && !isSearchingUsers && !spotSearchController.isSearching {
                Text("Keep typing to search spots, cities, or creators")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(TravColors.muted)
                    .padding(.horizontal, TravSpacing.xs)
                    .padding(.vertical, TravSpacing.xs)
            }
        }
        .padding(TravSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                .fill(TravColors.surfaceElevated)
        )
        .overlay {
            RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                .stroke(TravColors.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
    }
}

// MARK: - Popup cards

/// Story-style card for the "Happening Soon" carousel.
private struct PopupStoryCard: View {
    let popup: Popup
    private let cornerRadius: CGFloat = 16

    private var isToday: Bool {
        guard let start = popup.startTime else { return false }
        return Calendar.current.isDateInToday(start)
    }

    private var displayImageURL: URL? {
        popup.imageURL ?? popupImage(for: popup.name)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let coverURL = displayImageURL {
                RemoteImage(url: coverURL, height: 160, cornerRadius: cornerRadius)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.gray.opacity(0.2))
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            VStack {
                HStack(spacing: 4) {
                    Text("\(popup.category.emoji) \(popup.category.displayName.uppercased())")
                        .font(.system(size: 7, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(popup.category.badgeColor)
                        )
                    Spacer()
                    if isToday {
                        Text("TODAY")
                            .font(.system(size: 7, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.red))
                    }
                }
                .padding(6)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(popup.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    Text(popup.startTimeLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)

                    if let dist = popup.distanceLabel {
                        Text("• \(dist)")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(TravColors.accent)
                            .lineLimit(1)
                    }
                }
            }
            .padding([.horizontal, .bottom], 8)
        }
        .frame(width: 120, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 3)
    }
}

/// Detail sheet for a pop-up event.
private struct PopupDetailSheet: View {
    let popup: Popup
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: ShareItem?

    private var displayImageURL: URL? {
        popup.imageURL ?? popupImage(for: popup.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TravSpacing.md) {
            if let coverURL = displayImageURL {
                RemoteImage(url: coverURL, height: 180, cornerRadius: TravRadius.lg)
                    .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: TravSpacing.xs) {
                HStack {
                    HStack(spacing: 4) {
                        Text(popup.category.emoji)
                        Text(popup.category.displayName)
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(popup.category.badgeColor))

                    if let distance = popup.distanceLabel {
                        Text(distance)
                            .font(TravTypography.caption())
                            .foregroundStyle(TravColors.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(TravColors.surfaceElevated))
                    }

                    Spacer()
                }

                Text(popup.name)
                    .font(TravTypography.titleLarge())
                    .foregroundStyle(TravColors.primary)

                Label(popup.startTimeLabel, systemImage: "calendar")
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.accent)

                Label(popup.address, systemImage: "mappin.and.ellipse")
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.muted)

                if let desc = popup.description, !desc.isEmpty {
                    Text(desc)
                        .font(TravTypography.bodyMedium())
                        .foregroundStyle(TravColors.primary.opacity(0.9))
                        .padding(.top, TravSpacing.xs)
                }
            }

            Spacer()

            HStack(spacing: TravSpacing.sm) {
                if let extURL = popup.externalURL {
                    Link(destination: extURL) {
                        Label("View Event", systemImage: "safari.fill")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(TravColors.accent)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                    }
                }

                Button {
                    openInMaps()
                } label: {
                    Label(popup.externalURL == nil ? "Directions" : "Map", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(popup.externalURL == nil ? TravColors.accent : TravColors.surfaceElevated)
                        .foregroundStyle(popup.externalURL == nil ? .black : TravColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                }
                .buttonStyle(.plain)

                Button {
                    shareItem = ShareItem(
                        message: "\(popup.name) (\(popup.category.displayName)) — \(popup.startTimeLabel) at \(popup.address)",
                        url: popup.externalURL ?? URL(string: "https://maps.apple.com/?q=\(popup.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
                    )
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .padding(14)
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(TravColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share event")
            }
        }
        .padding(TravSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .travScreenBackground()
        .travShareSheet(item: $shareItem)
    }

    private func openInMaps() {
        let query = popup.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://maps.apple.com/?q=\(query)") {
            UIApplication.shared.open(url)
        }
    }
}

/// Cover image heuristics for pipeline events (no imagery in the source data).
private func popupImage(for title: String) -> URL? {
    let lowerTitle = title.lowercased()

    if lowerTitle.contains("ai") || lowerTitle.contains("neural") || lowerTitle.contains("openai") || lowerTitle.contains("voice") {
        return URL(string: "https://images.unsplash.com/photo-1677442136019-21780efad99a?w=800&q=80")
    }
    if lowerTitle.contains("meetup") || lowerTitle.contains("lounge") || lowerTitle.contains("founders") || lowerTitle.contains("builders") {
        return URL(string: "https://images.unsplash.com/photo-1515187029135-18ee286d815b?w=800&q=80")
    }
    if lowerTitle.contains("tech") || lowerTitle.contains("software") || lowerTitle.contains("hardware") || lowerTitle.contains("infra") {
        return URL(string: "https://images.unsplash.com/photo-1517694712202-14dd9538aa97?w=800&q=80")
    }
    if lowerTitle.contains("engineering") || lowerTitle.contains("pitch") {
        return URL(string: "https://images.unsplash.com/photo-1475721027785-f74eccf877e2?w=800&q=80")
    }
    if lowerTitle.contains("music") || lowerTitle.contains("sound") || lowerTitle.contains("concert") || lowerTitle.contains("band") {
        return URL(string: "https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=800&q=80")
    }
    if lowerTitle.contains("party") || lowerTitle.contains("dance") || lowerTitle.contains("bachata") || lowerTitle.contains("night") || lowerTitle.contains("noche") {
        return URL(string: "https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=800&q=80")
    }
    if lowerTitle.contains("paint") || lowerTitle.contains("art") || lowerTitle.contains("creative") || lowerTitle.contains("craft") {
        return URL(string: "https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=800&q=80")
    }
    if lowerTitle.contains("wine") || lowerTitle.contains("winery") {
        return URL(string: "https://images.unsplash.com/photo-1510812431401-41d2bd2722f3?w=800&q=80")
    }
    if lowerTitle.contains("book") || lowerTitle.contains("reading") || lowerTitle.contains("signing") || lowerTitle.contains("math") {
        return URL(string: "https://images.unsplash.com/photo-1497633762265-9d179a990aa6?w=800&q=80")
    }
    if lowerTitle.contains("film") || lowerTitle.contains("screening") || lowerTitle.contains("movie") {
        return URL(string: "https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?w=800&q=80")
    }
    if lowerTitle.contains("dinner") || lowerTitle.contains("food") || lowerTitle.contains("celebration") {
        return URL(string: "https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=800&q=80")
    }
    if lowerTitle.contains("market") || lowerTitle.contains("bazaar") || lowerTitle.contains("showcase") {
        return URL(string: "https://images.unsplash.com/photo-1533900298318-6b8da08a523e?w=800&q=80")
    }
    if lowerTitle.contains("chess") || lowerTitle.contains("game") || lowerTitle.contains("tournament") {
        return URL(string: "https://images.unsplash.com/photo-1529699211952-734e80c4d42b?w=800&q=80")
    }
    if lowerTitle.contains("berkeley") || lowerTitle.contains("golden") || lowerTitle.contains("hour") {
        return URL(string: "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800&q=80")
    }
    return URL(string: "https://images.unsplash.com/photo-1501281668745-f7f57925c3b4?w=800&q=80")
}
