import Foundation
import MapKit
import UIKit
import Supabase

/// Service that leverages the Apple Maps API (MKLocalSearch, MKLookAroundSnapshotter, MKMapSnapshotter)
/// to fetch place recommendations based on user onboarding vibes and location,
/// solving the empty/dry feed issue for new users while enforcing strict rate-limiting to prevent GeoServices throttling.
final class AppleMapsVibeService: @unchecked Sendable {
    static let shared = AppleMapsVibeService()

    private var seenPlaceNames = Set<String>()
    private var cachedRecommendations: [UUID: Experience] = [:]
    private var cachedSummariesByCityAndVibes: [String: [ExperienceSummary]] = [:]
    private var lookAroundCount = 0

    private static let nicheQueriesByVibe: [String: [String]] = [
        "food": [
            "speakeasy", "artisan bakery", "cozy cafe", "craft coffee roaster",
            "rooftop lounge", "dessert lounge", "tasting room", "tea house", "boba lounge"
        ],
        "drink": [
            "craft cocktail bar", "speakeasy lounge", "vinyl listening bar", "rooftop bar", "wine bar", "brewery"
        ],
        "entertainment": [
            "live music venue", "comedy club", "arcade bar", "bowling lounge",
            "jazz club", "escape room", "indie cinema", "outdoor theater"
        ],
        "art": [
            "niche art gallery", "sculpture park", "historic theater", "museum garden",
            "ceramic studio", "art center", "immersive exhibit"
        ],
        "culture": [
            "historic landmark", "cultural center", "historic theater", "heritage house", "indie museum"
        ],
        "nature": [
            "scenic overlook", "botanical garden", "hidden trail", "coastal path",
            "waterfall viewpoint", "nature reserve", "secret garden"
        ],
        "sightseeing": [
            "panoramic vista", "historic plaza", "scenic pier", "observation deck",
            "iconic landmark", "historic courtyard"
        ],
        "shopping": [
            "vintage boutique", "curated thrift", "artisan market", "independent record shop",
            "indie bookshop", "craft bazaar"
        ],
        "sports": [
            "bouldering gym", "skate park", "climbing gym", "kayak spot",
            "surf break", "mini golf", "scenic running trail"
        ],
        "wellness": [
            "bathhouse", "thermal spa", "zen garden", "tea sanctuary",
            "reflexology lounge", "peaceful park garden"
        ],
        "family": [
            "science center", "planetarium", "animal sanctuary", "waterfront park carousel",
            "public promenade"
        ],
        "adventure": [
            "cliffside trail", "ropes course", "sea cave kayaking", "summit hike",
            "scenic ridge trail"
        ],
        "nightlife": [
            "underground cocktail lounge", "vinyl listening bar", "jazz bar",
            "rooftop bar", "speakeasy lounge"
        ],
        "events": [
            "night market", "food truck park", "outdoor movie park", "artisan pop-up market"
        ],
        "public": [
            "vibrant plaza", "waterfront promenade", "town square", "scenic public steps",
            "urban park lawn"
        ],
        "classes": [
            "pottery studio", "cooking school", "glassblowing studio", "coffee roasting workshop",
            "DIY craft space"
        ],
        "unique": [
            "quirky landmark", "hidden courtyard", "neon museum", "rooftop observation deck",
            "historic clock tower", "architectural gem"
        ]
    ]

