import Foundation
import CoreLocation
import Observation
import SwiftUI

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

    private(set) var appleMapsScrollCount = 0
    private(set) var hasReachedScrollLimit = false

    private var experiencePage = 0
    private var placePage = 0
    private var hasMoreExperiences = true
    private var hasMorePlaces = true

    var items: [ExperienceSummary] {
        experiences + places
    }

    var hasMore: Bool {
        hasMoreExperiences || (hasMorePlaces && !hasReachedScrollLimit)
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

    private var cachedLat: Double?
    private var cachedLng: Double?
    private var cachedCity: String?

    func load(
        using environment: AppEnvironment,
        latitude: Double? = nil,
        longitude: Double? = nil,
        city: String? = nil,
        engagement: EngagementStore? = nil
    ) async {
        if let latitude { cachedLat = latitude }
        if let longitude { cachedLng = longitude }
        if let city { cachedCity = city }

        let targetLat = latitude ?? cachedLat
        let targetLng = longitude ?? cachedLng
        let targetCity = city ?? cachedCity

        if phase == .idle {
            phase = .loading
        }

        // Reset Apple Maps recommendation scroll state on new load
        appleMapsScrollCount = 0
        hasReachedScrollLimit = false

        let userVibes = environment.session.currentUser?.selectedVibes ?? [
            "🎨 Street Art",
            "🌙 Nightlife",
            "🛍️ Vintage Shops",
            "🍷 Rooftop Bars"
        ]
        let resolvedCity = targetCity ?? "Berkeley, CA"

        // Chunk 1: Immediate fetch of social feed experiences, places, and popups
        async let experiencesResult = fetchExperiencesPage(0, using: environment)
        async let placesResult = fetchPlacesPage(0, using: environment)
        async let popupsResult = fetchPopupsQuietly(using: environment, latitude: targetLat, longitude: targetLng, city: targetCity)

        let exp = await experiencesResult
        let pla = await placesResult
        let rawPopups = await popupsResult

        var uniquePopups: [Popup] = []
        let calendar = Calendar.current
        for p in rawPopups {
            let norm = p.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isDup = uniquePopups.contains { existing in
                let existingNorm = existing.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard existingNorm == norm else { return false }

                switch (existing.startTime, p.startTime) {
                case let (d1?, d2?):
                    return calendar.isDate(d1, inSameDayAs: d2)
                default:
                    return true
                }
            }
            if !isDup {
                uniquePopups.append(p)
            }
        }
        popups = uniquePopups

        let rawExperiences = exp?.items ?? []
        let rawPlaces = pla?.items ?? []

        // Exclude saved posts from user's own feed
        if let engagement {
            experiences = rawExperiences.filter { !engagement.isSaved($0.id) }
            places = rawPlaces.filter { !engagement.isSaved($0.id) }
        } else {
            experiences = rawExperiences
            places = rawPlaces
        }

        experiencePage = 0
        hasMoreExperiences = exp?.hasMore ?? false
        placePage = 0
        hasMorePlaces = true

        // Reveal content immediately as soon as Chunk 1 is ready!
        if !experiences.isEmpty || !places.isEmpty || !popups.isEmpty {
            phase = .loaded
        } else if exp == nil && pla == nil {
            phase = .failed("Couldn't reach Trav's servers. Check your connection and try again.")
        } else {
            phase = .loaded
        }

        // Chunk 2: Progressive background fetch of Apple Maps vibe recommendations
        let centerCoord = targetLat != nil && targetLng != nil ? CLLocationCoordinate2D(latitude: targetLat!, longitude: targetLng!) : nil
        let vibeRecs = await AppleMapsVibeService.shared.fetchVibeRecommendations(
            vibes: userVibes,
            city: resolvedCity,
            center: centerCoord,
            page: 0
        )

        // Progressively append Chunk 2 recommendations (filtering saved posts)
        var blendedPlaces = places
        for rec in vibeRecs {
            if let engagement, engagement.isSaved(rec.id) { continue }
            if !experiences.contains(where: { $0.id == rec.id }) && !blendedPlaces.contains(where: { $0.id == rec.id }) {
                blendedPlaces.append(rec)
            }
        }
        places = blendedPlaces
    }

    func loadMore(using environment: AppEnvironment) async {
        guard phase == .loaded, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        if hasMoreExperiences {
            if let next = await fetchExperiencesPage(experiencePage + 1, using: environment) {
                experiencePage += 1
                let newItems = next.items.filter { item in
                    !experiences.contains(where: { $0.id == item.id })
                }
                
                if !newItems.isEmpty {
                    Task.detached(priority: .medium) {
                        for item in newItems {
                            let lat = item.stops.first?.latitude ?? 0
                            let lng = item.stops.first?.longitude ?? 0
                            _ = await AppleMapsVibeService.shared.fetchStreetViewOrMapView(
                                latitude: lat,
                                longitude: lng,
                                title: item.title
                            )
                        }
                    }

                    withAnimation(TravAnimation.enter) {
                        experiences.append(contentsOf: newItems)
                    }
                }
                hasMoreExperiences = next.hasMore
                if !newItems.isEmpty { return }
            } else {
                hasMoreExperiences = false
            }
        }

        await loadMorePlaces(using: environment)
    }

    private func loadMorePlaces(using environment: AppEnvironment) async {
        let userVibes = environment.session.currentUser?.selectedVibes ?? [
            "🎨 Street Art",
            "🌙 Nightlife",
            "🛍️ Vintage Shops",
            "🍷 Rooftop Bars"
        ]
        let targetCity = cachedCity ?? "Berkeley, CA"
        let center = cachedLat != nil && cachedLng != nil ? CLLocationCoordinate2D(latitude: cachedLat!, longitude: cachedLng!) : nil

        appleMapsScrollCount += 1
        let nextPage = appleMapsScrollCount

        // 1. Parallelize recommendation engine and DB query execution
        async let recsTask = AppleMapsVibeService.shared.fetchVibeRecommendations(
            vibes: userVibes,
            city: targetCity,
            center: center,
            page: nextPage
        )

        let targetPlacePage = places.isEmpty ? 0 : placePage + 1
        async let dbTask: Paginated<ExperienceSummary>? = hasMorePlaces ? fetchPlacesPage(targetPlacePage, using: environment) : nil

        let (nextPageRecs, dbResult) = await (recsTask, dbTask)

        var fetchedFromDB: [ExperienceSummary] = []
        if let dbResult {
            placePage = targetPlacePage
            fetchedFromDB = dbResult.items
        }

        let allNewItems = fetchedFromDB + nextPageRecs

        // If page yielded no new items, try next page offset so infinite scroll never stalls out
        if allNewItems.isEmpty {
            let retryRecs = await AppleMapsVibeService.shared.fetchVibeRecommendations(
                vibes: userVibes,
                city: targetCity,
                center: center,
                page: nextPage + 1
            )
            if retryRecs.isEmpty {
                hasMorePlaces = false
            } else {
                appendPlaces(retryRecs)
            }
        } else {
            appendPlaces(allNewItems)
        }
    }

    private func appendPlaces(_ newItems: [ExperienceSummary]) {
        // Pre-warm card images in background so cards appear with zero spinner lag
        Task.detached(priority: .medium) {
            for item in newItems {
                let lat = item.stops.first?.latitude ?? 0
                let lng = item.stops.first?.longitude ?? 0
                _ = await AppleMapsVibeService.shared.fetchStreetViewOrMapView(
                    latitude: lat,
                    longitude: lng,
                    title: item.title
                )
            }
        }

        // Smooth spring animation state update
        withAnimation(TravAnimation.enter) {
            for item in newItems {
                if !places.contains(where: { $0.id == item.id }) && !experiences.contains(where: { $0.id == item.id }) {
                    places.append(item)
                }
            }
        }
    }

    /// The feed is ranked, not chronological: location, social proof, ratings and
    /// taste all feed the recommendation engine.
    private func fetchExperiencesPage(
        _ page: Int,
        using environment: AppEnvironment
    ) async -> Paginated<ExperienceSummary>? {
        do {
            return try await environment.experiences.fetchPersonalizedFeed(
                FeedRequest(
                    userID: environment.session.currentUser?.id,
                    latitude: cachedLat,
                    longitude: cachedLng,
                    page: page
                )
            )
        } catch {
            TravLog.network.error("personalized feed failed: \(error.localizedDescription, privacy: .public)")
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
        environment.router.noteExperiencePublished()
        await load(using: environment)
    }
}
