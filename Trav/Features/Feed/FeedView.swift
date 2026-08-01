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
    @State private var currentCity: String? = nil
    @State private var selectedSpotDetail: SpotSuggestion? = nil
    @State private var showFullSearchResults = false
    @State private var fullSearchInitialTab: SearchTab = .all

    // Quick Planner state
    @State private var draftStops: [StopPreview] = []
    @State private var draftCityName: String?
    @State private var itineraryTitle: String = ""
    @State private var isSavingItinerary = false
    @State private var plannerError: String?

    // Upcoming Trips state
    @State private var showingCreateTripSheet = false
    @State private var createTripInitialType: TripType = .upcomingTrip
    @State private var selectedTripForRec: UpcomingTrip? = nil
    @State private var selectedTripDetail: UpcomingTrip? = nil

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
        .sheet(isPresented: $showingCreateTripSheet) {
            CreateUpcomingTripSheet(initialTripType: createTripInitialType)
        }
        .sheet(item: $selectedTripForRec) { trip in
            TripDetailSheet(trip: trip)
        }
        .sheet(item: $selectedTripDetail) { trip in
            TripDetailSheet(trip: trip)
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

            // Load feed, popups, and upcoming trips
            await UpcomingTripService.shared.fetchTrips(using: environment)
            await reloadPopupsForActiveAppLocation()
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
        .onChange(of: router.selectedFeedCity) { _, _ in
            Task {
                await reloadPopupsForActiveAppLocation()
            }
        }
        .task(id: router.experienceCatalogRevision) {
            guard router.experienceCatalogRevision > 0 else { return }
            await reloadPopupsForActiveAppLocation()
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
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonExperienceCard()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, TravSpacing.sm)
            }
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
                upcomingTripsSection

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
                    ForEach(Array(filteredFeed.enumerated()), id: \.element.id) { index, experience in
                        ExperienceCard(
                            experience: experience,
                            badgeText: ownExperienceBadge(for: experience),
                            isSaved: engagement.isSaved(experience.id),
                            isLiked: engagement.isLiked(experience.id),
                            connectedLayout: false,
                            onTap: {
                                if isRecByTrav(experience) {
                                    selectedSpotDetail = spotSuggestion(from: experience)
                                } else {
                                    router.presentedRoute = .experience(experience.id)
                                }
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
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                                removal: .opacity
                            )
                        )
                        .onDrag {
                            NSItemProvider(object: experience.id.uuidString as NSString)
                        }
                        .onAppear {
                            // Prefetch next page 3 items before hitting the bottom for instant infinite scroll
                            if index >= max(0, filteredFeed.count - 3) {
                                Task { await viewModel.loadMore(using: environment) }
                            }
                        }
                    }

                    if viewModel.isLoadingMore {
                        SleekFeedLoadingIndicator()
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    } else if viewModel.hasReachedScrollLimit || (!viewModel.hasMore && !viewModel.isLoadingMore) {
                        UnlockRecsBannerView(
                            onInviteFriends: {
                                shareItem = ShareItem(
                                    message: "Join me on Trav to discover and share local spots!",
                                    url: URL(string: "https://trav.app/invite")!
                                )
                            },
                            onFindPeople: {
                                isSearchFocused = true
                            }
                        )
                        .padding(.vertical, TravSpacing.md)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                .animation(.smooth(duration: 0.35), value: filteredFeed.count)
                .padding(.horizontal, 12)
            }
            .padding(.vertical, TravSpacing.sm)
            .padding(.bottom, draftStops.isEmpty ? TravSpacing.tabBarBottom + 20 : TravSpacing.tabBarBottom + 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await reloadPopupsForActiveAppLocation()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 8).onChanged { _ in
                if isSearchFocused {
                    isSearchFocused = false
                }
            }
        )
    }

    // MARK: - Upcoming Trips section

    private var upcomingTripsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            UpcomingTripHeaderInputBar { type in
                createTripInitialType = type
                showingCreateTripSheet = true
            }

            let trips = UpcomingTripService.shared.trips
            if !trips.isEmpty && selectedFilter == .all {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Upcoming Trips")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(TravColors.primary)
                        Spacer()
                    }
                    .padding(.horizontal, TravSpacing.screenHorizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(trips) { trip in
                                UpcomingTripCard(
                                    trip: trip,
                                    onRecommend: {
                                        selectedTripForRec = trip
                                    },
                                    onTap: {
                                        selectedTripDetail = trip
                                    }
                                )
                                .frame(width: 320)
                            }
                        }
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                    }
                }
                .padding(.top, 4)
            }
        }
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
        if isRecByTrav(experience) {
            return "Rec by Trav"
        }
        if experience.isSpot || experience.stops.count <= 1 {
            return ""
        }
        guard let currentID = session.currentUser?.id,
              experience.creator.id == currentID else {
            return ""
        }
        return "Created by You"
    }

    private func isRecByTrav(_ experience: ExperienceSummary) -> Bool {
        experience.creator.id == ExperienceInsert.travAdminID
            || experience.creator.username.lowercased() == "trav"
            || experience.creator.displayName.lowercased() == "rec by trav"
    }

    private func spotSuggestion(from experience: ExperienceSummary) -> SpotSuggestion {
        let firstStop = experience.stops.first
        let emoji = firstStop?.emoji ?? "📍"
        
        let category: SpotCategory
        if let stored = SpotCategory(legacyRawValue: experience.category ?? "") {
            category = stored
        } else {
            switch emoji {
            case "🥾", "🌲", "🏞": category = .nature
            case "🌅", "🌆", "🏛", "🏛️": category = .landmarks
            case "🎨": category = .arts
            case "🛍️": category = .shopping
            case "🍲", "🍽️", "☕": category = .foodAndDrink
            case "🍸", "🍻": category = .nightlife
            case "🎢": category = .entertainment
            case "⛲": category = .landmarks
            default: category = SpotCategory.infer(title: experience.title, subtitle: experience.displayCityName)
            }
        }

        return SpotSuggestion(
            id: experience.id.uuidString,
            title: experience.title,
            subtitle: experience.displayCityName,
            category: category,
            latitude: firstStop?.latitude,
            longitude: firstStop?.longitude
        )
    }

    private var visiblePopups: [Popup] {
        let keyword = router.feedKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return viewModel.popups }
        return viewModel.popups.filter {
            $0.name.localizedCaseInsensitiveContains(keyword)
                || $0.address.localizedCaseInsensitiveContains(keyword)
        }
    }

    private func reloadPopupsForActiveAppLocation() async {
        let activeCity: String?
        let activeLat: Double?
        let activeLng: Double?

        if let userCoord = await cityLocator.requestLocationCoordinate(),
           let userCity = await cityLocator.requestCityLabel(), !userCity.isEmpty {
            // Priority 1: Device GPS location of the iPhone!
            activeCity = userCity
            activeLat = userCoord.latitude
            activeLng = userCoord.longitude
        } else if let profileLocation = environment.session.currentUser?.homeCityLabel, !profileLocation.isEmpty {
            // Priority 2: Location given by the user in their profile!
            activeCity = profileLocation
            activeLat = nil
            activeLng = nil
        } else if let selectedCity = router.selectedFeedCity {
            // Priority 3: City selected in app feed dropdown
            activeCity = selectedCity.name
            activeLat = selectedCity.latitude
            activeLng = selectedCity.longitude
        } else {
            // Priority 4: Default catalog city
            activeCity = catalogCities.first?.name ?? "Berkeley, CA"
            activeLat = 37.8715
            activeLng = -122.2730
        }

        if let city = activeCity {
            self.currentCity = city
        }

        await viewModel.load(
            using: environment,
            latitude: activeLat,
            longitude: activeLng,
            city: activeCity,
            engagement: engagement
        )
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

        if !engagement.blockedUserIDs.isEmpty {
            items = items.filter { !engagement.isBlocked($0.creator.id) }
        }

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
        return IntelligentSearchRanking.rankCatalogCities(
            catalogCities,
            query: trimmed,
            userCoordinate: spotSearchController.userCoordinate
                ?? LocationManager.shared.coordinateForSearch
        )
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
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            let results = (try? await environment.profiles.searchUsers(query: trimmed)) ?? []
            guard !Task.isCancelled else { return }
            userSearchResults = results.filter { !engagement.isBlocked($0.id) }
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
        HStack(spacing: TravSpacing.sm) {
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
        }
        .padding(.vertical, TravSpacing.xs)
    }

    private var searchSuggestionsOverlay: some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            // Header Bar with Close X Button
            HStack {
                Text("Search Results")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(TravColors.primary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSearchFocused = false
                        searchText = ""
                        userSearchResults = []
                        spotSearchController.clear()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(TravColors.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, TravSpacing.xs)

            // MARK: - Spots Section
            if spotSearchController.isSearching || !spotSearchController.spots.isEmpty {
                VStack(alignment: .leading, spacing: TravSpacing.xs) {
                    Text("SPOTS")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(TravColors.muted)
                        .padding(.horizontal, TravSpacing.xs)

                    if spotSearchController.isSearching && spotSearchController.spots.isEmpty {
                        ProgressView()
                            .tint(TravColors.accent)
                            .padding(.vertical, TravSpacing.sm)
                    }

                    VStack(spacing: 6) {
                        ForEach(spotSearchController.spots.prefix(3)) { spot in
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
                                        Text(spot.title)
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(TravColors.primary)
                                            .lineLimit(1)

                                        Text(spot.displayLocation)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(TravColors.muted)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 0)

                                    Text(spot.category.rawValue)
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(spot.category.badgeColor)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(Capsule().fill(spot.category.badgeColor.opacity(0.18)))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, TravSpacing.sm)
                                .padding(.vertical, 8)
                                .background(TravColors.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        if spotSearchController.spots.count > 3 {
                            Button {
                                fullSearchInitialTab = .spots
                                showFullSearchResults = true
                            } label: {
                                HStack {
                                    Text("View all \(spotSearchController.spots.count) spots")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundStyle(TravColors.accent)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // MARK: - Cities Section
            if !matchingCities.isEmpty {
                VStack(alignment: .leading, spacing: TravSpacing.xs) {
                    Text("CITIES")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(TravColors.muted)
                        .padding(.horizontal, TravSpacing.xs)

                    VStack(spacing: 6) {
                        ForEach(matchingCities.prefix(3)) { city in
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

                        if matchingCities.count > 3 {
                            Button {
                                fullSearchInitialTab = .cities
                                showFullSearchResults = true
                            } label: {
                                HStack {
                                    Text("View all \(matchingCities.count) cities")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundStyle(TravColors.accent)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // MARK: - Creators Section
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
                        ForEach(userSearchResults.prefix(3)) { user in
                            Button {
                                selectFeedUser(user)
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

                        if userSearchResults.count > 3 {
                            Button {
                                fullSearchInitialTab = .creators
                                showFullSearchResults = true
                            } label: {
                                HStack {
                                    Text("View all \(userSearchResults.count) creators")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundStyle(TravColors.accent)
                                .padding(.vertical, 4)
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

            // MARK: - View All Search Results Button
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                    .padding(.vertical, 4)

                Button {
                    fullSearchInitialTab = .all
                    showFullSearchResults = true
                } label: {
                    HStack {
                        Text("View all results for \"\(searchText)\"")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(TravColors.accent)
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(TravColors.accent)
                    }
                    .padding(.horizontal, TravSpacing.xs)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
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
        .fullScreenCover(isPresented: $showFullSearchResults) {
            FullSearchResultsView(initialQuery: searchText, initialTab: fullSearchInitialTab)
        }
    }
}

// MARK: - Popup cards

/// Story-style card for the "Happening Soon" carousel.
private struct PopupStoryCard: View {
    let popup: Popup
    private let cornerRadius: CGFloat = 16
    @State private var resolvedURL: URL?

    private var userCoverURL: URL? {
        if isUserUploadedImage(popup.imageURL) {
            return popup.imageURL
        }
        return nil
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let userCoverURL {
                RemoteImage(url: userCoverURL, height: 160, cornerRadius: cornerRadius)
            } else if let resolvedURL {
                RemoteImage(url: resolvedURL, height: 160, cornerRadius: cornerRadius)
            } else {
                ZStack {
                    Color(uiColor: .systemGroupedBackground)
                    ProgressView()
                        .tint(TravColors.muted)
                }
                .frame(height: 160)
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.90)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(popup.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                Text(popup.shortDateLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(width: 124, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 6, y: 3)
        .task(id: popup.id) {
            if userCoverURL == nil {
                let lat = popup.latitude ?? 0
                let lng = popup.longitude ?? 0
                if let url = await AppleMapsVibeService.shared.fetchStreetViewOrMapView(
                    latitude: lat,
                    longitude: lng,
                    title: popup.name
                ) {
                    self.resolvedURL = url
                }
            }
        }
    }
}

/// Detail sheet for a pop-up event.
private struct PopupDetailSheet: View {
    let popup: Popup
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: ShareItem?
    @State private var resolvedURL: URL?

    private var userCoverURL: URL? {
        if isUserUploadedImage(popup.imageURL) {
            return popup.imageURL
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TravSpacing.md) {
            if let userCoverURL {
                RemoteImage(url: userCoverURL, height: 180, cornerRadius: TravRadius.lg)
                    .frame(maxWidth: .infinity)
            } else if let resolvedURL {
                RemoteImage(url: resolvedURL, height: 180, cornerRadius: TravRadius.lg)
                    .frame(maxWidth: .infinity)
            } else {
                ZStack {
                    Color(uiColor: .systemGroupedBackground)
                    ProgressView()
                        .tint(TravColors.muted)
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg))
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
        .task(id: popup.id) {
            if userCoverURL == nil {
                let lat = popup.latitude ?? 0
                let lng = popup.longitude ?? 0
                if let url = await AppleMapsVibeService.shared.fetchStreetViewOrMapView(
                    latitude: lat,
                    longitude: lng,
                    title: popup.name
                ) {
                    self.resolvedURL = url
                }
            }
        }
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

private struct UnlockRecsBannerView: View {
    let onInviteFriends: () -> Void
    let onFindPeople: () -> Void

    var body: some View {
        VStack(spacing: TravSpacing.sm) {
            ZStack {
                Circle()
                    .fill(TravColors.accent.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(TravColors.accent)
            }

            VStack(spacing: 4) {
                Text("Unlock More Recs")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(TravColors.primary)

                Text("You must unlock more recs by inviting friends or following more people.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(TravColors.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TravSpacing.md)
            }

            HStack(spacing: TravSpacing.xs) {
                Button(action: onInviteFriends) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("Invite Friends")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, TravSpacing.md)
                    .padding(.vertical, 10)
                    .background(TravColors.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.96))

                Button(action: onFindPeople) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Find People")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, TravSpacing.md)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.1))
                    .foregroundStyle(TravColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.96))
            }
            .padding(.top, TravSpacing.xs)
        }
        .padding(TravSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: TravRadius.xl, style: .continuous)
                .fill(TravColors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TravRadius.xl, style: .continuous)
                .stroke(TravColors.accent.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}

/// Premium, sleek loading indicator for infinite feed scrolling.
private struct SleekFeedLoadingIndicator: View {
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(TravColors.accent)
                    .scaleEffect(0.9)

                Text("Discovering more spots...")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(TravColors.primary.opacity(0.9))

                Circle()
                    .fill(TravColors.accent)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isPulsing ? 1.4 : 0.8)
                    .opacity(isPulsing ? 1.0 : 0.4)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(TravColors.surfaceElevated.opacity(0.9))
                    .overlay(
                        Capsule()
                            .stroke(TravColors.accent.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: TravColors.accent.opacity(0.18), radius: 10, x: 0, y: 3)
            }
        }
        .padding(.vertical, TravSpacing.md)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
