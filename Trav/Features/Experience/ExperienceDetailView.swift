import SwiftUI

struct ExperienceDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(EngagementStore.self) private var engagement
    @State private var experience: Experience?
    @State private var isLoading = true
    @State private var error: Error?

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
        .task {
            await load()
            if let userID = environment.session.currentUser?.id {
                await engagement.bootstrap(userID: userID, using: environment)
            }
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
        HeroImageHeader(url: experience.coverImageURL, height: TravLayout.heroExperienceHeight) {
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
            coverImageURL: experience.coverImageURL,
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
                Task { await engagement.toggleComplete(experienceID: experience.id, using: environment) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 15, weight: .bold))
                    Text(isCompleted ? "Completed" : "Complete")
                        .font(TravTypography.labelMedium())
                        .fontWeight(.bold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(TravColors.accent)
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
            Text("About this Experience")
                .font(TravTypography.titleLarge())
                .fontWeight(.bold)
                .foregroundStyle(TravColors.primary)

            if !experience.description.isEmpty {
                Text(experience.description)
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            RoutePreview(stops: experience.stops.map {
                StopPreview(id: $0.id, name: $0.name, emoji: $0.emoji)
            })
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
