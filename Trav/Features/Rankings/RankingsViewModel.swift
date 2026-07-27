import Foundation
import Observation

@Observable
@MainActor
final class RankingsViewModel {
    enum LoadPhase {
        case idle
        case loading
        case loaded
        case empty
        case failed(Error)
    }

    var mode: RankingMode = .experiences
    var axis: RankingAxis = .overall
    var selectedCity: City?
    var selectedCreator: ProfileSummary?
    /// Free-text input for city search suggestions / city token.
    var searchText = ""

    private(set) var experiences: [ExperienceSummary] = []
    private(set) var creators: [RankedCreator] = []
    private(set) var phase: LoadPhase = .idle
    private(set) var catalogCities: [City] = []

    private var loadTask: Task<Void, Never>?

    var displayedCreators: [RankedCreator] {
        creators
    }

    func applyCreatorSearchFilter() {
        // Rankings search is cities-only; creator list is not text-filtered.
    }

    var matchingCities: [City] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return catalogCities.filter { city in
            city.name.localizedCaseInsensitiveContains(trimmed)
                || city.countryName.localizedCaseInsensitiveContains(trimmed)
                || city.locationLabel.localizedCaseInsensitiveContains(trimmed)
        }
    }

    func bootstrap(using environment: AppEnvironment) async {
        if catalogCities.isEmpty {
            catalogCities = (try? await environment.cities.fetchGlobeCities()) ?? MockData.cities
        }
        await reload(using: environment)
    }

    func reload(using environment: AppEnvironment) async {
        loadTask?.cancel()
        let mode = self.mode
        let axis = self.axis
        let cityID = selectedCity?.id
        let creatorID: UUID? = nil

        loadTask = Task {
            phase = experiences.isEmpty && creators.isEmpty ? .loading : phase
            do {
                switch mode {
                case .experiences:
                    let page = try await environment.experiences.fetchRankedExperiences(
                        cityID: cityID,
                        creatorID: creatorID,
                        axis: axis,
                        page: 0
                    )
                    guard !Task.isCancelled else { return }
                    experiences = page.items
                    creators = []
                    phase = page.items.isEmpty ? .empty : .loaded
                case .creators:
                    let page = try await environment.experiences.fetchRankedCreators(
                        cityID: cityID,
                        axis: axis,
                        page: 0
                    )
                    guard !Task.isCancelled else { return }
                    creators = page.items
                    experiences = []
                    phase = displayedCreators.isEmpty ? .empty : .loaded
                }
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error)
            }
        }
        await loadTask?.value
    }

    func selectCity(_ city: City) {
        selectedCity = city
        searchText = ""
    }

    func selectCreator(_ creator: ProfileSummary) {
        selectedCreator = creator
        searchText = ""
    }

    func clearCity() {
        selectedCity = nil
    }

    func clearCreator() {
        selectedCreator = nil
    }
}
