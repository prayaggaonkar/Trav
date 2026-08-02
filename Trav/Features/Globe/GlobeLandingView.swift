import SwiftUI

struct GlobeLandingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(AppearanceStore.self) private var appearance
    @Environment(EngagementStore.self) private var engagement
    @Environment(NotificationStore.self) private var notificationStore

    /// When false (Explore tab hidden), SceneKit stops continuous rendering.
    var isActive: Bool = true

    @State private var viewModel: GlobeViewModel?
    @State private var showOnboarding = false
    @State private var searchText = ""
    @State private var spotSearchController = SpotSearchController()
    @State private var selectedSpotDetail: SpotSuggestion? = nil
    @State private var userSearchResults: [ProfileSummary] = []
    @State private var isSearchingUsers = false
    @State private var userSearchTask: Task<Void, Never>?
    @State private var cityFilterTask: Task<Void, Never>?
    @State private var showFullSearchResults = false
    @State private var fullSearchInitialTab: SearchTab = .all

    var body: some View {
        ZStack {
            // Sky behind the globe follows light/dark; the SceneKit globe itself stays unchanged.
            HomeCelestialBackground()
                .ignoresSafeArea()

            GeometryReader { geo in
                if let viewModel {
                    // Full-bleed SceneKit view so a zoomed globe can extend under the
                    // Trav header / tab bar instead of being clipped by a short viewport.
                    EarthGlobeView(controller: viewModel.controller)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .position(x: geo.size.width * 0.5, y: geo.size.height * 0.5)
                        // SceneKit only — do not put this on a parent or it forces the whole screen dark.
                        .preferredColorScheme(.dark)

                    if let previewCity = viewModel.previewCity,
                       let pinInGlobe = viewModel.previewPinPoint {
                        let anchor = CGPoint(
                            x: pinInGlobe.x,
                            y: pinInGlobe.y
                        )
                        CityPinAnchoredPreview(
                            city: previewCity,
                            anchor: anchor,
                            containerSize: geo.size,
                            isLightMode: appearance.isLightMode,
                            onVisit: { viewModel.visitPreviewCity() },
                            onDismiss: { viewModel.dismissPreview(resetZoom: true) }
                        )
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                        .zIndex(1)
                    }
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, TravSpacing.xs)
                    .padding(.horizontal, TravSpacing.xxs)

                searchBar
                    .padding(.horizontal, TravSpacing.xxs)

                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchResultsOverlay
                        .padding(.horizontal, TravSpacing.xxs)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                if viewModel?.previewCity == nil, viewModel?.isFlyingToCity != true {
                    bottomCTA
                        .padding(.bottom, TravSpacing.md)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .safeAreaPadding(.top, TravSpacing.xxs)
            .safeAreaPadding(.bottom, TravSpacing.xs)
        }
        .animation(TravAnimation.enter, value: viewModel?.previewCity?.id)
        .animation(TravAnimation.quick, value: viewModel?.previewPinPoint != nil)
        .task {
            guard viewModel == nil else { return }
            let vm = GlobeViewModel(
                citiesRepository: environment.cities,
                router: environment.router
            )
            viewModel = vm
            vm.controller.setRenderingActive(isActive)
            await vm.prepare(isLightMode: appearance.isLightMode, userLocationName: session.currentUser?.homeCityLabel)
        }
        .task(id: session.currentUser?.homeCityLabel) {
            await viewModel?.loadCities(userLocationName: session.currentUser?.homeCityLabel)
        }
        .task(id: session.currentUser?.id) {
            if let userID = session.currentUser?.id {
                await engagement.bootstrap(userID: userID, using: environment)
                await notificationStore.refreshUnreadCount(userID: userID, using: environment)
            } else {
                notificationStore.reset()
            }
        }
        .onChange(of: isActive) { _, active in
            viewModel?.controller.setRenderingActive(active)
            if !active {
                viewModel?.resetZoomAfterReturningHome()
            }
        }
        .onChange(of: router.exploreActivationToken) { _, _ in
            // Driven from RootCoordinator when Explore becomes the active tab.
            viewModel?.controller.setRenderingActive(true)
            viewModel?.resetZoomAfterReturningHome()
            // Second pass next frame — SceneKit can briefly keep a late presentation value.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(32))
                viewModel?.resetZoomAfterReturningHome()
            }
        }
        .onChange(of: appearance.isLightMode) { _, isLight in
            viewModel?.controller.renderer.setDaytimeLook(isLight)
        }
        .onChange(of: router.presentedRoute) { previous, current in
            // When leaving a city (or any modal route) back to home, restore default zoom.
            if previous != nil, current == nil {
                viewModel?.resetZoomAfterReturningHome()
                if let userID = session.currentUser?.id {
                    Task {
                        await notificationStore.refreshUnreadCount(userID: userID, using: environment)
                    }
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            spotSearchController.query = newValue
            userSearchTask?.cancel()
            cityFilterTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                userSearchResults = []
                isSearchingUsers = false
                if case let .loaded(allCities) = viewModel?.loadState {
                    viewModel?.renderer.setCities(allCities)
                }
            } else {
                isSearchingUsers = true
                userSearchTask = Task {
                    try? await Task.sleep(for: .milliseconds(260))
                    guard !Task.isCancelled else { return }
                    if let currentUserID = session.currentUser?.id {
                        await engagement.bootstrap(userID: currentUserID, using: environment)
                    }
                    let results = (try? await environment.profiles.searchUsers(query: trimmed)) ?? []
                    if !Task.isCancelled {
                        userSearchResults = results.filter { !engagement.isBlocked($0.id) }
                        isSearchingUsers = false
                    }
                }

                cityFilterTask = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    if case let .loaded(allCities) = viewModel?.loadState {
                        let filtered = IntelligentSearchRanking.rankCatalogCities(
                            allCities,
                            query: newValue,
                            userCoordinate: spotSearchController.userCoordinate
                                ?? LocationManager.shared.coordinateForSearch
                        )
                        viewModel?.renderer.setCities(filtered)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .sheet(item: $selectedSpotDetail) { spot in
            SpotDetailSheet(spot: spot)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(TravRadius.xl)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            // Left Side: Brand Logo and Title
            HStack(spacing: TravSpacing.sm) {
                // Tap pin to toggle light / dark mode (globe appearance unchanged).
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        appearance.toggle()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(TravColors.accent.opacity(0.15))
                            .frame(width: 46, height: 46)

                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(TravColors.accent)
                    }
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.92))
                .accessibilityLabel(appearance.isLightMode ? "Switch to dark mode" : "Switch to light mode")
                .accessibilityHint("Toggles app appearance. Daytime land/ocean texture in light mode; purple network stays the same.")

                VStack(alignment: .leading, spacing: 2) {
                    Text("TRAV")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(appearance.isLightMode ? Color.black : .white)

                    Text("What's the move?")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(
                            appearance.isLightMode
                                ? Color.black.opacity(0.55)
                                : .white.opacity(0.5)
                        )
                }
            }            
            Spacer()
            
            // Right Side: Notifications / Sign In
            if session.isAuthenticated {
                Button {
                    router.openNotifications()
                } label: {
                    notificationsBell
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.92))
                .accessibilityLabel(
                    notificationStore.unreadCount > 0
                        ? "Notifications, \(notificationStore.unreadCount) unread"
                        : "Notifications"
                )
            } else {
                // Sign In Button
                Button { showOnboarding = true } label: {
                    Text("Sign In")
                        .font(TravTypography.bodyMedium())
                        .fontWeight(.bold)
                        .foregroundStyle(appearance.isLightMode ? Color.black : .white)
                        .padding(.horizontal, TravSpacing.lg)
                        .frame(height: 38)
                        .background(
                            Capsule()
                                .fill(TravColors.accent.opacity(appearance.isLightMode ? 0.12 : 0.15))
                        )
                        .overlay {
                            Capsule()
                                .stroke(TravColors.accent.opacity(0.3), lineWidth: 1)
                        }
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.95))
                .accessibilityLabel("Sign In")
            }
        }
        .padding(.vertical, TravSpacing.xs)
    }

    private var notificationsBell: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(appearance.isLightMode ? Color.black.opacity(0.06) : Color.white.opacity(0.08))
                    .frame(width: 44, height: 44)

                Image(systemName: notificationStore.unreadCount > 0 ? "bell.fill" : "bell")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(appearance.isLightMode ? Color.black : Color.white)
            }

            // Small purple unread indicator near the bell.
            if notificationStore.unreadCount > 0 {
                Circle()
                    .fill(TravColors.accent)
                    .frame(width: 9, height: 9)
                    .overlay {
                        Circle()
                            .stroke(
                                appearance.isLightMode ? Color.white : Color(white: 0.12),
                                lineWidth: 1.5
                            )
                    }
                    .offset(x: -2, y: 2)
                    .accessibilityHidden(true)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: TravSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TravColors.muted)

            TextField("Search spots, cities, creators...", text: $searchText)
                .font(TravTypography.bodyMedium())
                .foregroundStyle(appearance.isLightMode ? Color.black : Color.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button(action: {
                    withAnimation {
                        searchText = ""
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(TravColors.muted)
                }
            }
        }
        .padding(.horizontal, TravSpacing.md)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: TravRadius.md)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, appearance.isLightMode ? .light : .dark)
        )
        .overlay {
            RoundedRectangle(cornerRadius: TravRadius.md)
                .stroke(
                    appearance.isLightMode
                        ? Color.black.opacity(0.12)
                        : Color.white.opacity(0.15),
                    lineWidth: 1
                )
        }
        .padding(.vertical, TravSpacing.xs)
    }

    private var matchingCities: [City] {
        guard case let .loaded(allCities) = viewModel?.loadState else { return [] }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return IntelligentSearchRanking.rankCatalogCities(
            allCities,
            query: trimmed,
            userCoordinate: spotSearchController.userCoordinate
                ?? LocationManager.shared.coordinateForSearch
        )
    }

    private var searchResultsOverlay: some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            // MARK: - Header with Close Button
            HStack {
                Text("Search Results")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(appearance.isLightMode ? Color.black : Color.white)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
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
                    HStack {
                        Text("SPOTS")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(appearance.isLightMode ? Color.black.opacity(0.55) : Color.white.opacity(0.6))

                        Spacer()

                        if spotSearchController.isSearching {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(appearance.isLightMode ? TravColors.accent : .white)
                        }
                    }
                    .padding(.horizontal, TravSpacing.xs)

                    VStack(spacing: 6) {
                        ForEach(spotSearchController.spots.prefix(3)) { spot in
                            Button {
                                searchText = ""
                                userSearchResults = []
                                spotSearchController.clear()
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
                                            .foregroundStyle(appearance.isLightMode ? Color.black : Color.white)
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
                                .background(
                                    RoundedRectangle(cornerRadius: TravRadius.sm, style: .continuous)
                                        .fill(appearance.isLightMode ? Color.white.opacity(0.85) : Color.white.opacity(0.08))
                                )
                            }
                            .buttonStyle(TravPressButtonStyle(scale: 0.98))
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
                        .foregroundStyle(appearance.isLightMode ? Color.black.opacity(0.55) : Color.white.opacity(0.6))
                        .padding(.horizontal, TravSpacing.xs)

                    VStack(spacing: 6) {
                        ForEach(matchingCities.prefix(3)) { city in
                            Button {
                                searchText = ""
                                userSearchResults = []
                                spotSearchController.clear()
                                viewModel?.selectCity(city)
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

                                        Text(city.countryName)
                                            .font(.system(size: 12, weight: .regular, design: .rounded))
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
                                        .fill(appearance.isLightMode ? Color.white.opacity(0.85) : Color.white.opacity(0.08))
                                )
                            }
                            .buttonStyle(TravPressButtonStyle(scale: 0.98))
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

            // MARK: - Creators & Users Section
            VStack(alignment: .leading, spacing: TravSpacing.xs) {
                HStack {
                    Text("CREATORS & USERS")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(appearance.isLightMode ? Color.black.opacity(0.55) : Color.white.opacity(0.6))

                    Spacer()

                    if isSearchingUsers {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(appearance.isLightMode ? TravColors.accent : .white)
                    }
                }
                .padding(.horizontal, TravSpacing.xs)

                if spotSearchController.spots.isEmpty && userSearchResults.isEmpty && !isSearchingUsers && !spotSearchController.isSearching && matchingCities.isEmpty {
                    Text("No matching spots, cities, or users found for '\(searchText)'")
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                        .padding(.horizontal, TravSpacing.xs)
                        .padding(.vertical, 4)
                } else if !userSearchResults.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(userSearchResults.prefix(3)) { user in
                            GlobeUserSearchResultRow(user: user) {
                                searchText = ""
                                userSearchResults = []
                                spotSearchController.clear()
                                router.openProfile(user.username)
                            }
                            .padding(.horizontal, TravSpacing.sm)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: TravRadius.sm, style: .continuous)
                                    .fill(appearance.isLightMode ? Color.white.opacity(0.85) : Color.white.opacity(0.08))
                            )
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

            // MARK: - View All Results Button
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
        .padding(TravSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, appearance.isLightMode ? .light : .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                .stroke(appearance.isLightMode ? Color.black.opacity(0.1) : Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.vertical, TravSpacing.xs)
        .fullScreenCover(isPresented: $showFullSearchResults) {
            FullSearchResultsView(initialQuery: searchText, initialTab: fullSearchInitialTab)
        }
    }

    private var bottomCTA: some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            if case let .loaded(cities) = viewModel?.loadState {
                let allowedNames = ["Berkeley", "San Francisco", "Barcelona", "New York", "Paris", "London", "Tokyo", "Los Angeles"]
                let filtered = cities.filter { city in
                    allowedNames.contains(where: { $0.caseInsensitiveCompare(city.name) == .orderedSame }) &&
                    (searchText.isEmpty ||
                     city.name.localizedCaseInsensitiveContains(searchText) ||
                     city.countryName.localizedCaseInsensitiveContains(searchText))
                }.sorted { c1, c2 in
                    let idx1 = allowedNames.firstIndex(where: { $0.caseInsensitiveCompare(c1.name) == .orderedSame }) ?? 99
                    let idx2 = allowedNames.firstIndex(where: { $0.caseInsensitiveCompare(c2.name) == .orderedSame }) ?? 99
                    return idx1 < idx2
                }

                if filtered.isEmpty {
                    Text("No matching cities found")
                        .font(TravTypography.bodyMedium())
                        .foregroundStyle(TravColors.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, TravSpacing.md)
                } else {
                    Text("Tap a city pin to explore")
                        .font(TravTypography.labelMedium())
                        .foregroundStyle(
                            appearance.isLightMode
                                ? Color.black.opacity(0.55)
                                : .white.opacity(0.6)
                        )
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: TravSpacing.sm) {
                            ForEach(filtered) { city in
                                CityChip(city: city, isLightMode: appearance.isLightMode) {
                                    viewModel?.selectCity(city)
                                }
                            }
                        }
                        .padding(.vertical, TravSpacing.xxs)
                    }
                }
            } else if case .loading = viewModel?.loadState {
                ProgressView()
                    .tint(appearance.isLightMode ? TravColors.accent : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TravSpacing.sm)
            } else if case .failed = viewModel?.loadState {
                VStack(spacing: TravSpacing.sm) {
                    Text("Couldn't load cities")
                        .font(TravTypography.bodyMedium())
                        .foregroundStyle(TravColors.muted)
                    Button("Try Again") {
                        Task { await viewModel?.loadCities() }
                    }
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(TravColors.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, TravSpacing.sm)
            }
        }
    }
}

