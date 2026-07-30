import MapKit
import SwiftUI
import UIKit

struct ExperienceDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(EngagementStore.self) private var engagement
    @State private var experience: Experience?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var showComments = false
    @State private var shareItem: ShareItem?
    @State private var ratings: [Rating] = []
    @State private var localCommentCount: Int?
    @State private var activeImagePreview: ImagePreviewItem?
    @State private var initialIsSaved: Bool = false
    @State private var initialIsCompleted: Bool = false

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
                experienceBackToolbar
            }
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .modifier(HiddenToolbarBackgroundVisibility())
        }
        .travShareSheet(item: $shareItem)
        .overlay {
            if showComments {
                CommentsDrawer(
                    experienceID: experienceID,
                    onCountChange: { localCommentCount = $0 },
                    onDismiss: { showComments = false }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(50)
            }
        }
        .animation(TravAnimation.quick, value: showComments)
        .fullScreenCover(item: $activeImagePreview) { item in
            FullScreenImageViewer(urls: item.urls, initialIndex: item.initialIndex) {
                activeImagePreview = nil
            }
        }
        .task {
            if let userID = environment.session.currentUser?.id {
                await engagement.refreshBootstrap(userID: userID, using: environment)
            }
            await load()
        }
    }

    @ToolbarContentBuilder
    private var experienceBackToolbar: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) {
                experienceBackButton
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) {
                experienceBackButton
            }
        }
    }

    private var experienceBackButton: some View {
        Button {
            router.dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TravColors.primary)
                .frame(width: TravLayout.minTouchTarget, height: TravLayout.minTouchTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, TravSpacing.xs)
        .accessibilityLabel("Back")
    }

    private func summary(from experience: Experience) -> ExperienceSummary {
        experience.summary
    }

    private var allExperienceImageURLs: [URL] {
        guard let experience else { return [] }
        var urls: [URL] = []
        for url in experience.imageURLs {
            if !urls.contains(url) {
                urls.append(url)
            }
        }
        for stop in experience.stops {
            for item in stop.media {
                if !urls.contains(item.url) {
                    urls.append(item.url)
                }
            }
        }
        return urls
    }

    private func displaySaveCount(for exp: Experience) -> Int {
        let isCurrentlySaved = engagement.isSaved(exp.id)
        let delta = (isCurrentlySaved ? 1 : 0) - (initialIsSaved ? 1 : 0)
        return max(0, exp.saveCount + delta)
    }

    private func displayCompletionCount(for exp: Experience) -> Int {
        let isCurrentlyCompleted = engagement.isCompleted(exp.id)
        let delta = (isCurrentlyCompleted ? 1 : 0) - (initialIsCompleted ? 1 : 0)
        return max(0, exp.completionCount + delta)
    }

    private func openImagePreview(url: URL) {
        let allURLs = allExperienceImageURLs
        let initialIndex = allURLs.firstIndex(of: url) ?? 0
        activeImagePreview = ImagePreviewItem(
            urls: allURLs.isEmpty ? [url] : allURLs,
            initialIndex: initialIndex
        )
    }

    @ViewBuilder
    private func experienceContent(_ experience: Experience) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(experience)
                    .travAppear()

                actionBar(experience)
                    .travAppear(delay: 0.06)

                descriptionSection(experience)
                    .travAppear(delay: 0.08)

                timeline(experience, title: experience.stops.count > 1 ? "TIMELINE" : "ADDRESS")
                    .travAppear(delay: 0.1)

                overviewSection(experience)
                    .travAppear(delay: 0.14)
            }
            .padding(.bottom, TravSpacing.md)
            .safeAreaPadding(.bottom, TravSpacing.xs)
        }
        .trackScrollForNavBarZoom()
        .ignoresSafeArea(edges: .top)
        .modifier(HideTopScrollEdgeBlur())
    }

    @ViewBuilder
    private func hero(_ experience: Experience) -> some View {
        let commentCount = localCommentCount ?? experience.commentCount

        HeroMediaCarousel(
            urls: experience.imageURLs,
            stops: experience.stops,
            height: TravLayout.heroExperienceHeight,
            onImageTap: { index in
                if index < experience.imageURLs.count {
                    openImagePreview(url: experience.imageURLs[index])
                }
            }
        ) {
            Text(experience.title)
                .font(TravTypography.displayMedium())
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        } accessory: {
            HStack(alignment: .center, spacing: TravSpacing.md) {
                let isSpotRec = (experience.creator.displayName.lowercased() == "rec by trav" || experience.creator.username.lowercased() == "trav" || experience.stops.count <= 1)

                if !isSpotRec {
                    Button {
                        router.openProfile(experience.creator.username)
                    } label: {
                        HStack(spacing: TravSpacing.xs) {
                            AvatarView(url: experience.creator.avatarURL, size: 32)
                            Text(experience.creator.displayName)
                                .font(TravTypography.bodyMedium())
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(TravColors.accent)
                        Text(experience.stops.first?.description.isEmpty == false ? experience.stops.first!.description : "Spot Recommendation")
                            .font(TravTypography.bodyMedium())
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    showComments = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "bubble.right.fill")
                            .font(.system(size: 15.5, weight: .semibold))
                        Text(TravFormatters.count(commentCount))
                            .font(.system(size: 13.8, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11.5)
                    .padding(.vertical, 11.5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(TravPressButtonStyle())
                .layoutPriority(1)
                .accessibilityLabel("Comments, \(commentCount)")
            }
        }
    }

    private func actionBar(_ experience: Experience) -> some View {
        let isSaved = engagement.isSaved(experience.id)
        let isCompleted = engagement.isCompleted(experience.id)
        let summary = summary(from: experience)
        let isOwn = (session.currentUser?.id == experience.creator.id && experience.stops.count > 1)

        return HStack(alignment: .top, spacing: 0) {
            Button {
                guard !isOwn else { return }
                Task {
                    await engagement.toggleSave(
                        experienceID: experience.id,
                        summary: summary,
                        using: environment
                    )
                }
            } label: {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 14, weight: .bold))
                        Text(isSaved ? "Saved" : "Save")
                            .font(TravTypography.labelMedium())
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(isSaved ? .white : TravColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 45)
                    .background(isSaved ? Color(red: 0.78, green: 0.58, blue: 0.06) : TravColors.surfaceElevated)
                    .opacity(isOwn ? 0.4 : 1.0)

                    Text(TravFormatters.count(displaySaveCount(for: experience)))
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                }
            }
            .buttonStyle(TravPressButtonStyle())
            .disabled(isOwn)

            // Completing requires a rating, so this opens Create Rating rather
            // than toggling state. Tapping it once completed edits that rating.
            Button {
                engagement.requestCompletion(for: summary, using: environment)
            } label: {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 15, weight: .bold))
                        Text(isCompleted ? "Completed" : "Complete")
                            .font(TravTypography.labelMedium())
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(isCompleted ? .white : TravColors.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 45)
                    .background(isCompleted ? TravColors.accent : TravColors.surfaceElevated)

                    Text(TravFormatters.count(displayCompletionCount(for: experience)))
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                }
            }
            .buttonStyle(TravPressButtonStyle())
            .accessibilityLabel(isCompleted ? "Edit your rating" : "Complete and rate")
            .contextMenu {
                if isCompleted {
                    // The button itself no longer toggles off, so undoing a
                    // completion means deleting the rating behind it.
                    Button("Remove Rating", systemImage: "trash", role: .destructive) {
                        Task {
                            await engagement.removeCompletion(
                                experienceID: experience.id,
                                using: environment
                            )
                            await load()
                        }
                    }
                }
            }

            Button {
                shareItem = ShareItem(
                    message: "Check out \"\(experience.title)\" on Trav",
                    url: TravLinks.experience(experience.id)
                )
            } label: {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Share")
                            .font(TravTypography.labelMedium())
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(TravColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 45)
                    .background(TravColors.surfaceElevated)

                    Text(TravFormatters.count(experience.likeCount))
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                }
            }
            .buttonStyle(TravPressButtonStyle())
        }
        .padding(.bottom, TravSpacing.md)
        .animation(TravAnimation.quick, value: isSaved)
        .animation(TravAnimation.quick, value: isCompleted)
    }

    @ViewBuilder
    private func descriptionSection(_ experience: Experience) -> some View {
        let trimmed = experience.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            VStack(alignment: .leading, spacing: TravSpacing.xs) {
                Text("DESCRIPTION")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(TravColors.accent)

                Text(trimmed)
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .padding(.top, TravSpacing.sm)
            .padding(.bottom, TravSpacing.lg)
        }
    }

    @ViewBuilder
    private func overviewSection(_ experience: Experience) -> some View {
        VStack(alignment: .leading, spacing: TravSpacing.md) {
            ExperienceRouteMapView(stops: experience.stops)

            ratingSection(experience)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.bottom, TravSpacing.sm)
    }

    /// Purple once the community has rated, grey while the creator's own score is
    /// the only one on record — a creator rating is not public validation.
    @ViewBuilder
    private func ratingSection(_ experience: Experience) -> some View {
        let summary = experience.ratingSummary
        let radar = summary.displayRadar(creatorRadar: experience.rating)
        let hasCommunity = summary.hasCommunityValidation
        let score = summary.displayScore

        if let radar, let score, score > 0 {
            VStack(alignment: .leading, spacing: TravSpacing.sm) {
                HStack(alignment: .top, spacing: TravSpacing.sm) {
                    Text(hasCommunity ? "COMMUNITY RATING" : "CREATOR RATING")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .tracking(2.0)
                        .foregroundStyle(hasCommunity ? TravColors.accent : TravColors.muted)

                    Spacer(minLength: 0)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(TravFormatters.score(score))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(hasCommunity ? TravColors.accent : TravColors.muted)

                        Text("/ 10.0")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(TravColors.muted)
                    }
                }

                Text(summary.caption)
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)

                ReadOnlyRadarChartView(rating: radar, showsHeader: false)
                    .saturation(hasCommunity ? 1 : 0)
                    .opacity(hasCommunity ? 1 : 0.85)
            }
            .padding(.top, TravSpacing.xs)

            if !ratings.isEmpty {
                reviewsSection
            }
        }
    }

    /// Written reviews attached to community ratings.
    @ViewBuilder
    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            Text("REVIEWS")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .tracking(2.0)
                .foregroundStyle(TravColors.accent)

            ForEach(ratings.filter(\.hasReview).prefix(5)) { rating in
                VStack(alignment: .leading, spacing: TravSpacing.xs) {
                    HStack(spacing: TravSpacing.xs) {
                        AvatarView(url: rating.author.avatarURL, size: 28)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(rating.author.displayName)
                                .font(TravTypography.labelMedium())
                                .foregroundStyle(TravColors.primary)
                            Text(TravFormatters.relativeTime(rating.createdAt))
                                .font(TravTypography.caption())
                                .foregroundStyle(TravColors.muted)
                        }

                        Spacer(minLength: 0)

                        Text(TravFormatters.score(rating.overallScore))
                            .font(TravTypography.labelMedium())
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, TravSpacing.xs)
                            .padding(.vertical, 3)
                            .background(TravColors.accent)
                            .clipShape(Capsule())
                    }

                    if let review = rating.review {
                        Text(review)
                            .font(TravTypography.bodyMedium())
                            .foregroundStyle(TravColors.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(TravSpacing.md)
                .background(TravColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func timeline(_ experience: Experience, title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .tracking(2.0)
                .foregroundStyle(TravColors.accent)
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.bottom, TravSpacing.md)

            ForEach(Array(experience.stops.enumerated()), id: \.element.id) { index, stop in
                StopTimelineRow(
                    stop: stop,
                    index: index + 1,
                    isLast: index == experience.stops.count - 1,
                    onImageTap: { urls, mediaIndex in
                        if mediaIndex < urls.count {
                            openImagePreview(url: urls[mediaIndex])
                        }
                    }
                )
                .travAppear(delay: Double(index) * 0.05)
            }
        }
        .padding(.bottom, TravSpacing.lg)
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            let loaded = try await environment.experiences.fetchExperience(id: experienceID)
            experience = loaded
            initialIsSaved = engagement.isSaved(loaded.id)
            initialIsCompleted = engagement.isCompleted(loaded.id)
        } catch {
            self.error = error
        }
        isLoading = false

        // Reviews are secondary content: a failure here must not break the page.
        ratings = (try? await environment.ratings.fetchRatings(experienceID: experienceID, page: 0))?.items ?? []
    }
}

