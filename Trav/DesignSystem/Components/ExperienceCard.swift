import SwiftUI
import MapKit

/// Full-width experience card used across feeds.
/// Renders user-created experiences with the frosted glassmorphic card design & circular rating progress bar,
/// and non-user (system/editorial) experiences with the standard card design.
struct ExperienceCard: View {
    let experience: ExperienceSummary
    var badgeText: String = ""
    var isSaved: Bool = false
    var isLiked: Bool = false
    var connectedLayout: Bool = false
    var onTap: () -> Void
    var onCreatorTap: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    var onLike: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    var onComment: (() -> Void)? = nil

    var body: some View {
        if isUserCard {
            HeroExperienceCard(
                experience: experience,
                badgeText: badgeText,
                isSaved: isSaved,
                isLiked: isLiked,
                connectedLayout: connectedLayout,
                onTap: onTap,
                onCreatorTap: onCreatorTap,
                onSave: onSave,
                onLike: onLike,
                onShare: onShare,
                onComment: onComment
            )
        } else {
            GemPostCardView(
                experience: experience,
                badgeText: badgeText,
                isSaved: isSaved,
                isLiked: isLiked,
                connectedLayout: connectedLayout,
                onTap: onTap,
                onCreatorTap: onCreatorTap,
                onSave: onSave,
                onLike: onLike,
                onShare: onShare,
                onComment: onComment
            )
        }
    }

    private var isUserCard: Bool {
        if experience.creator.displayName.lowercased() == "rec by trav" { return true }
        if badgeText == "Created by You" || badgeText == "Created by Me" { return true }
        let systemNames = ["system", "trav editorial", "editorial", "trav"]
        return !systemNames.contains(experience.creator.displayName.lowercased())
    }
}

/// Frosted card design with a split action bar (private save + public watchlist) and facepile row.
struct GemPostCardView: View {
    let experience: ExperienceSummary
    var badgeText: String = ""
    var isSaved: Bool = false
    var isLiked: Bool = false
    var connectedLayout: Bool = false
    var onTap: () -> Void
    var onCreatorTap: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    var onLike: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    var onComment: (() -> Void)? = nil

    @Environment(AppEnvironment.self) private var environment
    @Environment(EngagementStore.self) private var engagement

    @State private var isSavedLocal: Bool
    @State private var isLikedLocal: Bool
    @State private var showEyesRain = false

    private var isWatchlisted: Bool {
        engagement.isCompleted(experience.id)
    }

    private var watchlistedToDisplay: [WatchlistUser] {
        var toDisplay: [WatchlistUser] = []
        if isWatchlisted, let currentUser = environment.session.currentUser {
            toDisplay.append(WatchlistUser(
                id: currentUser.id,
                name: currentUser.displayName,
                avatarImage: currentUser.avatarURL?.absoluteString ?? ""
            ))
        }
        let followers = experience.watchlistedBy.filter { user in
            engagement.followingUserIDs.contains(user.id) && user.id != environment.session.currentUser?.id
        }
        toDisplay.append(contentsOf: followers.prefix(3 - toDisplay.count))
        return toDisplay
    }

    init(
        experience: ExperienceSummary,
        badgeText: String = "",
        isSaved: Bool = false,
        isLiked: Bool = false,
        connectedLayout: Bool = false,
        onTap: @escaping () -> Void,
        onCreatorTap: (() -> Void)? = nil,
        onSave: (() -> Void)? = nil,
        onLike: (() -> Void)? = nil,
        onShare: (() -> Void)? = nil,
        onComment: (() -> Void)? = nil
    ) {
        self.experience = experience
        self.badgeText = badgeText
        self.connectedLayout = connectedLayout
        self.onTap = onTap
        self.onCreatorTap = onCreatorTap
        self.onSave = onSave
        self.onLike = onLike
        self.onShare = onShare
        self.onComment = onComment

        _isSavedLocal = State(initialValue: isSaved)
        _isLikedLocal = State(initialValue: isLiked)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                if let coverURL = experience.coverImageURL {
                    RemoteImage(
                        url: coverURL,
                        height: TravLayout.feedCardImageHeight,
                        cornerRadius: 0
                    )
                } else {
                    ExperienceStopsMapView(experience: experience)
                        .frame(height: TravLayout.feedCardImageHeight)
                }

                LinearGradient(
                    colors: [.black.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .center
                )

                HStack(spacing: TravSpacing.xs) {
                    if !badgeText.isEmpty {
                        Text(badgeText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                    }

                    // Rating pill — only shown when the experience has a real rating.
                    if let rating = experience.rating, rating.overallScore > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.0))

                            Text(String(format: "%.1f", rating.overallScore))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .accessibilityLabel("Rated \(String(format: "%.1f", rating.overallScore)) out of 10")
                    }

                    Spacer()
                }
                .padding(TravSpacing.sm)

