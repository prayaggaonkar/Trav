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
                    VStack { ProgressView(); Spacer() }
                case .empty:
                    Text("No experiences yet in this city.")
                        .font(TravTypography.bodyMedium())
                        .foregroundStyle(TravColors.muted)
                case let .loaded(content):
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            heroSection(content.city)
                            featuredSection(content.featured)
                            feedSection(content.feed)
                        }
                    }
                    .ignoresSafeArea(edges: .top)
                case let .failed(error):
                    VStack(spacing: TravSpacing.md) {
                        Text(error.localizedDescription)
                        PrimaryButton(title: "Try Again") {
                            Task { await viewModel.load(using: environment) }
                        }
                    }
                    .padding()
                }
            }
            .background(TravColors.surface)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        router.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(TravColors.primary)
                            .padding(10)
                            .background(TravColors.surfaceElevated)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .task {
            await viewModel.load(using: environment)
        }
    }

    @ViewBuilder
    private func heroSection(_ city: City) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = city.heroImageURL {
                    AsyncImage(url: url) { phase in
                        if case let .success(image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle().fill(TravColors.surfaceElevated)
                        }
                    }
                }
            }
            .frame(height: 380)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 380)

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
            .padding(TravSpacing.screenHorizontal)
            .padding(.bottom, TravSpacing.lg)
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
                        AsyncImage(url: featured.coverImageURL) { phase in
                            if case let .success(image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                Rectangle().fill(TravColors.surfaceElevated)
                            }
                        }
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipped()

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.65)],
                            startPoint: .center,
                            endPoint: .bottom
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(featured.title)
                                .font(TravTypography.titleLarge())
                                .foregroundStyle(.white)
                            RoutePreview(stops: featured.stops, compact: true)
                        }
                        .padding(TravSpacing.md)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
                }
                .buttonStyle(.plain)
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
                ForEach(feed) { experience in
                    ExperienceCard(experience: experience) {
                        router.openExperience(experience.id)
                    }
                }
            }
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .padding(.bottom, TravSpacing.xxl)
        }
    }
}