private struct StopTimelineRow: View {
    let stop: Stop
    let index: Int
    let isLast: Bool
    var onImageTap: (([URL], Int) -> Void)? = nil

    private let circleSize: CGFloat = 28

    var body: some View {
        HStack(alignment: .top, spacing: TravSpacing.md) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(TravColors.accent)
                        .frame(width: circleSize, height: circleSize)
                        .shadow(color: TravColors.accent.opacity(0.3), radius: 4, y: 2)

                    Text("\(index)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }

                if !isLast {
                    Rectangle()
                        .fill(TravColors.accent)
                        .frame(width: 2.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: circleSize)

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

                if !stop.media.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: TravSpacing.xs) {
                            ForEach(Array(stop.media.enumerated()), id: \.element.id) { mediaIndex, mediaItem in
                                Button {
                                    onImageTap?(stop.media.map(\.url), mediaIndex)
                                } label: {
                                    RemoteImage(url: mediaItem.url, height: 90, cornerRadius: TravRadius.sm)
                                        .frame(width: 120, height: 90)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, TravSpacing.xxs)
                }

                if let time = stop.recommendedTime {
                    Label(time, systemImage: "sun.max")
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                        .lineLimit(1)
                }
            }
            .padding(.bottom, isLast ? 0 : TravSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
    }
}

private struct HiddenToolbarBackgroundVisibility: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        } else {
            content
        }
    }
}

