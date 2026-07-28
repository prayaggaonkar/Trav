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

    var memberScope: MemberScopeFilter = .allMembers
    var selectedLocation: LocationOption = MockLeaderboardData.defaultLocation

    private(set) var allEntries: [LeaderboardEntry] = []
    private(set) var availableLocations: [LocationOption] = MockLeaderboardData.locationOptions
    private(set) var phase: LoadPhase = .loaded

    private var currentEnvironment: AppEnvironment?

    var filteredEntries: [LeaderboardEntry] {
        var items = allEntries

        // Member Scope Filter (All Members vs Friends)
        if memberScope == .friends {
            items = items.filter { $0.isFriend }
        }

        // Sort descending by number of experiences created in the selected location
        return items.sorted { lhs, rhs in
            if lhs.experienceCount != rhs.experienceCount {
                return lhs.experienceCount > rhs.experienceCount
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    func bootstrap(using environment: AppEnvironment) async {
        self.currentEnvironment = environment
        await reload(using: environment)
    }

    func reload(using environment: AppEnvironment) async {
        self.currentEnvironment = environment
        phase = .loading
        do {
            // Load globe cities for default location suggestions
            let fetchedCities = (try? await environment.cities.fetchGlobeCities()) ?? []
            var locs: [LocationOption] = [LocationOption.allLocations, MockLeaderboardData.defaultLocation]

            for city in fetchedCities {
                let name = "\(city.name), \(city.countryName)"
                if !locs.contains(where: { $0.name.lowercased() == name.lowercased() || $0.name.lowercased() == city.name.lowercased() }) {
                    locs.append(LocationOption(id: city.id.uuidString, name: city.name, subtitle: city.countryName))
                }
            }
            availableLocations = locs

            // Fetch real users and city-specific experience counts strictly from Supabase database
            let cityID: UUID? = (selectedLocation.id == LocationOption.allLocations.id) ? nil : UUID(uuidString: selectedLocation.id)
            let fetchedEntries = (try? await environment.experiences.fetchLeaderboardEntries(
                cityID: cityID,
                cityName: selectedLocation.id == LocationOption.allLocations.id ? nil : selectedLocation.name
            )) ?? []

            allEntries = fetchedEntries
            phase = filteredEntries.isEmpty ? .empty : .loaded
        } catch {
            allEntries = []
            phase = .empty
        }
    }

    func selectMemberScope(_ scope: MemberScopeFilter) {
        memberScope = scope
    }

    func selectLocation(_ location: LocationOption) {
        selectedLocation = location
        if let currentEnvironment {
            Task {
                await reload(using: currentEnvironment)
            }
        }
    }
}
