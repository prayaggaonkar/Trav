import Foundation
import Observation

/// Drives the home Feed tab: pop-up events, user-published experiences, and
/// curated places. Each source loads independently so a failure in one
/// (e.g. empty social feed) never hides preexisting places/events.
@MainActor
@Observable
final class FeedViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var popups: [Popup] = []
    private(set) var experiences: [ExperienceSummary] = []
    private(set) var places: [ExperienceSummary] = []
    private(set) var isLoadingMore = false

    private var experiencePage = 0
    private var placePage = 0
    private var hasMoreExperiences = true
    private var hasMorePlaces = true

    var items: [ExperienceSummary] {
        experiences + places
    }

    var hasMore: Bool {
        hasMoreExperiences || hasMorePlaces
    }

    func loadIfNeeded(
        using environment: AppEnvironment,
        latitude: Double? = nil,
        longitude: Double? = nil,
        city: String? = nil
    ) async {
        guard phase == .idle else { return }
        await load(using: environment, latitude: latitude, longitude: longitude, city: city)
    }

    func load(
        using environment: AppEnvironment,
        latitude: Double? = nil,
        longitude: Double? = nil,
        city: String? = nil
    ) async {
        phase = .loading

        async let experiencesResult = fetchExperiencesPage(0, using: environment)
        async let placesResult = fetchPlacesPage(0, using: environment)
        async let popupsResult = fetchPopupsQuietly(using: environment, latitude: latitude, longitude: longitude, city: city)

        let exp = await experiencesResult
        let pla = await placesResult
        popups = await popupsResult

        experiences = exp?.items ?? []
        experiencePage = 0
        hasMoreExperiences = exp?.hasMore ?? false

        places = pla?.items ?? []
        placePage = 0
        hasMorePlaces = pla?.hasMore ?? false

        if !experiences.isEmpty || !places.isEmpty || !popups.isEmpty {
            phase = .loaded
        } else if exp == nil && pla == nil {
            phase = .failed("Couldn't reach Trav's servers. Check your connection and try again.")
        } else {
            // Sources responded but were empty — still a successful load.
            phase = .loaded
        }
    }

    func loadMore(using environment: AppEnvironment) async {
        guard phase == .loaded, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        if hasMoreExperiences {
            if let next = await fetchExperiencesPage(experiencePage + 1, using: environment) {
                experiencePage += 1
                experiences.append(contentsOf: next.items.filter { item in
                    !experiences.contains(where: { $0.id == item.id })
                })
                hasMoreExperiences = next.hasMore
            } else {
                hasMoreExperiences = false
            }
            return
        }

        await loadMorePlaces(using: environment)
    }

    private func loadMorePlaces(using environment: AppEnvironment) async {
        guard hasMorePlaces else { return }
        let page = places.isEmpty ? 0 : placePage + 1
        guard let next = await fetchPlacesPage(page, using: environment) else {
            hasMorePlaces = false
            return
        }
        placePage = page
        places.append(contentsOf: next.items.filter { item in
            !places.contains(where: { $0.id == item.id })
        })
        hasMorePlaces = next.hasMore
    }

    private func fetchExperiencesPage(
        _ page: Int,
        using environment: AppEnvironment
    ) async -> Paginated<ExperienceSummary>? {
        do {
            return try await environment.experiences.fetchHomeFeed(page: page)
        } catch {
            TravLog.network.error("fetchHomeFeed failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchPlacesPage(
        _ page: Int,
        using environment: AppEnvironment
    ) async -> Paginated<ExperienceSummary>? {
        do {
            return try await environment.experiences.fetchPlacesFeed(page: page)
        } catch {
            TravLog.network.error("fetchPlacesFeed failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchPopupsQuietly(
        using environment: AppEnvironment,
        latitude: Double? = nil,
        longitude: Double? = nil,
        city: String? = nil
    ) async -> [Popup] {
        do {
            return try await environment.experiences.fetchPopups(
                latitude: latitude,
                longitude: longitude,
                city: city
            )
        } catch {
            TravLog.network.error("fetchPopups failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Quick Planner

    /// Publishes a Quick Planner route as a real experience. The city comes
    /// from the dropped stops (falling back to the user's selected feed city),
    /// never a hardcoded default.
    func saveQuickItinerary(
        title: String,
        stops: [StopPreview],
        cityName: String?,
        creatorID: UUID,
        using environment: AppEnvironment
    ) async throws {
        guard !stops.isEmpty else { return }

        let resolvedCity: City
        if let cityName, let match = try? await CityCatalog.shared.city(named: cityName) {
            resolvedCity = match
        } else if let first = try? await environment.cities.fetchGlobeCities().first {
            resolvedCity = first
        } else {
            throw RepositoryError.backendUnavailable
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = ExperienceDraft(
            title: trimmed.isEmpty ? "My Custom Route" : trimmed,
            description: "Route curated with Quick Planner.",
            city: resolvedCity,
            creatorID: creatorID,
            stops: stops.enumerated().map { index, preview in
                Stop(
                    id: UUID(),
                    orderIndex: index,
                    name: preview.name,
                    description: "",
                    creatorNotes: nil,
                    latitude: 0,
                    longitude: 0,
                    placeID: nil,
                    recommendedTime: nil,
                    durationMinutes: 45,
                    emoji: preview.emoji,
                    media: []
                )
            },
            rating: nil,
            imagesData: []
        )

        try await environment.experiences.publishExperience(draft)
        await load(using: environment)
    }
}
