import SwiftUI
import UIKit

struct GlobeLandingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @State private var viewModel: GlobeViewModel?
    @State private var topOverlayPadding: CGFloat = 79

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
                Color.clear
                    .frame(height: topOverlayPadding)
                    .allowsHitTesting(false)

                header
                    .offset(y: -20)

                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                bottomCTA
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .padding(.bottom, 100)
        }
        .onAppear(perform: refreshTopOverlayPadding)
        .task {
            guard viewModel == nil else { return }
            let vm = GlobeViewModel(
                citiesRepository: environment.cities,
                router: environment.router
            )
            viewModel = vm
            await vm.loadCities()
        }
    }

    private func refreshTopOverlayPadding() {
        let safeTop = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 59
        topOverlayPadding = safeTop + Self.headerTopInset
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Trav")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("What should you do today?")
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
            if !session.isAuthenticated {
                Button { router.presentAuth() } label: {
                    Text("Sign In")
                        .font(TravTypography.labelMedium())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var bottomCTA: some View {
        VStack(spacing: TravSpacing.sm) {
            if case let .loaded(cities) = viewModel?.loadState {
                Text("Tap a glowing city to explore")
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(.white.opacity(0.6))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TravSpacing.sm) {
                        ForEach(cities.prefix(6)) { city in
                            CityChip(city: city) { viewModel?.selectCity(city) }
                        }
                    }
                }
            } else if case .loading = viewModel?.loadState {
                ProgressView().tint(.white)
            }
        }
    }
}

private struct CityChip: View {
    let city: City
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(TravColors.accent).frame(width: 6, height: 6)
                Text(city.name).font(TravTypography.labelMedium()).foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
