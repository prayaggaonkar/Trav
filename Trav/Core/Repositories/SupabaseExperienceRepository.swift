import Foundation
import Supabase

struct SupabaseExperienceRepository: ExperienceRepository {
    private var client: SupabaseClient {
        guard let client = SupabaseManager.client else {
            preconditionFailure("SupabaseExperienceRepository used without a configured SupabaseClient.")
        }
        return client
    }

    // MARK: - DB Structs aligned with user's schema

    private struct DBExperienceInsert: Codable {
        let id: UUID
        let user_id: UUID
        let title: String
        let description: String
        let city: String
        let stops: [String]
        let created_at: Date
    }

    private struct DBExperience: Codable {
        let id: UUID
        let user_id: UUID
        let title: String
        let description: String
        let city: String
        let stops: [String]
        let created_at: Date
    }

    private struct DBProfileSummary: Codable {
        let id: UUID
        let username: String
        let display_name: String
        let avatar_url: String?
        let is_verified: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case username
            case display_name = "display_name"
            case avatar_url = "avatar_url"
            case is_verified = "is_verified"
        }
    }

    // MARK: - ExperienceRepository Protocol Implementation

    func publishExperience(
        title: String,
        description: String,
        cityID: UUID,
        creatorID: UUID,
        stops: [StopPreview]
    ) async throws {
        print("--- SupabaseExperienceRepository.publishExperience starting ---")
        let experienceID = UUID()

        // Match cityID to a name, or default to "Unknown"
        let cityName = MockData.cities.first(where: { $0.id == cityID })?.name ?? "Unknown"

        let experienceInsert = DBExperienceInsert(
            id: experienceID,
            user_id: creatorID,
            title: title,
            description: description,
            city: cityName,
            stops: stops.map { $0.name },
            created_at: Date()
        )

        print("Inserting experience into Supabase: \(experienceInsert)")

        // Insert experience row into experiences table
        try await client
            .from("experiences")
            .insert(experienceInsert)
            .execute()
            
        print("Successfully inserted experience into Supabase experiences table!")
    }

    func fetchExperience(id: UUID) async throws -> Experience {
        do {
            let dbExp: DBExperience = try await client
                .from("experiences")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value

            var dbProfile: DBProfileSummary?
            do {
                dbProfile = try await client
                    .from("profiles")
                    .select("id, username, display_name, avatar_url, is_verified")
                    .eq("id", value: dbExp.user_id)
                    .single()
                    .execute()
                    .value
            } catch {}

            let creator = ProfileSummary(
                id: dbProfile?.id ?? dbExp.user_id,
                username: dbProfile?.username ?? "unknown",
                displayName: dbProfile?.display_name ?? "Unknown Creator",
                avatarURL: dbProfile?.avatar_url.flatMap { URL(string: $0) },
                isVerified: dbProfile?.is_verified ?? false
            )

            // Convert string array to Stop array
            let stops = dbExp.stops.enumerated().map { (index, stopName) in
                Stop(
                    id: UUID(),
                    orderIndex: index,
                    name: stopName,
                    description: "",
                    creatorNotes: nil,
                    latitude: 0.0,
                    longitude: 0.0,
                    placeID: nil,
                    recommendedTime: nil,
                    durationMinutes: 30,
                    emoji: "📍",
                    media: []
                )
            }

            // Find city ID from city name
            let matchedCity = MockData.cities.first(where: { $0.name.localizedCaseInsensitiveCompare(dbExp.city) == .orderedSame })
            let cityID = matchedCity?.id ?? UUID()

            return Experience(
                id: dbExp.id,
                cityID: cityID,
                creator: creator,
                title: dbExp.title,
                description: dbExp.description,
                coverImageURL: nil,
                durationMinutes: stops.count * 30,
                costLevel: .budget,
                estimatedCostUSD: nil,
                transportMode: .walking,
                totalDistanceMeters: 0,
                saveCount: 0,
                likeCount: 0,
                completionCount: 0,
                commentCount: 0,
                isPublished: true,
                publishedAt: dbExp.created_at,
                stops: stops,
                routeSegments: []
            )
        } catch {
            print("Failed to fetch experience \(id) from Supabase, falling back to mock: \(error)")
            return try await MockExperienceRepository().fetchExperience(id: id)
        }
    }

    func fetchCityFeed(cityID: UUID, page: Int) async throws -> Paginated<ExperienceSummary> {
        do {
            // Find city name from cityID
            let cityName = MockData.cities.first(where: { $0.id == cityID })?.name ?? "Unknown"

            let dbExps: [DBExperience] = try await client
                .from("experiences")
                .select()
                .eq("city", value: cityName)
                .order("created_at", ascending: false)
                .execute()
                .value

            var summaries: [ExperienceSummary] = []
            for dbExp in dbExps {
                var dbProfile: DBProfileSummary?
                do {
                    dbProfile = try await client
                        .from("profiles")
                        .select("id, username, display_name, avatar_url, is_verified")
                        .eq("id", value: dbExp.user_id)
                        .single()
                        .execute()
                        .value
                } catch {}

                let creator = ProfileSummary(
                    id: dbProfile?.id ?? dbExp.user_id,
                    username: dbProfile?.username ?? "unknown",
                    displayName: dbProfile?.display_name ?? "Unknown Creator",
                    avatarURL: dbProfile?.avatar_url.flatMap { URL(string: $0) },
                    isVerified: dbProfile?.is_verified ?? false
                )

                let stopsPreviews = dbExp.stops.map { stopName in
                    StopPreview(id: UUID(), name: stopName, emoji: "📍")
                }

                let summary = ExperienceSummary(
                    id: dbExp.id,
                    cityID: cityID,
                    title: dbExp.title,
                    coverImageURL: nil,
                    creator: creator,
                    durationMinutes: dbExp.stops.count * 30,
                    costLevel: .budget,
                    estimatedCostUSD: nil,
                    saveCount: 0,
                    likeCount: 0,
                    completionCount: 0,
                    stops: stopsPreviews
                )
                summaries.append(summary)
            }

            if summaries.isEmpty {
                return try await MockExperienceRepository().fetchCityFeed(cityID: cityID, page: page)
            }

            return Paginated(items: summaries, page: page, hasMore: false)
        } catch {
            print("Failed to fetch city feed for \(cityID) from Supabase, falling back to mock: \(error)")
            return try await MockExperienceRepository().fetchCityFeed(cityID: cityID, page: page)
        }
    }
}
