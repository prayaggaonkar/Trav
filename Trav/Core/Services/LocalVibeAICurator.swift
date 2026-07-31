import Foundation
@preconcurrency import MapKit
import NaturalLanguage

/// Structure representing the local AI evaluation of a place recommendation.
struct LocalAICurationResult {
    let mapItem: MKMapItem
    let vibeScore: Double
    let hangoutConfidence: Double
    let relatableVibeNote: String
    let recommendedDurationMinutes: Int
    let bestTimeOfDay: String
}

/// On-Device Local AI Recommendation Curator Engine.
/// Leverages Apple's NaturalLanguage framework and local ML feature scoring heuristics
/// to evaluate candidate places from Apple Maps, rank them by hangout quality,
/// generate relatable local insider tips, and adapt to the user's local taste profile over time.
final class LocalVibeAICurator: @unchecked Sendable {
    static let shared = LocalVibeAICurator()

    private let embedding = NLEmbedding.wordEmbedding(for: .english)
    private var tasteProfile: [String: Double] = [:]

    private init() {
        loadTasteProfile()
    }

    // MARK: - On-Device Taste Profile Adaptation

    private func loadTasteProfile() {
        if let stored = UserDefaults.standard.dictionary(forKey: "trav_local_ai_taste_profile") as? [String: Double] {
            tasteProfile = stored
        } else {
            // Default baseline weights for high-quality hangout categories
            tasteProfile = [
                "cozy": 0.85,
                "scenic": 0.90,
                "coffee": 0.80,
                "view": 0.92,
                "bakery": 0.82,
                "sunset": 0.95,
                "speakeasy": 0.88,
                "bookstore": 0.80,
                "park": 0.85,
                "cocktail": 0.87,
                "art": 0.78
            ]
        }
    }

    /// Updates the local AI taste profile when user saves or rates a spot.
    func recordUserEngagement(vibeCategory: String, rating: Double = 8.5) {
        let key = vibeCategory.lowercased()
        let currentWeight = tasteProfile[key] ?? 0.5
        let boost = (rating / 10.0) * 0.1
        tasteProfile[key] = min(1.0, currentWeight + boost)
        UserDefaults.standard.set(tasteProfile, forKey: "trav_local_ai_taste_profile")
    }

    // MARK: - Local AI Curation & Ranking Engine

    /// Evaluates candidate MKMapItems and ranks them using local AI vibe scoring and relatability heuristics.
    func curateAndRank(
        mapItems: [MKMapItem],
        vibes: [String],
        cityName: String
    ) -> [LocalAICurationResult] {
        var results: [LocalAICurationResult] = []

        for mapItem in mapItems {
            guard let name = mapItem.name, !name.isEmpty else { continue }

            let vibeScore = computeVibeMatchScore(mapItem: mapItem, targetVibes: vibes)
            let hangoutConfidence = computeHangoutConfidence(mapItem: mapItem)

            // AI Quality Threshold: Filter out mediocre or low-hangout spots (< 0.60)
            guard hangoutConfidence >= 0.60 && vibeScore >= 0.40 else { continue }

            let note = generateRelatableVibeNote(mapItem: mapItem, category: mapItem.pointOfInterestCategory?.rawValue ?? "")
            let duration = determineDuration(mapItem: mapItem)
            let timeOfDay = determineBestTimeOfDay(mapItem: mapItem)

            results.append(
                LocalAICurationResult(
                    mapItem: mapItem,
                    vibeScore: vibeScore,
                    hangoutConfidence: hangoutConfidence,
                    relatableVibeNote: note,
                    recommendedDurationMinutes: duration,
                    bestTimeOfDay: timeOfDay
                )
            )
        }

        // Rank candidates by composite score: 60% Vibe Match + 40% Hangout Confidence
        return results.sorted { a, b in
            let scoreA = (a.vibeScore * 0.60) + (a.hangoutConfidence * 0.40)
            let scoreB = (b.vibeScore * 0.60) + (b.hangoutConfidence * 0.40)
            return scoreA > scoreB
        }
    }

    // MARK: - Scoring Logic