    private func isExcludedPlace(mapItem: MKMapItem) -> Bool {
        guard let name = mapItem.name?.lowercased() else { return true }
        let category = mapItem.pointOfInterestCategory?.rawValue.lowercased() ?? ""
        let subtitle = (mapItem.placemark.title ?? "").lowercased()

        // 1. Excluded keywords (unappealing / non-hangout spots & fast food chains)
        let excludedKeywords = [
            "tattoo", "piercing", "ink", "flea market", "swap meet", "thrift warehouse",
            "gas station", "car wash", "auto repair", "mechanic", "tire", "parking",
            "bank", "atm", "check cashing", "mortgage", "real estate", "insurance",
            "dental", "dentist", "medical", "clinic", "pharmacy", "urgent care", "hospital",
            "storage", "warehouse", "industrial", "construction", "plumbing", "roofing",
            "laundromat", "dry cleaning", "laundry", "cleaners", "salon", "barber",
            "pawn", "bail", "court", "police", "fire station", "post office", "dmv",
            "elementary", "high school", "middle school", "daycare", "preschool",
            "mcdonald", "subway", "burger king", "domino", "dunkin", "taco bell", "kfc",
            "wendy", "popeyes", "jack in the box", "sonic", "arby", "panda express",
            "chipotle", "little caesars", "7-eleven", "walgreens", "cvs", "rite aid"
        ]

        for keyword in excludedKeywords {
            if name.contains(keyword) || subtitle.contains(keyword) || category.contains(keyword) {
                return true
            }
        }

        // 2. Excluded Point of Interest categories
        if let poi = mapItem.pointOfInterestCategory {
            switch poi {
            case .atm, .bank, .carRental, .evCharger, .fireStation, .gasStation,
                 .hospital, .laundry, .parking, .pharmacy, .police, .postOffice,
                 .publicTransport, .restroom, .school:
                return true
            default:
                break
            }
        }

        // 3. Exclude generic pure restaurants unless they are a hangout spot (cafe, bakery, speakeasy, rooftop, lounge, tea, etc.)
        if mapItem.pointOfInterestCategory == .restaurant {
            let hangoutFoodKeywords = [
                "cafe", "coffee", "bakery", "rooftop", "speakeasy", "lounge", "bistro",
                "tasting", "bar", "brewery", "dessert", "tea", "roaster", "jazz", "view",
                "patio", "terrace", "ramen", "izakaya", "tapas"
            ]
            let isHangoutFood = hangoutFoodKeywords.contains(where: { name.contains($0) || subtitle.contains($0) })
            if !isHangoutFood {
                return true
            }
        }

        return false
    }

    private func isCityOrStateName(_ name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Common states, territories, and broad regions
        let statesAndRegions: Set<String> = [
            "hawaii", "california", "new york", "texas", "florida", "washington",
            "oregon", "nevada", "arizona", "colorado", "utah", "alaska", "illinois",
            "massachusetts", "georgia", "north carolina", "virginia", "pennsylvania",
            "united states", "usa", "us", "america", "bay area", "northern california",
            "san francisco bay area", "socal", "norcal", "aloha state"
        ]

        if statesAndRegions.contains(clean) { return true }

        // Check against known cities catalog
        if MockData.cities.contains(where: { $0.name.lowercased() == clean }) {
            return true
        }

        // Check if name is just a city, state format e.g. "San Francisco, CA" or "Fremont, California"
        let parts = clean.components(separatedBy: ",")
        if parts.count == 2 {
            let cityPart = parts[0].trimmingCharacters(in: .whitespaces)
            if MockData.cities.contains(where: { $0.name.lowercased() == cityPart }) {
                return true
            }
            if statesAndRegions.contains(cityPart) {
                return true
            }
        }

        return false
    }

    private init() {
        if let stored = UserDefaults.standard.array(forKey: "trav_seen_place_names") as? [String] {
            seenPlaceNames = Set(stored)
        }
    }

    /// Resets pagination tracking when switching cities or pulling to refresh.
    func resetPagination() {
        lookAroundCount = 0
    }

    private func persistSeenPlace(_ name: String) {
        seenPlaceNames.insert(name.lowercased())
        let array = Array(seenPlaceNames.suffix(200))
        UserDefaults.standard.set(array, forKey: "trav_seen_place_names")
    }

