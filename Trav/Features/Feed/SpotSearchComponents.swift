import SwiftUI
import MapKit
import CoreLocation

enum SpotCategory: String, CaseIterable, Codable, Sendable {
    case hike = "Hike"
    case viewpoint = "Viewpoint"
    case park = "Park"
    case landmark = "Landmark"
    case spot = "Spot"

    var emoji: String {
        switch self {
        case .hike: return "🥾"
        case .viewpoint: return "🏔"
        case .park: return "🏞"
        case .landmark: return "🏛"
        case .spot: return "📍"
        }
    }

    var badgeColor: Color {
        switch self {
        case .hike: return Color(red: 0.1, green: 0.75, blue: 0.45)
        case .viewpoint: return Color.cyan
        case .park: return Color.green
        case .landmark: return Color(red: 0.95, green: 0.65, blue: 0.1)
        case .spot: return TravColors.accent
        }
    }

    static func infer(title: String, subtitle: String) -> SpotCategory {
        let text = "\(title) \(subtitle)".lowercased()
        if text.contains("hike") || text.contains("trail") || text.contains("climb") || text.contains("summit") || text.contains("mountain") {
            return .hike
        }
        if text.contains("view") || text.contains("lookout") || text.contains("overlook") || text.contains("vista") || text.contains("point") || text.contains("peak") {
            return .viewpoint
        }
        if text.contains("park") || text.contains("garden") || text.contains("beach") || text.contains("lake") || text.contains("nature") || text.contains("preserve") {
            return .park
        }
        if text.contains("tower") || text.contains("bridge") || text.contains("monument") || text.contains("palace") || text.contains("museum") || text.contains("historic") || text.contains("statue") || text.contains("center") {
            return .landmark
        }
        return .spot
    }
}

/// Represents a non-food spot found via MapKit spot search.
struct SpotSuggestion: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let category: SpotCategory
    let latitude: Double?
    let longitude: Double?

    var displayLocation: String {
        let parts = subtitle.components(separatedBy: ",")
        if parts.count >= 2 {
            return "\(parts[0].trimmingCharacters(in: .whitespaces)), \(parts[1].trimmingCharacters(in: .whitespaces))"
        }
        return subtitle
    }

    var cityName: String? {
        let parts = subtitle.components(separatedBy: ",")
        if parts.count >= 2 {
            return parts[parts.count - 2].trimmingCharacters(in: .whitespaces)
        }
        return parts.first?.trimmingCharacters(in: .whitespaces)
    }
}

/// Controller dedicated to searching non-food spots (Hikes, Viewpoints, Parks, Landmarks, Activities).
@Observable
@MainActor
final class SpotSearchController: NSObject, CLLocationManagerDelegate {
    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            searchTask?.cancel()
            if trimmed.isEmpty {
                spots = []
                isSearching = false
            } else if trimmed != lastQueried {
                lastQueried = trimmed
                isSearching = true
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(220))
                    guard !Task.isCancelled else { return }
                    await performSpotSearch(for: trimmed)
                }
            }
        }
    }

    private(set) var spots: [SpotSuggestion] = []
    private(set) var isSearching = false

    private let locationManager = CLLocationManager()
    private var lastQueried = ""
    private var searchTask: Task<Void, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func clear() {
        searchTask?.cancel()
        query = ""
        spots = []
        lastQueried = ""
        isSearching = false
    }

    private static let excludedFoodKeywords = [
        "restaurant", "cafe", "coffee", "boba", "pizza", "burger", "tacos",
        "sushi", "bakery", "diner", "bistro", "bar", "pub", "grill", "eatery",
        "kitchen", "food", "noodle", "ramen", "steak", "bbq", "brewery", "winery"
    ]

    private func isFoodPlace(title: String, subtitle: String) -> Bool {
        let combined = "\(title) \(subtitle)".lowercased()
        return Self.excludedFoodKeywords.contains { combined.contains($0) }
    }

    private func performSpotSearch(for queryText: String) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = queryText
        request.resultTypes = [.pointOfInterest, .address]

        if #available(iOS 13.0, *) {
            request.pointOfInterestFilter = MKPointOfInterestFilter(excluding: [
                .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket, .nightlife
            ])
        }

        if let location = locationManager.location {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 100_000,
                longitudinalMeters: 100_000
            )
        }

        do {
            var search = MKLocalSearch(request: request)
            var response = try await search.start()

            // If regional search returned no items, attempt global search without regional bounds
            if response.mapItems.isEmpty {
                let globalRequest = MKLocalSearch.Request()
                globalRequest.naturalLanguageQuery = queryText
                globalRequest.resultTypes = [.pointOfInterest, .address]
                if #available(iOS 13.0, *) {
                    globalRequest.pointOfInterestFilter = MKPointOfInterestFilter(excluding: [
                        .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket, .nightlife
                    ])
                }
                search = MKLocalSearch(request: globalRequest)
                response = try await search.start()
            }

            guard !Task.isCancelled else { return }

            var results: [SpotSuggestion] = []
            var seen = Set<String>()

            for item in response.mapItems {
                guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
                let subtitle = item.placemark.title ?? ""

                // Filter out food places to keep search strictly focused on spots, hikes & activities
                if isFoodPlace(title: name, subtitle: subtitle) { continue }

                let category = SpotCategory.infer(title: name, subtitle: subtitle)
                let coord = item.placemark.coordinate
                let suggestion = SpotSuggestion(
                    id: "spot|\(name)|\(subtitle)",
                    title: name,
                    subtitle: subtitle,
                    category: category,
                    latitude: coord.latitude,
                    longitude: coord.longitude
                )

                let key = name.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                results.append(suggestion)

                if results.count >= 12 { break }
            }

            self.spots = results
            self.isSearching = false
        } catch {
            self.spots = []
            self.isSearching = false
        }
    }
}