// MARK: - Celestial backdrop

/// Sky behind the globe — night indigo in dark mode, soft daylight wash in light mode.
/// The SceneKit globe textures/lights are unchanged.
struct HomeCelestialBackground: View {
    @Environment(AppearanceStore.self) private var appearance

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let isLight = appearance.isLightMode

            ZStack {
                if isLight {
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.92, green: 0.93, blue: 0.97), location: 0),
                            .init(color: Color(red: 0.89, green: 0.90, blue: 0.95), location: 0.5),
                            .init(color: Color(red: 0.90, green: 0.91, blue: 0.96), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    RadialGradient(
                        colors: [
                            Color(red: 0.65, green: 0.62, blue: 0.85).opacity(0.15),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: min(size.width, size.height) * 0.8
                    )
                } else {
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.012, green: 0.014, blue: 0.035), location: 0),
                            .init(color: Color(red: 0.03, green: 0.035, blue: 0.08), location: 0.42),
                            .init(color: Color(red: 0.055, green: 0.045, blue: 0.11), location: 0.78),
                            .init(color: Color(red: 0.07, green: 0.055, blue: 0.13), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    RadialGradient(
                        colors: [
                            Color(red: 0.22, green: 0.18, blue: 0.36).opacity(0.18),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: min(size.width, size.height) * 0.8
                    )
                }

                DottedGridView()
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
    }
}