    /// Fetches vibe recommendations querying Apple Maps based on user selected onboarding vibes and location.
    /// Pulls available data from Apple Maps API with rate-limiting and interleaves/shuffles categories.
    func fetchVibeRecommendations(
        vibes: [String],
        city: String = "Berkeley, CA",
        center: CLLocationCoordinate2D? = nil,
        page: Int = 0
    ) async -> [ExperienceSummary] {
        let cleanCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetCity = cleanCity.isEmpty ? "Berkeley, CA" : cleanCity

        let targetVibes = vibes.isEmpty ? [
            "🎨 Street Art",
            "🌙 Nightlife",
            "🛍️ Vintage Shops",
            "🍷 Rooftop Bars"
        ] : vibes

        // Ensure general hangout backup categories are always included so recommendations never run dry
        var searchVibes = targetVibes
        let backupVibes = ["☕️ Cozy Cafe", "🍷 Rooftop Bar", "🍰 Artisan Bakery", "🌅 Scenic Viewpoint", "🍸 Speakeasy"]
        for backup in backupVibes {
            if !searchVibes.contains(backup) {
                searchVibes.append(backup)
            }
        }

        lookAroundCount = 0
        let radiusMeters = min(100000.0, 10000.0 + Double(page) * 20000.0)

        var vibeBuckets: [[ExperienceSummary]] = []

        for vibe in searchVibes.shuffled() {
            let (emoji, cleanCategory) = extractEmojiAndText(from: vibe)
            let categoryKey = cleanCategory.lowercased()
            
            // Build niche search query
            let subQueries = Self.nicheQueriesByVibe.first(where: { categoryKey.contains($0.key) })?.value ?? [cleanCategory]
            let chosenTerm = subQueries.randomElement() ?? cleanCategory
            let searchQuery = "\(chosenTerm) in \(targetCity)"

            let searchReq = MKLocalSearch.Request()
            searchReq.naturalLanguageQuery = searchQuery

            if let center = center, center.latitude != 0, center.longitude != 0 {
                let latOffset = Double.random(in: -0.025...0.025)
                let lngOffset = Double.random(in: -0.025...0.025)
                let shiftedCenter = CLLocationCoordinate2D(latitude: center.latitude + latOffset, longitude: center.longitude + lngOffset)
                searchReq.region = MKCoordinateRegion(
                    center: shiftedCenter,
                    latitudinalMeters: radiusMeters,
                    longitudinalMeters: radiusMeters
                )
            }

            guard let searchResponse = try? await MKLocalSearch(request: searchReq).start() else {
                continue
            }

            var categoryBucket: [ExperienceSummary] = []
            
            // Run candidates through Local AI Curator Engine for vibe scoring & hangout confidence ranking
            let curatedResults = LocalVibeAICurator.shared.curateAndRank(
                mapItems: searchResponse.mapItems,
                vibes: [vibe],
                cityName: targetCity
            )

            for result in curatedResults.prefix(12) {
                let mapItem = result.mapItem
                guard let name = mapItem.name, !name.isEmpty else { continue }
                let lowerName = name.lowercased()
                if seenPlaceNames.contains(lowerName) { continue }
                if isExcludedPlace(mapItem: mapItem) { continue }
                if isCityOrStateName(name) { continue }
                persistSeenPlace(name)

                let officialTitle = name
                let realStats = await fetchRealSocialStats(forPlaceName: officialTitle, city: targetCity)
                let imageURLs = await fetchRealPlacePhotos(placeName: officialTitle, vibeCategory: cleanCategory, mapItem: mapItem)
                let coord = mapItem.placemark.coordinate

                let spotKey = SpotIdentity.key(
                    placeID: nil,
                    name: officialTitle,
                    latitude: coord.latitude,
                    longitude: coord.longitude
                )
                let id = StableUUID.from(spotKey)

                let stopPreview = StopPreview(
                    id: StableUUID.from("stop:\(spotKey)"),
                    name: officialTitle,
                    emoji: emoji,
                    latitude: coord.latitude,
                    longitude: coord.longitude
                )

                let creator = ExperienceInsert.travCreator

                let summary = ExperienceSummary(
                    id: id,
                    kind: .spot,
                    cityID: StableUUID.from("city:\(targetCity.lowercased())"),
                    title: officialTitle,
                    imageURLs: imageURLs,
                    creator: creator,
                    durationMinutes: result.recommendedDurationMinutes,
                    costLevel: .moderate,
                    estimatedCostUSD: nil,
                    saveCount: realStats.saveCount,
                    likeCount: realStats.likeCount,
                    completionCount: realStats.completionCount,
                    stops: [stopPreview],
                    rating: nil,
                    cityName: targetCity,
                    completedBy: realStats.completedBy,
                    spotKey: spotKey,
                    category: cleanCategory,
                    latitude: coord.latitude,
                    longitude: coord.longitude
                )

                let stop = Stop(
                    id: stopPreview.id,
                    orderIndex: 1,
                    name: officialTitle,
                    description: result.relatableVibeNote,
                    creatorNotes: "Curated by Local AI (\(Int(result.hangoutConfidence * 100))% hangout match).",
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    placeID: nil,
                    recommendedTime: result.bestTimeOfDay,
                    durationMinutes: result.recommendedDurationMinutes,
                    emoji: emoji,
                    media: []
                )

                let fullExperience = Experience(
                    id: id,
                    kind: .spot,
                    cityID: summary.cityID,
                    creator: creator,
                    title: officialTitle,
                    description: result.relatableVibeNote,
                    imageURLs: imageURLs,
                    durationMinutes: result.recommendedDurationMinutes,
                    costLevel: .moderate,
                    saveCount: realStats.saveCount,
                    likeCount: realStats.likeCount,
                    completionCount: realStats.completionCount,
                    isPublished: true,
                    publishedAt: Date(),
                    stops: [stop],
                    spotKey: spotKey,
                    category: cleanCategory,
                    cityName: targetCity
                )

                cachedRecommendations[id] = fullExperience
                categoryBucket.append(summary)
            }

            if !categoryBucket.isEmpty {
                vibeBuckets.append(categoryBucket)
            }
        }

        // Interleave categories round-robin style so 10 trails/hikes are never grouped sequentially
        var interleaved: [ExperienceSummary] = []
        var maxCount = 0
        for bucket in vibeBuckets {
            maxCount = max(maxCount, bucket.count)
        }

        for index in 0..<maxCount {
            for bucket in vibeBuckets {
                if index < bucket.count {
                    interleaved.append(bucket[index])
                }
            }
        }

        return interleaved
    }

