import SwiftUI

struct ExperienceDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(EngagementStore.self) private var engagement
    @State private var experience: Experience?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var showEyesRain = false
    @State private var showComments = false
    @State private var showCompletionSheet = false
    @State private var shareItem: ShareItem?
    @State private var showReportDialog = false
    @State private var localCommentCount: Int?

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
                if let experience {
                    ToolbarItem(placement: .topBarTrailing) {
                        moderationMenu(experience)
                    }
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
        .travShareSheet(item: $shareItem)
        .sheet(isPresented: $showComments) {
            CommentsSheet(experienceID: experienceID) { count in
                localCommentCount = count
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(TravRadius.xl)
        }
        .sheet(isPresented: $showCompletionSheet) {
            if let experience {
                CompletionSheet(experience: summary(from: experience)) { completed in
                    if completed {
                        withAnimation { showEyesRain = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                            showEyesRain = false
                        }
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(TravRadius.xl)
            }
        }
        .confirmationDialog("Report Experience", isPresented: $showReportDialog, titleVisibility: .visible) {
            ForEach(ReportReason.allCases) { reason in
                Button(reason.displayName, role: reason == .other ? nil : .destructive) {
                    Task { await report(reason: reason) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            if let userID = environment.session.currentUser?.id {
                await engagement.refreshBootstrap(userID: userID, using: environment)
            }
            await load()
        }
    }

    private func summary(from experience: Experience) -> ExperienceSummary {
        ExperienceSummary(
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
    }

    private func moderationMenu(_ experience: Experience) -> some View {
        Menu {
            Button {
                shareItem = ShareItem(
                    message: "Check out \"\(experience.title)\" on Trav",
                    url: TravLinks.experience(experience.id)
                )
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            if session.currentUser?.id != experience.creator.id {
                Button(role: .destructive) {
                    showReportDialog = true
                } label: {
                    Label("Report", systemImage: "flag")
                }

                Button(role: .destructive) {
                    Task {
                        let blocked = await engagement.block(userID: experience.creator.id, using: environment)
                        if blocked { router.dismiss() }
                    }
                } label: {
                    Label("Block @\(experience.creator.username)", systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.9), .black.opacity(0.35))
        }
        .accessibilityLabel("More options")
    }

    private func report(reason: ReportReason) async {
        guard let user = session.currentUser else {
            router.presentAuth()
            return
        }
        try? await environment.engagementRepo.report(
            target: .experience(experienceID),
            reporterID: user.id,
            reason: reason,
            details: nil
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
        let isLiked = engagement.isLiked(experience.id)
        let summary = summary(from: experience)
        let likeCount = experience.likeCount + (isLiked ? 1 : 0)
        let commentCount = localCommentCount ?? experience.commentCount

        return VStack(spacing: TravSpacing.sm) {
            // Social row: like + comment with live counts.
            HStack(spacing: TravSpacing.lg) {
                Button {
                    Task {
                        await engagement.toggleLike(
                            experienceID: experience.id,
                            summary: summary,
                            using: environment
                        )
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(isLiked ? Color.red : TravColors.primary)
                        Text(TravFormatters.count(likeCount))
                            .font(TravTypography.labelMedium())
                            .foregroundStyle(TravColors.primary)
                    }
                }
                .buttonStyle(TravPressButtonStyle())
                .accessibilityLabel(isLiked ? "Unlike, \(likeCount) likes" : "Like, \(likeCount) likes")

                Button {
                    showComments = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 17, weight: .semibold))
                        Text(TravFormatters.count(commentCount))
                            .font(TravTypography.labelMedium())
                    }
                    .foregroundStyle(TravColors.primary)
                }
                .buttonStyle(TravPressButtonStyle())
                .accessibilityLabel("Comments, \(commentCount)")

                Spacer()

                Text("\(TravFormatters.count(experience.completionCount)) completed · \(TravFormatters.count(experience.saveCount)) saved")
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
            }

            HStack(spacing: TravSpacing.sm) {
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
                    if isCompleted {
                        // Un-completing is a quick toggle; completing opens the moment sheet.
                        Task {
                            await engagement.toggleComplete(experienceID: experience.id, summary: summary, using: environment)
                        }
                    } else if session.currentUser == nil {
                        router.presentAuth()
                    } else {
                        showCompletionSheet = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCompleted ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text(isCompleted ? "Completed" : "Mark Done")
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
                    shareItem = ShareItem(
                        message: "Check out \"\(experience.title)\" on Trav",
                        url: TravLinks.experience(experience.id)
                    )
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
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.vertical, TravSpacing.md)
        .animation(TravAnimation.quick, value: isSaved)
        .animation(TravAnimation.quick, value: isCompleted)
        .animation(TravAnimation.quick, value: isLiked)
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

            // Only render the radar when the creator actually rated the experience.
            if let rating = experience.rating, rating.overallScore > 0 {
                VStack(alignment: .leading, spacing: TravSpacing.xs) {
                    Text("Experience Rating")
                        .font(TravTypography.titleMedium())
                        .foregroundStyle(TravColors.primary)
                    ReadOnlyRadarChartView(rating: rating)
                }
                .padding(.top, TravSpacing.xs)
            }
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
