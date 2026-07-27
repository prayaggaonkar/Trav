import MapKit
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
        let summary = summary(from: experience)
        let commentCount = localCommentCount ?? experience.commentCount

        return VStack(spacing: TravSpacing.sm) {
            // Social row: comment button with live count.
            HStack(spacing: TravSpacing.lg) {
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

                Text("\(TravFormatters.count(experience.completionCount)) watchlisted · \(TravFormatters.count(experience.saveCount)) saved")
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
                    if session.currentUser == nil {
                        router.presentAuth()
                    } else {
                        if !isCompleted {
                            withAnimation { showEyesRain = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                                showEyesRain = false
                            }
                        }
                        Task {
                            await engagement.toggleComplete(experienceID: experience.id, summary: summary, using: environment)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCompleted ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text(isCompleted ? "In Watchlist" : "Watchlist")
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
    }

    @ViewBuilder
    private func overviewSection(_ experience: Experience) -> some View {
        VStack(alignment: .leading, spacing: TravSpacing.md) {
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

            ExperienceRouteMapView(stops: experience.stops, transportMode: experience.transportMode)

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
        VStack(alignment: .leading, spacing: 0) {
            Text("Timeline")
                .font(TravTypography.titleLarge())
                .foregroundStyle(TravColors.primary)
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.bottom, TravSpacing.md)

            ForEach(Array(experience.stops.enumerated()), id: \.element.id) { index, stop in
                StopTimelineRow(stop: stop, index: index + 1, isLast: index == experience.stops.count - 1)
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
    let isLast: Bool

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
            .padding(.bottom, isLast ? 0 : TravSpacing.lg)
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

// MARK: - Apple Maps Route Path Visualizer

private struct ExperienceRouteMapView: View {
    let stops: [Stop]
    let transportMode: TransportMode

    @State private var position: MapCameraPosition = .automatic
    @State private var routePolylines: [MKPolyline] = []

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

    var body: some View {
        VStack(alignment: .leading, spacing: TravSpacing.md) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ROUTE MAP")
                        .font(TravTypography.overline())
                        .tracking(2.0)
                        .foregroundStyle(TravColors.accent)

                    Text(resolvedStops.count == 1 ? "Stop Location" : "Path to Each Stop")
                        .font(TravTypography.titleLarge())
                        .foregroundStyle(TravColors.primary)
                }

                Spacer()

                if !coordinates.isEmpty {
                    Button(action: openInAppleMaps) {
                        HStack(spacing: 6) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 13, weight: .bold))
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
                    Map(position: $position) {
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
                        Text("·")
                        Label(transportMode.rawValue.capitalized, systemImage: transportMode.symbolName)
                    }
                    .font(TravTypography.caption())
                    .foregroundStyle(.white)
                    .padding(.horizontal, TravSpacing.md)
                    .padding(.vertical, TravSpacing.xs)
                    .background(.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(TravSpacing.md)
                }
            }
        }
        .padding(.vertical, TravSpacing.sm)
        .task(id: resolvedStops) {
            updateCameraPosition()
            await fetchRoutes()
        }
    }

    private func fetchRoutes() async {
        guard resolvedStops.count >= 2 else {
            await MainActor.run { self.routePolylines = [] }
            return
        }
        var polylines: [MKPolyline] = []

        for i in 0..<(resolvedStops.count - 1) {
            let start = CLLocationCoordinate2D(latitude: resolvedStops[i].latitude, longitude: resolvedStops[i].longitude)
            let destination = CLLocationCoordinate2D(latitude: resolvedStops[i+1].latitude, longitude: resolvedStops[i+1].longitude)

            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
            request.transportType = transportMode == .driving ? .automobile : (transportMode == .transit ? .transit : .walking)

            let directions = MKDirections(request: request)
            if let response = try? await directions.calculate(), let route = response.routes.first {
                polylines.append(route.polyline)
            }
        }

        let result = polylines
        await MainActor.run {
            self.routePolylines = result
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
            switch transportMode {
            case .walking: return MKLaunchOptionsDirectionsModeWalking
            case .transit: return MKLaunchOptionsDirectionsModeTransit
            case .driving, .mixed: return MKLaunchOptionsDirectionsModeDriving
            }
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