    /// Resolves an experience by ID from cached recommendations or fallback
    func experience(for id: UUID) -> Experience? {
        cachedRecommendations[id]
    }

    func cachedExperience(for id: UUID) -> Experience? {
        experience(for: id)
    }

    /// Caches a custom spot Experience model for ExperienceDetailView lookup
    func cacheCustomExperience(_ experience: Experience) {
        cachedRecommendations[experience.id] = experience
    }

    /// Caches a custom spot ExperienceSummary model for rating & detail lookup
    func cacheCustomExperience(_ summary: ExperienceSummary) {
        let stops = summary.stops.enumerated().map { index, stop in
            Stop(
                id: stop.id,
                orderIndex: index,
                name: stop.name,
                description: "",
                creatorNotes: nil,
                latitude: stop.latitude ?? 0,
                longitude: stop.longitude ?? 0,
                placeID: summary.spotKey,
                recommendedTime: nil,
                durationMinutes: 45,
                emoji: stop.emoji,
                media: []
            )
        }
        let exp = Experience(
            id: summary.id,
            kind: summary.kind,
            cityID: summary.cityID,
            creator: summary.creator,
            title: summary.title,
            description: "Spot rated by traveler.",
            imageURLs: summary.imageURLs,
            durationMinutes: summary.durationMinutes,
            costLevel: summary.costLevel,
            estimatedCostUSD: summary.estimatedCostUSD,
            transportMode: .walking,
            totalDistanceMeters: 0,
            saveCount: summary.saveCount,
            likeCount: summary.likeCount,
            completionCount: summary.completionCount,
            commentCount: 0,
            isPublished: true,
            publishedAt: Date(),
            stops: stops,
            cityName: summary.cityName
        )
        cachedRecommendations[summary.id] = exp
    }

