import CoreLocation
import Foundation
import MapKit
import Observation
import UIKit

struct CitySuggestion: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String

    var displayLabel: String {
        let cleanTitle = title.asPlainPlaceName()
        let cleanSubtitle = subtitle.asPlainPlaceName()
        if cleanSubtitle.isEmpty { return cleanTitle }
        let parts = cleanSubtitle
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let first = parts.first {
            return "\(cleanTitle), \(first)"
        }
        return cleanTitle
    }
}

/// MapKit city autocomplete with soft location bias, Trav catalog boost, and popularity ranking.
@Observable
@MainActor
final class CityAutocompleteController: NSObject, MKLocalSearchCompleterDelegate, CLLocationManagerDelegate {
    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            debounceTask?.cancel()
            if trimmed.isEmpty {
                suggestions = []
                lastQueried = ""
                isSearching = false
                completer.queryFragment = ""
            } else if trimmed != lastQueried {
                lastQueried = trimmed
                isSearching = true
                debounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    self.refreshRegionBias()
                    self.completer.queryFragment = trimmed
                    await self.mergeCatalogSuggestions(for: trimmed)
                }
            }
        }
    }

    private(set) var suggestions: [CitySuggestion] = []
    private(set) var isSearching = false

    private let completer = MKLocalSearchCompleter()
    private let locationManager = CLLocationManager()
    private var lastQueried = ""
    private var debounceTask: Task<Void, Never>?
    private var pendingCompleterSnapshots: [(title: String, subtitle: String)] = []
    private var userCoordinate: CLLocationCoordinate2D?

    /// Only used as the *last word* of a multi-word title (e.g. "Market Street").
    private static let streetSuffixes: Set<String> = [
        "st", "street", "ave", "avenue", "rd", "road", "blvd", "boulevard",
        "ln", "lane", "dr", "drive", "ct", "court", "hwy", "highway",
        "pkwy", "parkway", "ter", "terrace", "aly", "alley"
    ]

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        userCoordinate = locationManager.location?.coordinate
            ?? LocationManager.shared.coordinateForSearch
        refreshRegionBias()
        if locationManager.authorizationStatus == .authorizedWhenInUse
            || locationManager.authorizationStatus == .authorizedAlways {
            locationManager.requestLocation()
        }
    }

    func clear() {
        debounceTask?.cancel()
        query = ""
        suggestions = []
        lastQueried = ""
        isSearching = false
        pendingCompleterSnapshots = []
    }

    func dismissSuggestions() {
        suggestions = []
        isSearching = false
    }

    func resolve(_ suggestion: CitySuggestion) async -> String? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = suggestion.displayLabel
        request.resultTypes = .address
        if let coord = userCoordinate {
            request.region = MKCoordinateRegion(
                center: coord,
                latitudinalMeters: 500_000,
                longitudinalMeters: 500_000
            )
        }

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            for item in response.mapItems {
                if let label = Self.formatCity(from: item) {
                    return label.asPlainPlaceName()
                }
            }
        } catch {}
        return suggestion.displayLabel
    }

    func resolveCurrentLocation(coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            return Self.formatCity(from: placemark)?.asPlainPlaceName()
        } catch {
            return nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.userCoordinate = location.coordinate
            self.refreshRegionBias()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let coord = manager.location?.coordinate
        Task { @MainActor in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.userCoordinate = coord
                self.refreshRegionBias()
                self.locationManager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let snapshots: [(title: String, subtitle: String)] = completer.results.map {
            ($0.title, $0.subtitle)
        }
        Task { @MainActor in
            self.pendingCompleterSnapshots = snapshots
            await self.rebuildSuggestions()
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.isSearching = false
            await self.rebuildSuggestions()
        }
    }

    private func refreshRegionBias() {
        guard let coord = userCoordinate ?? LocationManager.shared.coordinateForSearch else { return }
        userCoordinate = coord
        // Soft bias (~400km): nearby cities rise for short queries without blocking worldwide.
        completer.region = MKCoordinateRegion(
            center: coord,
            latitudinalMeters: 400_000,
            longitudinalMeters: 400_000
        )
    }

    private func mergeCatalogSuggestions(for query: String) async {
        await rebuildSuggestions()
    }

    private func rebuildSuggestions() async {
        let trimmed = lastQueried
        guard !trimmed.isEmpty else {
            suggestions = []
            isSearching = false
            return
        }

        let intent = SearchIntent.classify(trimmed)
        var scored: [(CitySuggestion, Double)] = []
        var seen = Set<String>()

        for snapshot in pendingCompleterSnapshots {
            let title = snapshot.title.asPlainPlaceName()
            let subtitle = snapshot.subtitle.asPlainPlaceName()
            guard !title.isEmpty else { continue }
            guard !Self.isStreetAddress(title: title) else { continue }
            guard !Self.isBroadAdminArea(title: title, subtitle: subtitle) else { continue }

            let suggestion = CitySuggestion(
                id: "mk|\(title)|\(subtitle)",
                title: title,
                subtitle: subtitle
            )
            let key = suggestion.displayLabel.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            let score = IntelligentSearchRanking.scoreCity(
                name: title,
                countryName: subtitle,
                query: trimmed,
                experienceCount: 0,
                creatorCount: 0,
                coordinate: userCoordinate,
                userCoordinate: userCoordinate,
                intent: intent
            ) + IntelligentSearchRanking.majorCityPrior(name: title) * 0.1
            scored.append((suggestion, score))
        }

        // Boost with Trav catalog cities that match.
        let catalog = (try? await CityCatalog.shared.all()) ?? []
        let rankedCatalog = IntelligentSearchRanking.rankCatalogCities(
            catalog,
            query: trimmed,
            userCoordinate: userCoordinate
        )
        for city in rankedCatalog.prefix(12) {
            let suggestion = CitySuggestion(
                id: "catalog|\(city.id.uuidString)",
                title: city.name,
                subtitle: city.countryName
            )
            let key = suggestion.displayLabel.lowercased()
            if seen.contains(key) {
                // Raise score of existing MapKit row when Trav has activity.
                if let idx = scored.firstIndex(where: { $0.0.displayLabel.lowercased() == key }) {
                    let boost = IntelligentSearchRanking.scoreCity(
                        name: city.name,
                        countryName: city.countryName,
                        query: trimmed,
                        experienceCount: city.experienceCount,
                        creatorCount: city.creatorCount,
                        coordinate: CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude),
                        userCoordinate: userCoordinate,
                        intent: intent
                    )
                    scored[idx].1 = max(scored[idx].1, boost + 0.08)
                }
                continue
            }
            seen.insert(key)
            let score = IntelligentSearchRanking.scoreCity(
                name: city.name,
                countryName: city.countryName,
                query: trimmed,
                experienceCount: city.experienceCount,
                creatorCount: city.creatorCount,
                coordinate: CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude),
                userCoordinate: userCoordinate,
                intent: intent
            )
            scored.append((suggestion, score))
        }

        suggestions = scored
            .sorted { $0.1 > $1.1 }
            .prefix(20)
            .map(\.0)
        isSearching = false
    }

    private static func isBroadAdminArea(title: String, subtitle: String) -> Bool {
        let lower = title.lowercased()
        let adminHints = ["county", "parish", "province", "prefecture", "state of", "united states", "united kingdom"]
        if adminHints.contains(where: { lower == $0 || lower.hasSuffix(" \($0)") }) {
            return true
        }
        // Bare country rows often have empty locality-style subtitles.
        if subtitle.isEmpty && IntelligentSearchRanking.majorCityPrior(name: title) < 0.2
            && !title.contains(",") {
            // Keep short city-like titles; drop obvious countries handled above.
        }
        return false
    }

    /// True only for obvious street addresses — not for cities like "St. Louis".
    private static func isStreetAddress(title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        if trimmed.range(of: #"^\d+\s"#, options: .regularExpression) != nil {
            return true
        }

        let parts = trimmed.split(separator: " ").map(String.init)
        guard parts.count >= 2 else { return false }

        let last = parts.last!
            .lowercased()
            .trimmingCharacters(in: .punctuationCharacters)

        return streetSuffixes.contains(last)
    }

    private static func formatCity(from item: MKMapItem) -> String? {
        formatCity(from: item.placemark)
    }

    private static func formatCity(from placemark: CLPlacemark) -> String? {
        let city = (placemark.locality ?? placemark.subAdministrativeArea ?? placemark.name)?
            .asPlainPlaceName()
        guard let city, !city.isEmpty else { return nil }

        if let region = placemark.administrativeArea?.asPlainPlaceName(), !region.isEmpty {
            if placemark.isoCountryCode == "US" || placemark.isoCountryCode == "CA" || placemark.isoCountryCode == "AU" {
                return "\(city), \(region)"
            }
            if let country = placemark.country?.asPlainPlaceName(), !country.isEmpty, country != city {
                return "\(city), \(country)"
            }
            return "\(city), \(region)"
        }

        if let country = placemark.country?.asPlainPlaceName(), !country.isEmpty, country != city {
            return "\(city), \(country)"
        }
        return city
    }
}

