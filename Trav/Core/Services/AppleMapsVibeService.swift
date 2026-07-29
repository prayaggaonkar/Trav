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

    private init() {}

    /// Resets pagination tracking when switching cities or pulling to refresh.
    func resetPagination() {
        seenPlaceNames.removeAll()
        cachedSummariesByCityAndVibes.removeAll()
        lookAroundCount = 0
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

        // Reset LookAround counter per page fetch cycle to stay well under GeoServices 50 requests/min throttle limit
        lookAroundCount = 0

        // Expand radius dynamically on subsequent scroll pages
        let radiusMeters: Double
        switch page {
        case 0: radiusMeters = 8000
        case 1: radiusMeters = 20000
        case 2: radiusMeters = 40000
        default: radiusMeters = 60000
        }

        var vibeBuckets: [[ExperienceSummary]] = []

        for vibe in targetVibes {
            let (emoji, cleanCategory) = extractEmojiAndText(from: vibe)
            let searchQuery = "\(cleanCategory) in \(targetCity)"

            let searchReq = MKLocalSearch.Request()
            searchReq.naturalLanguageQuery = searchQuery

            if let center = center, center.latitude != 0, center.longitude != 0 {
                searchReq.region = MKCoordinateRegion(
                    center: center,
                    latitudinalMeters: radiusMeters,
                    longitudinalMeters: radiusMeters
                )
            }

            guard let searchResponse = try? await MKLocalSearch(request: searchReq).start() else {
                continue
            }

            var categoryBucket: [ExperienceSummary] = []
            
            // Limit to top 6 items per vibe category per page to prevent bursting GeoServices XPC request limit
            let candidateItems = Array(searchResponse.mapItems.prefix(6))

            for mapItem in candidateItems {
                guard let name = mapItem.name, !name.isEmpty else { continue }
                let lowerName = name.lowercased()
                if seenPlaceNames.contains(lowerName) { continue }
                seenPlaceNames.insert(lowerName)

                // Official place name (no emdash!)
                let officialTitle = name

                // Real Supabase data for saves/watchlists for this place if it exists
                let realStats = await fetchRealSocialStats(forPlaceName: officialTitle, city: targetCity)

                // Fetch real images that come from the Apple Maps API (throttled & disk-cached)
                let imageURL = await fetchRealAppleMapsImage(for: mapItem)

                let id = UUID()
                let coord = mapItem.placemark.coordinate
                
                let stopPreview = StopPreview(
                    id: UUID(),
                    name: officialTitle,
                    emoji: emoji,
                    latitude: coord.latitude,
                    longitude: coord.longitude
                )

                let creator = ProfileSummary(
                    id: ExperienceInsert.travAdminID,
                    username: "trav",
                    displayName: "Rec by Trav",
                    avatarURL: nil,
                    isVerified: true
                )

                let imageURLs = imageURL != nil ? [imageURL!] : []

                let summary = ExperienceSummary(
                    id: id,
                    cityID: UUID(),
                    title: officialTitle, // Official name only!
                    imageURLs: imageURLs,
                    creator: creator,
                    durationMinutes: 45,
                    costLevel: .moderate,
                    estimatedCostUSD: nil,
                    saveCount: realStats.saveCount,
                    likeCount: realStats.likeCount,
                    completionCount: realStats.completionCount,
                    stops: [stopPreview],
                    rating: nil, // Don't give these types of recommendations a rating
                    cityName: targetCity,
                    watchlistedBy: realStats.watchlistedBy
                )

                // Store in-memory Experience model for detail view lookup
                let stop = Stop(
                    id: stopPreview.id,
                    orderIndex: 1,
                    name: officialTitle,
                    description: "Apple Maps recommendation based on your \(vibe) preference in \(targetCity).",
                    creatorNotes: "Discovered via Apple Maps.",
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    placeID: nil,
                    recommendedTime: nil,
                    durationMinutes: 45,
                    emoji: emoji,
                    media: []
                )

                let experience = Experience(
                    id: id,
                    cityID: summary.cityID,
                    creator: creator,
                    title: summary.title,
                    description: "Featured \(cleanCategory) recommendation in \(targetCity), sourced directly from Apple Maps based on your vibe profile.",
                    imageURLs: imageURLs,
                    durationMinutes: 45,
                    costLevel: .moderate,
                    estimatedCostUSD: nil,
                    transportMode: .walking,
                    totalDistanceMeters: 0,
                    saveCount: summary.saveCount,
                    likeCount: summary.likeCount,
                    completionCount: summary.completionCount,
                    commentCount: 0,
                    isPublished: true,
                    publishedAt: Date(),
                    stops: [stop],
                    routeSegments: [],
                    rating: nil // Don't give these types of recommendations a rating
                )

                cachedRecommendations[id] = experience
                categoryBucket.append(summary)
            }

            if !categoryBucket.isEmpty {
                vibeBuckets.append(categoryBucket.shuffled())
            }
        }

        // Interleave categories round-robin so the feed isn't just a bunch of the same vibe in a row
        var interleavedSummaries: [ExperienceSummary] = []
        let maxBucketSize = vibeBuckets.map(\.count).max() ?? 0

        for index in 0..<maxBucketSize {
            for bucket in vibeBuckets {
                if index < bucket.count {
                    interleavedSummaries.append(bucket[index])
                }
            }
        }

        return interleavedSummaries
    }

    /// Looks up a cached Apple Maps recommendation Experience by ID
    func cachedExperience(for id: UUID) -> Experience? {
        cachedRecommendations[id]
    }

    /// Fetches real social stats (saves, likes, completions, watchlistedBy profiles) from Supabase if existing for this place.
    private func fetchRealSocialStats(forPlaceName placeName: String, city: String) async -> (saveCount: Int, likeCount: Int, completionCount: Int, watchlistedBy: [WatchlistUser]) {
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

            var watchlistUsers: [WatchlistUser] = []
            if !matchingExpIDs.isEmpty {
                struct SaveRow: Decodable {
                    let user_id: UUID
                }
                let expIDStrings = matchingExpIDs.map { $0.uuidString.lowercased() }
                let saveRows: [SaveRow] = (try? await client
                    .from("experience_saves")
                    .select("user_id")
                    .in("experience_id", values: expIDStrings)
                    .limit(5)
                    .execute()
                    .value) ?? []

                let userIDs = Array(Set(saveRows.map { $0.user_id.uuidString.lowercased() }))
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
                        .limit(3)
                        .execute()
                        .value) ?? []

                    watchlistUsers = profiles.map { p in
                        WatchlistUser(
                            id: p.id,
                            name: p.display_name ?? "Explorer",
                            avatarImage: p.avatar_url ?? ""
                        )
                    }
                }
            }

            return (totalSaves, totalLikes, totalCompletions, watchlistUsers)
        } catch {
            return (0, 0, 0, [])
        }
    }

    /// Fetches a real image from Apple Maps API using MKLookAroundSnapshotter or MKMapSnapshotter
    /// Includes disk caching and request throttling to prevent GEOErrorDomain Code=-3 (REQUEST_TYPE_PLACE_REFINEMENT throttled).
    func fetchRealAppleMapsImage(for mapItem: MKMapItem) async -> URL? {
        let identifier = mapItem.name ?? UUID().uuidString

        // 1. Check local disk cache first (0 network calls)
        if let existingDiskURL = checkDiskCache(identifier: identifier) {
            return existingDiskURL
        }

        // 2. Method 1: Apple Maps Look Around Street/3D Photo Snapshotter (Max 2 per page cycle to avoid GeoServices throttling)
        if lookAroundCount < 2 {
            lookAroundCount += 1
            let sceneRequest = MKLookAroundSceneRequest(mapItem: mapItem)
            do {
                if let scene = try await sceneRequest.scene {
                    let options = MKLookAroundSnapshotter.Options()
                    options.size = CGSize(width: 800, height: 500)
                    let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
                    let snapshot = try await snapshotter.snapshot
                    if let savedURL = saveImageToDisk(snapshot.image, identifier: "lookaround_\(identifier)") {
                        return savedURL
                    }
                }
            } catch {
                // Ignore throttling / scene failure and fall through to MKMapSnapshotter
            }
        }

        // 3. Method 2: Apple Maps Map Snapshotter (high-res hybrid satellite/vector map imagery with POI pin)
        // Does NOT issue PlaceRequest.REQUEST_TYPE_PLACE_REFINEMENT GeoServices calls
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: mapItem.placemark.coordinate,
            latitudinalMeters: 300,
            longitudinalMeters: 300
        )
        options.mapType = .hybrid
        options.size = CGSize(width: 800, height: 500)
        options.pointOfInterestFilter = .includingAll

        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snapshot = try await snapshotter.start()
            if let savedURL = saveImageToDisk(snapshot.image, identifier: "snapshot_\(identifier)") {
                return savedURL
            }
        } catch {
            return nil
        }

        return nil
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
        let snapshotURL = cachesDirectory.appendingPathComponent("apple_maps_snapshot_\(cleanID).jpg")
        if FileManager.default.fileExists(atPath: snapshotURL.path) {
            return snapshotURL
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
