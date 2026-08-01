import Foundation
import Supabase

struct SupabaseCityRepository: CityRepository {
    private var client: SupabaseClient {
        get throws {
            guard let client = SupabaseManager.client else {
                throw RepositoryError.backendUnavailable
            }
            return client
        }
    }

    func fetchGlobeCities() async throws -> [City] {
        try await CityCatalog.shared.all()
    }

    func fetchCity(id: UUID) async throws -> City {
        guard let city = try await CityCatalog.shared.city(id: id) else {
            throw RepositoryError.notFound
        }
        return city
    }

    func fetchCityStats(for city: City) async -> City {
        guard let client = try? client else {
            let matches = MockData.experiences.filter { exp in
                exp.cityID == city.id || (exp.cityName != nil && exp.cityName?.localizedCaseInsensitiveCompare(city.name) == .orderedSame)
            }
            let expCount = matches.count
            let creatorsCount = Set(matches.map { $0.creator.id }).count
            var updated = city
            updated.experienceCount = expCount
            updated.creatorCount = creatorsCount
            return updated
        }

        do {
            struct Row: Decodable { let user_id: UUID }
            let rows: [Row] = try await client
                .from("experiences")
                .select("user_id")
                .or("city_id.eq.\(city.id.uuidString.lowercased()),city.ilike.\(city.name)")
                .eq("is_published", value: true)
                .execute()
                .value

            let expCount = rows.count
            let creatorsCount = Set(rows.map { $0.user_id }).count
            var updated = city
            updated.experienceCount = expCount
            updated.creatorCount = creatorsCount
            return updated
        } catch {
            let matches = MockData.experiences.filter { exp in
                exp.cityID == city.id || (exp.cityName != nil && exp.cityName?.localizedCaseInsensitiveCompare(city.name) == .orderedSame)
            }
            let expCount = matches.count
            let creatorsCount = Set(matches.map { $0.creator.id }).count
            var updated = city
            updated.experienceCount = expCount
            updated.creatorCount = creatorsCount
            return updated
        }
    }

    func fetchFeaturedExperience(cityID: UUID) async throws -> ExperienceSummary? {
        let feed = try await SupabaseExperienceRepository().fetchCityFeed(cityID: cityID, page: 0)
        return feed.items.max { lhs, rhs in
            (lhs.saveCount + lhs.completionCount) < (rhs.saveCount + rhs.completionCount)
        }
    }

    func fetchTrendingCreators(cityID: UUID) async throws -> [Profile] {
        struct Row: Decodable { let user_id: UUID }
        let rows: [Row] = try await client
            .from("experiences")
            .select("user_id")
            .eq("city_id", value: cityID.uuidString.lowercased())
            .eq("is_published", value: true)
            .order("created_at", ascending: false)
            .limit(60)
            .execute()
            .value

        var counts: [UUID: Int] = [:]
        for row in rows {
            counts[row.user_id, default: 0] += 1
        }
        let topIDs = counts.sorted { $0.value > $1.value }.prefix(6).map(\.key)
        guard !topIDs.isEmpty else { return [] }

        let profiles: [ProfileRow] = try await client
            .from("profiles")
            .select()
            .in("id", values: topIDs.map(\.uuidString))
            .execute()
            .value

        let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.profile) })
        return topIDs.compactMap { byID[$0] }
    }
}
