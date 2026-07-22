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
        let description: String
        let city: String
        let stops: [String]
        let image: String?
        let created_at: Date
    }

    private struct DBExperience: Codable {
        let id: UUID
        let user_id: UUID
        let title: String
        let description: String
        let city: String
        let stops: [String]
        let image: String?
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
        description: String,
        cityID: UUID,
        creatorID: UUID,
        stops: [StopPreview],
        imageData: Data?
    ) async throws {
        print("--- SupabaseExperienceRepository.publishExperience starting ---")
        let experienceID = UUID()

        // Match cityID to a name, or default to "Unknown"
        let cityName = MockData.cities.first(where: { $0.id == cityID })?.name ?? "Unknown"

        var publicURLString: String? = nil

        if let data = imageData {
            let path = "\(experienceID.uuidString.lowercased())/cover.jpg"
            print("Uploading cover image to Supabase Storage: path=\(path), size=\(data.count) bytes")
            
            _ = try await client.storage
                .from("experiences")
                .upload(
                    path,
                    data: data,
                    options: FileOptions(contentType: "image/jpeg")
                )
            
            let publicURL = try client.storage.from("experiences").getPublicURL(path: path)
            publicURLString = publicURL.absoluteString
            print("Successfully uploaded cover image to Supabase Storage. Public URL: \(publicURLString ?? "nil")")
        }

        let experienceInsert = DBExperienceInsert(
            id: experienceID,
            user_id: creatorID,
            title: title,
            description: description,
            city: cityName,
            stops: stops.map { $0.name },
            image: publicURLString,
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
            let targetID = id.uuidString.lowercased()
            let dbExps: [DBExperience] = try await client
                .from("experiences")
                .select()
                .execute()
                .value

            guard let dbExp = dbExps.first(where: { $0.id.uuidString.lowercased() == targetID }) else {
                throw RepositoryError.notFound
            }

            let profilesMap = await fetchProfiles(for: [dbExp.user_id])
            let creator = profilesMap[dbExp.user_id] ?? ProfileSummary(
                id: dbExp.user_id,
                username: "traveler",
                displayName: "Traveler",
                avatarURL: nil,
                isVerified: false
            )

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

            let matchedCity = MockData.cities.first(where: { $0.name.localizedCaseInsensitiveCompare(dbExp.city) == .orderedSame })
            let cityID = matchedCity?.id ?? UUID()

            return Experience(
                id: dbExp.id,
                cityID: cityID,
                creator: creator,
                title: dbExp.title,
                description: dbExp.description,
                coverImageURL: dbExp.image.flatMap { URL(string: $0) },
                durationMinutes: max(30, stops.count * 30),
                costLevel: .budget,
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
                    StopPreview(id: UUID(), name: stopName, emoji: "📍")
                }

                let creator = profilesMap[dbExp.user_id] ?? ProfileSummary(
                    id: dbExp.user_id,
                    username: "traveler",
                    displayName: "Traveler",
                    avatarURL: nil,
                    isVerified: false
                )

                let summary = ExperienceSummary(
                    id: dbExp.id,
                    cityID: cityID,
                    title: dbExp.title,
                    coverImageURL: dbExp.image.flatMap { URL(string: $0) },
                    creator: creator,
                    durationMinutes: max(30, dbExp.stops.count * 30),
                    costLevel: .budget,
                    estimatedCostUSD: nil,
                    saveCount: 0,
                    likeCount: 0,
                    completionCount: 0,
                    stops: stopsPreviews
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
                    StopPreview(id: UUID(), name: stopName, emoji: "📍")
                }

                let summary = ExperienceSummary(
                    id: dbExp.id,
                    cityID: cityID,
                    title: dbExp.title,
                    coverImageURL: dbExp.image.flatMap { URL(string: $0) },
                    creator: creator,
                    durationMinutes: max(30, dbExp.stops.count * 30),
                    costLevel: .budget,
                    estimatedCostUSD: nil,
                    saveCount: 0,
                    likeCount: 0,
                    completionCount: 0,
                    stops: stopsPreviews
                )
                summaries.append(summary)
            }
            return summaries
        } catch {
            print("Failed to fetch user experiences for \(cityID) from Supabase: \(error)")
            return []
        }
    }
}
