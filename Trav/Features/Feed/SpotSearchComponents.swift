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

    var resolvedCityName: String {
        let parts = subtitle.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count >= 2 {
            // Address format: "Street/Venue, City, State Zip" or "City, State"
            let candidateCity = parts[parts.count - 2]
            let cleanCity = candidateCity.components(separatedBy: .decimalDigits).joined().trimmingCharacters(in: .whitespaces)
            if !cleanCity.isEmpty {
                return cleanCity
            }
        }
        return subtitle.isEmpty ? "" : subtitle
    }

    var cityName: String? {
        resolvedCityName
    }

    func asExperienceSummary(creator currentUser: ProfileSummary? = nil) -> ExperienceSummary {
        let canonicalKey = SpotIdentity.key(
            placeID: nil,
            name: title,
            latitude: latitude ?? 0,
            longitude: longitude ?? 0
        )
        let spotUUID = StableUUID.from(canonicalKey)
        let stop = StopPreview(
            id: UUID(),
            name: title,
            emoji: category.emoji,
            latitude: latitude,
            longitude: longitude
        )
        let city = resolvedCityName
        let creatorSummary = ExperienceInsert.travCreator
        let summary = ExperienceSummary(
            id: spotUUID,
            kind: .spot,
            cityID: StableUUID.from("city:\(city.lowercased())"),
            title: title,
            imageURLs: [],
            creator: creatorSummary,
            durationMinutes: 45,
            costLevel: .free,
            estimatedCostUSD: nil,
            saveCount: 0,
            likeCount: 0,
            completionCount: 0,
            stops: [stop],
            rating: nil,
            ratingSummary: .empty,
            cityName: city,
            completedBy: [],
            spotKey: canonicalKey,
            category: category.rawValue,
            latitude: latitude,
            longitude: longitude
        )
        AppleMapsVibeService.shared.cacheCustomExperience(summary)
        return summary
    }
}

