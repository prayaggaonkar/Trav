import SwiftUI

struct GlobeLandingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @State private var viewModel: GlobeViewModel?
    @State private var topOverlayPadding: CGFloat = 79
    @State private var showOnboarding = false

    /// Extra clearance below the status bar / Dynamic Island.
    private static let headerTopInset: CGFloat = 20

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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

                Text("What should you do today?")
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
