import SwiftUI

struct GlobeLandingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @State private var viewModel: GlobeViewModel?
    @State private var showOnboarding = false

    var body: some View {
        ZStack {
            HomeCelestialBackground()
                .ignoresSafeArea()

            GeometryReader { geo in
                if let viewModel {
                    EarthGlobeView(controller: viewModel.controller)
                        .frame(width: geo.size.width, height: geo.size.height * 0.68)
                        .position(x: geo.size.width * 0.5, y: geo.size.height * 0.40)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, TravSpacing.sm)

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
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: TravSpacing.md) {
            VStack(alignment: .leading, spacing: TravSpacing.xxs) {
                Text("Trav")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("What's the move?")
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !session.isAuthenticated {
                Button { showOnboarding = true } label: {
                    Text("Sign In")
                        .font(TravTypography.labelMedium())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, TravSpacing.md)
                        .frame(minHeight: TravLayout.minTouchTarget)
                        .background(.white.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.96))
                .accessibilityLabel("Sign In")
            }
        }
    }

    private var bottomCTA: some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            if case let .loaded(cities) = viewModel?.loadState {
                Text("Tap a glowing city to explore")
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TravSpacing.sm) {
                        ForEach(cities.prefix(6)) { city in
                            CityChip(city: city) { viewModel?.selectCity(city) }
                        }
                    }
                    .padding(.vertical, TravSpacing.xxs)
                }
            } else if case .loading = viewModel?.loadState {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TravSpacing.sm)
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

                StarFieldCanvas(seed: 42, starCount: 420)
                // Extra sparse layer of finer dust for depth.
                StarFieldCanvas(seed: 137, starCount: 180)
                    .opacity(0.65)
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
    }
}

private struct StarFieldCanvas: View {
    let seed: UInt64
    let starCount: Int

    var body: some View {
        Canvas { context, size in
            var rng = SeededGenerator(seed: seed)

            for index in 0..<starCount {
                let x = CGFloat.random(in: 0...size.width, using: &rng)
                let y = CGFloat.random(in: 0...size.height, using: &rng)

                // Prefer denser, brighter stars in the upper 60% (darker sky).
                let verticalBias = 1 - (y / max(size.height, 1))
                let baseAlpha = Double.random(in: 0.12...0.55, using: &rng) * (0.55 + 0.45 * verticalBias)
                let radius = CGFloat.random(in: 0.35...1.35, using: &rng)
                    * (index % 17 == 0 ? 1.7 : 1)

                let coolWhite = Color(
                    red: 0.86 + Double.random(in: 0...0.1, using: &rng),
                    green: 0.9 + Double.random(in: 0...0.08, using: &rng),
                    blue: 1.0,
                    opacity: min(0.85, baseAlpha)
                )

                let rect = CGRect(
                    x: x - radius,
                    y: y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(coolWhite))

                // Occasional soft halo on brighter stars.
                if index % 23 == 0 {
                    let halo = radius * 2.8
                    let haloRect = CGRect(
                        x: x - halo,
                        y: y - halo,
                        width: halo * 2,
                        height: halo * 2
                    )
                    context.fill(
                        Path(ellipseIn: haloRect),
                        with: .color(coolWhite.opacity(0.12))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Deterministic RNG so the starfield doesn’t reshuffle on redraw.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEAD_BEEF : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
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