                repostBubble
            }
            .frame(height: TravLayout.feedCardImageHeight)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: TravSpacing.xs) {
                Text(experience.title)
                    .font(TravTypography.titleMedium())
                    .foregroundStyle(TravColors.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    onCreatorTap?()
                } label: {
                    Text("by \(experience.creator.displayName)")
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(onCreatorTap == nil)

                Text("\(TravFormatters.duration(experience.durationMinutes)) · \(experience.costLabel)")
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
                    .lineLimit(1)

                Text("\(TravFormatters.count(experience.completionCount)) completed · \(TravFormatters.count(displaySaveCount)) saved")
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                RoutePreview(stops: experience.stops, maxVisibleStops: 3, compact: true)
                    .padding(.top, TravSpacing.xxs)

                // Facepile (Social Proof) Row
                if !experience.watchlistedBy.isEmpty {
                    HStack(spacing: 0) {
                        HStack(spacing: -8) {
                            ForEach(experience.watchlistedBy.prefix(3)) { user in
                                AsyncImage(url: URL(string: user.avatarImage)) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Image(systemName: "person.crop.circle.fill")
                                        .foregroundStyle(TravColors.muted)
                                }
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            }
                        }
                        .padding(.trailing, 6)

                        Group {
                            if experience.watchlistedBy.count == 1 {
                                Text("Added to watchlist by ") +
                                Text(experience.watchlistedBy[0].name)
                                    .fontWeight(.bold)
                            } else {
                                Text("Added to watchlist by ") +
                                Text(experience.watchlistedBy[0].name)
                                    .fontWeight(.bold) +
                                Text(" and ") +
                                Text("\(experience.watchlistedBy.count - 1) others")
                                    .fontWeight(.bold)
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(Color.gray)
                    }
                    .padding(.vertical, 6)
                }

                // Split Action Bar
                Divider()
                    .background(TravColors.border.opacity(0.3))
                    .padding(.vertical, 8)

                HStack {
                    // Left Group: Save, Comment, Share
                    HStack(spacing: 16) {

                        Button {
                            isSavedLocal.toggle()
                            onSave?()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: isSavedLocal ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 18))
                                .foregroundStyle(isSavedLocal ? Color.yellow : TravColors.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isSavedLocal ? "Remove bookmark" : "Bookmark")

                        Button {
                            (onComment ?? onTap)()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: "bubble.right")
                                .font(.system(size: 18))
                                .foregroundStyle(TravColors.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Comments")

                        Button {
                            onShare?()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18))
                                .foregroundStyle(TravColors.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Share")
                    }

                    Spacer()

                    // Right Group: Watchlist Pill Button
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if environment.session.currentUser == nil {
                            environment.router.presentAuth()
                        } else {
                            let expID = experience.id
                            let summary = experience
                            if !isWatchlisted {
                                withAnimation { showEyesRain = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                                    showEyesRain = false
                                }
                            }
                            Task {
                                _ = await engagement.toggleComplete(
                                    experienceID: expID,
                                    summary: summary,
                                    using: environment
                                )
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isWatchlisted ? "checkmark.circle.fill" : "plus.circle.fill")
                            Text(isWatchlisted ? "In Watchlist" : "Watchlist")
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(isWatchlisted ? Color.gray.opacity(0.4) : TravColors.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(connectedLayout ? 20 : TravSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: connectedLayout ? 0 : TravRadius.lg, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: connectedLayout ? 0 : TravRadius.lg, style: .continuous))
        .overlay(connectedLayoutOverlay)
        .overlay(eyesRainOverlay)
        .onTapGesture(perform: onTap)
    }

    private var displaySaveCount: Int {
        experience.saveCount + (isSavedLocal ? 1 : 0)
    }

    @ViewBuilder
    private var repostBubble: some View {
        if !watchlistedToDisplay.isEmpty {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    HStack(spacing: -6) {
                        ForEach(watchlistedToDisplay) { user in
                            avatarView(for: user)
                        }
                        Text("Reposted")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.leading, 2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.65)))
                    .padding(8)
                }
            }
        }
    }

    @ViewBuilder
    private func avatarView(for user: WatchlistUser) -> some View {
        if let url = URL(string: user.avatarImage), !user.avatarImage.isEmpty {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.gray)
            }
            .frame(width: 20, height: 20)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 20, height: 20)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
        }
    }

    @ViewBuilder
    private var connectedLayoutOverlay: some View {
        if connectedLayout {
            VStack {
                Spacer()
                Divider()
                    .background(TravColors.border.opacity(0.3))
            }
        }
    }

    @ViewBuilder
    private var eyesRainOverlay: some View {
        if showEyesRain {
            EmojiParticleView()
        }
    }
}

