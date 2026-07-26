import Foundation
import Supabase

struct SupabaseExperienceRepository: ExperienceRepository {
    private var client: SupabaseClient {
        guard let client = SupabaseManager.serviceClient ?? SupabaseManager.client else {
            preconditionFailure("SupabaseExperienceRepository used without a configured SupabaseClient.")
        }
        return client
    }

    // MARK: - DB Structs aligned with user's schema

    private struct DBExperienceInsert: Codable {
        let id: UUID
        let user_id: UUID
        let title: String
        let city: String
        let stops: [String]
        let image: [String]?
        let created_at: Date
        let rating: [String: Double]?
    }

    private struct DBExperience: Codable {
        let id: UUID
        let user_id: UUID
        let title: String
        let city: String
        let stops: [String]
        let image: StringOrArray?
        let rating: RadarRating?
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

    private func fetchProfiles(for userIDs: [UUID]) async -> [UUID: ProfileSummary] {
        guard !userIDs.isEmpty else { return [:] }
        do {
            let dbProfiles: [DBProfileSummary] = try await client
                .from("profiles")
                .select()
                .in("id", values: userIDs)
                .execute()
                .value
            var map: [UUID: ProfileSummary] = [:]
            for p in dbProfiles {
                map[p.id] = ProfileSummary(
                    id: p.id,
                    username: p.username,
                    displayName: p.display_name,
                    avatarURL: p.avatar_url.flatMap { URL(string: $0) },
                    isVerified: p.is_verified
                )
            }
            return map
        } catch {
            print("Failed to fetch creator profiles for IDs \(userIDs): \(error)")
            return [:]
        }
    }

    // MARK: - ExperienceRepository Protocol Implementation

