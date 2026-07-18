import SwiftUI

struct GlobeLandingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @State private var viewModel: GlobeViewModel?
    @State private var showOnboarding = false
    @State private var searchText = ""

    var body: some View {
        ZStack {
            HomeCelestialBackground()
                .ignoresSafeArea()

            GeometryReader { geo in
                if let viewModel {
                    EarthGlobeView(controller: viewModel.controller)
                        .frame(width: geo.size.width, height: geo.size.height * 0.68)
                        // Nudged up ~1/10″ from prior seat for hero balance.
                        .position(x: geo.size.width * 0.5, y: geo.size.height * 0.48 + 1)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, TravSpacing.sm)

                searchBar
                    .padding(.horizontal, TravSpacing.xxs)

                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                bottomCTA
                    .padding(.bottom, TravSpacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .safeAreaPadding(.top, TravSpacing.xs)
            .safeAreaPadding(.bottom, TravSpacing.xs)
        }
        .task {
            guard viewModel == nil else { return }
            let vm = GlobeViewModel(
                citiesRepository: environment.cities,
                router: environment.router
            )
            viewModel = vm
            await vm.loadCities()
        }
        .onChange(of: router.presentedRoute) { previous, current in
            // When leaving a city (or any modal route) back to home, restore default zoom.
            if previous != nil, current == nil {
                viewModel?.resetZoomAfterReturningHome()
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            if case let .loaded(allCities) = viewModel?.loadState {
                if newValue.isEmpty {
                    viewModel?.renderer.setCities(allCities)
                } else {
                    let filtered = allCities.filter { city in
                        city.name.localizedCaseInsensitiveContains(newValue) ||
                        city.countryName.localizedCaseInsensitiveContains(newValue)
                    }
                    viewModel?.renderer.setCities(filtered)
                }
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            // Left Side: Brand Logo and Title
            HStack(spacing: TravSpacing.sm) {
                // Violet map pin brand badge
                ZStack {
                    Circle()
                        .fill(TravColors.accent.opacity(0.15))
                        .frame(width: 46, height: 46)
                    
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(TravColors.accent)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRAV")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(.white)
                    
                    Text("What's the move?")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            
            Spacer()
            
            // Right Side: Auth / Profile Action
            if session.isAuthenticated {
                Button(action: {
                    if let username = session.currentUser?.username {
                        router.presentedRoute = .profile(username)
                    }
                }) {
                    if let avatarURL = session.currentUser?.avatarURL {
                        AsyncImage(url: avatarURL) { image in
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            defaultAvatar
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(Color.white.opacity(0.15), lineWidth: 1)
                        }
                    } else {
                        defaultAvatar
                    }
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.92))
                .accessibilityLabel("Profile")
            } else {
                // Sign In Button
                Button { showOnboarding = true } label: {
                    Text("Sign In")
                        .font(TravTypography.bodyMedium())
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, TravSpacing.lg)
                        .frame(height: 38)
                        .background(
                            Capsule()
                                .fill(TravColors.accent.opacity(0.15))
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
        .padding(.vertical, TravSpacing.sm)
    }

    private var defaultAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 44, height: 44)
            
            Image(systemName: "person.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TravColors.muted)
        }
    }

    private var searchBar: some View {
        HStack(spacing: TravSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TravColors.muted)
            
            TextField("Search spots, cities, creators...", text: $searchText)
                .font(TravTypography.bodyMedium())
                .foregroundStyle(.white)
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
        )
        .overlay {
            RoundedRectangle(cornerRadius: TravRadius.md)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        }
        .padding(.vertical, TravSpacing.xs)
    }

    private var bottomCTA: some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            if case let .loaded(cities) = viewModel?.loadState {
                let filtered = cities.filter { city in
                    searchText.isEmpty ||
                    city.name.localizedCaseInsensitiveContains(searchText) ||
                    city.countryName.localizedCaseInsensitiveContains(searchText)
                }

                if filtered.isEmpty {
                    Text("No matching cities found")
                        .font(TravTypography.bodyMedium())
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, TravSpacing.md)
                } else {
                    Text("Tap a city pin to explore")
                        .font(TravTypography.labelMedium())
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: TravSpacing.sm) {
                                let prefixCities = Array(filtered.prefix(6))
                                ForEach(0..<prefixCities.count, id: \.self) { index in
                                    CityChip(city: prefixCities[index]) {
                                        viewModel?.selectCity(prefixCities[index])
                                    }
                                    .id(index)
                                }
                            }
                            .padding(.vertical, TravSpacing.xxs)
                        }
                        .task {
                            let count = min(filtered.count, 6)
                            await runAutoScroll(proxy: proxy, count: count)
                        }
                    }
                }
            } else if case .loading = viewModel?.loadState {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TravSpacing.sm)
            }
        }
    }

    private func runAutoScroll(proxy: ScrollViewProxy, count: Int) async {
        guard count > 1 else { return }
        
        var currentIndex = 0
        var goingForward = true
        
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            
            if goingForward {
                currentIndex += 1
                if currentIndex >= count {
                    currentIndex = count - 2
                    goingForward = false
                }
            } else {
                currentIndex -= 1
                if currentIndex < 0 {
                    currentIndex = 1
                    goingForward = true
                }
            }
            
            withAnimation(.easeInOut(duration: 1.5)) {
                proxy.scrollTo(currentIndex, anchor: .center)
            }
        }
    }
}

// MARK: - Celestial night backdrop

/// Darker night-sky gradient with a soft galactic haze and a procedural star field.
/// Inspired by a deep indigo→violet starfield — not a pasted photo asset.
private struct HomeCelestialBackground: View {
    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                // Base vertical wash: near-black navy → deep indigo → muted plum.
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

                // Soft central haze — faint Milky Way band, kept dark.
                EllipticalGradient(
                    colors: [
                        Color(red: 0.22, green: 0.18, blue: 0.36).opacity(0.22),
                        Color(red: 0.12, green: 0.1, blue: 0.22).opacity(0.1),
                        .clear
                    ],
                    center: .center,
                    startRadiusFraction: 0.05,
                    endRadiusFraction: 0.72
                )
                .scaleEffect(x: 0.55, y: 1.15)
                .blur(radius: 28)
                .opacity(0.85)

                // Slight secondary bloom toward the lower third.
                RadialGradient(
                    colors: [
                        Color(red: 0.2, green: 0.14, blue: 0.32).opacity(0.16),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.78),
                    startRadius: 0,
                    endRadius: min(size.width, size.height) * 0.55
                )

                // Subtle dotted grid background instead of stars
                DottedGridView()
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
    }
}


private struct CityChip: View {
    let city: City
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TravSpacing.xs) {
                Circle()
                    .fill(TravColors.accent)
                    .frame(width: 6, height: 6)
                Text(city.name)
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, TravSpacing.sm + TravSpacing.xxs)
            .frame(minHeight: 36)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.96))
        .accessibilityLabel(city.name)
    }
}