/// Custom radar chart axes tailored for rating spots & outdoor experiences.
enum SpotRatingAxes {
    static let axes: [RadarAxis] = [
        RadarAxis(id: "Views", name: "Views", iconName: "mountain.2.fill", minValue: 1.0, maxValue: 10.0),
        RadarAxis(id: "Vibe", name: "Vibe", iconName: "sparkles", minValue: 1.0, maxValue: 10.0),
        RadarAxis(id: "Difficulty", name: "Difficulty", iconName: "figure.hiking", minValue: 1.0, maxValue: 10.0),
        RadarAxis(id: "Memorability", name: "Memorability", iconName: "star.fill", minValue: 1.0, maxValue: 10.0),
        RadarAxis(id: "Worth It", name: "Worth It", iconName: "checkmark.circle.fill", minValue: 1.0, maxValue: 10.0)
    ]

    static var defaultRating: RadarRating {
        RadarRating(scores: [
            "Views": 9.0,
            "Vibe": 8.5,
            "Difficulty": 5.0,
            "Memorability": 8.8,
            "Worth It": 9.2
        ])
    }
}

/// Sheet for rating a searched spot (e.g. Big C Hike, Dolores Park, Coit Tower).
struct RateSpotSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session
    @Environment(EngagementStore.self) private var engagement
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    let spot: SpotSuggestion
    var onSaved: (() -> Void)? = nil

    @State private var rating: RadarRating = SpotRatingAxes.defaultRating
    @State private var note: String = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showEyesRain = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TravSpacing.lg) {
                    // Header card with spot info
                    spotHeaderCard

                    // Score pill + radar chart
                    VStack(alignment: .leading, spacing: TravSpacing.xs) {
                        HStack {
                            Text("RATE THIS SPOT")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(1.2)
                                .foregroundStyle(TravColors.muted)

                            Spacer()

                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.yellow)
                                Text(String(format: "%.1f / 10", rating.overallScore))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(TravColors.accent.opacity(0.2)))
                        }

                        InteractiveRadarChartView(
                            rating: $rating,
                            axes: SpotRatingAxes.axes
                        )
                        .background(
                            RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                                .fill(TravColors.surfaceElevated)
                        )
                    }

                    // Optional review note
                    VStack(alignment: .leading, spacing: TravSpacing.xs) {
                        Text("YOUR THOUGHTS (OPTIONAL)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(TravColors.muted)

                        TextField(
                            "",
                            text: $note,
                            prompt: Text("What made this spot special? (e.g., best sunset spot)").foregroundColor(TravColors.muted),
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .padding(TravSpacing.md)
                        .background(TravColors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                        .tint(TravColors.accent)
                    }

                    if let saveError {
                        Text(saveError)
                            .font(TravTypography.caption())
                            .foregroundStyle(TravColors.error)
                    }

                    // Save action button
                    Button {
                        Task { await saveSpotRating() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Image(systemName: "star.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                                Text("Save & Add to Watchlist")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                            }
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(TravColors.accent)
                        .clipShape(Capsule())
                    }
                    .disabled(isSaving)
                    .buttonStyle(TravPressButtonStyle())
                }
                .padding(TravSpacing.lg)
            }
            .travScreenBackground()
            .navigationTitle("Rate Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(TravColors.muted)
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
    }

    private var spotHeaderCard: some View {
        HStack(spacing: TravSpacing.md) {
            ZStack {
                Circle()
                    .fill(spot.category.badgeColor.opacity(0.2))
                    .frame(width: 48, height: 48)
                Text(spot.category.emoji)
                    .font(.system(size: 24))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(spot.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(spot.category.rawValue)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(spot.category.badgeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(spot.category.badgeColor.opacity(0.18))
                        .clipShape(Capsule())
                }

                Text(spot.displayLocation)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TravColors.muted)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(TravSpacing.md)
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
    }

    private func saveSpotRating() async {
        guard let user = session.currentUser else {
            dismiss()
            router.presentAuth()
            return
        }

        isSaving = true
        saveError = nil

        let resolvedCity: City
        if let cityName = spot.cityName, let match = try? await CityCatalog.shared.city(named: cityName) {
            resolvedCity = match
        } else if let first = try? await environment.cities.fetchGlobeCities().first {
            resolvedCity = first
        } else {
            isSaving = false
            saveError = "Couldn't resolve city location."
            return
        }

        let draft = ExperienceDraft(
            title: spot.title,
            description: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rated \(spot.category.rawValue) spot." : note,
            city: resolvedCity,
            creatorID: user.id,
            stops: [
                Stop(
                    id: UUID(),
                    orderIndex: 0,
                    name: spot.title,
                    description: spot.subtitle,
                    creatorNotes: nil,
                    latitude: spot.latitude ?? resolvedCity.latitude,
                    longitude: spot.longitude ?? resolvedCity.longitude,
                    placeID: spot.id,
                    recommendedTime: nil,
                    durationMinutes: 60,
                    emoji: spot.category.emoji,
                    media: []
                )
            ],
            rating: rating,
            imagesData: []
        )

        do {
            try await environment.experiences.publishExperience(draft)

            isSaving = false
            withAnimation { showEyesRain = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)

            onSaved?()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                dismiss()
            }
        } catch {
            isSaving = false
            saveError = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

/// Comprehensive detail view shown when tapping a spot in search suggestions.
/// Displays spot info, community & follower ratings, photos, linked follower experience posts,
/// unified action bar (Watchlist, Save, Rate/Edit), and smart user status.
struct SpotDetailSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    let spot: SpotSuggestion

    @State private var matchingExperiences: [ExperienceSummary] = []
    @State private var isLoading = true
    @State private var isWatchlisted = false
    @State private var isSaved = false
    @State private var showEyesRain = false
    @State private var mapSnapshotImage: UIImage? = nil

    private var currentUserID: UUID? {
        environment.session.currentUser?.id
    }

    private var userExperience: ExperienceSummary? {
        guard let currentUserID else { return nil }
        return matchingExperiences.first(where: { $0.creator.id == currentUserID })
    }

    /// Follower experiences excluding the logged in user's own post
    private var followerExperiences: [ExperienceSummary] {
        guard let currentUserID else { return matchingExperiences }
        return matchingExperiences.filter { $0.creator.id != currentUserID }
    }

    private var averageRatingScore: Double? {
        let ratedExps = followerExperiences.compactMap { $0.rating?.overallScore }
        guard !ratedExps.isEmpty else { return nil }
        let sum = ratedExps.reduce(0.0, +)
        return (sum / Double(ratedExps.count) * 10).rounded() / 10
    }

    private var userPostImages: [URL] {
        matchingExperiences.flatMap { $0.imageURLs }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: TravSpacing.md) {
                        // Hero Media Carousel (User posts or centered Apple Maps satellite snapshot)
                        heroMediaSection

                        // Spot Title & Category Header (Handles long text)
                        spotHeaderSection

                        // Action Bar: Watchlist (if not own post), Save, Rate/Edit
                        quickActionBar

                        // Current User Status (if user already rated)
                        if let userExp = userExperience {
                            userAlreadyRatedBanner(userExp: userExp)
                        }

                        // Follower & Community Rating Summary
                        communityRatingCard

                        // Linked Follower Experience Posts
                        linkedPostsSection

                        Spacer(minLength: TravSpacing.lg)
                    }
                    .padding(.bottom, TravSpacing.xl)
                }
                .travScreenBackground()

                if showEyesRain {
                    EmojiParticleView()
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .zIndex(100)
                }
            }
            .navigationTitle(spot.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(TravColors.muted)
                }
            }
            .task {
                await loadMatchingExperiences()
                await loadMapSnapshot()
            }
        }
    }

    private var heroMediaSection: some View {
        Group {
            if !userPostImages.isEmpty {
                TabView {
                    ForEach(userPostImages, id: \.self) { url in
                        RemoteImage(url: url, height: 200, cornerRadius: TravRadius.lg)
                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
                    }
                }
                .tabViewStyle(.page)
            } else if let snapshot = mapSnapshotImage {
                ZStack(alignment: .bottom) {
                    Image(uiImage: snapshot)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))

                    // Centered Apple Maps Badge Overlay
                    HStack(spacing: 4) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 11))
                        Text("Apple Maps Satellite View")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.65))
                    .clipShape(Capsule())
                    .padding(.bottom, 10)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                        .fill(TravColors.surfaceElevated)

                    VStack(spacing: 8) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(TravColors.accent)
                        Text(spot.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, TravSpacing.md)
                    }
                }
            }
        }
        .frame(height: 200)
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.top, TravSpacing.xs)
    }

    private var spotHeaderSection: some View {
        VStack(alignment: .leading, spacing: TravSpacing.xs) {
            HStack(spacing: TravSpacing.xs) {
                Text(spot.category.emoji)
                    .font(.system(size: 18))
                Text(spot.category.rawValue.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(spot.category.badgeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(spot.category.badgeColor.opacity(0.18))
                    .clipShape(Capsule())
            }

            Text(spot.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13))
                    .foregroundStyle(TravColors.accent)
                    .padding(.top, 2)

                Text(spot.displayLocation)
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
    }

    private var quickActionBar: some View {
        HStack(spacing: TravSpacing.sm) {
            // 1. Watchlist Button with Eyes Rain (Only available if NOT user's own post)
            if userExperience == nil {
                Button {
                    isWatchlisted.toggle()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if isWatchlisted {
                        withAnimation { showEyesRain = true }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(isWatchlisted ? "👀 Listed" : "👀 Watchlist")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(isWatchlisted ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        Capsule()
                            .fill(isWatchlisted ? TravColors.accent : TravColors.surfaceElevated)
                    )
                    .overlay(
                        Capsule()
                            .stroke(isWatchlisted ? Color.clear : Color.white.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(TravPressButtonStyle())
            }

            // 2. Save Button
            Button {
                isSaved.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 12, weight: .bold))
                    Text(isSaved ? "Saved" : "Save")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(isSaved ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    Capsule()
                        .fill(isSaved ? Color.yellow : TravColors.surfaceElevated)
                )
                .overlay(
                    Capsule()
                        .stroke(isSaved ? Color.clear : Color.white.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(TravPressButtonStyle())

            // 3. Action Button: "Edit Post" if user already rated, otherwise "Rate Spot"
            Button {
                dismiss()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if let userExp = userExperience {
                    router.openExperience(userExp.id)
                } else {
                    router.openCreateWithSpot(
                        title: spot.title,
                        subtitle: spot.displayLocation,
                        emoji: spot.category.emoji,
                        latitude: spot.latitude,
                        longitude: spot.longitude,
                        cityName: spot.cityName
                    )
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: userExperience != nil ? "square.and.pencil" : "star.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(userExperience != nil ? "Edit Post" : "Rate Spot")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(TravColors.accent)
                .clipShape(Capsule())
                .shadow(color: TravColors.accent.opacity(0.35), radius: 8, y: 2)
            }
            .buttonStyle(TravPressButtonStyle())
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
    }

    private func userAlreadyRatedBanner(userExp: ExperienceSummary) -> some View {
        Button {
            dismiss()
            router.openExperience(userExp.id)
        } label: {
            HStack(spacing: TravSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(TravColors.accent.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(TravColors.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("YOU ALREADY RATED THIS SPOT")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(TravColors.accent)

                    Text(userExp.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer()

                if let overall = userExp.rating?.overallScore {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.yellow)
                        Text(String(format: "%.1f", overall))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(TravColors.surfaceElevated))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TravColors.muted)
            }
            .padding(TravSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                    .fill(TravColors.accent.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                            .stroke(TravColors.accent.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(TravPressButtonStyle())
        .padding(.horizontal, TravSpacing.screenHorizontal)
    }

    private var communityRatingCard: some View {
        VStack(alignment: .leading, spacing: TravSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FOLLOWER & COMMUNITY RATING")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(TravColors.muted)

                    if let _ = averageRatingScore {
                        Text("Based on \(followerExperiences.count) follower review\(followerExperiences.count == 1 ? "" : "s")")
                            .font(TravTypography.caption())
                            .foregroundStyle(Color.white.opacity(0.6))
                    } else {
                        Text("Be the first to rate this spot!")
                            .font(TravTypography.bodyMedium())
                            .foregroundStyle(Color.white.opacity(0.9))
                    }
                }

                Spacer()

                if let score = averageRatingScore {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.yellow)
                        Text(String(format: "%.1f", score))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("/ 10")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TravColors.muted)
                    }
                    .padding(.horizontal, TravSpacing.md)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(TravColors.surfaceElevated))
                }
            }
        }
        .padding(TravSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                .fill(TravColors.surfaceElevated)
        )
        .padding(.horizontal, TravSpacing.screenHorizontal)
    }

    private var linkedPostsSection: some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            Text("POSTS BY PEOPLE YOU FOLLOW")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(TravColors.muted)
                .padding(.horizontal, TravSpacing.screenHorizontal)

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, TravSpacing.lg)
            } else if followerExperiences.isEmpty {
                VStack(spacing: TravSpacing.xs) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(TravColors.muted.opacity(0.5))
                    Text("No follower posts for this spot yet")
                        .font(TravTypography.bodyMedium())
                        .foregroundStyle(TravColors.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, TravSpacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: TravRadius.lg)
                        .fill(TravColors.surfaceElevated.opacity(0.5))
                )
                .padding(.horizontal, TravSpacing.screenHorizontal)
            } else {
                VStack(spacing: TravSpacing.sm) {
                    ForEach(followerExperiences, id: \.id) { (experience: ExperienceSummary) in
                        Button {
                            dismiss()
                            router.openExperience(experience.id)
                        } label: {
                            HStack(spacing: TravSpacing.md) {
                                if let avatarURL = experience.creator.avatarURL {
                                    RemoteImage(url: avatarURL, height: 40, cornerRadius: 20)
                                        .frame(width: 40, height: 40)
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 40))
                                        .foregroundStyle(TravColors.accent)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(experience.creator.displayName)
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)

                                        Text("@\(experience.creator.username)")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(TravColors.muted)
                                            .lineLimit(1)

                                        Spacer()

                                        if let overall = experience.rating?.overallScore {
                                            HStack(spacing: 3) {
                                                Image(systemName: "star.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(Color.yellow)
                                                Text(String(format: "%.1f", overall))
                                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                                    .foregroundStyle(.white)
                                            }
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(TravColors.accent.opacity(0.2)))
                                        }
                                    }

                                    Text(experience.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(TravColors.accent)
                                        .lineLimit(1)

                                    let stopNames = experience.stops.map(\.name).joined(separator: " • ")
                                    if !stopNames.isEmpty {
                                        Text(stopNames)
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundStyle(Color.white.opacity(0.7))
                                            .lineLimit(2)
                                    }
                                }

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(TravColors.muted)
                            }
                            .padding(TravSpacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                                    .fill(TravColors.surfaceElevated)
                            )
                        }
                        .buttonStyle(TravPressButtonStyle(scale: 0.98))
                    }
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
            }
        }
    }

    private func loadMatchingExperiences() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await environment.experiences.fetchHomeFeed(page: 0)
            let query = spot.title.lowercased()
            matchingExperiences = page.items.filter { exp in
                exp.title.lowercased().contains(query) ||
                exp.stops.contains(where: { $0.name.lowercased().contains(query) }) ||
                (exp.cityName?.lowercased().contains(query) ?? false)
            }
        } catch {
            matchingExperiences = []
        }
    }

    private func loadMapSnapshot() async {
        guard let lat = spot.latitude, let lon = spot.longitude else { return }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            latitudinalMeters: 600,
            longitudinalMeters: 600
        )
        options.mapType = .hybrid
        options.size = CGSize(width: 600, height: 320)
        let snapshotter = MKMapSnapshotter(options: options)

        do {
            let snapshot = try await snapshotter.start()
            await MainActor.run {
                self.mapSnapshotImage = snapshot.image
            }
        } catch {
            // Snapshot fallback
        }
    }
}