typealias StandardExperienceCard = GemPostCardView

struct EmojiParticleView: View {
    @State private var animate = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<30, id: \.self) { i in
                    let size = CGFloat.random(in: 25...50)
                    let xPos = CGFloat.random(in: 10...geo.size.width - 10)
                    let startY = -size - CGFloat.random(in: 10...120)
                    let endY = geo.size.height + size + CGFloat.random(in: 10...120)
                    
                    Text("👀")
                        .font(.system(size: size))
                        .position(x: xPos, y: animate ? endY : startY)
                        .rotationEffect(.degrees(animate ? Double.random(in: 180...720) : 0))
                        .animation(
                            .linear(duration: Double.random(in: 1.8...3.0))
                            .delay(Double.random(in: 0...0.8)),
                            value: animate
                        )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            DispatchQueue.main.async {
                animate = true
            }
        }
    }
}

/// Mini map view displayed on experience cards when no cover image media is available.
/// Displays markers and connecting polyline route for the experience stops.
struct ExperienceStopsMapView: View {
    let experience: ExperienceSummary

    @State private var position: MapCameraPosition = .automatic

    private var resolvedCoordinates: [CLLocationCoordinate2D] {
        let cityBase = getCityBaseCoordinate()
        var coords: [CLLocationCoordinate2D] = []

        for (index, stop) in experience.stops.enumerated() {
            if let lat = stop.latitude, let lon = stop.longitude, lat != 0 || lon != 0 {
                coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            } else {
                // Offset around city base coordinate to show distinct stop locations
                let latOffset = (Double(index * 7 + 4) / 1000.0) * (index % 2 == 0 ? 1 : -1)
                let lonOffset = (Double(index * 9 + 5) / 1000.0) * (index % 3 == 0 ? -1 : 1)
                coords.append(CLLocationCoordinate2D(
                    latitude: cityBase.latitude + latOffset,
                    longitude: cityBase.longitude + lonOffset
                ))
            }
        }

        if coords.isEmpty {
            coords.append(cityBase)
        }
        return coords
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Map(position: $position, interactionModes: []) {
                ForEach(Array(resolvedCoordinates.enumerated()), id: \.offset) { index, coord in
                    Annotation("", coordinate: coord) {
                        ZStack {
                            Circle()
                                .fill(TravColors.accent)
                                .frame(width: 18, height: 18)
                                .shadow(color: .black.opacity(0.35), radius: 2)

                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }

                if resolvedCoordinates.count >= 2 {
                    MapPolyline(coordinates: resolvedCoordinates)
                        .stroke(TravColors.accent, lineWidth: 2.5)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls {
                // No controls — keep card maps from requesting extra chrome / safe-area.
            }

            if resolvedCoordinates.count >= 2 {
                let routeInfo = RouteTravelCalculator.calculate(for: resolvedCoordinates)
                HStack(spacing: 4) {
                    Image(systemName: routeInfo.iconName)
                        .font(.system(size: 9, weight: .bold))
                    Text(routeInfo.timeAndModeLabel)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.7)))
                .padding(6)
            }
        }
        .onAppear {
            setupCamera()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func getCityBaseCoordinate() -> CLLocationCoordinate2D {
        if let city = MockData.cities.first(where: { $0.id == experience.cityID }) {
            return CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude)
        }
        if let cityName = experience.cityName,
           let city = MockData.cities.first(where: { $0.name.caseInsensitiveCompare(cityName) == .orderedSame }) {
            return CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude)
        }
        return CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    }

    private func setupCamera() {
        let coords = resolvedCoordinates
        guard !coords.isEmpty else { return }

        if coords.count == 1 {
            position = .region(MKCoordinateRegion(
                center: coords[0],
                span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
            ))
            return
        }

        var minLat = coords[0].latitude
        var maxLat = coords[0].latitude
        var minLon = coords[0].longitude
        var maxLon = coords[0].longitude

        for coord in coords {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latDelta = max((maxLat - minLat) * 1.5, 0.012)
        let lonDelta = max((maxLon - minLon) * 1.5, 0.012)

        position = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        ))
    }
}
