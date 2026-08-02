import Foundation
import CoreLocation
import MapKit

/// How a typed query should bias location vs global recall.
enum SearchIntent: Sendable {
    case generic
    case uniqueName
    case mixed

    static func classify(_ query: String) -> SearchIntent {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .mixed }

        let tokens = trimmed
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return .mixed }

        let hasGeneric = tokens.contains { genericHangoutTokens.contains($0) }
        let looksProper: Bool = {
            let words = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard words.count >= 2 else {
                // Single capitalized token without generic meaning → unique-ish brand/place.
                if let first = words.first,
                   first.first?.isUppercase == true,
                   !genericHangoutTokens.contains(first.lowercased()) {
                    return true
                }
                return false
            }
            let capitalCount = words.filter { $0.first?.isUppercase == true }.count
            return capitalCount >= 2 || (capitalCount >= 1 && !hasGeneric)
        }()

        if tokens.count == 1 && hasGeneric {
            return .generic
        }
        if looksProper && !hasGeneric {
            return .uniqueName
        }
        if hasGeneric && tokens.count <= 2 {
            return .generic
        }
        if looksProper {
            return .uniqueName
        }
        return .mixed
    }

    private static let genericHangoutTokens: Set<String> = [
        "cafe", "café", "coffee", "restaurant", "bar", "pub", "bakery", "boba",
        "park", "beach", "trail", "hike", "museum", "gallery", "zoo", "aquarium",
        "spa", "yoga", "club", "nightlife", "mall", "market", "shop", "shopping",
        "bowling", "arcade", "karaoke", "theater", "theatre", "cinema", "golf",
        "gym", "stadium", "plaza", "pier", "boardwalk", "viewpoint", "lookout",
        "brewery", "winery", "dessert", "food", "brunch", "lunch", "dinner"
    ]

    /// Proximity weight used in spot scoring for this intent.
    var proximityWeight: Double {
        switch self {
        case .generic: return 0.20
        case .mixed: return 0.12
        case .uniqueName: return 0.05
        }
    }

    var textWeight: Double { 0.40 }
    var popularityWeight: Double { 0.30 }
    var hangoutWeight: Double { 0.10 }

    /// Regional search radius in meters.
    var localRadiusMeters: CLLocationDistance {
        switch self {
        case .generic: return 60_000
        case .mixed: return 80_000
        case .uniqueName: return 100_000
        }
    }
}

/// Shared scoring helpers for spots, cities, users, and experiences.
enum IntelligentSearchRanking {

    // MARK: - Saturation (mirrors feed popularity curve)

    static func saturate(_ value: Double, _ cap: Double) -> Double {
        guard cap > 0 else { return 0 }
        return min(1.0, value / cap)
    }

    static func popularityScore(saves: Int, completions: Int, likes: Int) -> Double {
        let raw = Double(saves) + 2.0 * Double(completions) + 0.5 * Double(likes)
        return saturate(raw, 60)
    }

    // MARK: - Text relevance

    static func textRelevance(candidate: String, query: String) -> Double {
        let c = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !c.isEmpty, !q.isEmpty else { return 0 }

        if c == q { return 1.0 }
        if c.hasPrefix(q) { return 0.92 }
        if c.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 0.8 }
        if c.contains(q) { return 0.62 }

