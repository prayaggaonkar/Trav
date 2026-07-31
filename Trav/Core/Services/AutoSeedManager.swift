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

    /// Checks if a city has an official recommendation. Auto-seeding of multi-stop itineraries is disabled.
    @discardableResult
    func checkAndSeedCity(city: String) async -> Bool {
        return false
    }
}