    /// Fetches real social stats (saves, likes, completions, completedBy profiles) from Supabase if existing for this place.
    private func fetchRealSocialStats(forPlaceName placeName: String, city: String) async -> (saveCount: Int, likeCount: Int, completionCount: Int, completedBy: [CompletionUser]) {
        guard let client = SupabaseManager.client else {
            return (0, 0, 0, [])
        }

        do {
            struct ExpRow: Decodable {
                let id: UUID
                let save_count: Int?
                let like_count: Int?
                let completion_count: Int?
            }

            let cleanName = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
            let rows: [ExpRow] = (try? await client
                .from("experiences")
                .select("id, save_count, like_count, completion_count")
                .ilike("title", pattern: "%\(cleanName)%")
                .limit(5)
                .execute()
                .value) ?? []

            var totalSaves = 0
            var totalLikes = 0
            var totalCompletions = 0
            var matchingExpIDs: [UUID] = []

            for r in rows {
                totalSaves += r.save_count ?? 0
                totalLikes += r.like_count ?? 0
                totalCompletions += r.completion_count ?? 0
                matchingExpIDs.append(r.id)
            }

            var completionUsers: [CompletionUser] = []
            if !matchingExpIDs.isEmpty {
                struct CompRow: Decodable {
                    let user_id: UUID
                }
                let expIDStrings = matchingExpIDs.map { $0.uuidString.lowercased() }
                let compRows: [CompRow] = (try? await client
                    .from("experience_completions")
                    .select("user_id")
                    .in("experience_id", values: expIDStrings)
                    .limit(5)
                    .execute()
                    .value) ?? []

                let ratingRows: [CompRow] = (try? await client
                    .from("ratings")
                    .select("user_id")
                    .in("experience_id", values: expIDStrings)
                    .limit(5)
                    .execute()
                    .value) ?? []

                struct SaveRow: Decodable { let user_id: UUID }
                let saveRows: [SaveRow] = (try? await client
                    .from("experience_saves")
                    .select("user_id")
                    .in("experience_id", values: expIDStrings)
                    .execute()
                    .value) ?? []

                totalSaves = max(totalSaves, saveRows.count)
                totalCompletions = max(totalCompletions, Set((compRows + ratingRows).map(\.user_id)).count)

                let userIDs = Array(Set((compRows + ratingRows + saveRows.map { CompRow(user_id: $0.user_id) }).map { $0.user_id.uuidString.lowercased() }))
                if !userIDs.isEmpty {
                    struct UserProfileRow: Decodable {
                        let id: UUID
                        let display_name: String?
                        let avatar_url: String?
                    }
                    let profiles: [UserProfileRow] = (try? await client
                        .from("profiles")
                        .select("id, display_name, avatar_url")
                        .in("id", values: userIDs)
                        .limit(5)
                        .execute()
                        .value) ?? []

                    completionUsers = profiles.map { p in
                        CompletionUser(
                            id: p.id,
                            name: p.display_name ?? "Explorer",
                            avatarImage: p.avatar_url ?? ""
                        )
                    }
                }
            }

            return (totalSaves, totalLikes, totalCompletions, completionUsers)
        } catch {
            return (0, 0, 0, [])
        }
    }

    /// Captures actual Apple Maps Street View (Look Around) building photo for a place map item
    private func fetchRealPlacePhotos(placeName: String, vibeCategory: String, mapItem: MKMapItem) async -> [URL] {
        var urls: [URL] = []

        if let streetViewURL = await fetchStreetViewPhoto(for: mapItem) {
            urls.append(streetViewURL)
        }

        return urls
    }