/// Controller leveraging Apple Maps Search API (MKLocalSearch) to find any place, spot, address, or landmark worldwide.
@Observable
@MainActor
final class SpotSearchController: NSObject, CLLocationManagerDelegate {
    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            searchTask?.cancel()
            currentSearch?.cancel()
            if trimmed.isEmpty {
                spots = []
                isSearching = false
            } else if trimmed != lastQueried {
                lastQueried = trimmed
                isSearching = true
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(200))
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
    private var currentSearch: MKLocalSearch?
    private var userCoordinate: CLLocationCoordinate2D?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
            userCoordinate = locationManager.location?.coordinate
        }
    }

    func clear() {
        searchTask?.cancel()
        currentSearch?.cancel()
        currentSearch = nil
        query = ""
        spots = []
        lastQueried = ""
        isSearching = false
    }

    // MARK: - CLLocationManagerDelegate (Safe Non-isolated Handlers)

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coord = location.coordinate
        Task { @MainActor in
            self.userCoordinate = coord
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            let loc = manager.location?.coordinate
            Task { @MainActor in
                self.userCoordinate = loc
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: - Apple Maps Search

    private func performSpotSearch(for queryText: String) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = queryText
        request.resultTypes = [.pointOfInterest, .address]

        // Localized regional search around user location if available
        if let coord = userCoordinate {
            request.region = MKCoordinateRegion(
                center: coord,
                latitudinalMeters: 100_000,
                longitudinalMeters: 100_000
            )
        }

        do {
            let search = MKLocalSearch(request: request)
            currentSearch = search
            var response = try await search.start()

            // If regional search returned no items, execute global search without bounds
            if response.mapItems.isEmpty {
                let globalRequest = MKLocalSearch.Request()
                globalRequest.naturalLanguageQuery = queryText
                globalRequest.resultTypes = [.pointOfInterest, .address]
                let globalSearch = MKLocalSearch(request: globalRequest)
                currentSearch = globalSearch
                response = try await globalSearch.start()
            }

            guard !Task.isCancelled else { return }

            var results: [SpotSuggestion] = []
            var seen = Set<String>()

            for item in response.mapItems {
                guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
                let subtitle = item.placemark.title ?? ""

                let category = SpotCategory.infer(title: name, subtitle: subtitle)
                let coord = item.placemark.coordinate
                let suggestion = SpotSuggestion(
                    id: "spot|\(name)|\(subtitle)|\(coord.latitude),\(coord.longitude)",
                    title: name,
                    subtitle: subtitle,
                    category: category,
                    latitude: coord.latitude,
                    longitude: coord.longitude
                )

                let key = "\(name.lowercased())|\(subtitle.lowercased())"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                results.append(suggestion)

                if results.count >= 15 { break }
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

    static var emptyRating: RadarRating {
        RadarRating(
            scores: [:],
            disabledCategories: Set(axes.map(\.id))
        )
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

    @State private var rating: RadarRating = SpotRatingAxes.emptyRating
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
                                Text(rating.hasActiveScores ? String(format: "%.1f / 10", rating.overallScore) : "-- / 10")
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
                    .disabled(isSaving || !rating.hasActiveScores)
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
        .alert("Couldn't Save", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
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
        guard rating.hasActiveScores else {
            saveError = "Rate at least one category on the polygon to submit."
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
        if let cityName = spot.cityName, !cityName.isEmpty, let match = try? await CityCatalog.shared.city(named: cityName) {
            return match
        }

        // 1. Reverse-geocode spot's coordinates via CoreLocation CLGeocoder
        if let lat = spot.latitude, let lng = spot.longitude, lat != 0 && lng != 0 {
            let location = CLLocation(latitude: lat, longitude: lng)
            let geocoder = CLGeocoder()
            if let placemarks = try? await geocoder.reverseGeocodeLocation(location),
               let placemark = placemarks.first,
               let localityName = placemark.locality ?? placemark.subAdministrativeArea {
                let matchedCity = (try? await CityCatalog.shared.city(named: localityName)) ?? City(
                    id: UUID(),
                    name: localityName,
                    slug: localityName.lowercased().replacingOccurrences(of: " ", with: "-"),
                    countryCode: placemark.isoCountryCode ?? "US",
                    latitude: lat,
                    longitude: lng,
                    heroImageURL: nil,
                    timezone: TimeZone.current.identifier,
                    experienceCount: 0,
                    creatorCount: 0
                )
                return matchedCity
            }
        }

        // 2. Return city constructed from spot's resolved cityName
        if let cityName = spot.cityName, !cityName.isEmpty {
            return City(
                id: UUID(),
                name: cityName,
                slug: cityName.lowercased().replacingOccurrences(of: " ", with: "-"),
                countryCode: "US",
                latitude: spot.latitude ?? 37.7749,
                longitude: spot.longitude ?? -122.4194,
                heroImageURL: nil,
                timezone: TimeZone.current.identifier,
                experienceCount: 0,
                creatorCount: 0
            )
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

        // 2. Capture actual Apple Maps 3D Street View or Map View snapshot if no user photos exist
        if photoURLs.isEmpty {
            if let mapURL = await AppleMapsVibeService.shared.fetchStreetViewOrMapView(
                latitude: spot.latitude,
                longitude: spot.longitude,
                title: spot.title
            ) {
                photoURLs.append(mapURL)
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

        let creator = ExperienceInsert.travCreator

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

// MARK: - Full Search Results Component

enum SearchTab: String, CaseIterable, Identifiable {
    case all = "All"
    case spots = "Spots"
    case cities = "Cities"
    case creators = "Creators"
    case itineraries = "Itineraries"

    var id: String { rawValue }
}

struct FullSearchResultsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(AppearanceStore.self) private var appearance
    @Environment(\.dismiss) private var dismiss

    let initialQuery: String
    let initialTab: SearchTab

    @State private var query: String
    @State private var selectedTab: SearchTab
    @State private var spots: [SpotSuggestion] = []
    @State private var cities: [City] = []
    @State private var users: [ProfileSummary] = []
    @State private var itineraries: [ExperienceSummary] = []
    @State private var isLoading: Bool = false
    @State private var selectedSpotDetail: SpotSuggestion?
    @FocusState private var isSearchFocused: Bool

    init(initialQuery: String, initialTab: SearchTab = .all) {
        self.initialQuery = initialQuery
        self.initialTab = initialTab
        _query = State(initialValue: initialQuery)
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Search Bar & Header
                headerView

                // Category Filter Pills
                filterPillsView
                    .padding(.vertical, TravSpacing.xs)

                // Results Content
                ScrollView {
                    VStack(alignment: .leading, spacing: TravSpacing.md) {
                        if isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(TravColors.accent)
                                    .padding(.top, 40)
                                Spacer()
                            }
                        } else if isEmptyResults {
                            emptyStateView
                        } else {
                            resultsContent
                        }
                    }
                    .padding(.horizontal, TravSpacing.screenHorizontal)
                    .padding(.bottom, 40)
                }
            }
            .background(TravColors.surface.ignoresSafeArea())
            .task(id: query) {
                await performSearch()
            }
            .sheet(item: $selectedSpotDetail) { spot in
                SpotDetailSheet(spot: spot)
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: TravSpacing.xs) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TravColors.primary)
                    .frame(width: 38, height: 38)
                    .background(TravColors.surfaceElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: TravSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TravColors.muted)

                TextField("Search spots, cities, creators...", text: $query)
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.primary)
                    .focused($isSearchFocused)
                    .autocorrectionDisabled()

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(TravColors.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(TravColors.surfaceElevated)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(TravColors.border.opacity(0.4), lineWidth: 1)
            )
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.top, TravSpacing.xs)
    }

    private var filterPillsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchTab.allCases) { tab in
                    let count = countForTab(tab)
                    Button {
                        withAnimation(TravAnimation.quick) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: selectedTab == tab ? .bold : .medium, design: .rounded))

                            if tab != .all && count > 0 {
                                Text("(\(count))")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .opacity(0.85)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .foregroundStyle(selectedTab == tab ? .white : TravColors.primary)
                        .background(
                            Capsule().fill(selectedTab == tab ? AnyShapeStyle(TravColors.accent) : AnyShapeStyle(TravColors.surfaceElevated))
                        )
                        .overlay(
                            Capsule().stroke(selectedTab == tab ? Color.clear : TravColors.border.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TravSpacing.screenHorizontal)
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        switch selectedTab {
        case .all:
            if !spots.isEmpty {
                sectionHeader(title: "SPOTS", count: spots.count) { selectedTab = .spots }
                spotsListView(limit: 4)
            }
            if !cities.isEmpty {
                sectionHeader(title: "CITIES", count: cities.count) { selectedTab = .cities }
                citiesListView(limit: 4)
            }
            if !users.isEmpty {
                sectionHeader(title: "CREATORS & USERS", count: users.count) { selectedTab = .creators }
                usersListView(limit: 4)
            }
            if !itineraries.isEmpty {
                sectionHeader(title: "ITINERARIES", count: itineraries.count) { selectedTab = .itineraries }
                itinerariesListView(limit: 4)
            }
        case .spots:
            spotsListView(limit: nil)
        case .cities:
            citiesListView(limit: nil)
        case .creators:
            usersListView(limit: nil)
        case .itineraries:
            itinerariesListView(limit: nil)
        }
    }

    private func countForTab(_ tab: SearchTab) -> Int {
        switch tab {
        case .all: spots.count + cities.count + users.count + itineraries.count
        case .spots: spots.count
        case .cities: cities.count
        case .creators: users.count
        case .itineraries: itineraries.count
        }
    }

    private var isEmptyResults: Bool {
        spots.isEmpty && cities.isEmpty && users.isEmpty && itineraries.isEmpty && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(TravColors.muted)
                .padding(.top, 40)

            Text("No results found for \"\(query)\"")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(TravColors.primary)

            Text("Try searching for a different spot name, city, or creator handle.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(TravColors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(title: String, count: Int, onViewAll: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(TravColors.muted)

            Spacer()

            if count > 4 {
                Button {
                    onViewAll()
                } label: {
                    HStack(spacing: 3) {
                        Text("View all (\(count))")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(TravColors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, TravSpacing.xs)
    }

    private func spotsListView(limit: Int?) -> some View {
        let items = limit != nil ? Array(spots.prefix(limit!)) : spots
        return VStack(spacing: 8) {
            ForEach(items) { spot in
                Button {
                    selectedSpotDetail = spot
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(spot.category.badgeColor.opacity(0.18))
                                .frame(width: 38, height: 38)
                            Text(spot.category.emoji)
                                .font(.system(size: 18))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(spot.title)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(TravColors.primary)

                                Text(spot.category.rawValue)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(spot.category.badgeColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(spot.category.badgeColor.opacity(0.18))
                                    .clipShape(Capsule())
                            }

                            Text(spot.displayLocation)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(TravColors.muted)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "star.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(TravColors.accent)
                    }
                    .padding(12)
                    .background(TravColors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.98))
            }
        }
    }

    private func citiesListView(limit: Int?) -> some View {
        let items = limit != nil ? Array(cities.prefix(limit!)) : cities
        return VStack(spacing: 8) {
            ForEach(items) { city in
                Button {
                    dismiss()
                    router.openCity(city)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(TravColors.accent.opacity(0.15))
                                .frame(width: 38, height: 38)

                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(TravColors.accent)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(city.name)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(TravColors.primary)

                            Text(city.countryName)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(TravColors.muted)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(TravColors.muted)
                    }
                    .padding(12)
                    .background(TravColors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.98))
            }
        }
    }

    private func usersListView(limit: Int?) -> some View {
        let items = limit != nil ? Array(users.prefix(limit!)) : users
        return VStack(spacing: 8) {
            ForEach(items) { user in
                Button {
                    dismiss()
                    router.openProfile(user.username)
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(url: user.avatarURL, size: 40)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(user.displayName)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(TravColors.primary)

                            Text("@\(user.username)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(TravColors.muted)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(TravColors.muted)
                    }
                    .padding(12)
                    .background(TravColors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.98))
            }
        }
    }

    private func itinerariesListView(limit: Int?) -> some View {
        let items = limit != nil ? Array(itineraries.prefix(limit!)) : itineraries
        return VStack(spacing: 12) {
            ForEach(items) { experience in
                ExperienceCard(
                    experience: experience,
                    onTap: {
                        dismiss()
                        router.openExperience(experience.id)
                    },
                    onCreatorTap: {
                        dismiss()
                        router.openProfile(experience.creator.username)
                    }
                )
            }
        }
    }

    private func performSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            spots = []
            cities = []
            users = []
            itineraries = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        // 1. Fetch Apple Maps places (MKLocalSearch)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.pointOfInterest, .address]

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            var mapSpots: [SpotSuggestion] = []
            var seen = Set<String>()

            for item in response.mapItems {
                guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
                let subtitle = item.placemark.title ?? ""
                let category = SpotCategory.infer(title: name, subtitle: subtitle)
                let coord = item.placemark.coordinate
                let suggestion = SpotSuggestion(
                    id: "spot|\(name)|\(subtitle)|\(coord.latitude),\(coord.longitude)",
                    title: name,
                    subtitle: subtitle,
                    category: category,
                    latitude: coord.latitude,
                    longitude: coord.longitude
                )

                let key = "\(name.lowercased())|\(subtitle.lowercased())"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                mapSpots.append(suggestion)
            }
            spots = mapSpots
        } catch {
            spots = []
        }

        // 2. Fetch matching cities
        do {
            let allCities = try await environment.cities.fetchGlobeCities()
            cities = allCities.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.countryName.localizedCaseInsensitiveContains(trimmed)
            }
        } catch {
            cities = []
        }

        // 3. Fetch matching profiles
        do {
            users = try await environment.profiles.searchUsers(query: trimmed)
        } catch {
            users = []
        }

        // 4. Fetch matching experiences
        do {
            let matches = try await environment.experiences.searchExperiences(query: trimmed, kind: nil, limit: 15)
            itineraries = matches.filter { !$0.isSpot }
        } catch {
            itineraries = []
        }
    }
}
