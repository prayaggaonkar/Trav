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
                                Text("Submit & Complete")
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

        do {
            // Spots are never authored here: sync the canonical place, then
            // attach this user's rating to it.
            let city = await resolveCity()
            let spotID = try await environment.experiences.syncSpot(
                SpotSyncRequest(
                    placeID: spot.id,
                    name: spot.title,
                    description: spot.subtitle,
                    cityName: city?.name ?? spot.cityName ?? "",
                    cityID: city?.id,
                    latitude: spot.latitude ?? city?.latitude,
                    longitude: spot.longitude ?? city?.longitude,
                    imageURLs: [],
                    category: spot.category.rawValue,
                    emoji: spot.category.emoji
                )
            )

            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await environment.ratings.submitRating(
                RatingDraft(
                    experienceID: spotID,
                    radar: rating,
                    review: trimmedNote.isEmpty ? nil : trimmedNote
                ),
                userID: user.id
            )
            environment.router.noteExperienceCatalogChanged()

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

    private func resolveCity() async -> City? {
        if let cityName = spot.cityName, let match = try? await CityCatalog.shared.city(named: cityName) {
            return match
        }
        return try? await environment.cities.fetchGlobeCities().first
    }
}

/// Sheet presenting spot detail using the unified ExperienceDetailView UI.
struct SpotDetailSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    let spot: SpotSuggestion

    @State private var experienceID: UUID?

    var body: some View {
        Group {
            if let experienceID {
                ExperienceDetailView(experienceID: experienceID)
            } else {
                ProgressView()
                    .tint(TravColors.accent)
            }
        }
        .task {
            await setupExperience()
        }
    }

    private func setupExperience() async {
        if let existingUUID = UUID(uuidString: spot.id),
           let cached = AppleMapsVibeService.shared.cachedExperience(for: existingUUID),
           !cached.imageURLs.isEmpty {
            self.experienceID = existingUUID
            return
        }

        let id = UUID(uuidString: spot.id) ?? UUID()
        let emoji = spot.category.emoji
        var photoURLs: [URL] = []

        // 1. Check for real user-uploaded photos from Supabase for this place
        let query = spot.title.lowercased()
        if let page = try? await environment.experiences.fetchHomeFeed(page: 0) {
            let matches = page.items.filter { exp in
                exp.title.lowercased().contains(query) ||
                exp.stops.contains(where: { $0.name.lowercased().contains(query) })
            }
            photoURLs = matches.flatMap(\.imageURLs)
        }

        // 2. Capture actual Apple Maps 3D Street View / Building photo if no user photos exist
        if photoURLs.isEmpty {
            if let streetViewURL = await AppleMapsVibeService.shared.fetchStreetViewPhoto(
                latitude: spot.latitude,
                longitude: spot.longitude,
                title: spot.title
            ) {
                photoURLs.append(streetViewURL)
            }
        }
        
        let stop = Stop(
            id: UUID(),
            orderIndex: 1,
            name: spot.title,
            description: spot.displayLocation,
            creatorNotes: "Discovered spot in \(spot.displayLocation).",
            latitude: spot.latitude ?? 0,
            longitude: spot.longitude ?? 0,
            placeID: nil,
            recommendedTime: nil,
            durationMinutes: 45,
            emoji: emoji,
            media: []
        )

        let creator = ProfileSummary(
            id: ExperienceInsert.travAdminID,
            username: "trav",
            displayName: "Rec by Trav",
            avatarURL: nil,
            isVerified: true
        )

        let exp = Experience(
            id: id,
            cityID: UUID(),
            creator: creator,
            title: spot.title,
            description: "Featured \(spot.category.rawValue) recommendation in \(spot.displayLocation), sourced from Apple Maps.",
            imageURLs: photoURLs,
            durationMinutes: 45,
            costLevel: .moderate,
            estimatedCostUSD: nil,
            transportMode: .walking,
            totalDistanceMeters: 0,
            saveCount: 0,
            likeCount: 0,
            completionCount: 0,
            commentCount: 0,
            isPublished: true,
            publishedAt: Date(),
            stops: [stop],
            routeSegments: [],
            rating: nil
        )

        AppleMapsVibeService.shared.cacheCustomExperience(exp)
        self.experienceID = id
    }
}
