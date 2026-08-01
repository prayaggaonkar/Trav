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
    var selectedLocation: LocationOption = LocationOption.allLocations

    private(set) var allEntries: [LeaderboardEntry] = []
    private(set) var availableLocations: [LocationOption] = [LocationOption.allLocations]
    private(set) var phase: LoadPhase = .loaded

    var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    private var currentEnvironment: AppEnvironment?

    func filteredEntries(followingIDs: Set<UUID>, currentUserID: UUID?) -> [LeaderboardEntry] {
        var items = allEntries.filter { $0.experienceCount > 0 }

        // Member Scope Filter (All Members vs Friends)
        if memberScope == .friends {
            items = items.filter { entry in
                followingIDs.contains(entry.id) || entry.id == currentUserID
            }
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
        if allEntries.isEmpty {
            phase = .loading
        }
        do {
            // Load globe cities for default location suggestions
            let fetchedCities = (try? await environment.cities.fetchGlobeCities()) ?? []
            var locs: [LocationOption] = [LocationOption.allLocations]

            for city in fetchedCities {
                let name = "\(city.name), \(city.countryName)"
                if !locs.contains(where: { $0.name.lowercased() == name.lowercased() || $0.name.lowercased() == city.name.lowercased() }) {
                    locs.append(LocationOption(id: city.id.uuidString, name: city.name, subtitle: city.countryName))
                }
            }

            // Fetch real users and city-specific experience counts strictly from Supabase database
            let cityID: UUID? = (selectedLocation.id == LocationOption.allLocations.id) ? nil : UUID(uuidString: selectedLocation.id)
            let fetchedEntries = (try? await environment.experiences.fetchLeaderboardEntries(
                cityID: cityID,
                cityName: selectedLocation.id == LocationOption.allLocations.id ? nil : selectedLocation.name
            )) ?? []

            availableLocations = locs
            allEntries = fetchedEntries
            phase = allEntries.isEmpty ? .empty : .loaded
        } catch {
            if allEntries.isEmpty {
                phase = .empty
            }
        }
    }

    func selectMemberScope(_ scope: MemberScopeFilter) {
        memberScope = scope
        phase = .loading
        if let currentEnvironment {
            Task {
                await reload(using: currentEnvironment)
            }
        }
    }

    func selectLocation(_ location: LocationOption) {
        selectedLocation = location
        if location.id != LocationOption.allLocations.id,
           !availableLocations.contains(where: { $0.id == location.id || $0.name.lowercased() == location.name.lowercased() }) {
            availableLocations.insert(location, at: 1)
        }
        phase = .loading
        if let currentEnvironment {
            Task {
                await reload(using: currentEnvironment)
            }
        }
    }
}
