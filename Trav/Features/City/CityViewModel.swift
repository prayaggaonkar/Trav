import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class CityViewModel {
    struct Content {
        let city: City
        let featured: ExperienceSummary?
        let feed: [ExperienceSummary]
        let creators: [Profile]
    }

    enum LoadPhase {
        case loading
        case empty
        case loaded(Content)
        case failed(Error)
    }

    private let cityID: UUID
    private(set) var phase: LoadPhase = .loading
    var searchQuery = ""
    private(set) var savedIDs: Set<UUID> = []
    private(set) var likedIDs: Set<UUID> = []

    init(cityID: UUID) {
        self.cityID = cityID
    }

    func load(using environment: AppEnvironment) async {
        phase = .loading
        do {
            async let city = environment.cities.fetchCity(id: cityID)
            async let featured = environment.cities.fetchFeaturedExperience(cityID: cityID)
            async let feed = environment.experiences.fetchCityFeed(cityID: cityID, page: 0)
            async let creators = environment.cities.fetchTrendingCreators(cityID: cityID)

            let content = Content(
                city: try await city,
                featured: try await featured,
                feed: try await feed.items,
                creators: try await creators
            )
            phase = content.feed.isEmpty && content.featured == nil ? .empty : .loaded(content)
        } catch {
            phase = .failed(error)
        }
    }

    func filteredFeed(from content: Content) -> [ExperienceSummary] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = content.feed.filter { summary in
            content.featured.map { $0.id != summary.id } ?? true
        }

        guard !query.isEmpty else { return base }

        return base.filter { experience in
            experience.title.localizedCaseInsensitiveContains(query)
                || experience.creator.displayName.localizedCaseInsensitiveContains(query)
                || experience.creator.username.localizedCaseInsensitiveContains(query)
                || experience.stops.contains {
                    $0.name.localizedCaseInsensitiveContains(query)
                }
        }
    }

    func toggleSave(for experienceID: UUID) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if savedIDs.contains(experienceID) {
            savedIDs.remove(experienceID)
        } else {
            savedIDs.insert(experienceID)
        }
    }

    func toggleLike(for experienceID: UUID) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if likedIDs.contains(experienceID) {
            likedIDs.remove(experienceID)
        } else {
            likedIDs.insert(experienceID)
        }
    }

    func isSaved(_ experienceID: UUID) -> Bool {
        savedIDs.contains(experienceID)
    }

    func isLiked(_ experienceID: UUID) -> Bool {
        likedIDs.contains(experienceID)
    }

    func shareText(for experience: ExperienceSummary, cityName: String) -> String {
        "Explore \"\(experience.title)\" in \(cityName) on Trav"
    }
}