private struct CityPinAnchoredPreview: View {
    let city: City
    let anchor: CGPoint
    let containerSize: CGSize
    var isLightMode: Bool = false
    let onVisit: () -> Void
    let onDismiss: () -> Void

    private let cardWidth: CGFloat = 280

    var body: some View {
        let halfWidth = cardWidth / 2
        let margin: CGFloat = 16
        // Keep the card on-screen horizontally; arrow stays under the pin via midX alignment.
        let clampedX = min(
            max(anchor.x, halfWidth + margin),
            containerSize.width - halfWidth - margin
        )

        CityGlobePreviewCard(
            city: city,
            isLightMode: isLightMode,
            onVisit: onVisit,
            onDismiss: onDismiss
        )
        .frame(width: cardWidth)
        // Top-leading layout + offset so the view's hit box is only the card,
        // with the caret tip sitting exactly on the pin tip.
        .offset(x: clampedX - halfWidth, y: anchor.y)
    }
}

private struct CityGlobePreviewCard: View {
    let city: City
    var isLightMode: Bool = false
    let onVisit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Caret tip is the top of this stack — must sit flush against the pin tip.
            CityPreviewCaret(isLightMode: isLightMode)

            VStack(alignment: .leading, spacing: TravSpacing.sm) {
                HStack(alignment: .top, spacing: TravSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(city.name)
                            .font(TravTypography.titleMedium())
                            .foregroundStyle(isLightMode ? Color.black : Color.white)
                            .lineLimit(1)

                        Text(city.countryName)
                            .font(TravTypography.caption())
                            .foregroundStyle(TravColors.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: TravSpacing.sm)

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(TravColors.muted)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(isLightMode ? Color.black.opacity(0.06) : Color.white.opacity(0.1))
                            )
                    }
                    .buttonStyle(TravPressButtonStyle(scale: 0.92))
                    .accessibilityLabel("Dismiss")
                }

                HStack(spacing: TravSpacing.xs) {
                    CityPreviewStat(
                        symbol: "sparkles",
                        value: TravFormatters.count(city.experienceCount),
                        label: city.experienceCount == 1 ? "experience" : "experiences",
                        isLightMode: isLightMode
                    )
                    CityPreviewStat(
                        symbol: "person.2.fill",
                        value: TravFormatters.count(city.creatorCount),
                        label: city.creatorCount == 1 ? "creator" : "creators",
                        isLightMode: isLightMode
                    )
                }

                Button(action: onVisit) {
                    Text("Visit city")
                        .font(TravTypography.labelMedium())
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(TravColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.sm, style: .continuous))
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.97))
                .accessibilityLabel("Visit \(city.name)")
            }
            .padding(TravSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, isLightMode ? .light : .dark)
            )
            .overlay {
                RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                    .stroke(
                        isLightMode ? Color.black.opacity(0.1) : Color.white.opacity(0.14),
                        lineWidth: 1
                    )
            }
            .overlay {
                CityPreviewTracingGlow(cornerRadius: TravRadius.lg)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(isLightMode ? 0.1 : 0.35), radius: 18, y: 8)
        }
        .frame(width: 280)
        .accessibilityElement(children: .contain)
    }
}

