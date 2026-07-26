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
    /// Free-text filter used in Creators mode (and as search input for city/creator tokens).
    var searchText = ""

    private(set) var experiences: [ExperienceSummary] = []
    private(set) var creators: [RankedCreator] = []
    private(set) var phase: LoadPhase = .idle
    private(set) var catalogCities: [City] = []

    private var loadTask: Task<Void, Never>?

    var displayedCreators: [RankedCreator] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .creators, !query.isEmpty else { return creators }
        return creators.filter {
            $0.profile.displayName.localizedCaseInsensitiveContains(query)
                || $0.profile.username.localizedCaseInsensitiveContains(query)
        }
    }

    func applyCreatorSearchFilter() {
        guard mode == .creators else { return }
        switch phase {
        case .loaded, .empty:
            phase = displayedCreators.isEmpty ? .empty : .loaded
        case .idle, .loading, .failed:
            break
        }
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
        let creatorID = mode == .experiences ? selectedCreator?.id : nil

        loadTask = Task {
            phase = experiences.isEmpty && creators.isEmpty ? .loading : phase
            do {
                switch mode {
                case .experiences:
                    var page = try await environment.experiences.fetchRankedExperiences(
                        cityID: cityID,
                        creatorID: creatorID,
                        axis: axis,
                        page: 0
                    )
                    // Until live ratings are populated, fall back to curated mock rankings.
                    if page.items.isEmpty {
                        page = try await MockExperienceRepository().fetchRankedExperiences(
                            cityID: cityID,
                            creatorID: creatorID,
                            axis: axis,
                            page: 0
                        )
                    }
                    guard !Task.isCancelled else { return }
                    experiences = page.items
                    creators = []
                    phase = page.items.isEmpty ? .empty : .loaded
                case .creators:
                    var page = try await environment.experiences.fetchRankedCreators(
                        cityID: cityID,
                        axis: axis,
                        page: 0
                    )
                    if page.items.isEmpty {
                        page = try await MockExperienceRepository().fetchRankedCreators(
                            cityID: cityID,
                            axis: axis,
                            page: 0
                        )
                    }
                    guard !Task.isCancelled else { return }
                    creators = page.items
                    experiences = []
                    let visible = displayedCreators
                    phase = visible.isEmpty ? .empty : .loaded
                }
            } catch {
                guard !Task.isCancelled else { return }
                // Live fetch failed — still show mock rankings so the tab is usable.
                do {
                    switch mode {
                    case .experiences:
                        let page = try await MockExperienceRepository().fetchRankedExperiences(
                            cityID: cityID,
                            creatorID: creatorID,
                            axis: axis,
                            page: 0
                        )
                        experiences = page.items
                        creators = []
                        phase = page.items.isEmpty ? .empty : .loaded
                    case .creators:
                        let page = try await MockExperienceRepository().fetchRankedCreators(
                            cityID: cityID,
                            axis: axis,
                            page: 0
                        )
                        creators = page.items
                        experiences = []
                        phase = displayedCreators.isEmpty ? .empty : .loaded
                    }
                } catch {
                    phase = .failed(error)
                }
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
