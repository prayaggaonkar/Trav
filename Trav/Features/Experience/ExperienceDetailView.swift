import SwiftUI

struct ExperienceDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(EngagementStore.self) private var engagement
    @State private var experience: Experience?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var showEyesRain = false

    let experienceID: UUID

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ExperienceDetailSkeleton()
                } else if let experience {
                    experienceContent(experience)
                } else if let error {
                    ErrorStateView(message: error.localizedDescription) {
                        Task { await load() }
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
        .overlay(
            Group {
                if showEyesRain {
                    EmojiParticleView()
                }
            }
        )
        .task {
            if let userID = environment.session.currentUser?.id {
                await engagement.refreshBootstrap(userID: userID, using: environment)
            }
            await load()
        }
    }

    @ViewBuilder
    private func experienceContent(_ experience: Experience) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(experience)
                    .travAppear()

                actionBar(experience)
                    .travAppear(delay: 0.06)

                overviewSection(experience)
                    .travAppear(delay: 0.1)

                timeline(experience)
                    .travAppear(delay: 0.14)
            }
            .padding(.bottom, TravSpacing.xxl)
            .safeAreaPadding(.bottom, TravSpacing.sm)
        }
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private func hero(_ experience: Experience) -> some View {
        HeroMediaCarousel(urls: experience.imageURLs, height: TravLayout.heroExperienceHeight) {
            VStack(alignment: .leading, spacing: TravSpacing.sm) {
                Text(experience.title)
                    .font(TravTypography.displayMedium())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    router.openProfile(experience.creator.username)
                } label: {
                    HStack(spacing: TravSpacing.xs) {
                        AvatarView(url: experience.creator.avatarURL, size: 32)
                        Text(experience.creator.displayName)
                            .font(TravTypography.bodyMedium())
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actionBar(_ experience: Experience) -> some View {
        let isSaved = engagement.isSaved(experience.id)
        let isCompleted = engagement.isCompleted(experience.id)
        let summary = ExperienceSummary(
            id: experience.id,
            cityID: experience.cityID,
            title: experience.title,
            imageURLs: experience.imageURLs,
            creator: experience.creator,
            durationMinutes: experience.durationMinutes,
            costLevel: experience.costLevel,
            estimatedCostUSD: experience.estimatedCostUSD,
            saveCount: experience.saveCount,
            likeCount: experience.likeCount,
            completionCount: experience.completionCount,
            stops: experience.stops.map { StopPreview(id: $0.id, name: $0.name, emoji: $0.emoji) }
        )

        return HStack(spacing: TravSpacing.sm) {
            Button {
                Task {
                    await engagement.toggleSave(
                        experienceID: experience.id,
                        summary: summary,
                        using: environment
                    )
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14, weight: .semibold))
                    Text(isSaved ? "Saved" : "Save")
                        .font(TravTypography.labelMedium())
                        .fontWeight(.semibold)
                }
                .foregroundStyle(TravColors.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(TravColors.surfaceElevated)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(TravPressButtonStyle())

            Button {
                let wasCompleted = isCompleted
                Task {
                    let nowCompleted = await engagement.toggleComplete(experienceID: experience.id, summary: summary, using: environment)
                    if nowCompleted && !wasCompleted {
                        withAnimation {
                            showEyesRain = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                            showEyesRain = false
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text(isCompleted ? "I'm Down" : "Watchlist")
                        .font(TravTypography.labelMedium())
                        .fontWeight(.bold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isCompleted ? Color.gray.opacity(0.4) : TravColors.accent)
                .clipShape(Capsule())
            }
            .buttonStyle(TravPressButtonStyle())

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Share")
                        .font(TravTypography.labelMedium())
                        .fontWeight(.semibold)
                }
                .foregroundStyle(TravColors.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(TravColors.surfaceElevated)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(TravPressButtonStyle())
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.vertical, TravSpacing.md)
        .animation(TravAnimation.quick, value: isSaved)
        .animation(TravAnimation.quick, value: isCompleted)
    }

    @ViewBuilder
    private func overviewSection(_ experience: Experience) -> some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            if experience.imageURLs.count > 1 {
                VStack(alignment: .leading, spacing: TravSpacing.xs) {
                    Text("Media Gallery (\(experience.imageURLs.count))")
                        .font(TravTypography.titleMedium())
                        .foregroundStyle(TravColors.primary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: TravSpacing.sm) {
                            ForEach(Array(experience.imageURLs.enumerated()), id: \.offset) { index, url in
                                RemoteImage(url: url, height: 110, cornerRadius: TravRadius.md)
                                    .frame(width: 150, height: 110)
                            }
                        }
                    }
                }
                .padding(.vertical, TravSpacing.xs)
            }

            RoutePreview(stops: experience.stops.map {
                StopPreview(id: $0.id, name: $0.name, emoji: $0.emoji)
            })

            let ratingToDisplay = experience.rating ?? .defaultRating
            VStack(alignment: .leading, spacing: TravSpacing.xs) {
                Text("Experience Rating")
                    .font(TravTypography.titleMedium())
                    .foregroundStyle(TravColors.primary)
                ReadOnlyRadarChartView(rating: ratingToDisplay)
            }
            .padding(.top, TravSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.bottom, TravSpacing.xl)
    }

    @ViewBuilder
    private func timeline(_ experience: Experience) -> some View {
        VStack(alignment: .leading, spacing: TravSpacing.lg) {
            Text("Timeline")
                .font(TravTypography.titleLarge())
                .foregroundStyle(TravColors.primary)
                .padding(.horizontal, TravSpacing.screenHorizontal)

            ForEach(Array(experience.stops.enumerated()), id: \.element.id) { index, stop in
                StopTimelineRow(stop: stop, index: index + 1)
                    .travAppear(delay: Double(index) * 0.05)
            }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            experience = try await environment.experiences.fetchExperience(id: experienceID)
        } catch {
            self.error = error
        }
        isLoading = false
    }
}

private struct StopTimelineRow: View {
    let stop: Stop
    let index: Int

    var body: some View {
        HStack(alignment: .top, spacing: TravSpacing.md) {
            Text("\(index)")
                .font(TravTypography.labelMedium())
                .foregroundStyle(.white)
                .frame(width: TravLayout.minTouchTarget - 16, height: TravLayout.minTouchTarget - 16)
                .background(TravColors.accent)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: TravSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: TravSpacing.xxs) {
                    if let emoji = stop.emoji {
                        Image(systemName: sfSymbolForEmojiOrCategory(emoji))
                            .font(.system(size: 14))
                            .foregroundStyle(TravColors.accent)
                    }
                    Text(stop.name)
                        .font(TravTypography.titleMedium())
                        .foregroundStyle(TravColors.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(stop.description)
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let notes = stop.creatorNotes {
                    Text(notes)
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.accent)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(TravSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(TravColors.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.sm, style: .continuous))
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: TravSpacing.sm) {
                        if let time = stop.recommendedTime {
                            Label(time, systemImage: "sun.max")
                        }
                        Label(TravFormatters.duration(stop.durationMinutes), systemImage: "clock")
                    }
                    VStack(alignment: .leading, spacing: TravSpacing.xxs) {
                        if let time = stop.recommendedTime {
                            Label(time, systemImage: "sun.max")
                        }
                        Label(TravFormatters.duration(stop.durationMinutes), systemImage: "clock")
                    }
                }
                .font(TravTypography.caption())
                .foregroundStyle(TravColors.muted)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
    }
}

private struct HeroMediaCarousel<Overlay: View>: View {
    let urls: [URL]
    let height: CGFloat
    @ViewBuilder let overlay: () -> Overlay

    @State private var currentIndex = 0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if urls.count > 1 {
                TabView(selection: $currentIndex) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        RemoteImage(url: url, height: height, cornerRadius: 0)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else {
                RemoteImage(url: urls.first, height: height, cornerRadius: 0)
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)

            overlay()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.bottom, TravSpacing.lg)

            if urls.count > 1 {
                HStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.system(size: 10))
                    Text("\(currentIndex + 1)/\(urls.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.65))
                .clipShape(Capsule())
                .padding(.trailing, TravSpacing.screenHorizontal)
                .padding(.bottom, TravSpacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}
