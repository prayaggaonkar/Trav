import Foundation
import Supabase

/// Cached city catalog loaded from the `cities` table. Repositories use it to
/// resolve city ids/names without re-querying on every feed request.
actor CityCatalog {
    static let shared = CityCatalog()

    private var cities: [City] = []
    private var lastFetch: Date?
    private var inFlight: Task<[City], Error>?

    private static let ttl: TimeInterval = 10 * 60

    private struct DBCityRow: Decodable {
        let id: UUID
        let name: String
        let slug: String
        let country_code: String
        let latitude: Double
        let longitude: Double
        let hero_image_url: String?
        let timezone: String
        let experience_count: Int
        let creator_count: Int

        var city: City {
            City(
                id: id,
                name: name,
                slug: slug,
                countryCode: country_code.trimmingCharacters(in: .whitespaces),
                latitude: latitude,
                longitude: longitude,
                heroImageURL: hero_image_url.flatMap { URL(string: $0) },
                timezone: timezone,
                experienceCount: experience_count,
                creatorCount: creator_count
            )
        }
    }

    func all() async throws -> [City] {
        if let lastFetch, !cities.isEmpty, Date().timeIntervalSince(lastFetch) < Self.ttl {
            return cities
        }
        if let inFlight {
            return try await inFlight.value
        }

        guard let client = SupabaseManager.client else {
            // Mock/dev mode: fall back to the bundled catalog.
            return MockData.cities
        }

        let task = Task<[City], Error> {
            let rows: [DBCityRow] = try await client
                .from("cities")
                .select()
                .eq("is_active", value: true)
                .order("name")
                .execute()
                .value
            return rows.map(\.city)
        }
        inFlight = task
        defer { inFlight = nil }

        do {
            let fetched = try await task.value
            if !fetched.isEmpty {
                cities = fetched
                lastFetch = Date()
            }
            return fetched.isEmpty ? (cities.isEmpty ? MockData.cities : cities) : fetched
        } catch {
            // Serve stale data over an error when possible.
            if !cities.isEmpty { return cities }
            throw error
        }
    }

    func city(id: UUID) async throws -> City? {
        try await all().first { $0.id == id }
    }

    func city(named name: String) async throws -> City? {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await all().first {
            $0.name.caseInsensitiveCompare(target) == .orderedSame
        }
    }

    func invalidate() {
        lastFetch = nil
    }
}
