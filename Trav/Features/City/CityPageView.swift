import SwiftUI

struct CityPageView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(EngagementStore.self) private var engagement
    @State private var viewModel: CityViewModel
    @State private var scrollOffset: CGFloat = 0
    @State private var sharePayload: SharePayload?
    @State private var heroHeight: CGFloat = TravLayout.heroCityHeight

    init(cityID: UUID) {
        _viewModel = State(initialValue: CityViewModel(cityID: cityID))
    }

    private var showsNavTitle: Bool {
        scrollOffset > heroHeight - 88
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                TravColors.surface.ignoresSafeArea()

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

                // Overlay back control — avoids iOS toolbar glass creating a second circle.
                CityBackButton(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    router.dismiss()
                }, prominent: !showsNavTitle)
                .padding(.leading, TravSpacing.screenHorizontal)
                .safeAreaPadding(.top, TravSpacing.xs)
                .navBarZoomable()
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if case let .loaded(content) = viewModel.phase, showsNavTitle {
                        Text(content.city.name)
                            .font(TravTypography.titleMedium())
                            .foregroundStyle(TravColors.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .transition(.opacity)
                            .navBarZoomable()
                    }
                }
            }
            .toolbarBackground(showsNavTitle ? .visible : .hidden, for: .navigationBar)
            .toolbarBackground(TravColors.surface.opacity(0.94), for: .navigationBar)
            .animation(TravAnimation.quick, value: showsNavTitle)
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: [payload.text])
        }
        .task {
            await viewModel.load(using: environment)
        }
        .onChange(of: session.currentUser) { _, _ in
            Task {
                await viewModel.load(using: environment)
            }
        }
    }

    private static func resolvedHeroHeight(for screenHeight: CGFloat) -> CGFloat {
        min(
            TravLayout.heroCityHeight,
            max(TravLayout.heroCityHeightMin, screenHeight * 0.34)
        )
    }

    @ViewBuilder
    private func loadedContent(_ content: CityViewModel.Content) -> some View {
        let feed = viewModel.filteredFeed(from: content)

        GeometryReader { geometry in
            let resolvedHero = Self.resolvedHeroHeight(for: geometry.size.height)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: TravSpacing.lg) {
                    Color.clear
                        .frame(height: 0)
                        .onAppear { heroHeight = resolvedHero }
                        .onChange(of: resolvedHero) { _, newValue in
                            heroHeight = newValue
                        }
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: CityScrollOffsetKey.self,
                                    value: -proxy.frame(in: .named("cityScroll")).minY
                                )
                            }
                        }

                    let experiencesCount = feed.count
                    let creatorsCount = Set(feed.map { $0.creator.id }).count

                    heroSection(
                        content.city,
                        experiencesCount: experiencesCount,
                        creatorsCount: creatorsCount,
                        height: resolvedHero
                    )
                        .frame(width: geometry.size.width)
                        .padding(.bottom, -TravSpacing.lg)
                        .travAppear()

                    feedSection(feed, cityName: content.city.name)
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                        .travAppear(delay: 0.08)
                }
                .padding(.bottom, TravSpacing.lg)
                .frame(maxWidth: geometry.size.width, alignment: .leading)
            }
            .trackScrollForNavBarZoom()
            .coordinateSpace(name: "cityScroll")
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .ignoresSafeArea(edges: .top)
            .onPreferenceChange(CityScrollOffsetKey.self) { value in
                scrollOffset = value
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { heroHeight = resolvedHero }
        }
    }

    @ViewBuilder
    private func heroSection(
        _ city: City,
        experiencesCount: Int,
        creatorsCount: Int,
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: city.heroImageURL, height: height, cornerRadius: 0)

            LinearGradient(
                colors: [
                    .black.opacity(0.2),
                    .clear,
                    .black.opacity(0.5),
                    .black.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: TravSpacing.xs) {
                Text(city.locationLabel)
                    .font(TravTypography.displayLarge())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(TravFormatters.groupedCount(experiencesCount)) experiences · \(TravFormatters.groupedCount(creatorsCount)) creators")
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .padding(.bottom, TravSpacing.lg)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func featuredSection(_ featured: ExperienceSummary, cityName: String) -> some View {
        FeaturedExperienceCard(
            experience: featured,
            isSaved: engagement.isSaved(featured.id),
            isLiked: engagement.isLiked(featured.id),
            onTap: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                router.openExperience(featured.id)
            },
            onCreatorTap: {
                router.openProfile(featured.creator.username)
            },
            onSave: {
                Task {
                    await engagement.toggleSave(
                        experienceID: featured.id,
                        summary: featured,
                        using: environment
                    )
                }
            },
            onLike: {
                Task {
                    await engagement.toggleLike(
                        experienceID: featured.id,
                        summary: featured,
                        using: environment
                    )
                }
            },
            onShare: {
                sharePayload = SharePayload(
                    text: viewModel.shareText(for: featured, cityName: cityName)
                )
            }
        )
    }

    @ViewBuilder
    private func feedSection(_ feed: [ExperienceSummary], cityName: String) -> some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            Text(viewModel.searchQuery.isEmpty ? "Experiences" : "Results")
                .font(TravTypography.titleMedium())
                .foregroundStyle(TravColors.primary)
                .lineLimit(1)

            if feed.isEmpty {
                Text(viewModel.searchQuery.isEmpty
                    ? "No experiences to show yet."
                    : "No experiences match your search.")
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVStack(spacing: TravSpacing.md) {
                    ForEach(Array(feed.enumerated()), id: \.element.id) { index, experience in
                        let isUserCreated = session.currentUser?.id == experience.creator.id
                        let badgeText = isUserCreated ? "Created by You" : ""
                        ExperienceCard(
                            experience: experience,
                            badgeText: badgeText,
                            isSaved: engagement.isSaved(experience.id),
                            isLiked: engagement.isLiked(experience.id),
                            onTap: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                router.openExperience(experience.id)
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
                                sharePayload = SharePayload(
                                    text: viewModel.shareText(for: experience, cityName: cityName)
                                )
                            }
                        )
                        .travAppear(delay: Double(min(index, 6)) * 0.04)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Share

private struct SharePayload: Identifiable {
    let id = UUID()
    let text: String
}
