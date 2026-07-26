import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class GlobeViewModel {
    enum LoadState {
        case loading
        case loaded([City])
        case failed(Error)
    }

    private(set) var loadState: LoadState = .loading

    let renderer: EarthGlobeRenderer
    let controller: EarthGlobeController

    private let citiesRepository: any CityRepository
    private let router: AppRouter

    init(citiesRepository: any CityRepository, router: AppRouter) {
        let renderer = EarthGlobeRenderer()
        self.renderer = renderer
        self.controller = EarthGlobeController(renderer: renderer)
        self.citiesRepository = citiesRepository
        self.router = router

        renderer.onCitySelected = { [weak router] city in
            router?.openCity(city)
        }
    }

    /// Decode globe textures off the main thread, then load city markers.
    func prepare(isLightMode: Bool) async {
        await renderer.loadTextures(preferDaytime: isLightMode)
        await loadCities()
    }

    func loadCities() async {
        loadState = .loading
        do {
            let cities = try await citiesRepository.fetchGlobeCities()
            renderer.setCities(cities)
            loadState = .loaded(cities)
        } catch {
            loadState = .failed(error)
        }
    }

    func selectCity(_ city: City) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        controller.flyTo(city: city) { [weak router] in
            router?.openCity(city)
        }
    }

    func resetZoomAfterReturningHome() {
        controller.resetZoom(animated: true)
    }
}
