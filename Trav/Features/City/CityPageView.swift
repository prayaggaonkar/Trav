import SwiftUI

struct CityPageView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @State private var viewModel: CityViewModel
    @State private var scrollOffset: CGFloat = 0
    @State private var sharePayload: SharePayload?
    @State private var heroHeight: CGFloat = TravLayout.heroCityHeight

    init(cityID: UUID) {
        _viewModel = State(initialValue: CityViewModel(cityID: cityID))
    }

    private var showsNavTitle: Bool {
        scrollOffset > heroHeight - 96
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let computedHero = max(TravLayout.heroCityHeight, geometry.size.height * 0.36)

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
                        loadedContent(content, heroHeight: computedHero)
                            .onAppear { heroHeight = computedHero }
                            .onChange(of: computedHero) { _, newValue in
                                heroHeight = newValue
                            }
                    case let .failed(error):
                        ErrorStateView(message: error.localizedDescription) {
                            Task { await viewModel.load(using: environment) }
                        }
                    }
                }
                .travScreenBackground()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CityBackButton(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        router.dismiss()
                    }, prominent: !showsNavTitle)
                }

                ToolbarItem(placement: .principal) {
                    if case let .loaded(content) = viewModel.phase, showsNavTitle {
                        Text(content.city.name)
                            .font(TravTypography.titleMedium())
                            .foregroundStyle(TravColors.primary)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
            .toolbarBackground(showsNavTitle ? .visible : .hidden, for: .navigationBar)
            .toolbarBackground(TravColors.surface.opacity(0.92), for: .navigationBar)
            .animation(TravAnimation.quick, value: showsNavTitle)
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: [payload.text])
        }
        .task {
            await viewModel.load(using: environment)
        }
    }

    @ViewBuilder
    private func loadedContent(_ content: CityViewModel.Content, heroHeight: CGFloat) -> some View {
        let feed = viewModel.filteredFeed(from: content)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: CityScrollOffsetKey.self,
                            value: -proxy.frame(in: .named("cityScroll")).minY
                        )
                }
                .frame(height: 0)

                heroSection(content.city, height: heroHeight)
                    .travAppear()

                VStack(alignment: .leading, spacing: TravSpacing.xl) {
                    CitySearchBar(text: $viewModel.searchQuery, cityName: content.city.name)
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                        .travAppear(delay: 0.05)

                    if let featured = content.featured, viewModel.searchQuery.isEmpty {
                        featuredSection(featured, cityName: content.city.name)
                            .travAppear(delay: 0.08)
                    }

                    if !content.creators.isEmpty, viewModel.searchQuery.isEmpty {
                        TrendingCreatorsSection(creators: content.creators) { creator in
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            router.openProfile(creator.username)
                        }
                        .travAppear(delay: 0.11)
                    }

                    feedSection(feed, cityName: content.city.name)
                        .travAppear(delay: 0.14)
                }
                .padding(.top, TravSpacing.lg)
                .padding(.bottom, TravSpacing.xxl)
            }
        }
        .coordinateSpace(name: "cityScroll")
        .ignoresSafeArea(edges: .top)
        .onPreferenceChange(CityScrollOffsetKey.self) { value in
            scrollOffset = value
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func heroSection(_ city: City, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: city.heroImageURL, height: height, cornerRadius: 0)

            LinearGradient(
                colors: [
                    .black.opacity(0.15),
                    .clear,
                    .black.opacity(0.55),
                    .black.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: TravSpacing.sm) {
                Text(city.locationLabel)
                    .font(TravTypography.displayLarge())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 2)

                VStack(alignment: .leading, spacing: TravSpacing.xxs) {
                    Text("\(TravFormatters.groupedCount(city.experienceCount)) Experiences")
                        .font(TravTypography.titleMedium())
                        .foregroundStyle(.white.opacity(0.92))
                    Text("\(TravFormatters.groupedCount(city.creatorCount)) Creators")
                        .font(TravTypography.bodyMedium())
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .padding(.bottom, TravSpacing.xl)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func featuredSection(_ featured: ExperienceSummary, cityName: String) -> some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            FeaturedExperienceCard(
                experience: featured,
                isSaved: viewModel.isSaved(featured.id),
                isLiked: viewModel.isLiked(featured.id),
                onTap: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    router.openExperience(featured.id)
                },
                onCreatorTap: {
                    router.openProfile(featured.creator.username)
                },
                onSave: { viewModel.toggleSave(for: featured.id) },
                onLike: { viewModel.toggleLike(for: featured.id) },
                onShare: {
                    sharePayload = SharePayload(
                        text: viewModel.shareText(for: featured, cityName: cityName)
                    )
                }
            )
            .padding(.horizontal, TravSpacing.screenHorizontal)
        }
    }

    @ViewBuilder
    private func feedSection(_ feed: [ExperienceSummary], cityName: String) -> some View {
        VStack(alignment: .leading, spacing: TravSpacing.md) {
            HStack {
                Text(viewModel.searchQuery.isEmpty ? "Experiences" : "Results")
                    .font(TravTypography.titleLarge())
                    .foregroundStyle(TravColors.primary)

                Spacer()

                if !feed.isEmpty {
                    Text("\(feed.count)")
                        .font(TravTypography.labelMedium())
                        .foregroundStyle(TravColors.muted)
                }
            }
            .padding(.horizontal, TravSpacing.screenHorizontal)

            if feed.isEmpty {
                Text(viewModel.searchQuery.isEmpty
                    ? "No experiences to show yet."
                    : "No experiences match your search.")
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.muted)
                    .padding(.horizontal, TravSpacing.screenHorizontal)
                    .padding(.top, TravSpacing.sm)
            } else {
                LazyVStack(spacing: TravSpacing.lg) {
                    ForEach(Array(feed.enumerated()), id: \.element.id) { index, experience in
                        ExperienceCard(
                            experience: experience,
                            isSaved: viewModel.isSaved(experience.id),
                            isLiked: viewModel.isLiked(experience.id),
                            onTap: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                router.openExperience(experience.id)
                            },
                            onCreatorTap: {
                                router.openProfile(experience.creator.username)
                            },
                            onSave: { viewModel.toggleSave(for: experience.id) },
                            onLike: { viewModel.toggleLike(for: experience.id) },
                            onShare: {
                                sharePayload = SharePayload(
                                    text: viewModel.shareText(for: experience, cityName: cityName)
                                )
                            }
                        )
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                        .travAppear(delay: Double(min(index, 6)) * 0.04)
                    }
                }
            }
        }
    }
}

// MARK: - Share

private struct SharePayload: Identifiable {
    let id = UUID()
    let text: String
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