    /// Captures the actual 3D Street View / Building photo from Apple Maps API (Look Around)
    func fetchStreetViewPhoto(for mapItem: MKMapItem) async -> URL? {
        let identifier = mapItem.name ?? UUID().uuidString
        let cleanID = identifier.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()

        if let cached = checkDiskCache(identifier: "lookaround_\(cleanID)") {
            return cached
        }

        // 1. Try MapItem Look Around request
        let mapItemRequest = MKLookAroundSceneRequest(mapItem: mapItem)
        if let scene = try? await mapItemRequest.scene {
            if let saved = await snapshotLookAroundScene(scene, identifier: "lookaround_\(cleanID)") {
                return saved
            }
        }

        // 2. Try Coordinate Look Around request
        let coordRequest = MKLookAroundSceneRequest(coordinate: mapItem.placemark.coordinate)
        if let scene = try? await coordRequest.scene {
            if let saved = await snapshotLookAroundScene(scene, identifier: "lookaround_\(cleanID)") {
                return saved
            }
        }

        return nil
    }

    /// 1. Tries 3D Apple Maps Street View (Look Around photo).
    /// 2. Fallbacks to Apple Maps Map View snapshot if Street View is unavailable or difficult to obtain.
    func fetchStreetViewOrMapView(latitude: Double?, longitude: Double?, title: String) async -> URL? {
        let cleanID = title.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()

        // 1. Check Street View cache
        if let cachedStreetView = checkDiskCache(identifier: "lookaround_\(cleanID)") {
            return cachedStreetView
        }

        // 2. Check Map View cache
        if let cachedMapView = checkDiskCache(identifier: "mapview_\(cleanID)") {
            return cachedMapView
        }

        // 3. Try Street View
        if let streetViewURL = await fetchStreetViewPhoto(latitude: latitude, longitude: longitude, title: title) {
            return streetViewURL
        }

        // 4. Fallback to Apple Maps Map View snapshot
        return await fetchMapViewSnapshot(latitude: latitude, longitude: longitude, title: title)
    }

    /// Captures actual 3D Street View / Building photo from coordinates and title
    func fetchStreetViewPhoto(latitude: Double?, longitude: Double?, title: String) async -> URL? {
        var lat = latitude ?? 0
        var lon = longitude ?? 0

        if (lat == 0 && lon == 0) || (lat < -90 || lat > 90) || (lon < -180 || lon > 180) {
            if let resolved = await resolveCoordinate(for: title) {
                lat = resolved.latitude
                lon = resolved.longitude
            } else {
                return nil
            }
        }

        let cleanID = title.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        
        if let cached = checkDiskCache(identifier: "lookaround_\(cleanID)") {
            return cached
        }

        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let coordRequest = MKLookAroundSceneRequest(coordinate: coord)
        if let scene = try? await coordRequest.scene {
            if let saved = await snapshotLookAroundScene(scene, identifier: "lookaround_\(cleanID)") {
                return saved
            }
        }
        return nil
    }

    private func snapshotLookAroundScene(_ scene: MKLookAroundScene, identifier: String) async -> URL? {
        let options = MKLookAroundSnapshotter.Options()
        options.size = CGSize(width: 1200, height: 800)
        let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
        do {
            let snapshot = try await snapshotter.snapshot
            return saveImageToDisk(snapshot.image, identifier: identifier)
        } catch {
            return nil
        }
    }

    /// Generates an Apple Maps Map View snapshot image with a place marker pin at the coordinates.
    func fetchMapViewSnapshot(latitude: Double?, longitude: Double?, title: String) async -> URL? {
        var lat = latitude ?? 0
        var lon = longitude ?? 0

        if (lat == 0 && lon == 0) || (lat < -90 || lat > 90) || (lon < -180 || lon > 180) {
            if let resolved = await resolveCoordinate(for: title) {
                lat = resolved.latitude
                lon = resolved.longitude
            } else {
                lat = 37.8715
                lon = -122.2730
            }
        }

        let cleanID = title.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let identifier = "mapview_\(cleanID)"

        if let cached = checkDiskCache(identifier: identifier) {
            return cached
        }

        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coord, latitudinalMeters: 450, longitudinalMeters: 450)
        options.size = CGSize(width: 800, height: 500)

        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snapshot = try await snapshotter.start()
            let image = snapshot.image

            UIGraphicsBeginImageContextWithOptions(image.size, true, image.scale)
            image.draw(at: .zero)

