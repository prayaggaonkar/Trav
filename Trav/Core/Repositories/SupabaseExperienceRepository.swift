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

    private struct DBPlace: Codable {
        let id: String
        let name: String
        let basic_category: String
        let latitude: Double
        let longitude: Double
        let stops: [String]?
    }

    private struct DBStop: Codable {
        let id: UUID
        let name: String
        let emoji: String?
        let description: String
        let latitude: Double
        let longitude: Double
        let place_id: String?
        let orderIndex: Int
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
            let idStr = id.uuidString.lowercased()
            
            let dbPlace: DBPlace = try await client
                .from("places")
                .select()
                .eq("id", value: idStr)
                .single()
                .execute()
                .value

            let recCreator = ProfileSummary(
                id: UUID(),
                username: "rec_by_trav",
                displayName: "Rec by Trav",
                avatarURL: nil,
                isVerified: true
            )

            let stops: [Stop]
            if let stopsArray = dbPlace.stops, !stopsArray.isEmpty {
                stops = stopsArray.compactMap { stopStr in
                    guard let data = stopStr.data(using: .utf8),
                          let dbStop = try? JSONDecoder().decode(DBStop.self, from: data) else {
                        return nil
                    }
                    return Stop(
                        id: dbStop.id,
                        orderIndex: dbStop.orderIndex,
                        name: dbStop.name,
                        description: dbStop.description,
                        creatorNotes: nil,
                        latitude: dbStop.latitude,
                        longitude: dbStop.longitude,
                        placeID: dbStop.place_id,
                        recommendedTime: nil,
                        durationMinutes: 30,
                        emoji: dbStop.emoji,
                        media: []
                    )
                }
            } else {
                let stop = Stop(
                    id: UUID(),
                    orderIndex: 0,
                    name: dbPlace.name,
                    description: "Curated hangout spot.",
                    creatorNotes: nil,
                    latitude: dbPlace.latitude,
                    longitude: dbPlace.longitude,
                    placeID: dbPlace.id,
                    recommendedTime: nil,
                    durationMinutes: 45,
                    emoji: emojiForCategory(dbPlace.basic_category),
                    media: []
                )
                stops = [stop]
            }

            let matchedCity = MockData.cities.first(where: { $0.name.localizedCaseInsensitiveCompare("Berkeley") == .orderedSame })
            let cityID = matchedCity?.id ?? UUID()

            return Experience(
                id: id,
                cityID: cityID,
                creator: recCreator,
                title: dbPlace.name,
                description: "Explore local spots and neighborhood favorites curated by Trav.",
                coverImageURL: defaultCoverForCategory(dbPlace.name),
                durationMinutes: stops.count * 30,
                costLevel: .moderate,
                estimatedCostUSD: nil,
                transportMode: .walking,
                totalDistanceMeters: 0,
                saveCount: 0,
                likeCount: 0,
                completionCount: 0,
                commentCount: 0,
                isPublished: true,
                publishedAt: Date(),
                stops: stops,
                routeSegments: []
            )
        } catch {
            print("Failed to fetch experience \(id) from Supabase places, falling back to mock: \(error)")
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

    // MARK: - Helpers for Places mapping

    private func defaultCoverForCategory(_ text: String) -> URL? {
        let textLower = text.lowercased()
        if textLower.contains("bar") || textLower.contains("pub") || textLower.contains("drink") || textLower.contains("lounge") {
            return URL(string: "https://images.unsplash.com/photo-1514933651103-005eec06c04b?w=800&q=80")
        }
        if textLower.contains("coffee") || textLower.contains("cafe") || textLower.contains("brew") || textLower.contains("espresso") {
            return URL(string: "https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=800&q=80")
        }
        if textLower.contains("shop") || textLower.contains("store") || textLower.contains("market") || textLower.contains("vintage") {
            return URL(string: "https://images.unsplash.com/photo-1483985988355-763728e1935b?w=800&q=80")
        }
        if textLower.contains("hike") || textLower.contains("trail") || textLower.contains("mountain") || textLower.contains("climb") {
            return URL(string: "https://images.unsplash.com/photo-1501555088652-021faa106b9b?w=800&q=80")
        }
        if textLower.contains("park") || textLower.contains("garden") || textLower.contains("lawn") || textLower.contains("field") {
            return URL(string: "https://images.unsplash.com/photo-1502082553048-f009c37129b9?w=800&q=80")
        }
        if textLower.contains("view") || textLower.contains("sunset") || textLower.contains("scenic") || textLower.contains("vista") {
            return URL(string: "https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=800&q=80")
        }
        if textLower.contains("museum") || textLower.contains("art") || textLower.contains("gallery") {
            return URL(string: "https://images.unsplash.com/photo-1545987796-200677ee1011?w=800&q=80")
        }
        if textLower.contains("book") || textLower.contains("read") || textLower.contains("library") {
            return URL(string: "https://images.unsplash.com/photo-1521587760476-6c12a4b040da?w=800&q=80")
        }
        return URL(string: "https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=800&q=80")
    }

    private func emojiForCategory(_ category: String) -> String {
        let emojis: [String: String] = [
            "bar": "🍻",
            "shopping": "🛍️",
            "vintage_store": "🧥",
            "hiking_trail": "🥾",
            "park": "🌳",
            "scenic_viewpoint": "🌅",
            "museum": "🖼️",
            "bookstore": "📚"
        ]
        return emojis[category.lowercased()] ?? "📍"
    }
}