        // Token overlap for multi-word queries.
        let qTokens = Set(q.split(whereSeparator: \.isWhitespace).map(String.init))
        let cTokens = Set(c.split(whereSeparator: \.isWhitespace).map(String.init))
        guard !qTokens.isEmpty else { return 0 }
        let overlap = Double(qTokens.intersection(cTokens).count) / Double(qTokens.count)
        return 0.35 * overlap
    }

    // MARK: - Proximity

    static func proximityScore(
        itemCoordinate: CLLocationCoordinate2D?,
        userCoordinate: CLLocationCoordinate2D?,
        intent: SearchIntent
    ) -> Double {
        guard let itemCoordinate, let userCoordinate,
              CLLocationCoordinate2DIsValid(itemCoordinate),
              CLLocationCoordinate2DIsValid(userCoordinate) else {
            return intent == .uniqueName ? 0.55 : 0.35
        }
        let meters = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
            .distance(from: CLLocation(latitude: itemCoordinate.latitude, longitude: itemCoordinate.longitude))
        // Soft decay: full score within ~5km, near-zero beyond ~150km.
        let score = exp(-meters / 45_000)
        return min(1.0, max(0.0, score))
    }

    // MARK: - Spot ranking

    static func scoreSpot(
        title: String,
        query: String,
        mapKitRankIndex: Int,
        mapKitCount: Int,
        saves: Int,
        completions: Int,
        likes: Int,
        coordinate: CLLocationCoordinate2D?,
        userCoordinate: CLLocationCoordinate2D?,
        intent: SearchIntent,
        hangoutConfidence: Double = 0.85
    ) -> Double {
        let text = textRelevance(candidate: title, query: query)
        let mapKitPrior: Double = {
            guard mapKitCount > 0 else { return 0.5 }
            return 1.0 - (Double(mapKitRankIndex) / Double(max(mapKitCount, 1)))
        }()
        let blendedText = 0.75 * text + 0.25 * mapKitPrior
        let popularity = popularityScore(saves: saves, completions: completions, likes: likes)
        let proximity = proximityScore(
            itemCoordinate: coordinate,
            userCoordinate: userCoordinate,
            intent: intent
        )

        // Renormalize when proximity weight shrinks for unique names.
        let pWeight = intent.proximityWeight
        let base = intent.textWeight + intent.popularityWeight + intent.hangoutWeight
        let tWeight = intent.textWeight / (base + pWeight) * (base + 0.20)
        let popWeight = intent.popularityWeight / (base + pWeight) * (base + 0.20)
        let hWeight = intent.hangoutWeight / (base + pWeight) * (base + 0.20)
        let proxWeight = pWeight / (base + pWeight) * (base + 0.20)

        return tWeight * blendedText
            + popWeight * popularity
            + proxWeight * proximity
            + hWeight * hangoutConfidence
    }

    // MARK: - Cities

    static let majorCityNames: [String] = [
        "San Francisco", "New York", "Tokyo", "Paris", "London", "Barcelona",
        "Rome", "Amsterdam", "Berlin", "Sydney", "Seoul", "Singapore",
        "Dubai", "Rio de Janeiro", "Mexico City", "Los Angeles", "Chicago", "Miami", "Kyoto",
        "Boston", "Seattle", "Austin", "Portland", "Denver", "Toronto", "Vancouver",
        "Madrid", "Lisbon", "Prague", "Vienna", "Bangkok", "Hong Kong", "Taipei"
    ]

    static func majorCityPrior(name: String) -> Double {
        let lower = name.lowercased()
        if let idx = majorCityNames.firstIndex(where: {
            lower == $0.lowercased()
                || lower.contains($0.lowercased())
                || $0.lowercased().contains(lower)
        }) {
            return 1.0 - (Double(idx) / Double(max(majorCityNames.count, 1))) * 0.5
        }
        return 0.15
    }

    static func scoreCity(
        name: String,
        countryName: String,
        query: String,
        experienceCount: Int,
        creatorCount: Int,
        coordinate: CLLocationCoordinate2D?,
        userCoordinate: CLLocationCoordinate2D?,
        intent: SearchIntent
    ) -> Double {
        let label = "\(name), \(countryName)"
        let text = max(
            textRelevance(candidate: name, query: query),
            textRelevance(candidate: label, query: query) * 0.9
        )
        let activity = saturate(Double(experienceCount) + 0.5 * Double(creatorCount), 40)
        let major = majorCityPrior(name: name)
        let proximity: Double = {
            guard intent != .uniqueName else { return 0.4 }
            return proximityScore(
                itemCoordinate: coordinate,
                userCoordinate: userCoordinate,
                intent: .generic
            )
        }()
        // 0.45 text + 0.35 activity + 0.15 major + 0.05 proximity (light)
        return 0.45 * text + 0.35 * activity + 0.15 * major + 0.05 * proximity
    }

    static func rankCatalogCities(
        _ cities: [City],
        query: String,
        userCoordinate: CLLocationCoordinate2D? = nil
    ) -> [City] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let intent = SearchIntent.classify(trimmed)
        return cities
            .filter {
                $0.name.localizedCaseInsensitiveContains(trimmed)
                    || $0.countryName.localizedCaseInsensitiveContains(trimmed)
                    || $0.locationLabel.localizedCaseInsensitiveContains(trimmed)
            }
            .map { city -> (City, Double) in
                let score = scoreCity(
                    name: city.name,
                    countryName: city.countryName,
                    query: trimmed,
                    experienceCount: city.experienceCount,
                    creatorCount: city.creatorCount,
                    coordinate: CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude),
                    userCoordinate: userCoordinate,
                    intent: intent
                )
                return (city, score)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    // MARK: - Users

    static func scoreUser(
        username: String,
        displayName: String,
        query: String,
        followerCount: Int,
        experienceCount: Int
    ) -> Double {
        let text = max(
            textRelevance(candidate: username, query: query),
            textRelevance(candidate: displayName, query: query) * 0.95
        )
        let followers = saturate(Double(followerCount), 500)
        let experiences = saturate(Double(experienceCount), 40)
        return 0.50 * text + 0.30 * followers + 0.20 * experiences
    }

    // MARK: - Experiences / itineraries

    static func scoreExperience(
        title: String,
        query: String,
        saves: Int,
        completions: Int,
        likes: Int
    ) -> Double {
        let text = textRelevance(candidate: title, query: query)
        let popularity = popularityScore(saves: saves, completions: completions, likes: likes)
        return 0.45 * text + 0.55 * popularity
    }

    static func rankExperiences(_ items: [ExperienceSummary], query: String) -> [ExperienceSummary] {
        items
            .map { item -> (ExperienceSummary, Double) in
                (
                    item,
                    scoreExperience(
                        title: item.title,
                        query: query,
                        saves: item.saveCount,
                        completions: item.completionCount,
                        likes: item.likeCount
                    )
                )
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}