/// Short glowing accent segment that continuously traces the card perimeter.
private struct CityPreviewTracingGlow: View {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let lapDuration: TimeInterval = 2.8
    private let segmentLength: CGFloat = 0.14

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 12.0 : 1.0 / 60.0)) { context in
            let phase: CGFloat = {
                if reduceMotion { return 0.08 }
                let t = context.date.timeIntervalSinceReferenceDate
                return CGFloat(t.truncatingRemainder(dividingBy: lapDuration) / lapDuration)
            }()

            ZStack {
                glowStroke(from: phase, length: segmentLength, lineWidth: 2.5, blur: 6, opacity: 0.55)
                glowStroke(from: phase, length: segmentLength, lineWidth: 1.6, blur: 2, opacity: 1.0)
            }
        }
    }

    @ViewBuilder
    private func glowStroke(
        from phase: CGFloat,
        length: CGFloat,
        lineWidth: CGFloat,
        blur: CGFloat,
        opacity: Double
    ) -> some View {
        let start = phase.truncatingRemainder(dividingBy: 1)
        let end = start + length
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        let color = TravColors.accent.opacity(opacity)

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .trim(from: start, to: min(end, 1))
                .stroke(color, style: style)

            if end > 1 {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .trim(from: 0, to: end - 1)
                    .stroke(color, style: style)
            }
        }
        .shadow(color: TravColors.accent.opacity(opacity * 0.9), radius: blur)
        .shadow(color: TravColors.accent.opacity(opacity * 0.45), radius: blur * 1.8)
    }
}

