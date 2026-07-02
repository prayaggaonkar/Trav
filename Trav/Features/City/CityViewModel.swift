import Foundation
import Observation

@Observable
@MainActor
final class CityViewModel {
    struct Content {
        let city: City
        let featured: ExperienceSummary?
        let feed: [ExperienceSummary]
    }

    enum LoadPhase {
        case loading
        case empty
        case loaded(Content)
        case failed(Error)
    }

    private let cityID: UUID
    private(set) var phase: LoadPhase = .loading

    init(cityID: UUID) {
        self.cityID = cityID
    }

    func load(using environment: AppEnvironment) async {
        phase = .loading
        do {
            async let city = environment.cities.fetchCity(id: cityID)
            async let featured = environment.cities.fetchFeaturedExperience(cityID: cityID)
            async let feed = environment.experiences.fetchCityFeed(cityID: cityID, page: 0)

            let content = Content(
                city: try await city,
                featured: try await featured,
                feed: try await feed.items
            )
            phase = content.feed.isEmpty && content.featured == nil ? .empty : .loaded(content)
        } catch {
            phase = .failed(error)
        }
    }
}
