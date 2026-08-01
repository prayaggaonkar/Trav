import Foundation
import MapKit
import CoreLocation

/// Category tag for MapKit POIs
public enum POICategoryType: String, Sendable {
    case nature = "Hikes & Outdoors"
    case nightlife = "Nightlife & Bars"
    case sports = "Sports & Activities"
    case culture = "Arts"
    case food = "Eats & Hangouts"
}

public struct CategorizedPOI: @unchecked Sendable {
    public let mapItem: MKMapItem
    public let category: POICategoryType

    public init(mapItem: MKMapItem, category: POICategoryType) {
        self.mapItem = mapItem
        self.category = category
    }
}

/// MapKit Data Fetcher that queries real places and points of interest across diverse categories using Apple Maps.
/// Designed to continuously discover new places with expanding radiuses and neighborhood fallbacks.
public final class LocalPlaceFetcher: Sendable {
    public static let shared = LocalPlaceFetcher()

    private init() {}

    /// Fetches diverse nearby points of interest, dynamically expanding radiuses and search keywords
    /// so place discovery NEVER stops even when a location is heavily seeded.
    public func fetchDiversePlaces(
        center: CLLocationCoordinate2D? = nil,
        radius: CLLocationDistance = 3000,
        city: String = "San Francisco",
        excludingStops: Set<String> = []
    ) async -> [CategorizedPOI] {
        let cleanCity = city
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? city

        let targetCity = cleanCity.isEmpty ? "San Francisco" : cleanCity

        // Step 1: Resolve coordinate
        var searchCenter = center
        if searchCenter == nil || searchCenter?.latitude == 0 {
            let geocoder = CLGeocoder()
            if let placemarks = try? await geocoder.geocodeAddressString(targetCity),
               let location = placemarks.first?.location {
                searchCenter = location.coordinate
            }
        }

        var results: [CategorizedPOI] = []
        var seenNames = Set<String>(excludingStops.map { $0.lowercased() })

        // Expand radius based on how many places are already excluded
        let multiplier = max(1.0, Double(excludingStops.count / 3) + 1.0)
        let dynamicRadius = min(50000, radius * multiplier) // Up to 50km radius expansion

        // Sub-neighborhood search queries to ensure endless place discovery
        let neighborhoods = [
            targetCity,
            "Downtown \(targetCity)",
            "North \(targetCity)",
            "South \(targetCity)",
            "East \(targetCity)",
            "West \(targetCity)"
        ]

        var sportsPOIs: [MKPointOfInterestCategory] = [.stadium, .amusementPark, .fitnessCenter]
        var culturePOIs: [MKPointOfInterestCategory] = [.museum, .theater, .library]
        var naturePOIs: [MKPointOfInterestCategory] = [.park, .nationalPark, .campground, .beach, .marina]
        if #available(iOS 18.0, *) {
            sportsPOIs += [.golf, .tennis, .skating, .skatePark, .rockClimbing, .bowling, .miniGolf, .goKart]
            culturePOIs += [.landmark, .nationalMonument, .musicVenue]
            naturePOIs += [.hiking]
        }

        let searchCategories: [(POICategoryType, [MKPointOfInterestCategory], [String])] = [
            (.nature, naturePOIs, [
                "hikes parks nature",
                "scenic view trail",
                "botanical gardens reserve",
                "beaches lake lookout"
            ]),
            (.nightlife, [.nightlife, .brewery, .winery, .theater, .movieTheater], [
                "nightlife bars music",
                "cocktail lounge pub",
                "breweries wine bar",
                "speakeasy rooftop lounge"
            ]),
            (.sports, sportsPOIs, [
                "sports stadium activities",
                "recreation park golf",
                "bowling billiards climbing",
                "spa yoga wellness"
            ]),
            (.culture, culturePOIs, [
                "museums landmarks art",
                "historical site gallery",
                "sculpture park theater",
                "zoo aquarium theme park"
            ]),
            (.food, [.cafe, .restaurant, .bakery, .store], [
                "cafes food hangouts",
                "bakery bistro breakfast",
                "coffee roasters matcha",
                "shopping mall boutique market"
            ])
        ]

        for neighborhood in neighborhoods {
            if results.count >= 15 { break }

            for (catType, poiCategories, nlQueries) in searchCategories {
                var itemsForCat: [MKMapItem] = []

                if let validCenter = searchCenter, validCenter.latitude != 0, validCenter.longitude != 0 {
                    let poiReq = MKLocalPointsOfInterestRequest(center: validCenter, radius: dynamicRadius)
                    poiReq.pointOfInterestFilter = MKPointOfInterestFilter(including: poiCategories)
                    if let response = try? await MKLocalSearch(request: poiReq).start() {
                        itemsForCat.append(contentsOf: response.mapItems)
                    }
                }

                // Execute natural language search queries
                for queryTerm in nlQueries {
                    let searchReq = MKLocalSearch.Request()
                    searchReq.naturalLanguageQuery = "\(queryTerm) in \(neighborhood)"
                    if let response = try? await MKLocalSearch(request: searchReq).start() {
                        itemsForCat.append(contentsOf: response.mapItems)
                    }
                }

                for item in itemsForCat {
                    guard HangoutSpotFilter.isEligibleSpot(item) else { continue }
                    guard let name = item.name, !name.isEmpty else { continue }
                    let lowerName = name.lowercased()
                    if !seenNames.contains(lowerName) {
                        seenNames.insert(lowerName)
                        results.append(CategorizedPOI(mapItem: item, category: catType))
                    }
                }
            }
        }

        return results
    }

    /// Legacy method for single place fetching compatibility
    public func fetchNearbyPlaces(
        center: CLLocationCoordinate2D? = nil,
        radius: CLLocationDistance = 2000,
        city: String = "San Francisco"
    ) async throws -> [MKMapItem] {
        let categorized = await fetchDiversePlaces(center: center, radius: radius, city: city)
        return categorized.map { $0.mapItem }
    }
}
