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

/// Frosted card design with a split action bar (private save + public complete) and facepile row.
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

    private var isOwn: Bool {
        if let currentUserID = environment.session.currentUser?.id {
            return currentUserID == experience.creator.id
        }
        return badgeText == "Created by You" || badgeText == "Created by Me"
    }

    private var isCompleted: Bool {
        isOwn || engagement.isCompleted(experience.id)
    }

    private var completedByToDisplay: [CompletionUser] {
        var toDisplay: [CompletionUser] = []
        let creatorID = experience.creator.id
        for user in experience.completedBy {
            if user.id != creatorID && (engagement.isFollowing(user.id) || user.id == environment.session.currentUser?.id) && !toDisplay.contains(where: { $0.id == user.id }) {
                toDisplay.append(user)
            }
        }
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
            ZStack(alignment: .topLeading) {
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
                    colors: [.black.opacity(0.45), .clear],
                    startPoint: .top,
                    endPoint: .center
                )

                HStack(alignment: .center, spacing: TravSpacing.xs) {
                    let completers = !experience.completedBy.isEmpty ? experience.completedBy : completedByToDisplay
                    if !completers.isEmpty {
                        HStack(spacing: 6) {
                            HStack(spacing: -8) {
                                ForEach(completers.prefix(3)) { user in
                                    if let url = URL(string: user.avatarImage), !user.avatarImage.isEmpty {
                                        AsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } placeholder: {
                                            Image(systemName: "person.crop.circle.fill")
                                                .resizable()
                                                .foregroundStyle(.white.opacity(0.85))
                                        }
                                        .frame(width: 22, height: 22)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                    } else {
                                        Image(systemName: "person.crop.circle.fill")
                                            .resizable()
                                            .foregroundStyle(.white.opacity(0.85))
                                            .frame(width: 22, height: 22)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                    }
                                }
                            }

                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color(red: 0.2, green: 0.85, blue: 0.45))

                                Group {
                                    if completers.count == 1 {
                                        Text(experience.isSpot ? "Visited by \(completers[0].name)" : "Completed by \(completers[0].name)")
                                    } else {
                                        Text(experience.isSpot ? "Your friends completed this spot" : "Your friends completed this")
                                    }
                                }
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .overlay(Capsule().stroke(Color(red: 0.2, green: 0.85, blue: 0.45).opacity(0.8), lineWidth: 1.2))
                    } else if !badgeText.isEmpty {
                        Text(badgeText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                    }

                    Spacer()

                    let resolvedScore = experience.ratingSummary.displayScore ?? experience.rating?.overallScore
                    if let score = resolvedScore, score > 0 {
                        let hasCommunity = experience.ratingSummary.hasCommunityValidation || experience.ratingSummary.communityRatingCount > 0
                        HStack(spacing: 3) {
                            Image(systemName: hasCommunity ? "hexagon.fill" : "hexagon")
                                .font(.system(size: 10, weight: .bold))
                            Text(TravFormatters.score(score))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(
                                hasCommunity
                                    ? AnyShapeStyle(TravColors.accent.opacity(0.92))
                                    : AnyShapeStyle(Color.black.opacity(0.65))
                            )
                        )
                    }
                }
                .frame(maxWidth: .infinity)
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

                Text("\(TravFormatters.duration(experience.durationMinutes)) · \(experience.costLabel)")
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
                    .lineLimit(1)

                Text("\(TravFormatters.count(displayCompletionCount)) completed · \(TravFormatters.count(displaySaveCount)) saved")
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                RoutePreview(stops: experience.stops, maxVisibleStops: 3, compact: true)
                    .padding(.top, TravSpacing.xxs)

                // Facepile (Social Proof) Row
                let facepileUsers = completedByToDisplay
                if !facepileUsers.isEmpty {
                    HStack(spacing: 6) {
                        HStack(spacing: -8) {
                            ForEach(facepileUsers.prefix(3)) { user in
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

                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(red: 0.2, green: 0.85, blue: 0.45))

                            Group {
                                let isSpotCard = experience.isSpot || experience.stops.count <= 1
                                if facepileUsers.count == 1 {
                                    Text(isSpotCard ? "Visited by " : "Completed by ") +
                                    Text(facepileUsers[0].name)
                                        .fontWeight(.bold)
                                } else {
                                    Text(isSpotCard ? "Visited by " : "Completed by ") +
                                    Text(facepileUsers[0].name)
                                        .fontWeight(.bold) +
                                    Text(" and ") +
                                    Text("\(facepileUsers.count - 1) others")
                                        .fontWeight(.bold)
                                }
                            }
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(TravColors.primary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.2, green: 0.85, blue: 0.45).opacity(0.12))
                    .clipShape(Capsule())
                    .padding(.vertical, 4)
                }

                // Author line ALWAYS at the VERY BOTTOM of the text column with extra spacing
                let systemNames = ["rec by trav", "system", "trav editorial", "editorial", "trav"]
                let creatorName = experience.creator.displayName.lowercased()
                let isRecByTrav = systemNames.contains(creatorName) || experience.creator.username.lowercased() == "trav"

                Button {
                    onCreatorTap?()
                } label: {
                    HStack(spacing: 4) {
                        if isRecByTrav {
                            Text("by Trav")
                                .font(TravTypography.caption())
                                .foregroundStyle(TravColors.muted)
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(TravColors.accent)
                        } else {
                            Text("by \(experience.creator.displayName)")
                                .font(TravTypography.caption())
                                .foregroundStyle(TravColors.muted)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(onCreatorTap == nil)
                .padding(.top, 6)

                // Split Action Bar
                Divider()
                    .background(TravColors.border.opacity(0.3))
                    .padding(.vertical, 8)

                    let isOwnExperience = (environment.session.currentUser?.id == experience.creator.id)
                    let resolvedIsSaved = isSavedLocal || engagement.isSaved(experience.id)

                    HStack {
                        // Left Group: Save, Comment, Share
                        HStack(spacing: 16) {

                            Button {
                                isSavedLocal.toggle()
                                onSave?()
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Image(systemName: resolvedIsSaved ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: 18))
                                    .foregroundStyle(resolvedIsSaved ? Color.yellow : TravColors.muted)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(resolvedIsSaved ? "Remove bookmark" : "Bookmark")

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

                        // Right Group: Complete pill (hidden for own experience).
                        // Completing means rating, so this jumps to Create Rating.
                        if !isOwnExperience {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                engagement.requestCompletion(for: experience, using: environment)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "plus")
                                    Text(isCompleted ? "Completed" : "Complete")
                                }
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(isCompleted ? Color.white : TravColors.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(isCompleted ? TravColors.accent : TravColors.surfaceElevated)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(isCompleted)
                            .opacity(isCompleted ? 0.85 : 1)
                            .accessibilityLabel(isCompleted ? "Already completed" : "Complete and rate")
                        }
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
        .onTapGesture(perform: onTap)
        .onAppear {
            isSavedLocal = isSaved || engagement.isSaved(experience.id)
            let completers = !experience.completedBy.isEmpty ? experience.completedBy : completedByToDisplay
            let compNames = experience.completedBy.map(\.name).joined(separator: ", ")
            let dispNames = completers.map(\.name).joined(separator: ", ")
            let scoreStr = String(format: "%.1f", experience.ratingSummary.displayScore ?? experience.rating?.overallScore ?? -1.0)
            TravLog.general.notice("[GemPostCardView] Rendering '\(experience.title, privacy: .public)', isSpot: \(experience.isSpot, privacy: .public), completedBy: [\(compNames, privacy: .public)], completersToDisplay: [\(dispNames, privacy: .public)], score: \(scoreStr, privacy: .public)")
        }
        .onChange(of: engagement.savedExperienceIDs) { _ in
            isSavedLocal = engagement.isSaved(experience.id)
        }
    }

    private var displaySaveCount: Int {
        let base = experience.saveCount
        let currentlySaved = engagement.isSaved(experience.id)
        let delta = (currentlySaved ? 1 : 0) - (_isSavedLocal.wrappedValue ? 1 : 0)
        return max(0, base + delta)
    }

    private var displayCompletionCount: Int {
        max(0, experience.completionCount + (isCompleted ? 1 : 0))
    }

    @ViewBuilder
    private var repostBubble: some View {
        if !completedByToDisplay.isEmpty {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    HStack(spacing: -6) {
                        ForEach(completedByToDisplay) { user in
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
    private func avatarView(for user: CompletionUser) -> some View {
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
    @State private var showInteractiveMap = false

    private var resolvedCoordinates: [CLLocationCoordinate2D] {
        let cityBase = getCityBaseCoordinate()
        var coords: [CLLocationCoordinate2D] = []

        for (index, stop) in experience.stops.enumerated() {
            if let lat = stop.latitude, let lon = stop.longitude, lat != 0 || lon != 0 {
                coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            } else {
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
            .mapControls {}

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
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showInteractiveMap = true
        }
        .sheet(isPresented: $showInteractiveMap) {
            InAppInteractiveMapView(title: experience.title, stopPreviews: experience.stops)
        }
        .onAppear {
            setupCamera()
        }
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

// MARK: - In-App Interactive Map Viewer

/// Full-screen in-app interactive map viewer.
/// Allows users to pan, pinch-zoom, switch map styles, inspect nearby places (POIs),
/// tap stop markers, and cycle through stops via a bottom carousel.
struct InAppInteractiveMapView: View {
    let title: String
    let stops: [Stop]
    var initialSelectedStopID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(AppearanceStore.self) private var appearance

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedStopID: UUID?
    @State private var mapStyleOption: MapStyleOption = .standard
    @State private var routePolylines: [MKPolyline] = []
    @State private var mapKitTravelTimeMinutes: Int? = nil

    enum MapStyleOption: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case satellite = "Satellite"
        case hybrid = "Hybrid"

        var id: String { rawValue }

        var mapStyle: MapStyle {
            switch self {
            case .standard:
                return .standard(elevation: .realistic, pointsOfInterest: .all)
            case .satellite:
                return .imagery(elevation: .realistic)
            case .hybrid:
                return .hybrid(elevation: .realistic, pointsOfInterest: .all)
            }
        }
    }

    private var resolvedStops: [Stop] {
        stops.enumerated().map { index, stop in
            var updated = stop
            if updated.latitude == 0 && updated.longitude == 0 {
                let cityBase = getCityBaseCoordinate()
                let latOffset = (Double(index * 7 + 4) / 1000.0) * (index % 2 == 0 ? 1 : -1)
                let lonOffset = (Double(index * 9 + 5) / 1000.0) * (index % 3 == 0 ? -1 : 1)
                updated.latitude = cityBase.latitude + latOffset
                updated.longitude = cityBase.longitude + lonOffset
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

    init(title: String, stops: [Stop], initialSelectedStopID: UUID? = nil) {
        self.title = title
        self.stops = stops
        self.initialSelectedStopID = initialSelectedStopID
        _selectedStopID = State(initialValue: initialSelectedStopID)
    }

    init(title: String, stopPreviews: [StopPreview], initialSelectedStopID: UUID? = nil) {
        let convertedStops = stopPreviews.enumerated().map { index, preview in
            Stop(
                id: preview.id,
                orderIndex: index + 1,
                name: preview.name,
                description: "",
                creatorNotes: nil,
                latitude: preview.latitude ?? 0,
                longitude: preview.longitude ?? 0,
                placeID: nil,
                recommendedTime: nil,
                durationMinutes: 0,
                emoji: preview.emoji,
                media: []
            )
        }
        self.init(title: title, stops: convertedStops, initialSelectedStopID: initialSelectedStopID)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main Map with full interaction modes
            Map(position: $position, interactionModes: .all, selection: $selectedStopID) {
                // Polylines between stops
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

                // Annotations for each stop
                ForEach(Array(resolvedStops.enumerated()), id: \.element.id) { index, stop in
                    let isSelected = selectedStopID == stop.id
                    Annotation(
                        stop.name,
                        coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude),
                        anchor: .bottom
                    ) {
                        InteractiveStopAnnotationView(
                            index: index + 1,
                            stop: stop,
                            isSelected: isSelected
                        )
                        .onTapGesture {
                            withAnimation(TravAnimation.quick) {
                                selectedStopID = stop.id
                                focusOnStop(stop)
                            }
                        }
                    }
                    .tag(stop.id)
                }
            }
            .mapStyle(mapStyleOption.mapStyle)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .mapControlVisibility(.automatic)
            .ignoresSafeArea()

            // Top chrome — floating over the map (no separate bar)
            VStack(spacing: 0) {
                HStack(spacing: TravSpacing.xs) {
                    HStack(spacing: 4) {
                        ForEach(MapStyleOption.allCases) { style in
                            let isSelected = mapStyleOption == style
                            Button {
                                mapStyleOption = style
                            } label: {
                                Text(style.rawValue)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(
                                        isSelected
                                            ? Color.white
                                            : (appearance.isLightMode ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color.white)
                                    )
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: TravRadius.sm, style: .continuous)
                                            .fill(
                                                isSelected
                                                    ? TravColors.accent
                                                    : (appearance.isLightMode ? Color.white.opacity(0.92) : Color.black.opacity(0.72))
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: TravRadius.sm, style: .continuous)
                                            .stroke(
                                                appearance.isLightMode ? Color.black.opacity(0.12) : Color.white.opacity(0.12),
                                                lineWidth: 1
                                            )
                                    )
                                    .shadow(
                                        color: Color.black.opacity(appearance.isLightMode ? 0.08 : 0.25),
                                        radius: 4,
                                        y: 2
                                    )
                            }
                            .buttonStyle(TravPressButtonStyle(scale: 0.97))
                        }
                    }

                    Spacer(minLength: TravSpacing.sm)

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(appearance.isLightMode ? Color(red: 0.1, green: 0.1, blue: 0.1) : .white)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(appearance.isLightMode ? Color.white.opacity(0.92) : Color.black.opacity(0.72))
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        appearance.isLightMode ? Color.black.opacity(0.12) : Color.white.opacity(0.12),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(
                                color: Color.black.opacity(appearance.isLightMode ? 0.08 : 0.25),
                                radius: 4,
                                y: 2
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close map")
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.top, 8)
                .safeAreaPadding(.top)

                Spacer(minLength: 0)
            }
            .allowsHitTesting(true)

            // Bottom Controls & Carousel Overlay
            VStack(spacing: TravSpacing.xs) {
                HStack {
                    // Re-center button — also clears stop selection so the full route is shown
                    Button {
                        withAnimation(TravAnimation.quick) {
                            selectedStopID = nil
                            setupCameraToFitAll()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11, weight: .bold))
                            Text("Fit Route")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(TravColors.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(TravColors.surfaceElevated)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(TravColors.border.opacity(0.5), lineWidth: 1)
                        )
                    }
                    .buttonStyle(TravPressButtonStyle(scale: 0.96))

                    Spacer()

                    // Transport Info Badge
                    if coordinates.count >= 2 {
                        let travelMins = mapKitTravelTimeMinutes ?? routeInfo.estimatedTravelTimeMinutes
                        let travelLabel = mapKitTravelTimeMinutes != nil
                            ? "\(travelMins >= 60 ? TravFormatters.duration(travelMins) : "\(travelMins) min") · \(routeInfo.modeName)"
                            : routeInfo.timeAndModeLabel
                        HStack(spacing: 5) {
                            Image(systemName: routeInfo.iconName)
                                .font(.system(size: 11, weight: .bold))
                            Text(travelLabel)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(appearance.isLightMode ? Color(red: 0.1, green: 0.1, blue: 0.1) : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(appearance.isLightMode ? Color.white.opacity(0.92) : Color.black.opacity(0.75))
                        )
                        .overlay(
                            Capsule().stroke(appearance.isLightMode ? Color.black.opacity(0.12) : Color.white.opacity(0.12), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)

                // Bottom Stop Carousel
                if !resolvedStops.isEmpty {
                    ScrollViewReader { scrollProxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: TravSpacing.sm) {
                                ForEach(Array(resolvedStops.enumerated()), id: \.element.id) { index, stop in
                                    let isSelected = selectedStopID == stop.id
                                    Button {
                                        withAnimation(TravAnimation.quick) {
                                            selectedStopID = stop.id
                                            focusOnStop(stop)
                                        }
                                    } label: {
                                        HStack(spacing: TravSpacing.xs) {
                                            ZStack {
                                                Circle()
                                                    .fill(isSelected ? TravColors.accent : Color.gray.opacity(0.3))
                                                    .frame(width: 26, height: 26)

                                                Text("\(index + 1)")
                                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                                    .foregroundStyle(.white)
                                            }

                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 4) {
                                                    if let emoji = stop.emoji, !emoji.isEmpty {
                                                        Image(systemName: sfSymbolForEmojiOrCategory(emoji))
                                                            .font(.system(size: 11))
                                                            .foregroundStyle(isSelected ? TravColors.accent : TravColors.primary)
                                                    }
                                                    Text(stop.name)
                                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                                        .foregroundStyle(TravColors.primary)
                                                        .lineLimit(1)
                                                }

                                                if let time = stop.recommendedTime {
                                                    Text(time)
                                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                                        .foregroundStyle(TravColors.muted)
                                                        .lineLimit(1)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(isSelected ? TravColors.surfaceElevated : TravColors.surfaceElevated.opacity(0.85))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(isSelected ? TravColors.accent : TravColors.border.opacity(0.4), lineWidth: isSelected ? 2 : 1)
                                        )
                                        .shadow(color: isSelected ? TravColors.accent.opacity(0.25) : .black.opacity(0.08), radius: 6, y: 3)
                                    }
                                    .buttonStyle(TravPressButtonStyle(scale: 0.97))
                                    .id(stop.id)
                                }
                            }
                            .padding(.horizontal, TravSpacing.screenHorizontal)
                            .padding(.vertical, 4)
                        }
                        .onChange(of: selectedStopID) { _, newID in
                            if let newID {
                                withAnimation(TravAnimation.quick) {
                                    scrollProxy.scrollTo(newID, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, TravSpacing.md)
        }
        .background(TravColors.surface)
        .task {
            selectedStopID = initialSelectedStopID
            setupCameraToFitAll()
            await fetchRoutes()
        }
    }

    private func getCityBaseCoordinate() -> CLLocationCoordinate2D {
        if let firstWithCoord = stops.first(where: { $0.latitude != 0 || $0.longitude != 0 }) {
            return CLLocationCoordinate2D(latitude: firstWithCoord.latitude, longitude: firstWithCoord.longitude)
        }
        return CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    }

    private func focusOnStop(_ stop: Stop) {
        position = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        ))
    }

    private func setupCameraToFitAll() {
        let coords = coordinates
        guard !coords.isEmpty else { return }

        if coords.count == 1 {
            position = .region(MKCoordinateRegion(
                center: coords[0],
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
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
        let latDelta = max((maxLat - minLat) * 1.5, 0.015)
        let lonDelta = max((maxLon - minLon) * 1.5, 0.015)

        position = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        ))
    }

    private func fetchRoutes() async {
        guard resolvedStops.count >= 2 else { return }
        var polylines: [MKPolyline] = []
        var totalSeconds: TimeInterval = 0

        for i in 0..<(resolvedStops.count - 1) {
            let src = resolvedStops[i]
            let dst = resolvedStops[i + 1]
            let start = CLLocationCoordinate2D(latitude: src.latitude, longitude: src.longitude)
            let end = CLLocationCoordinate2D(latitude: dst.latitude, longitude: dst.longitude)
            let distance = RouteTravelCalculator.segmentDistanceMeters(from: start, to: end)
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
            request.transportType = RouteTravelCalculator.isDrivingSegment(distanceMeters: distance) ? .automobile : .walking

            if let response = try? await MKDirections(request: request).calculate(),
               let route = response.routes.first {
                polylines.append(route.polyline)
                totalSeconds += route.expectedTravelTime
            }
        }

        let mins = Int(round(totalSeconds / 60.0))
        await MainActor.run {
            if !polylines.isEmpty {
                self.routePolylines = polylines
                if mins > 0 {
                    self.mapKitTravelTimeMinutes = mins
                }
            }
        }
    }
}

/// Custom annotation marker for stops on the interactive map
private struct InteractiveStopAnnotationView: View {
    let index: Int
    let stop: Stop
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(isSelected ? TravColors.accent : Color.white)
                    .frame(width: isSelected ? 32 : 26, height: isSelected ? 32 : 26)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.clear : Color.black.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: isSelected ? TravColors.accent.opacity(0.4) : .black.opacity(0.3), radius: isSelected ? 6 : 3)

                Text("\(index)")
                    .font(.system(size: isSelected ? 13 : 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : Color.black)
            }

            Text(stop.name)
                .font(.system(size: 10, weight: isSelected ? .bold : .semibold, design: .rounded))
                .foregroundStyle(isSelected ? TravColors.accent : TravColors.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.72))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.15), radius: 2)
        }
        .scaleEffect(isSelected ? 1.15 : 1.0)
        .animation(TravAnimation.quick, value: isSelected)
    }
}