    private func computeVibeMatchScore(mapItem: MKMapItem, targetVibes: [String]) -> Double {
        let name = (mapItem.name ?? "").lowercased()
        let category = (mapItem.pointOfInterestCategory?.rawValue ?? "").lowercased()
        let title = (mapItem.placemark.title ?? "").lowercased()
        let combinedText = "\(name) \(category) \(title)"

        var maxSimilarity: Double = 0.50

        // 1. Check against user selected onboarding vibes
        for vibe in targetVibes {
            let cleanVibe = vibe.replacingOccurrences(of: "[^a-zA-Z ]", with: "", options: .regularExpression).lowercased()

            if combinedText.contains(cleanVibe) {
                maxSimilarity = max(maxSimilarity, 0.95)
            } else if let embedding {
                // Calculate semantic similarity using Apple NL Natural Language embedding
                let distance = embedding.distance(between: name, and: cleanVibe, distanceType: .cosine)
                if !distance.isNaN {
                    let similarity = max(0.0, 1.0 - distance)
                    maxSimilarity = max(maxSimilarity, similarity)
                }
            }
        }

        // 2. Weight by local taste profile
        for (tasteKey, weight) in tasteProfile {
            if combinedText.contains(tasteKey) {
                maxSimilarity = min(1.0, maxSimilarity + (weight * 0.15))
            }
        }

        return maxSimilarity
    }

    private func computeHangoutConfidence(mapItem: MKMapItem) -> Double {
        var score: Double = 0.70

        guard let poi = mapItem.pointOfInterestCategory else {
            return mapItem.name?.lowercased().contains("park") == true ? 0.85 : 0.65
        }

        switch poi {
        case .cafe, .bakery, .brewery, .winery:
            score += 0.20
        case .park, .nationalPark, .beach:
            score += 0.22
        case .nightlife, .restaurant:
            score += 0.18
        case .museum, .theater, .movieTheater:
            score += 0.15
        case .store:
            let name = (mapItem.name ?? "").lowercased()
            if name.contains("book") || name.contains("vintage") || name.contains("records") {
                score += 0.15
            } else {
                score -= 0.10
            }
        default:
            score -= 0.05
        }

        return min(1.0, max(0.0, score))
    }

    // MARK: - Relatable Local Vibe Note Synthesis

    func generateRelatableVibeNote(mapItem: MKMapItem, category: String) -> String {
        let name = mapItem.name ?? "This spot"
        let nameLower = name.lowercased()
        let categoryLower = category.lowercased()

        if nameLower.contains("coffee") || nameLower.contains("roaster") || categoryLower.contains("cafe") {
            return "Cozy neighborhood spot for a slow morning brew and fresh pastries."
        }
        if nameLower.contains("bakery") || nameLower.contains("pastry") || categoryLower.contains("bakery") {
            return "Local favorite for warm artisanal baked goods and sweet treats."
        }
        if nameLower.contains("park") || nameLower.contains("lookout") || nameLower.contains("view") || nameLower.contains("ridge") || categoryLower.contains("park") {
            return "Great outdoor spot to catch panoramic sunset views and relax with friends."
        }
        if nameLower.contains("trail") || nameLower.contains("hike") || nameLower.contains("peak") {
            return "Invigorating scenic walk with beautiful nature and fresh air."
        }
        if nameLower.contains("cocktail") || nameLower.contains("speakeasy") || nameLower.contains("lounge") || categoryLower.contains("nightlife") {
            return "Intimate evening hangout with handcrafted drinks and great ambient lighting."
        }
        if nameLower.contains("book") || nameLower.contains("gallery") || nameLower.contains("art") || categoryLower.contains("museum") {
            return "Inspiring spot to wander through curated collections and creative finds."
        }

        return "A curated local gem perfect for a relaxed hangout."
    }

    private func determineDuration(mapItem: MKMapItem) -> Int {
        let category = (mapItem.pointOfInterestCategory?.rawValue ?? "").lowercased()
        let name = (mapItem.name ?? "").lowercased()

        if name.contains("trail") || name.contains("hike") || category.contains("park") { return 75 }
        if category.contains("museum") || category.contains("theater") { return 90 }
        if category.contains("cafe") || category.contains("bakery") { return 45 }
        if category.contains("nightlife") || category.contains("brewery") { return 60 }
        return 45
    }

    private func determineBestTimeOfDay(mapItem: MKMapItem) -> String {
        let category = (mapItem.pointOfInterestCategory?.rawValue ?? "").lowercased()
        let name = (mapItem.name ?? "").lowercased()

        if name.contains("coffee") || name.contains("bakery") || category.contains("cafe") { return "Morning" }
        if name.contains("sunset") || name.contains("lookout") || name.contains("view") { return "Golden Hour" }
        if category.contains("nightlife") || name.contains("cocktail") || name.contains("speakeasy") { return "Evening" }
        return "Afternoon"
    }
}