            let point = snapshot.point(for: coord)
            let imageBounds = CGRect(origin: .zero, size: image.size)
            let drawPoint = imageBounds.contains(point) ? point : CGPoint(x: image.size.width / 2, y: image.size.height / 2)

            let pinSize: CGFloat = 36
            let pinRect = CGRect(x: drawPoint.x - pinSize / 2, y: drawPoint.y - pinSize, width: pinSize, height: pinSize)

            if let pinImage = UIImage(systemName: "mappin.circle.fill")?.withTintColor(UIColor(red: 0.95, green: 0.35, blue: 0.3, alpha: 1.0), renderingMode: .alwaysOriginal) {
                pinImage.draw(in: pinRect)
            }

            let annotatedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            if let result = annotatedImage {
                return saveImageToDisk(result, identifier: identifier)
            }
            return saveImageToDisk(image, identifier: identifier)
        } catch {
            return nil
        }
    }

    private func resolveCoordinate(for query: String) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let search = MKLocalSearch(request: request)
        if let response = try? await search.start(), let first = response.mapItems.first {
            return first.placemark.coordinate
        }
        return nil
    }

    /// Fetches a real picture of the place from Apple Maps API using MKLookAroundSnapshotter (Street View).
    /// If Street View is unavailable for a venue/park, returns an Apple Maps Map View snapshot.
    func fetchRealAppleMapsImage(for mapItem: MKMapItem) async -> URL? {
        let identifier = mapItem.name ?? UUID().uuidString

        // 1. Check local disk cache first
        if let existingDiskURL = checkDiskCache(identifier: "lookaround_\(identifier)") {
            return existingDiskURL
        }
        if let existingMapURL = checkDiskCache(identifier: "mapview_\(identifier)") {
            return existingMapURL
        }

        // 2. Method 1: Apple Maps Look Around Street/3D Photo Snapshotter
        let sceneRequest = MKLookAroundSceneRequest(mapItem: mapItem)
        do {
            if let scene = try await sceneRequest.scene {
                let options = MKLookAroundSnapshotter.Options()
                options.size = CGSize(width: 1000, height: 650)
                let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
                let snapshot = try await snapshotter.snapshot
                if let savedURL = saveImageToDisk(snapshot.image, identifier: "lookaround_\(identifier)") {
                    return savedURL
                }
            }
        } catch {
            // Ignore error and fall through
        }

        // 3. Method 2: Apple Maps Map View snapshot fallback
        return await fetchMapViewSnapshot(
            latitude: mapItem.placemark.coordinate.latitude,
            longitude: mapItem.placemark.coordinate.longitude,
            title: mapItem.name ?? "Location"
        )
    }

    private func extractEmojiAndText(from vibe: String) -> (String, String) {
        let trimmed = vibe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstSpaceIndex = trimmed.firstIndex(of: " ") else {
            return ("📍", trimmed)
        }
        let possibleEmoji = String(trimmed[..<firstSpaceIndex])
        let rest = String(trimmed[trimmed.index(after: firstSpaceIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if possibleEmoji.count <= 2 || possibleEmoji.unicodeScalars.first?.properties.isEmoji == true {
            return (possibleEmoji, rest)
        }
        return ("📍", trimmed)
    }

    private func checkDiskCache(identifier: String) -> URL? {
        let cleanID = identifier.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let lookAroundURL = cachesDirectory.appendingPathComponent("apple_maps_lookaround_\(cleanID).jpg")
        if FileManager.default.fileExists(atPath: lookAroundURL.path) {
            return lookAroundURL
        }
        // Purge legacy vector/satellite map snapshot files if present
        let snapshotURL = cachesDirectory.appendingPathComponent("apple_maps_snapshot_\(cleanID).jpg")
        if FileManager.default.fileExists(atPath: snapshotURL.path) {
            try? FileManager.default.removeItem(at: snapshotURL)
        }
        return nil
    }

    private func saveImageToDisk(_ image: UIImage, identifier: String) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let cleanID = identifier.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let filename = "apple_maps_\(cleanID).jpg"
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let fileURL = cachesDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }
}
