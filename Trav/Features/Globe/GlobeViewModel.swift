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
        "Berkeley",
        "San Francisco",
        "Barcelona",
        "New York",
        "Paris",
        "London",
        "Tokyo",
        "Los Angeles"
    ]

    private func organizeCities(allCities: [City], userLocationName: String?) async -> [City] {
        let allowedNames = Self.recognizedMajorCityNames
        let combined = MockData.cities + allCities
        
        var pool: [City] = []
        for name in allowedNames {
            if let matched = combined.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                if !pool.contains(where: { $0.id == matched.id }) {
                    pool.append(matched)
                }
            }
        }
        return pool
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
