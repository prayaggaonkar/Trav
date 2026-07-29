import Foundation
import CoreLocation
import MapKit
import Supabase

/// Manages fetching real places from Apple Maps, deduplicating against existing Supabase database records,
/// and inserting structured multi-stop itineraries and single spots into Supabase without RLS errors.
@MainActor
final class SeedManager: ObservableObject {
    static let shared = SeedManager()

    private var client: SupabaseClient? {
        SupabaseManager.client
    }

    private init() {}

    /// Fetches diverse nearby Apple Maps POIs, deduplicates against existing database entries,
    /// constructs curated 2-3 stop itineraries & single spots, and inserts them into Supabase.
    func seedRealPlaces(coordinate: CLLocationCoordinate2D? = nil, city: String = "San Francisco") async {
        guard let client = client else {
            print("SeedManager: Supabase client unavailable.")
            return
        }

        let targetCity = city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "San Francisco" : city
        print("SeedManager: Fetching diverse Apple Maps places for '\(targetCity)'...")

        do {
            // 1. Fetch existing database records to perform deduplication
            struct ExistingExp: Decodable {
                let title: String
                let stops: [String]?
            }

            let existingRows: [ExistingExp] = (try? await client
                .from("experiences")
                .select("title, stops")
                .ilike("city", value: "%\(targetCity)%")
                .execute()
                .value) ?? []

            let existingTitles = Set(existingRows.map { $0.title.lowercased() })
            let existingStops = Set(existingRows.flatMap { $0.stops ?? [] }.map { $0.lowercased() })

            if !existingTitles.isEmpty {
                print("SeedManager: Found \(existingRows.count) existing experiences for \(targetCity). Deduplicating \(existingStops.count) place names.")
            }

            // 2. Fetch fresh, non-duplicate POIs from Apple Maps
            let categorized = await LocalPlaceFetcher.shared.fetchDiversePlaces(
                center: coordinate,
                city: targetCity,
                excludingStops: existingStops
            )

            guard !categorized.isEmpty else {
                print("SeedManager: All places in \(targetCity) are already seeded or no new MapKit places found.")
                return
            }

            print("SeedManager: MapKit returned \(categorized.count) new, non-duplicate places across categories for \(targetCity).")

            // 3. Always attribute seeded recommendations to official Rec by Trav user ID (00000000-0000-0000-0000-000000000000)
            let validUserID: UUID = ExperienceInsert.travAdminID

            // 4. Separate into category buckets
            let nature = categorized.filter { $0.category == .nature }.map { $0.mapItem.name ?? "Park" }
            let nightlife = categorized.filter { $0.category == .nightlife }.map { $0.mapItem.name ?? "Nightlife" }
            let sports = categorized.filter { $0.category == .sports }.map { $0.mapItem.name ?? "Stadium" }
            let culture = categorized.filter { $0.category == .culture }.map { $0.mapItem.name ?? "Museum" }
            let food = categorized.filter { $0.category == .food }.map { $0.mapItem.name ?? "Cafe" }

            var createdExperiences: [(title: String, stops: [String], desc: String)] = []

            // Multi-Stop Itinerary 1: Hikes & Local Brews/Bites
            if let h1 = nature.first, let f1 = food.first {
                let title = "Outdoor Hike & Local Eats in \(targetCity)"
                if !existingTitles.contains(title.lowercased()) {
                    createdExperiences.append((
                        title: title,
                        stops: [h1, f1],
                        desc: "Start with a refreshing hike at \(h1), followed by great food and drinks at \(f1)."
                    ))
                }
            }

            // Multi-Stop Itinerary 2: Arts, Dinner & Nightlife
            if let c1 = culture.first, let f2 = food.dropFirst().first ?? food.first, let n1 = nightlife.first {
                let title = "Arts & Nightlife Evening in \(targetCity)"
                if !existingTitles.contains(title.lowercased()) {
                    createdExperiences.append((
                        title: title,
                        stops: Array(Set([c1, f2, n1])),
                        desc: "A classic night out in \(targetCity): explore \(c1), enjoy dinner at \(f2), and wrap up with drinks at \(n1)."
                    ))
                }
            }

            // Multi-Stop Itinerary 3: Sports Activity & Hangout
            if let s1 = sports.first, let f3 = food.dropFirst(2).first ?? food.first {
                let title = "Sports & Local Hangout in \(targetCity)"
                if !existingTitles.contains(title.lowercased()) {
                    createdExperiences.append((
                        title: title,
                        stops: [s1, f3],
                        desc: "Catch an active sports outing at \(s1) and unwind at \(f3) afterwards."
                    ))
                }
            }

            // Multi-Stop Itinerary 4: Parks & Coffee Walk
            if let h2 = nature.dropFirst().first ?? nature.first, let c2 = food.first {
                let title = "Park Walk & Coffee in \(targetCity)"
                if !existingTitles.contains(title.lowercased()) {
                    createdExperiences.append((
                        title: title,
                        stops: Array(Set([h2, c2])),
                        desc: "Stroll through \(h2) with fresh coffee from \(c2)."
                    ))
                }
            }

            // Standalone Single-Spot Recommendations
            for n in nature.prefix(2) {
                let title = "\(n) — Scenic Spot in \(targetCity)"
                if !existingTitles.contains(title.lowercased()) {
                    createdExperiences.append((
                        title: title,
                        stops: [n],
                        desc: "An incredible outdoor park and trail spot in \(targetCity)."
                    ))
                }
            }
            for nl in nightlife.prefix(2) {
                let title = "\(nl) — Hotspot Nightlife in \(targetCity)"
                if !existingTitles.contains(title.lowercased()) {
                    createdExperiences.append((
                        title: title,
                        stops: [nl],
                        desc: "Top evening vibe and hangout location in \(targetCity)."
                    ))
                }
            }
            for sp in sports.prefix(2) {
                let title = "\(sp) — Sports & Recreation in \(targetCity)"
                if !existingTitles.contains(title.lowercased()) {
                    createdExperiences.append((
                        title: title,
                        stops: [sp],
                        desc: "Premier sports venue and recreation arena in \(targetCity)."
                    ))
                }
            }

            guard !createdExperiences.isEmpty else {
                print("SeedManager: All generated itineraries already exist in Supabase for \(targetCity).")
                return
            }

            // 5. Build inserts with NaturalLanguage vector embeddings
            let inserts: [ExperienceInsert] = createdExperiences.map { exp in
                let fullText = "\(exp.title). \(exp.desc) Stops: \(exp.stops.joined(separator: ", ")). City: \(targetCity)."
                let embedding = RecommendationService.shared.generateVector(forText: fullText)

                return ExperienceInsert(
                    id: UUID(),
                    user_id: validUserID,
                    title: exp.title,
                    city: targetCity,
                    stops: exp.stops,
                    description: exp.desc,
                    is_published: true,
                    embedding: embedding
                )
            }

            print("SeedManager: Inserting \(inserts.count) new, non-duplicate itineraries into Supabase...")

            try await client
                .from("experiences")
                .insert(inserts)
                .execute()

            print("SeedManager: Successfully inserted \(inserts.count) new multi-stop & single spot itineraries into Supabase for \(targetCity)!")
            TravLog.general.info("SeedManager: Successfully seeded \(inserts.count) new itineraries for \(targetCity)")
        } catch {
            print("SeedManager: Error inserting itineraries into Supabase: \(error)")
            TravLog.general.error("SeedManager: Failed to seed itineraries: \(error)")
        }
    }
}
