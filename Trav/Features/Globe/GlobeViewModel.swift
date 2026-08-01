import Foundation
import Observation
import UIKit
import CoreLocation

@Observable
@MainActor
final class GlobeViewModel {
    enum LoadState {
        case loading
        case loaded([City])
        case failed(Error)
    }

    private(set) var loadState: LoadState = .loading
    /// City framed by the fly-to animation; shows a descriptor card until Visit or dismiss.
    private(set) var previewCity: City?
    /// True while the camera is flying to a city (hides chips so they don't flash mid-zoom).
    private(set) var isFlyingToCity = false
    /// Pin tip in the SceneKit view's coordinates — popup arrow anchors here.
    private(set) var previewPinPoint: CGPoint?

    let renderer: EarthGlobeRenderer
    let controller: EarthGlobeController

    private let citiesRepository: any CityRepository
    private let router: AppRouter
    private(set) var currentLoadedLocationName: String?

    init(citiesRepository: any CityRepository, router: AppRouter) {
        let renderer = EarthGlobeRenderer()
        self.renderer = renderer
        self.controller = EarthGlobeController(renderer: renderer)
        self.citiesRepository = citiesRepository
        self.router = router

        renderer.onCitySelected = { [weak self] city in
            self?.presentPreview(for: city)
        }

        controller.onFlyToStarted = { [weak self] in
            self?.beginFlyTo()
        }

        controller.onUserInteractionStarted = { [weak self] in
            self?.dismissPreview(resetZoom: false)
        }
    }

    /// Decode globe textures off the main thread, then load city markers.
    func prepare(isLightMode: Bool, userLocationName: String? = nil) async {
        await renderer.loadTextures(preferDaytime: isLightMode)
        await loadCities(userLocationName: userLocationName)
    }

    func loadCities(userLocationName: String? = nil) async {
        self.currentLoadedLocationName = userLocationName
        loadState = .loading
        do {
            let rawCities = try await citiesRepository.fetchGlobeCities()
            let organizedCities = await organizeCities(allCities: rawCities, userLocationName: userLocationName)
            renderer.setCities(organizedCities)
            loadState = .loaded(organizedCities)
        } catch {
            loadState = .failed(error)
        }
    }

    private static let recognizedMajorCityNames: [String] = [
        "San Francisco", "New York", "Tokyo", "Paris", "London", "Barcelona",
        "Rome", "Amsterdam", "Berlin", "Sydney", "Seoul", "Singapore",
        "Dubai", "Rio de Janeiro", "Mexico City", "Los Angeles", "Chicago", "Miami", "Kyoto"
    ]

    private func organizeCities(allCities: [City], userLocationName: String?) async -> [City] {
        let majorNames = Self.recognizedMajorCityNames
        
        // Start with MockData.cities (which includes curated major global cities across countries)
        var pool = MockData.cities
        
        // Merge in any matching major cities from allCities (excluding obscure/unknown towns like French Lick)
        for city in allCities {
            let isMajor = majorNames.contains(where: { mName in
                city.name.localizedCaseInsensitiveCompare(mName) == .orderedSame ||
                city.name.localizedCaseInsensitiveContains(mName) ||
                mName.localizedCaseInsensitiveContains(city.name)
            })
            if isMajor {
                if let idx = pool.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(city.name) == .orderedSame }) {
                    pool[idx] = city
                } else {
                    pool.append(city)
                }
            }
        }
        
        // Sort pool so major cities appear in standard curated priority order
        var sortedCities = pool.sorted { c1, c2 in
            let idx1 = majorNames.firstIndex(where: { c1.name.localizedCaseInsensitiveContains($0) || $0.localizedCaseInsensitiveContains(c1.name) }) ?? 999
            let idx2 = majorNames.firstIndex(where: { c2.name.localizedCaseInsensitiveContains($0) || $0.localizedCaseInsensitiveContains(c2.name) }) ?? 999
            if idx1 != idx2 {
                return idx1 < idx2
            }
            return c1.experienceCount > c2.experienceCount
        }
        
        // If user hasn't indicated a location in profile, return sorted major cities (first city is San Francisco)
        guard let userLoc = userLocationName?.trimmingCharacters(in: .whitespacesAndNewlines), !userLoc.isEmpty else {
            return sortedCities
        }
        
        // If user's profile location matches a city in sortedCities:
        if let matchIndex = sortedCities.firstIndex(where: {
            $0.name.localizedCaseInsensitiveCompare(userLoc) == .orderedSame ||
            userLoc.localizedCaseInsensitiveContains($0.name) ||
            $0.name.localizedCaseInsensitiveContains(userLoc)
        }) {
            let userCity = sortedCities.remove(at: matchIndex)
            sortedCities.insert(userCity, at: 0)
            return sortedCities
        }
        
        // If user's location is a custom location, geocode it for accurate globe pin placement and set as City #1
        var lat: Double = 37.7749
        var lng: Double = -122.4194
        if let placemarks = try? await CLGeocoder().geocodeAddressString(userLoc),
           let location = placemarks.first?.location {
            lat = location.coordinate.latitude
            lng = location.coordinate.longitude
        }
        
        let userCity = City(
            id: UUID(),
            name: userLoc,
            slug: userLoc.lowercased().replacingOccurrences(of: " ", with: "-"),
            countryCode: "US",
            latitude: lat,
            longitude: lng,
            heroImageURL: nil,
            timezone: TimeZone.current.identifier,
            experienceCount: 0,
            creatorCount: 1
        )
        sortedCities.insert(userCity, at: 0)
        return sortedCities
    }

    func selectCity(_ city: City) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        controller.flyTo(city: city) { [weak self] in
            self?.presentPreview(for: city)
        }
    }

    func visitPreviewCity() {
        guard let city = previewCity else { return }
        clearPreviewState()
        controller.resetZoom(animated: false)
        router.openFeed(city: city)
    }

    func dismissPreview(resetZoom: Bool = true) {
        guard previewCity != nil || isFlyingToCity else { return }
        clearPreviewState()
        if resetZoom {
            controller.resetZoom(animated: true)
        }
    }

    func resetZoomAfterReturningHome() {
        clearPreviewState()
        controller.resetZoom(animated: false)
    }

    private func beginFlyTo() {
        previewCity = nil
        previewPinPoint = nil
        isFlyingToCity = true
        controller.suppressesIdleMotion = true
    }

    private func presentPreview(for city: City) {
        isFlyingToCity = false
        previewCity = city
        controller.suppressesIdleMotion = true
        // Wait one frame so SceneKit's presentation node matches the finished fly-to.
        Task { @MainActor in
            let liveCity = await self.citiesRepository.fetchCityStats(for: city)
            if self.previewCity?.id == city.id {
                self.previewCity = liveCity
            }
            await Task.yield()
            guard self.previewCity?.id == city.id else { return }
            self.previewPinPoint = self.controller.pinTipScreenPoint(for: city)
        }
    }

    private func clearPreviewState() {
        previewCity = nil
        previewPinPoint = nil
        isFlyingToCity = false
        controller.suppressesIdleMotion = false
    }
}
