import SwiftUI

struct CityPageView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @State private var viewModel: CityViewModel

    init(cityID: UUID) {
        _viewModel = State(initialValue: CityViewModel(cityID: cityID))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .loading:
                    CityPageSkeleton()
                case .empty:
                    EmptyStateView(
                        icon: "map",
                        title: "No Experiences Yet",
                        description: "This city doesn't have any published experiences. Check back soon."
                    )
                case let .loaded(content):
                    loadedContent(content)
                case let .failed(error):
                    ErrorStateView(message: error.localizedDescription) {
                        Task { await viewModel.load(using: environment) }
                    }
                }
            }
            .travScreenBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DismissButton { router.dismiss() }
                }
            }
        }
        .task {
            await viewModel.load(using: environment)
        }
    }

    @ViewBuilder
    private func loadedContent(_ content: CityViewModel.Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroSection(content.city)
                    .travAppear()

                featuredSection(content.featured)
                    .travAppear(delay: 0.08)

                feedSection(content.feed)
                    .travAppear(delay: 0.14)
            }
            .padding(.bottom, TravSpacing.xxl)
        }
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private func heroSection(_ city: City) -> some View {
        HeroImageHeader(url: city.heroImageURL, height: TravLayout.heroCityHeight) {
            VStack(alignment: .leading, spacing: TravSpacing.xs) {
                Text(city.name)
                    .font(TravTypography.displayLarge())
                    .foregroundStyle(.white)

                HStack(spacing: TravSpacing.md) {
                    Label("\(city.experienceCount) experiences", systemImage: "map")
                    Label("\(city.creatorCount) creators", systemImage: "person.2")
                }
                .font(TravTypography.labelMedium())
                .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    @ViewBuilder
    private func featuredSection(_ featured: ExperienceSummary?) -> some View {
        if let featured {
            VStack(alignment: .leading, spacing: TravSpacing.sm) {
                Text("Featured Experience")
                    .font(TravTypography.titleLarge())
                    .foregroundStyle(TravColors.primary)
                    .padding(.horizontal, TravSpacing.screenHorizontal)

                Button {
                    router.openExperience(featured.id)
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        RemoteImage(
                            url: featured.coverImageURL,
                            height: TravLayout.featuredCardHeight,
                            cornerRadius: TravRadius.lg
                        )

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.65)],
                            startPoint: .center,
                            endPoint: .bottom
                        )

                        VStack(alignment: .leading, spacing: TravSpacing.xs) {
                            Text(featured.title)
                                .font(TravTypography.titleLarge())
                                .foregroundStyle(.white)
                            RoutePreview(stops: featured.stops, compact: true)
                        }
                        .padding(TravSpacing.md)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
                }
                .buttonStyle(TravPressButtonStyle())
                .padding(.horizontal, TravSpacing.screenHorizontal)
            }
            .padding(.top, TravSpacing.lg)
        }
    }

    @ViewBuilder
    private func feedSection(_ feed: [ExperienceSummary]) -> some View {
        VStack(alignment: .leading, spacing: TravSpacing.md) {
            Text("Discover")
                .font(TravTypography.titleLarge())
                .foregroundStyle(TravColors.primary)
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.top, TravSpacing.lg)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: TravSpacing.md),
                    GridItem(.flexible(), spacing: TravSpacing.md)
                ],
                spacing: TravSpacing.md
            ) {
                ForEach(Array(feed.enumerated()), id: \.element.id) { index, experience in
                    ExperienceCard(experience: experience) {
                        router.openExperience(experience.id)
                    }
                    .travAppear(delay: Double(index) * 0.04)
                }
            }
            .padding(.horizontal, TravSpacing.screenHorizontal)
        }
    }
}