private struct CityPreviewStat: View {
    let symbol: String
    let value: String
    let label: String
    var isLightMode: Bool = false

    var body: some View {
        HStack(spacing: TravSpacing.xxs) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TravColors.accent)

            Text("\(value) \(label)")
                .font(TravTypography.caption())
                .foregroundStyle(isLightMode ? Color.black.opacity(0.65) : Color.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, TravSpacing.xs)
        .padding(.vertical, TravSpacing.xxs + 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TravRadius.sm, style: .continuous)
                .fill(isLightMode ? Color.black.opacity(0.04) : Color.white.opacity(0.07))
        )
    }
}

private struct CityPreviewCaret: View {
    var isLightMode: Bool = false

    var body: some View {
        Triangle()
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, isLightMode ? .light : .dark)
            .frame(width: 18, height: 10)
            .overlay {
                Triangle()
                    .stroke(
                        isLightMode ? Color.black.opacity(0.1) : Color.white.opacity(0.14),
                        lineWidth: 1
                    )
            }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct CityChip: View {
    let city: City
    var isLightMode: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TravSpacing.xs) {
                Circle()
                    .fill(TravColors.accent)
                    .frame(width: 6, height: 6)
                Text(city.name)
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(isLightMode ? Color.black : .white)
                    .lineLimit(1)
            }
            .padding(.horizontal, TravSpacing.sm + TravSpacing.xxs)
            .frame(minHeight: 36)
            .background(
                isLightMode
                    ? TravColors.surfaceElevated.opacity(0.95)
                    : Color.white.opacity(0.12)
            )
            .clipShape(Capsule())
            .overlay {
                if isLightMode {
                    Capsule().stroke(Color.black.opacity(0.18), lineWidth: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.96))
        .accessibilityLabel(city.name)
    }
}

private struct GlobeUserSearchResultRow: View {
    let user: ProfileSummary
    @Environment(SessionStore.self) private var session
    @Environment(EngagementStore.self) private var engagement
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router

    var onSelect: () -> Void

    private var isFollowing: Bool? {
        guard let currentUserID = session.currentUser?.id else { return nil }
        if currentUserID == user.id { return nil }
        return engagement.isFollowing(user.id)
    }

    var body: some View {
        ProfileUserRow(
            user: user,
            isFollowing: isFollowing,
            onTap: onSelect,
            onFollowToggle: session.currentUser?.id == user.id ? nil : {
                Task {
                    let stub = Profile(
                        id: user.id,
                        username: user.username,
                        displayName: user.displayName,
                        bio: nil,
                        avatarURL: user.avatarURL,
                        homeCityID: nil,
                        homeCityName: nil,
                        followerCount: 0,
                        followingCount: 0,
                        experienceCount: 0,
                        completionCount: 0,
                        isVerified: user.isVerified,
                        selectedVibes: nil,
                        onboardingLocation: nil,
                        isFollowing: engagement.isFollowing(user.id)
                    )
                    _ = await engagement.toggleFollow(target: stub, using: environment)
                }
            }
        )
    }
}
