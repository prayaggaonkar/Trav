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
                    ProgressView()
                } else if let experience {
                    experienceContent(experience)
                } else if let error {
                    VStack(spacing: TravSpacing.md) {
                        Text(error.localizedDescription)
                        PrimaryButton(title: "Try Again") {
                            Task { await load() }
                        }
                    }
                    .padding()
                }
            }
            .background(TravColors.surface)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    closeButton
                }
            }
        }
        .task { await load() }
    }

    private var closeButton: some View {
        Button { router.dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .padding(10)
                .background(TravColors.surfaceElevated)
                .clipShape(Circle())
        }
    }

    @ViewBuilder
    private func experienceContent(_ experience: Experience) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(experience)
                actionBar(experience)
                statsRow(experience)
                routeOverview(experience)
                timeline(experience)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private func hero(_ experience: Experience) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: experience.coverImageURL) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(TravColors.surfaceElevated)
                }
            }
            .frame(height: 420)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: TravSpacing.sm) {
                Text(experience.title)
                    .font(TravTypography.displayMedium())
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    AvatarView(url: experience.creator.avatarURL, size: 32)
                    Text(experience.creator.displayName)
                        .font(TravTypography.bodyMedium())
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(TravSpacing.screenHorizontal)
            .padding(.bottom, TravSpacing.lg)
        }
    }

    @ViewBuilder
    private func actionBar(_ experience: Experience) -> some View {
        HStack(spacing: TravSpacing.md) {
            actionButton(symbol: "bookmark", label: "Save")
            actionButton(symbol: "checkmark.circle.fill", label: "Complete", accent: true)
            actionButton(symbol: "square.and.arrow.up", label: "Share")
        }
        .padding(TravSpacing.screenHorizontal)
        .padding(.vertical, TravSpacing.md)
    }

    @ViewBuilder
    private func actionButton(symbol: String, label: String, accent: Bool = false) -> some View {
        Button {} label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                Text(label)
                    .font(TravTypography.caption())
            }
            .foregroundStyle(accent ? TravColors.accent : TravColors.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, TravSpacing.sm)
            .background(accent ? TravColors.accentSoft : TravColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statsRow(_ experience: Experience) -> some View {
        HStack(spacing: TravSpacing.sm) {
            StatPill(symbol: "clock", value: formatDuration(experience.durationMinutes))
            StatPill(symbol: "dollarsign.circle", value: experience.costLevel.displayName)
            StatPill(symbol: "figure.walk", value: formatDistance(experience.totalDistanceMeters))
            StatPill(symbol: "checkmark.circle", value: "\(experience.completionCount)")
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
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

            RoutePreview(stops: experience.stops.map {
                StopPreview(id: $0.id, name: $0.name, emoji: $0.emoji)
            })
        }
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
            }
        }
        .padding(.bottom, TravSpacing.xxl)
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

    private func formatDuration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private func formatDistance(_ meters: Int) -> String {
        meters >= 1000 ? String(format: "%.1f km", Double(meters) / 1000) : "\(meters) m"
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
                .frame(width: 28, height: 28)
                .background(TravColors.accent)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let emoji = stop.emoji { Text(emoji) }
                    Text(stop.name)
                        .font(TravTypography.titleMedium())
                        .foregroundStyle(TravColors.primary)
                }

                Text(stop.description)
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.muted)

                if let notes = stop.creatorNotes {
                    Text(notes)
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.accent)
                        .padding(TravSpacing.sm)
                        .background(TravColors.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.sm, style: .continuous))
                }

                HStack {
                    if let time = stop.recommendedTime {
                        Label(time, systemImage: "sun.max")
                    }
                    Label("\(stop.durationMinutes)m", systemImage: "clock")
                }
                .font(TravTypography.caption())
                .foregroundStyle(TravColors.muted)
            }
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
    }
}
