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
        "hike": ["hidden trail", "scenic overlook", "bouldering spot", "secret garden", "nature reserve", "scenic ridge", "waterfall trail", "coastal path"],
        "outdoors": ["botanical garden", "panoramic lookout", "cliffside trail", "community garden", "hidden cove", "sunset point", "arboretum"],
        "food": ["speakeasy", "artisan bakery", "hole in the wall", "family-owned bistro", "rooftop terrace", "tasting room", "local deli", "handcrafted noodles"],
        "nightlife": ["jazz club", "underground lounge", "craft cocktail bar", "vinyl listening bar", "speakeasy lounge", "local venue"],
        "art": ["indie bookstore", "niche gallery", "sculpture garden", "vintage vinyl", "artist studio", "historic theater", "ceramic studio"],
        "shopping": ["vintage boutique", "flea market", "curated thrift", "artisan market", "antique hall", "independent record shop"]
    ]

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

        lookAroundCount = 0

        let radiusMeters: Double
        switch page {
        case 0: radiusMeters = 8000
        case 1: radiusMeters = 20000
        case 2: radiusMeters = 40000
        default: radiusMeters = 60000
        }

        var vibeBuckets: [[ExperienceSummary]] = []

        for vibe in targetVibes.shuffled() {
            let (emoji, cleanCategory) = extractEmojiAndText(from: vibe)
            let categoryKey = cleanCategory.lowercased()
            
            // Build niche search query
            let subQueries = Self.nicheQueriesByVibe.first(where: { categoryKey.contains($0.key) })?.value ?? [cleanCategory]
            let chosenTerm = subQueries.randomElement() ?? cleanCategory
            let searchQuery = "\(chosenTerm) in \(targetCity)"

            let searchReq = MKLocalSearch.Request()
            searchReq.naturalLanguageQuery = searchQuery

            if let center = center, center.latitude != 0, center.longitude != 0 {
                // Add slight coordinate perturbation to explore different neighborhoods on each launch
                let latOffset = Double.random(in: -0.015...0.015)
                let lngOffset = Double.random(in: -0.015...0.015)
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
            let candidateItems = Array(searchResponse.mapItems.shuffled().prefix(6))

            for mapItem in candidateItems {
                guard let name = mapItem.name, !name.isEmpty else { continue }
                let lowerName = name.lowercased()
                if seenPlaceNames.contains(lowerName) { continue }
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
                    durationMinutes: 45,
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
                    description: mapItem.placemark.title ?? officialTitle,
                    creatorNotes: "Discovered via Apple Maps.",
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    placeID: nil,
                    recommendedTime: nil,
                    durationMinutes: 45,
                    emoji: emoji,
                    media: []
                )

                let fullExperience = Experience(
                    id: id,
                    kind: .spot,
                    cityID: summary.cityID,
                    creator: creator,
                    title: officialTitle,
                    description: mapItem.placemark.title ?? "A curated \(cleanCategory) spot in \(targetCity).",
                    imageURLs: imageURLs,
                    durationMinutes: 45,
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

        return interleaved.shuffled()
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

    /// Captures actual 3D Street View / Building photo from coordinates and title
    func fetchStreetViewPhoto(latitude: Double?, longitude: Double?, title: String) async -> URL? {
        guard let lat = latitude, let lon = longitude, lat != 0, lon != 0 else { return nil }
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

    /// Fetches a real picture of the place from Apple Maps API using MKLookAroundSnapshotter (Street View)
    /// If Street View is unavailable for a venue/park, returns a real photographic location photo instead of a map drawing.
    func fetchRealAppleMapsImage(for mapItem: MKMapItem) async -> URL? {
        let identifier = mapItem.name ?? UUID().uuidString

        // 1. Check local disk cache first (real Look Around street view image)
        if let existingDiskURL = checkDiskCache(identifier: identifier) {
            return existingDiskURL
        }

        // 2. Method 1: Apple Maps Look Around Street/3D Photo Snapshotter (Real Street View photo)
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
            // Ignore error and fall through to real location photo
        }

        // 3. Method 2: Real Photographic Location Photo (high-resolution real photo of place type, NO map drawings!)
        return getRealCategoryPhoto(for: mapItem)
    }

    private func getRealCategoryPhoto(for mapItem: MKMapItem) -> URL {
        let nameLower = (mapItem.name ?? "").lowercased()
        let category = mapItem.pointOfInterestCategory?.rawValue.lowercased() ?? ""

        if nameLower.contains("park") || nameLower.contains("garden") || nameLower.contains("trail") || category.contains("park") {
            return URL(string: "https://images.unsplash.com/photo-1519331379826-f10be5486c6f?w=1000&q=80")!
        }
        if nameLower.contains("coffee") || nameLower.contains("cafe") || nameLower.contains("roaster") || category.contains("cafe") {
            return URL(string: "https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?w=1000&q=80")!
        }
        if nameLower.contains("bakery") || nameLower.contains("pastry") || nameLower.contains("bread") || category.contains("bakery") {
            return URL(string: "https://images.unsplash.com/photo-1509440159596-0249088772ff?w=1000&q=80")!
        }
        if nameLower.contains("pizza") || nameLower.contains("burger") || nameLower.contains("taco") || nameLower.contains("sushi") || category.contains("restaurant") {
            return URL(string: "https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=1000&q=80")!
        }
        if nameLower.contains("beach") || nameLower.contains("cove") || nameLower.contains("pier") || category.contains("beach") {
            return URL(string: "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=1000&q=80")!
        }
        if nameLower.contains("museum") || nameLower.contains("art") || nameLower.contains("gallery") || category.contains("museum") {
            return URL(string: "https://images.unsplash.com/photo-1565008447742-97f6f38c985c?w=1000&q=80")!
        }
        return URL(string: "https://images.unsplash.com/photo-1519501025264-65ba15a82390?w=1000&q=80")!
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