private struct HideTopScrollEdgeBlur: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}

private struct HeroMediaCarousel<Title: View, Accessory: View>: View {
    let urls: [URL]
    var stops: [Stop] = []
    let height: CGFloat
    var onImageTap: ((Int) -> Void)? = nil
    @ViewBuilder let title: () -> Title
    @ViewBuilder let accessory: () -> Accessory

    @State private var currentIndex = 0
    @State private var dragOffset: CGFloat = 0
    /// True when the top of the current hero image is light — use dark dots for contrast.
    @State private var useDarkDots = false

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)

            ZStack(alignment: .bottomLeading) {
                if !urls.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(Array(displayURLs.enumerated()), id: \.offset) { index, url in
                            RemoteImage(url: url, height: height, cornerRadius: 0)
                                .frame(width: width, height: height)
                                .clipped()
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onImageTap?(index)
                                }
                        }
                    }
                    .offset(x: -CGFloat(currentIndex) * width + dragOffset)
                    .frame(width: width, height: height, alignment: .leading)
                    .clipped()
                } else {
                    ExperienceRouteMapView(stops: stops)
                        .frame(width: width, height: height)
                        .clipped()
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                if displayURLs.count > 1 {
                    let active = useDarkDots ? Color.black : Color.white
                    let inactive = useDarkDots ? Color.black.opacity(0.45) : Color.white.opacity(0.55)
                    HStack(spacing: TravSpacing.xs) {
                        ForEach(0..<displayURLs.count, id: \.self) { index in
                            Capsule()
                                .fill(index == currentIndex ? active : inactive)
                                .frame(width: index == currentIndex ? 16 : 6, height: 6)
                        }
                    }
                    // Keep indicators crisp — avoid soft shadows / being sampled into scroll-edge blur.
                    .compositingGroup()
                    .padding(.top, TravSpacing.xxl + TravSpacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                    .zIndex(20)
                }

                // Drag/tap layer above non-interactive chrome; accessory button stays on top.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onImageTap?(currentIndex)
                    }
                    .gesture(horizontalPageGesture(pageWidth: width))
                    .allowsHitTesting(onImageTap != nil || displayURLs.count > 1)

                VStack(alignment: .leading, spacing: TravSpacing.sm) {
                    title()
                        .allowsHitTesting(false)
                    accessory()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.bottom, TravSpacing.md)
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .animation(TravAnimation.quick, value: currentIndex)
        .task(id: currentIndex) {
            await updateDotContrast()
        }
    }

    private var displayURLs: [URL?] {
        if urls.isEmpty { return [nil] }
        return urls.map { Optional($0) }
    }

    private func updateDotContrast() async {
        guard currentIndex < urls.count else {
            useDarkDots = false
            return
        }
        let url = urls[currentIndex]
        guard let image = await ImageCache.shared.image(for: url, maxPixelSize: 400) else {
            useDarkDots = false
            return
        }
        // Sample the top band where page dots sit.
        let luminance = image.travAverageLuminance(in: CGRect(x: 0.25, y: 0.05, width: 0.5, height: 0.12))
        useDarkDots = luminance > 0.58
    }

    private func horizontalPageGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard displayURLs.count > 1 else { return }
                let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.15
                guard horizontal else {
                    dragOffset = 0
                    return
                }
                var translation = value.translation.width
                if (currentIndex == 0 && translation > 0)
                    || (currentIndex == displayURLs.count - 1 && translation < 0) {
                    translation *= 0.35
                }
                dragOffset = translation
            }
            .onEnded { value in
                guard displayURLs.count > 1 else {
                    dragOffset = 0
                    return
                }
                let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.15
                let threshold = pageWidth * 0.2
                var next = currentIndex
                if horizontal {
                    if value.translation.width < -threshold {
                        next = min(currentIndex + 1, displayURLs.count - 1)
                    } else if value.translation.width > threshold {
                        next = max(currentIndex - 1, 0)
                    }
                }
                withAnimation(TravAnimation.quick) {
                    currentIndex = next
                    dragOffset = 0
                }
            }
    }
}