extension String {
    /// Keeps only letters, digits, spaces, and common place punctuation.
    /// Guarantees no emoji (including 🗽), flags, or pictographs remain.
    func asPlainPlaceName() -> String {
        let allowed = CharacterSet.letters
            .union(.decimalDigits)
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: ".,'-/"))

        let filtered = unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()

        return filtered
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Back-compat alias used by older call sites.
    func strippingEmojiAndSymbols() -> String { asPlainPlaceName() }
}

// MARK: - Timestamped Location Entry for 24-Hour Verification

struct TimestampedLocation: Codable, Sendable, Equatable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var clLocation: CLLocation {
        CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: timestamp)
    }
}

// MARK: - LocationManager & 24-Hour Location Verification

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = LocationManager()

    private let manager = CLLocationManager()

    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var currentLocation: CLLocation? = nil
    var recordedLocations: [TimestampedLocation] = []

    /// Best-effort coordinate for search bias (live fix or last known).
    var coordinateForSearch: CLLocationCoordinate2D? {
        currentLocation?.coordinate ?? manager.location?.coordinate
    }

    private let storageKey = "trav_location_history_24h"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 50 // Log location fix every 50 meters
        authorizationStatus = manager.authorizationStatus
        loadRecordedLocations()
    }

    // MARK: - Permissions & Control

    func requestLocationPermission() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    func startTracking() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else { return }
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            startTracking()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        currentLocation = latest

        let newEntry = TimestampedLocation(
            latitude: latest.coordinate.latitude,
            longitude: latest.coordinate.longitude,
            timestamp: latest.timestamp
        )

        recordLocation(newEntry)
    }

    // MARK: - 24-Hour Location Log Maintenance

    private func recordLocation(_ entry: TimestampedLocation) {
        let cutoff = Date().addingTimeInterval(-86400) // Past 24 hours
        recordedLocations = recordedLocations.filter { $0.timestamp >= cutoff }
        recordedLocations.append(entry)
        saveRecordedLocations()
    }

    private func loadRecordedLocations() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TimestampedLocation].self, from: data) else { return }
        let cutoff = Date().addingTimeInterval(-86400)
        recordedLocations = decoded.filter { $0.timestamp >= cutoff }
    }

    private func saveRecordedLocations() {
        if let encoded = try? JSONEncoder().encode(recordedLocations) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    // MARK: - 24-Hour Location Match Validation Logic

    /// Validates whether the user physically visited the experience's coordinate within the 24 hours prior to post creation.
    /// - Parameters:
    ///   - experienceCoordinate: Location coordinate of the experience.
    ///   - creationDate: Post creation timestamp (default: now).
    ///   - maxDistanceMeters: Verification threshold in meters (default: 1000m / 1km).
    /// - Returns: Bool indicating if a verified 24-hour location match exists.
    func isLocationVerifiedForExperience(
        experienceCoordinate: CLLocationCoordinate2D,
        creationDate: Date = Date(),
        maxDistanceMeters: CLLocationDistance = 1000
    ) -> Bool {
        // Disqualified if location permissions denied or restricted
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return false
        }

        let experienceLocation = CLLocation(
            latitude: experienceCoordinate.latitude,
            longitude: experienceCoordinate.longitude
        )

        let windowStart = creationDate.addingTimeInterval(-86400) // 24 hours prior
        let validFixes = recordedLocations.filter { $0.timestamp >= windowStart && $0.timestamp <= creationDate }

        // Fallback: check current real-time location if log has no historical entries yet
        if validFixes.isEmpty, let current = currentLocation {
            let currentAge = abs(current.timestamp.timeIntervalSince(creationDate))
            if currentAge <= 86400 {
                return current.distance(from: experienceLocation) <= maxDistanceMeters
            }
        }

        for fix in validFixes {
            if fix.clLocation.distance(from: experienceLocation) <= maxDistanceMeters {
                return true
            }
        }

        return false
    }
}
