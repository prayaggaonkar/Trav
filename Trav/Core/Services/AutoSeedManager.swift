import Foundation
import CoreLocation
import MapKit
import Supabase
import Combine

/// Background manager to automatically generate high-quality, walkable itinerary recommendations
/// ("Recs by Trav") when a user enters an unseeded city.
@MainActor
final class AutoSeedManager: ObservableObject {
    static let shared = AutoSeedManager()

    private var activeSeedCities: Set<String> = []

    private init() {}

    /// Checks if a city has an official "Rec by Trav" experience in Supabase and generates a 3-stop itinerary if unseeded.
    @discardableResult
    func checkAndSeedCity(city: String) async -> Bool {
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCity.isEmpty else { return false }

        let normalizedKey = trimmedCity.lowercased()
        guard !activeSeedCities.contains(normalizedKey) else { return false }
        activeSeedCities.insert(normalizedKey)
        defer { activeSeedCities.remove(normalizedKey) }

        // Step A: Supabase check specifically for Trav Admin experience in this city
        guard let client = SupabaseManager.client else { return false }
        do {
            let response = try await client
                .from("experiences")
                .select("id", count: .exact)
                .eq("city", value: trimmedCity)
                .eq("user_id", value: ExperienceInsert.travAdminID.uuidString.lowercased())
                .execute()

            if (response.count ?? 0) > 0 {
                return false
            }
        } catch {
            TravLog.general.error("AutoSeedManager: Error querying existing experiences for \(trimmedCity): \(error)")
            return false
        }

        // Geocode city to find center coordinate
        let geocoder = CLGeocoder()
        guard let placemarks = try? await geocoder.geocodeAddressString(trimmedCity),
              let placemark = placemarks.first,
              let location = placemark.location else {
            return false
        }
        let cityCoordinate = location.coordinate

        // Step B: MapKit Search & Popularity Ranking
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmedCity
        request.region = MKCoordinateRegion(
            center: cityCoordinate,
            latitudinalMeters: 10000,
            longitudinalMeters: 10000
        )
        var poiCategories: [MKPointOfInterestCategory] = [
            .cafe,
            .bakery,
            .park,
            .museum,
            .restaurant,
            .nightlife,
            .brewery,
            .winery
        ]
        if #available(iOS 18.0, *) {
            poiCategories.append(.landmark)
        }
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: poiCategories)

        guard let searchResponse = try? await MKLocalSearch(request: request).start() else {
            return false
        }

        let mapItems = searchResponse.mapItems
        guard !mapItems.isEmpty else { return false }

        // Step C: Spatial Clustering & Time-of-Day Chronological Sorting
        func categoryWeight(for item: MKMapItem) -> Int? {
            guard let category = item.pointOfInterestCategory else { return nil }
            if category == .cafe || category == .bakery {
                return 1
            }
            if category == .museum || category == .park {
                return 2
            }
            if #available(iOS 18.0, *) {
                if category == .landmark {
                    return 2
                }
            }
            if category == .restaurant || category == .nightlife || category == .brewery || category == .winery {
                return 3
            }
            return nil
        }

        let morningCandidates = mapItems.filter { categoryWeight(for: $0) == 1 }
        let afternoonCandidates = mapItems.filter { categoryWeight(for: $0) == 2 }
        let eveningCandidates = mapItems.filter { categoryWeight(for: $0) == 3 }

        // Anchor Spot Selection: Find top-ranked Afternoon spot (Weight 2)
        guard let afternoonAnchor = afternoonCandidates.first ?? mapItems.first(where: { categoryWeight(for: $0) != nil }) else {
            return false
        }

        let anchorLocation = afternoonAnchor.placemark.location ?? CLLocation(
            latitude: afternoonAnchor.placemark.coordinate.latitude,
            longitude: afternoonAnchor.placemark.coordinate.longitude
        )

        // Walkability Filter: Candidate spots within 1,500 meters of anchor spot
        let walkableMorning = morningCandidates.filter { candidate in
            guard candidate !== afternoonAnchor else { return false }
            let candidateLoc = candidate.placemark.location ?? CLLocation(
                latitude: candidate.placemark.coordinate.latitude,
                longitude: candidate.placemark.coordinate.longitude
            )
            return anchorLocation.distance(from: candidateLoc) <= 1500
        }

        let walkableEvening = eveningCandidates.filter { candidate in
            guard candidate !== afternoonAnchor else { return false }
            let candidateLoc = candidate.placemark.location ?? CLLocation(
                latitude: candidate.placemark.coordinate.latitude,
                longitude: candidate.placemark.coordinate.longitude
            )
            return anchorLocation.distance(from: candidateLoc) <= 1500
        }

        guard let morningSpot = walkableMorning.first ?? morningCandidates.first(where: { $0 !== afternoonAnchor }) ?? mapItems.first(where: { $0 !== afternoonAnchor }) else {
            return false
        }

        guard let eveningSpot = walkableEvening.first ?? eveningCandidates.first(where: { $0 !== afternoonAnchor && $0 !== morningSpot }) ?? mapItems.first(where: { $0 !== afternoonAnchor && $0 !== morningSpot }) else {
            return false
        }

        let stops = [morningSpot, afternoonAnchor, eveningSpot]

        // Step D: Smart Description Templating & Database Insertion
        let description = generateItineraryDescription(stops: stops, city: trimmedCity)
        let title = "The Best of \(trimmedCity) in One Day"
        let stopNames = stops.compactMap { $0.name }

        let insertRecord = ExperienceInsert(
            title: title,
            city: trimmedCity,
            stops: stopNames,
            description: description
        )

        do {
            try await client
                .from("experiences")
                .insert(insertRecord)
                .execute()
            TravLog.general.info("AutoSeedManager: Successfully seeded itinerary for \(trimmedCity)")
            return true
        } catch {
            TravLog.general.error("AutoSeedManager: Failed to insert itinerary for \(trimmedCity): \(error)")
            return false
        }
    }

    /// Generates a natural 2-sentence itinerary description based on the spot categories.
    func generateItineraryDescription(stops: [MKMapItem], city: String) -> String {
        let morningName = stops.count > 0 ? (stops[0].name ?? "a local café") : "a local café"
        let afternoonName = stops.count > 1 ? (stops[1].name ?? "local landmarks") : "local landmarks"
        let eveningName = stops.count > 2 ? (stops[2].name ?? "a great dinner spot") : "a great dinner spot"

        let morningCategory = stops.first?.pointOfInterestCategory

        if morningCategory == .cafe || morningCategory == .bakery {
            return "A perfect 1-day loop in \(city): Start with coffee at \(morningName), explore \(afternoonName), and wrap up the evening at \(eveningName)."
        } else {
            return "The ultimate local day out in \(city), featuring stops at \(morningName), \(afternoonName), and \(eveningName)."
        }
    }
}