    func publishExperience(
        title: String,
        cityID: UUID,
        creatorID: UUID,
        stops: [StopPreview],
        rating: RadarRating?,
        imagesData: [Data]
    ) async throws {
        print("--- SupabaseExperienceRepository.publishExperience starting ---")
        let experienceID = UUID()

        // Match cityID to a name, or default to "San Francisco"
        let cityName = MockData.cities.first(where: { $0.id == cityID })?.name ?? "San Francisco"

        var imageURLStrings: [String] = []

        for (index, data) in imagesData.enumerated() {
            let path = "\(experienceID.uuidString.lowercased())/photo_\(index).jpg"
            print("Uploading image \(index + 1)/\(imagesData.count) to Supabase Storage: path=\(path), size=\(data.count) bytes")
            
            do {
                _ = try await client.storage
                    .from("experiences")
                    .upload(
                        path,
                        data: data,
                        options: FileOptions(contentType: "image/jpeg")
                    )
                
                let publicURL = try client.storage.from("experiences").getPublicURL(path: path)
                imageURLStrings.append(publicURL.absoluteString)
                print("Successfully uploaded image \(index + 1). Public URL: \(publicURL.absoluteString)")
            } catch {
                print("Error uploading image \(index): \(error)")
            }
        }

        let experienceInsert = DBExperienceInsert(
            id: experienceID,
            user_id: creatorID,
            title: title,
            city: cityName,
            stops: stops.map { $0.name },
            image: imageURLStrings.isEmpty ? nil : imageURLStrings,
            created_at: Date(),
            rating: rating?.scores
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
            
            // 1. Try to fetch from experiences table first (User Posts)
            if let dbExp: DBExperience = try? await client
                .from("experiences")
                .select()
                .eq("id", value: idStr)
                .single()
                .execute()
                .value {
                
                // Fetch author's profile details
                let dbProfile: DBProfileSummary? = try? await client
                    .from("profiles")
                    .select("id, username, display_name, avatar_url, is_verified")
                    .eq("id", value: dbExp.user_id)
                    .single()
                    .execute()
                    .value
                
                let userCreator = ProfileSummary(
                    id: dbExp.user_id,
                    username: dbProfile?.username ?? "traveler",
                    displayName: dbProfile?.display_name ?? "Shared by Traveler",
                    avatarURL: dbProfile?.avatar_url.flatMap { URL(string: $0) },
                    isVerified: dbProfile?.is_verified ?? false
                )
                
                let stops: [Stop] = dbExp.stops.enumerated().compactMap { (index, stopStr) in
                    guard let data = stopStr.data(using: .utf8),
                          let dbStop = try? JSONDecoder().decode(DBStop.self, from: data) else {
                        // Fallback to name and assign dynamic SF Symbol if plain text string
                        return Stop(
                            id: UUID(),
                            orderIndex: index,
                            name: stopStr,
                            description: "Curated hangout stop.",
                            creatorNotes: nil,
                            latitude: 0.0,
                            longitude: 0.0,
                            placeID: nil,
                            recommendedTime: nil,
                            durationMinutes: 30,
                            emoji: sfSymbolForEmojiOrCategory(stopStr),
                            media: []
                        )
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
                
                let matchedCity = MockData.cities.first(where: { $0.name.localizedCaseInsensitiveCompare(dbExp.city) == .orderedSame })
                let cityID = matchedCity?.id ?? UUID()
                
                let firstStopName = stops.first?.name ?? "park"
                let parsedURLs = dbExp.image?.values.compactMap { URL(string: $0) } ?? []
                let imageURLs = parsedURLs.isEmpty ? [defaultCoverForCategory(firstStopName)].compactMap { $0 } : parsedURLs
                
                return Experience(
                    id: dbExp.id,
                    cityID: cityID,
                    creator: userCreator,
                    title: dbExp.title,
                    description: "",
                    imageURLs: imageURLs,
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
                    routeSegments: [],
                    rating: dbExp.rating
                )
            }
            
            // 2. Otherwise, fallback to public places table (System Recommendations)
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
            print("Failed to fetch experience \(id) from Supabase, falling back to mock: \(error)")
            return try await MockExperienceRepository().fetchExperience(id: id)
        }
    }

    func fetchCityFeed(cityID: UUID, page: Int) async throws -> Paginated<ExperienceSummary> {
        debugLog("SupabaseExperienceRepository.fetchCityFeed started for cityID: \(cityID)")
        do {
            // Find city name from cityID
            let cityName = MockData.cities.first(where: { $0.id == cityID })?.name ?? "Unknown"
            debugLog("SupabaseExperienceRepository.fetchCityFeed: resolved cityName: '\(cityName)'")

            let allExps: [DBExperience] = try await client
                .from("experiences")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value

            debugLog("SupabaseExperienceRepository.fetchCityFeed: total experiences in table = \(allExps.count)")

            let dbExps = allExps.filter { dbExp in
                let expCity = dbExp.city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let targetCity = cityName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return expCity == targetCity || expCity.contains(targetCity) || targetCity.contains(expCity)
            }

            debugLog("SupabaseExperienceRepository.fetchCityFeed: matched \(dbExps.count) experiences for '\(cityName)'")

            let userIDs = Array(Set(dbExps.map(\.user_id)))
            let profilesMap = await fetchProfiles(for: userIDs)

            var summaries: [ExperienceSummary] = []
            for dbExp in dbExps {
                let stopsPreviews = dbExp.stops.map { stopName in
                    StopPreview(id: UUID(), name: stopName, emoji: nil)
                }

                let creator = profilesMap[dbExp.user_id] ?? ProfileSummary(
                    id: dbExp.user_id,
                    username: "traveler",
                    displayName: "Traveler",
                    avatarURL: nil,
                    isVerified: false
                )

                let parsedURLs = dbExp.image?.values.compactMap { URL(string: $0) } ?? []
                let imageURLs = parsedURLs.isEmpty ? [defaultCoverForCategory(dbExp.title)].compactMap { $0 } : parsedURLs

                let summary = ExperienceSummary(
                    id: dbExp.id,
                    cityID: cityID,
                    title: dbExp.title,
                    imageURLs: imageURLs,
                    creator: creator,
                    durationMinutes: max(30, dbExp.stops.count * 30),
                    costLevel: .budget,
                    estimatedCostUSD: nil,
                    saveCount: 0,
                    likeCount: 0,
                    completionCount: 0,
                    stops: stopsPreviews,
                    rating: dbExp.rating
                )
                summaries.append(summary)
            }

            return Paginated(items: summaries, page: page, hasMore: false)
        } catch {
            debugLog("SupabaseExperienceRepository.fetchCityFeed failed with error: \(error)")
            return Paginated(items: [], page: page, hasMore: false)
        }
    }

    func fetchUserExperiences(cityID: UUID, userID: UUID) async throws -> [ExperienceSummary] {
        do {
            let cityName = MockData.cities.first(where: { $0.id == cityID })?.name ?? "Unknown"

            let allExps: [DBExperience] = try await client
                .from("experiences")
                .select()
                .eq("user_id", value: userID)
                .order("created_at", ascending: false)
                .execute()
                .value

            let dbExps = allExps.filter { dbExp in
                let expCity = dbExp.city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let targetCity = cityName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return expCity == targetCity || expCity.contains(targetCity) || targetCity.contains(expCity)
            }

            let profilesMap = await fetchProfiles(for: [userID])
            let creator = profilesMap[userID] ?? ProfileSummary(
                id: userID,
                username: "traveler",
                displayName: "Traveler",
                avatarURL: nil,
                isVerified: false
            )

            var summaries: [ExperienceSummary] = []
            for dbExp in dbExps {
                let stopsPreviews = dbExp.stops.map { stopName in
                    StopPreview(id: UUID(), name: stopName, emoji: nil)
                }

                let parsedURLs = dbExp.image?.values.compactMap { URL(string: $0) } ?? []
                let imageURLs = parsedURLs.isEmpty ? [defaultCoverForCategory(dbExp.title)].compactMap { $0 } : parsedURLs

                let summary = ExperienceSummary(
                    id: dbExp.id,
                    cityID: cityID,
                    title: dbExp.title,
                    imageURLs: imageURLs,
                    creator: creator,
                    durationMinutes: max(30, dbExp.stops.count * 30),
                    costLevel: .budget,
                    estimatedCostUSD: nil,
                    saveCount: 0,
                    likeCount: 0,
                    completionCount: 0,
                    stops: stopsPreviews,
                    rating: dbExp.rating
                )
                summaries.append(summary)
            }
            return summaries
        } catch {
            print("Failed to fetch user experiences for \(cityID) from Supabase: \(error)")
            return []
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
