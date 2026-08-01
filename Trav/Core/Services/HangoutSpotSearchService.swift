import Foundation
import MapKit
import CoreLocation

/// Unified hangout-spot search: dual MapKit fetch, Trav engagement enrich, intent-aware rank.
enum HangoutSpotSearchService {
    static let defaultDebounceMilliseconds: UInt64 = 220

    /// Searches eligible hangout spots for `query`, ranked for Trav.
    static func search(
        query: String,
        userCoordinate: CLLocationCoordinate2D?,
        limit: Int = 15
    ) async -> [SpotSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let intent = SearchIntent.classify(trimmed)

        async let localItems = fetchMapItems(
            query: trimmed,
            center: userCoordinate,
            radiusMeters: intent.localRadiusMeters
        )
        async let globalItems = fetchMapItems(
            query: trimmed,
            center: nil,
            radiusMeters: nil
        )

        let local = await localItems
        let global = await globalItems

        var merged: [MKMapItem] = []
        var seen = Set<String>()

        // Prefer local order first for generic intents; global first for unique names.
        let primary = intent == .uniqueName ? global : local
        let secondary = intent == .uniqueName ? local : global
        for item in primary + secondary {
            guard HangoutSpotFilter.isEligibleSpot(item) else { continue }
            guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
            let coord = item.placemark.coordinate
            let key = "\(name.lowercased())|\(String(format: "%.4f", coord.latitude))|\(String(format: "%.4f", coord.longitude))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(item)
        }

        guard !merged.isEmpty else { return [] }

        let names = merged.compactMap { $0.name }
        let engagement = await SpotEngagementLookup.stats(forPlaceNames: names)

        let scored: [(SpotSuggestion, Double)] = merged.enumerated().compactMap { index, item in
            guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return nil
            }
            let subtitle = item.placemark.title ?? ""
            let coord = item.placemark.coordinate
            let stats = engagement[name.lowercased()] ?? .zero
            let category = HangoutSpotFilter.category(for: item)
            let score = IntelligentSearchRanking.scoreSpot(
                title: name,
                query: trimmed,
                mapKitRankIndex: index,
                mapKitCount: merged.count,
                saves: stats.saveCount,
                completions: stats.completionCount,
                likes: stats.likeCount,
                coordinate: coord,
                userCoordinate: userCoordinate,
                intent: intent,
                hangoutConfidence: 0.9
            )
            let suggestion = SpotSuggestion(
                id: "spot|\(name)|\(subtitle)|\(coord.latitude),\(coord.longitude)",
                title: name,
                subtitle: subtitle,
                category: category,
                latitude: coord.latitude,
                longitude: coord.longitude
            )
            return (suggestion, score)
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    // MARK: - MapKit

    private static func fetchMapItems(
        query: String,
        center: CLLocationCoordinate2D?,
        radiusMeters: CLLocationDistance?
    ) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = HangoutSpotFilter.pointOfInterestFilter

        if let center, let radiusMeters, CLLocationCoordinate2DIsValid(center) {
            request.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: radiusMeters,
                longitudinalMeters: radiusMeters
            )
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems
        } catch {
            return []
        }
    }
}
