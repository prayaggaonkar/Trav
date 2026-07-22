import SwiftUI

struct ExperienceDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
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
        .task { await load() }
    }

    @ViewBuilder
    private func experienceContent(_ experience: Experience) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(experience)
                    .travAppear()

                actionBar
                    .travAppear(delay: 0.06)

                statsRow(experience)
                    .travAppear(delay: 0.1)

                routeOverview(experience)
                    .travAppear(delay: 0.14)

                timeline(experience)
                    .travAppear(delay: 0.18)
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

                HStack(spacing: TravSpacing.xs) {
                    AvatarView(url: experience.creator.avatarURL, size: 32)
                    Text(experience.creator.displayName)
                        .font(TravTypography.bodyMedium())
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionBar: some View {
        HStack(spacing: TravSpacing.sm) {
            TravActionButton(symbol: "bookmark", label: "Save") {}
            TravActionButton(symbol: "checkmark.circle.fill", label: "Complete", isAccent: true) {}
            TravActionButton(symbol: "square.and.arrow.up", label: "Share") {}
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.vertical, TravSpacing.md)
    }

    @ViewBuilder
    private func statsRow(_ experience: Experience) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TravSpacing.sm) {
                StatPill(symbol: "clock", value: TravFormatters.duration(experience.durationMinutes))
                StatPill(symbol: "dollarsign.circle", value: experience.costLevel.displayName)
                StatPill(symbol: "figure.walk", value: TravFormatters.distance(experience.totalDistanceMeters))
                StatPill(symbol: "checkmark.circle", value: TravFormatters.count(experience.completionCount))
            }
            .padding(.horizontal, TravSpacing.screenHorizontal)
        }
        .padding(.bottom, TravSpacing.lg)
    }

    @ViewBuilder
    private func routeOverview(_ experience: Experience) -> some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            Text("Route")
                .font(TravTypography.titleLarge())
                .foregroundStyle(TravColors.primary)

            Text(experience.description)
                .font(TravTypography.bodyMedium())
                .foregroundStyle(TravColors.muted)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

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