private extension UIImage {
    /// Average perceived luminance (0...1) inside a normalized rect of the image.
    func travAverageLuminance(in normalizedRect: CGRect) -> CGFloat {
        guard let cgImage else { return 0.3 }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return 0.3 }

        let sampleWidth = max(1, Int(CGFloat(width) * normalizedRect.width))
        let sampleHeight = max(1, Int(CGFloat(height) * normalizedRect.height))
        let originX = max(0, Int(CGFloat(width) * normalizedRect.minX))
        let originY = max(0, Int(CGFloat(height) * normalizedRect.minY))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var data = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        guard let context = CGContext(
            data: &data,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: sampleWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0.3 }

        context.interpolationQuality = .low
        context.draw(
            cgImage,
            in: CGRect(
                x: -originX,
                y: -originY,
                width: width,
                height: height
            )
        )

        var total: CGFloat = 0
        let pixelCount = sampleWidth * sampleHeight
        guard pixelCount > 0 else { return 0.3 }
        for i in 0..<pixelCount {
            let o = i * 4
            let r = CGFloat(data[o]) / 255
            let g = CGFloat(data[o + 1]) / 255
            let b = CGFloat(data[o + 2]) / 255
            total += (0.299 * r) + (0.587 * g) + (0.114 * b)
        }
        return total / CGFloat(pixelCount)
    }
}

// MARK: - Apple Maps Route Path Visualizer

private struct ExperienceRouteMapView: View {
    let stops: [Stop]

    @State private var position: MapCameraPosition = .automatic
    @State private var routePolylines: [MKPolyline] = []
    @State private var mapKitTravelLabel: String? = nil
    @State private var showInteractiveMap = false

    private var resolvedStops: [Stop] {
        stops.enumerated().map { index, stop in
            var updated = stop
            if updated.latitude == 0 && updated.longitude == 0 {
                updated.latitude = 37.7749 + Double(index) * 0.006 - 0.003
                updated.longitude = -122.4194 + Double(index) * 0.008 - 0.004
            }
            return updated
        }
    }

    private var coordinates: [CLLocationCoordinate2D] {
        resolvedStops.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var routeInfo: RouteTravelInfo {
        RouteTravelCalculator.calculate(for: coordinates)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TravSpacing.md) {
            HStack(alignment: .center) {
                Text("MAP")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(TravColors.accent)

                Spacer()

                if !coordinates.isEmpty {
                    Button(action: openInAppleMaps) {
                        HStack(spacing: 5) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Open Maps")
                                .font(TravTypography.labelMedium())
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(TravColors.accent)
                        .padding(.horizontal, TravSpacing.md)
                        .padding(.vertical, TravSpacing.xs)
                        .background(TravColors.accentSoft)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(TravPressButtonStyle())
                }
            }

            if coordinates.isEmpty {
                ContentUnavailableView(
                    "No Location Coordinates",
                    systemImage: "location.slash",
                    description: Text("Location details are not available for this route.")
                )
                .frame(height: 180)
            } else {
                ZStack(alignment: .bottomLeading) {
                    Map(position: $position, interactionModes: []) {
                        if !routePolylines.isEmpty {
                            ForEach(Array(routePolylines.enumerated()), id: \.offset) { _, polyline in
                                MapPolyline(polyline)
                                    .stroke(
                                        TravColors.accent,
                                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                                    )
                            }
                        } else if coordinates.count > 1 {
                            MapPolyline(coordinates: coordinates)
                                .stroke(
                                    LinearGradient(
                                        colors: [TravColors.accent, TravColors.accent.opacity(0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                                )
                        }

                        ForEach(Array(resolvedStops.enumerated()), id: \.element.id) { index, stop in
                            Annotation(
                                stop.name,
                                coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude),
                                anchor: .bottom
                            ) {
                                MapStopAnnotationView(index: index + 1, name: stop.name)
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                            .stroke(TravColors.border.opacity(0.5), lineWidth: 1)
                    )

                    HStack(spacing: TravSpacing.xs) {
                        Label("\(resolvedStops.count) Stop\(resolvedStops.count == 1 ? "" : "s")", systemImage: "flag.fill")
                        if resolvedStops.count >= 2 {
                            Text("·")
                            Label(
                                mapKitTravelLabel ?? routeInfo.timeAndModeLabel,
                                systemImage: routeInfo.iconName
                            )
                        }
                    }
                    .font(TravTypography.caption())
                    .foregroundStyle(.white)
                    .padding(.horizontal, TravSpacing.md)
                    .padding(.vertical, TravSpacing.xs)
                    .background(.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(TravSpacing.md)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showInteractiveMap = true
                }
            }
        }
        .padding(.vertical, TravSpacing.sm)
        .sheet(isPresented: $showInteractiveMap) {
            InAppInteractiveMapView(title: "Map", stops: resolvedStops)
        }
        .task(id: resolvedStops) {
            updateCameraPosition()
            await fetchRoutes()
        }
    }

    private func fetchRoutes() async {
        guard resolvedStops.count >= 2 else {
            await MainActor.run {
                self.routePolylines = []
                self.mapKitTravelLabel = nil
            }
            return
        }
        var polylines: [MKPolyline] = []
        var walkingSeconds: TimeInterval = 0
        var drivingSeconds: TimeInterval = 0

        for i in 0..<(resolvedStops.count - 1) {
            let start = CLLocationCoordinate2D(latitude: resolvedStops[i].latitude, longitude: resolvedStops[i].longitude)
            let destination = CLLocationCoordinate2D(latitude: resolvedStops[i + 1].latitude, longitude: resolvedStops[i + 1].longitude)
            let distance = RouteTravelCalculator.segmentDistanceMeters(from: start, to: destination)
            let isDriving = RouteTravelCalculator.isDrivingSegment(distanceMeters: distance)

            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
            request.transportType = isDriving ? .automobile : .walking

            let directions = MKDirections(request: request)
            if let response = try? await directions.calculate(), let route = response.routes.first {
                polylines.append(route.polyline)
                if isDriving {
                    drivingSeconds += route.expectedTravelTime
                } else {
                    walkingSeconds += route.expectedTravelTime
                }
            }
        }

        let walkingMins = Int(round(walkingSeconds / 60.0))
        let drivingMins = Int(round(drivingSeconds / 60.0))
        let label: String? = {
            switch (walkingMins > 0, drivingMins > 0) {
            case (true, true):
                return "\(RouteTravelInfo.formatMinutes(walkingMins)) walk · \(RouteTravelInfo.formatMinutes(drivingMins)) drive"
            case (false, true):
                return "\(RouteTravelInfo.formatMinutes(drivingMins)) drive"
            case (true, false):
                return "\(RouteTravelInfo.formatMinutes(walkingMins)) walk"
            default:
                return nil
            }
        }()

        let result = polylines
        await MainActor.run {
            self.routePolylines = result
            self.mapKitTravelLabel = label
        }
    }

    private func updateCameraPosition() {
        guard !coordinates.isEmpty else { return }
        if coordinates.count == 1 {
            position = .region(MKCoordinateRegion(
                center: coordinates[0],
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            ))
            return
        }

        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latDelta = max((maxLat - minLat) * 1.5, 0.01)
        let lonDelta = max((maxLon - minLon) * 1.5, 0.01)

        position = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        ))
    }

    private func openInAppleMaps() {
        guard !resolvedStops.isEmpty else { return }

        let mapItems = resolvedStops.map { stop in
            let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude))
            let item = MKMapItem(placemark: placemark)
            item.name = stop.name
            return item
        }

        let modeKey: String = {
            if routeInfo.hasDriving && !routeInfo.hasWalking {
                return MKLaunchOptionsDirectionsModeDriving
            }
            if routeInfo.hasDriving {
                // Mixed routes: prefer driving so longer hops still navigate correctly.
                return MKLaunchOptionsDirectionsModeDriving
            }
            return MKLaunchOptionsDirectionsModeWalking
        }()

        MKMapItem.openMaps(with: mapItems, launchOptions: [
            MKLaunchOptionsDirectionsModeKey: modeKey
        ])
    }
}

private struct MapStopAnnotationView: View {
    let index: Int
    let name: String

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text("\(index)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(TravColors.accent)
                    .clipShape(Circle())

                Text(name)
                    .font(TravTypography.caption())
                    .fontWeight(.bold)
                    .foregroundStyle(TravColors.primary)
                    .lineLimit(1)
            }
            .padding(.trailing, 8)
            .padding(.leading, 3)
            .padding(.vertical, 3)
            .background(TravColors.surfaceElevated)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(TravColors.accent, lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)

            Image(systemName: "triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(TravColors.accent)
                .rotationEffect(.degrees(180))
                .offset(y: -3)
        }
    }
}
