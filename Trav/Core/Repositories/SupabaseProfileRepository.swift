import Foundation
import Supabase

struct SupabaseProfileRepository: ProfileRepository {
    private var client: SupabaseClient {
        guard let client = SupabaseManager.client else {
            preconditionFailure("SupabaseProfileRepository used without a configured SupabaseClient.")
        }
        return client
    }

    func fetchProfile(username: String) async throws -> Profile {
        let normalized = UsernameValidator.normalize(username)
        let row: ProfileRow = try await client
            .from("profiles")
            .select()
            .eq("username", value: normalized)
            .single()
            .execute()
            .value
        var profile = row.profile

        let followersCount = (try? await client
            .from("followers")
            .select("follower_id", count: .exact)
            .eq("following_id", value: profile.id)
            .execute()
            .count) ?? profile.followerCount

        let followingCount = (try? await client
            .from("followers")
            .select("following_id", count: .exact)
            .eq("follower_id", value: profile.id)
            .execute()
            .count) ?? profile.followingCount

        let createdExpCount = (try? await client
            .from("experiences")
            .select("id", count: .exact)
            .eq("user_id", value: profile.id)
            .neq("description", value: ProfileLimits.bookmarkDescriptionSentinel)
            .execute()
            .count) ?? profile.experienceCount

        profile.followerCount = followersCount
        profile.followingCount = followingCount
        profile.experienceCount = createdExpCount
        return profile
    }

    func fetchProfile(id: UUID) async throws -> Profile {
        let row: ProfileRow = try await client
            .from("profiles")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
        var profile = row.profile

        let followersCount = (try? await client
            .from("followers")
            .select("follower_id", count: .exact)
            .eq("following_id", value: id)
            .execute()
            .count) ?? profile.followerCount

        let followingCount = (try? await client
            .from("followers")
            .select("following_id", count: .exact)
            .eq("follower_id", value: id)
            .execute()
            .count) ?? profile.followingCount

        let createdExpCount = (try? await client
            .from("experiences")
            .select("id", count: .exact)
            .eq("user_id", value: id)
            .neq("description", value: ProfileLimits.bookmarkDescriptionSentinel)
            .execute()
            .count) ?? profile.experienceCount

        profile.followerCount = followersCount
        profile.followingCount = followingCount
        profile.experienceCount = createdExpCount
        return profile
    }

    func updateProfile(userID: UUID, update: ProfileUpdate) async throws -> Profile {
        struct ProfilePatch: Encodable {
            var display_name: String?
            var username: String?
            var bio: String?
            /// Persisted on the existing `onboarding_location` column (compatible with live schema).
            var onboarding_location: String?
            var avatar_url: String?
            var clearBio: Bool = false
            var clearHomeCity: Bool = false
            var clearAvatar: Bool = false

            enum CodingKeys: String, CodingKey {
                case display_name, username, bio, onboarding_location, avatar_url
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                if let display_name { try container.encode(display_name, forKey: .display_name) }
                if let username { try container.encode(username, forKey: .username) }
                if clearBio {
                    try container.encodeNil(forKey: .bio)
                } else if let bio {
                    try container.encode(bio, forKey: .bio)
                }
                if clearHomeCity {
                    try container.encodeNil(forKey: .onboarding_location)
                } else if let onboarding_location {
                    try container.encode(onboarding_location, forKey: .onboarding_location)
                }
                if clearAvatar {
                    try container.encodeNil(forKey: .avatar_url)
                } else if let avatar_url {
                    try container.encode(avatar_url, forKey: .avatar_url)
                }
            }

            var isEmpty: Bool {
                display_name == nil && username == nil && bio == nil && onboarding_location == nil
                    && avatar_url == nil && !clearBio && !clearHomeCity && !clearAvatar
            }
        }

        var patch = ProfilePatch()
        patch.display_name = update.displayName
        patch.username = update.username.map(UsernameValidator.normalize)
        patch.bio = update.bio
        patch.onboarding_location = update.homeCityName
        patch.avatar_url = update.avatarURL?.absoluteString
        patch.clearBio = update.clearBio
        patch.clearHomeCity = update.clearHomeCity
        patch.clearAvatar = update.clearAvatar

        guard !patch.isEmpty else {
            return try await fetchProfile(id: userID)
        }

        try await client
            .from("profiles")
            .update(patch)
            .eq("id", value: userID)
            .execute()

        if update.clearAvatar {
            let path = "\(userID.uuidString.lowercased())/avatar.jpg"
            try? await client.storage.from("avatars").remove(paths: [path])
        }

        return try await fetchProfile(id: userID)
    }

    func checkUsernameAvailability(_ username: String, excludingUserID: UUID?) async throws -> UsernameAvailability {
        let format = UsernameValidator.validateFormat(username)
        if case .invalid = format { return format }

        let normalized = UsernameValidator.normalize(username)

        do {
            struct Params: Encodable {
                let candidate: String
                let excluding_user_id: UUID?
            }
            let available: Bool = try await client
                .rpc("is_username_available", params: Params(candidate: normalized, excluding_user_id: excludingUserID))
                .execute()
                .value
            return available ? .available : .unavailable(reason: "That username is taken.")
        } catch {
            let rows: [ProfileRow] = try await client
                .from("profiles")
                .select()
                .ilike("username", pattern: normalized)
                .limit(1)
                .execute()
                .value
            if let existing = rows.first, existing.id != excludingUserID {
                return .unavailable(reason: "That username is taken.")
            }
            return .available
        }
    }

    func uploadAvatar(userID: UUID, imageData: Data) async throws -> URL {
        // Must use the authenticated client so storage RLS (`auth.uid()`) can authorize
        // the write. `serviceClient` has no user session and owner-write policies reject it.
        let path = "\(userID.uuidString.lowercased())/avatar.jpg"
        _ = try await client.storage
            .from("avatars")
            .upload(
                path,
                data: imageData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
        let publicURL = try client.storage.from("avatars").getPublicURL(path: path)
        // Bust URL caches (AsyncImage / CDN) so a replaced avatar refreshes immediately.
        var components = URLComponents(url: publicURL, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970))))
        components?.queryItems = items
        return components?.url ?? publicURL
    }

    func fetchFollowers(userID: UUID, query: String?, page: Int) async throws -> Paginated<ProfileSummary> {
        try await fetchFollowList(
            column: "following_id",
            joinColumn: "follower_id",
            userID: userID,
            query: query,
            page: page
        )
    }

    func fetchFollowing(userID: UUID, query: String?, page: Int) async throws -> Paginated<ProfileSummary> {
        try await fetchFollowList(
            column: "follower_id",
            joinColumn: "following_id",
            userID: userID,
            query: query,
            page: page
        )
    }

    func searchUsers(query: String) async throws -> [ProfileSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        do {
            let rows: [ProfileRow] = try await client
                .from("profiles")
                .select()
                .or("username.ilike.%\(trimmed)%,display_name.ilike.%\(trimmed)%")
                .limit(20)
                .execute()
                .value
            return rows.map { $0.profile.summary }
        } catch {
            print("Failed to search users in Supabase: \(error)")
            return []
        }
    }

    func isFollowing(followerID: UUID, followingID: UUID) async throws -> Bool {
        struct FollowRow: Decodable { let follower_id: UUID }
        let rows: [FollowRow] = try await client
            .from("followers")
            .select("follower_id")
            .eq("follower_id", value: followerID)
            .eq("following_id", value: followingID)
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }

    func follow(followerID: UUID, followingID: UUID) async throws {
        struct FollowInsert: Encodable {
            let follower_id: UUID
            let following_id: UUID
        }
        do {
            try await client
                .from("followers")
                .insert(FollowInsert(follower_id: followerID, following_id: followingID))
                .execute()
        } catch {
            // Row already exists or constraint matched; ensure call succeeds idempotently.
            print("SupabaseProfileRepository.follow notice: \(error)")
        }
    }

    func unfollow(followerID: UUID, followingID: UUID) async throws {
        do {
            try await client
                .from("followers")
                .delete()
                .eq("follower_id", value: followerID)
                .eq("following_id", value: followingID)
                .execute()
        } catch {
            print("SupabaseProfileRepository.unfollow notice: \(error)")
        }
    }

    func fetchCreatedExperiences(userID: UUID, page: Int) async throws -> Paginated<ExperienceSummary> {
        let pageSize = ProfileLimits.pageSize
        let from = page * pageSize
        let to = from + pageSize - 1

        struct DBExperience: Decodable {
            let id: UUID
            let title: String
            let description: String
            let city: String
            let stops: [String]
            let image: String?
            let save_count: Int?
            let completion_count: Int?
            let user_id: UUID
        }

        let rows: [DBExperience] = try await client
            .from("experiences")
            .select()
            .eq("user_id", value: userID)
            .neq("description", value: ProfileLimits.bookmarkDescriptionSentinel)
            .order("created_at", ascending: false)
            .range(from: from, to: to)
            .execute()
            .value

        let creator = (try? await fetchProfile(id: userID))?.summary
            ?? ProfileSummary(id: userID, username: "traveler", displayName: "Traveler", avatarURL: nil, isVerified: false)

        let expIDs = rows.map { $0.id.uuidString.lowercased() }
        struct SaveCountRow: Decodable { let experience_id: UUID }
        let saveRows: [SaveCountRow] = expIDs.isEmpty ? [] : ((try? await client
            .from("saved_experiences")
            .select("experience_id")
            .in("experience_id", values: expIDs)
            .execute()
            .value) ?? [])

        var saveCounts: [UUID: Int] = [:]
        for r in saveRows {
            saveCounts[r.experience_id, default: 0] += 1
        }

        let items = rows.map { row -> ExperienceSummary in
            let cityID = MockData.cities.first { $0.name.caseInsensitiveCompare(row.city) == .orderedSame }?.id ?? UUID()
            let liveSaveCount = saveCounts[row.id] ?? row.save_count ?? 0
            return ExperienceSummary(
                id: row.id,
                cityID: cityID,
                title: row.title,
                coverImageURL: row.image.flatMap(URL.init(string:)),
                creator: creator,
                durationMinutes: max(row.stops.count, 1) * 30,
                costLevel: .budget,
                estimatedCostUSD: nil,
                saveCount: liveSaveCount,
                likeCount: 0,
                completionCount: row.completion_count ?? 0,
                stops: row.stops.map { StopPreview(id: UUID(), name: $0, emoji: nil) },
                cityName: row.city
            )
        }

        return Paginated(items: items, page: page, hasMore: rows.count == pageSize)
    }

    func fetchSavedExperiences(userID: UUID, page: Int) async throws -> Paginated<ExperienceSummary> {
        let pageSize = ProfileLimits.pageSize
        let from = page * pageSize
        let to = from + pageSize - 1
        let user = userID.uuidString.lowercased()

        struct SaveRow: Decodable {
            let experience_id: UUID
        }

        struct ExperienceJoin: Decodable {
            let id: UUID
            let title: String
            let city: String
            let stops: [String]
            let image: String?
            let save_count: Int?
            let completion_count: Int?
            let user_id: UUID
        }

        struct PlaceJoin: Decodable {
            let id: String
            let name: String
            let basic_category: String
            let latitude: Double
            let longitude: Double
            let stops: [String]?
        }

        var items: [ExperienceSummary] = []
        var seen = Set<UUID>()

        var rows: [SaveRow] = []
        do {
            rows = try await client
                .from("saved_experiences")
                .select("experience_id")
                .eq("user_id", value: user)
                .order("created_at", ascending: false)
                .range(from: from, to: to)
                .execute()
                .value
        } catch {
            print("SupabaseProfileRepository.fetchSavedExperiences notice (saved_experiences): \(error)")
        }

        if rows.isEmpty {
            do {
                rows = try await client
                    .from("experience_saves")
                    .select("experience_id")
                    .eq("user_id", value: user)
                    .order("created_at", ascending: false)
                    .range(from: from, to: to)
                    .execute()
                    .value
            } catch {
                print("SupabaseProfileRepository.fetchSavedExperiences notice (experience_saves): \(error)")
            }
        }

        if !rows.isEmpty {
            let expIDs = rows.map { $0.experience_id.uuidString.lowercased() }

            let exps: [ExperienceJoin] = (try? await client
                .from("experiences")
                .select("id, title, city, stops, image, save_count, completion_count, user_id")
                .in("id", values: expIDs)
                .execute()
                .value) ?? []

            struct SaveCountRow: Decodable { let experience_id: UUID }
            let saveRows: [SaveCountRow] = (try? await client
                .from("saved_experiences")
                .select("experience_id")
                .in("experience_id", values: expIDs)
                .execute()
                .value) ?? []

            var saveCounts: [UUID: Int] = [:]
            for r in saveRows {
                saveCounts[r.experience_id, default: 0] += 1
            }

            let userIDs = Array(Set(exps.map(\.user_id)))
            let creatorsMap = await fetchCreatorProfiles(for: userIDs)

            let expByID = Dictionary(uniqueKeysWithValues: exps.map { ($0.id, $0) })

            let foundExpIDs = Set(exps.map(\.id))
            let missingExpIDs = rows.map(\.experience_id).filter { !foundExpIDs.contains($0) }
            var placesByID: [UUID: PlaceJoin] = [:]
            if !missingExpIDs.isEmpty {
                let placeIDs = missingExpIDs.map { $0.uuidString.lowercased() }
                let places: [PlaceJoin] = (try? await client
                    .from("places")
                    .select("id, name, basic_category, latitude, longitude, stops")
                    .in("id", values: placeIDs)
                    .execute()
                    .value) ?? []
                for p in places {
                    if let u = UUID(uuidString: p.id) {
                        placesByID[u] = p
                    }
                }
            }

            for row in rows {
                guard seen.insert(row.experience_id).inserted else { continue }
                if let exp = expByID[row.experience_id] {
                    let cityID = MockData.cities.first { $0.name.caseInsensitiveCompare(exp.city) == .orderedSame }?.id ?? UUID()
                    let liveSaveCount = saveCounts[exp.id] ?? exp.save_count ?? 0
                    let creator = creatorsMap[exp.user_id] ?? ProfileSummary(
                        id: exp.user_id,
                        username: "traveler",
                        displayName: "Traveler",
                        avatarURL: nil,
                        isVerified: false
                    )
                    items.append(
                        ExperienceSummary(
                            id: exp.id,
                            cityID: cityID,
                            title: exp.title,
                            coverImageURL: exp.image.flatMap(URL.init(string:)),
                            creator: creator,
                            durationMinutes: max(exp.stops.count, 1) * 30,
                            costLevel: .budget,
                            estimatedCostUSD: nil,
                            saveCount: liveSaveCount,
                            likeCount: 0,
                            completionCount: exp.completion_count ?? 0,
                            stops: exp.stops.map { StopPreview(id: UUID(), name: $0, emoji: nil) },
                            cityName: exp.city
                        )
                    )
                } else if let place = placesByID[row.experience_id] {
                    let matchedCity = MockData.cities.first(where: { $0.name.localizedCaseInsensitiveCompare("Berkeley") == .orderedSame })
                    let cityID = matchedCity?.id ?? UUID()
                    let recCreator = ProfileSummary(
                        id: UUID(),
                        username: "rec_by_trav",
                        displayName: "Rec by Trav",
                        avatarURL: nil,
                        isVerified: true
                    )
                    items.append(
                        ExperienceSummary(
                            id: row.experience_id,
                            cityID: cityID,
                            title: place.name,
                            coverImageURL: nil,
                            creator: recCreator,
                            durationMinutes: 45,
                            costLevel: .budget,
                            estimatedCostUSD: nil,
                            saveCount: 1,
                            likeCount: 0,
                            completionCount: 0,
                            stops: [StopPreview(id: UUID(), name: place.name, emoji: nil)],
                            cityName: "Berkeley"
                        )
                    )
                }
            }
        }

        return Paginated(items: items, page: page, hasMore: rows.count == pageSize)
    }

    private func fetchCreatorProfiles(for userIDs: [UUID]) async -> [UUID: ProfileSummary] {
        guard !userIDs.isEmpty else { return [:] }
        struct DBProfileSummary: Decodable {
            let id: UUID
            let username: String
            let display_name: String
            let avatar_url: String?
            let is_verified: Bool
        }
        do {
            let dbProfiles: [DBProfileSummary] = try await client
                .from("profiles")
                .select("id, username, display_name, avatar_url, is_verified")
                .in("id", values: userIDs.map(\.uuidString))
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
            print("Failed to fetch creator profiles for \(userIDs): \(error)")
            return [:]
        }
    }


    func fetchCompletedExperiences(userID: UUID, page: Int) async throws -> Paginated<CompletedExperienceItem> {
        let pageSize = ProfileLimits.pageSize
        let from = page * pageSize
        let to = from + pageSize - 1

        struct CompletionJoin: Decodable {
            let id: UUID
            let completed_at: Date
            let note: String?
            let experience: ExperienceJoin?
        }
        struct ExperienceJoin: Decodable {
            let id: UUID
            let title: String
            let city: String
            let stops: [String]
            let image: String?
            let save_count: Int?
            let completion_count: Int?
            let user_id: UUID
        }

        let rows: [CompletionJoin] = try await client
            .from("experience_completions")
            .select("id, completed_at, note, experience:experiences(*)")
            .eq("user_id", value: userID)
            .order("completed_at", ascending: false)
            .range(from: from, to: to)
            .execute()
            .value

        let items = rows.compactMap { row -> CompletedExperienceItem? in
            guard let exp = row.experience else { return nil }
            let cityID = MockData.cities.first { $0.name.caseInsensitiveCompare(exp.city) == .orderedSame }?.id ?? UUID()
            let summary = ExperienceSummary(
                id: exp.id,
                cityID: cityID,
                title: exp.title,
                coverImageURL: exp.image.flatMap(URL.init(string:)),
                creator: ProfileSummary(id: exp.user_id, username: "traveler", displayName: "Traveler", avatarURL: nil, isVerified: false),
                durationMinutes: max(exp.stops.count, 1) * 30,
                costLevel: .budget,
                estimatedCostUSD: nil,
                saveCount: exp.save_count ?? 0,
                likeCount: 0,
                completionCount: exp.completion_count ?? 0,
                stops: exp.stops.map { StopPreview(id: UUID(), name: $0, emoji: nil) },
                cityName: exp.city
            )
            return CompletedExperienceItem(id: row.id, experience: summary, completedAt: row.completed_at, note: row.note)
        }

        return Paginated(items: items, page: page, hasMore: items.count == pageSize)
    }

    // MARK: - Private

    private func fetchFollowList(
        column: String,
        joinColumn: String,
        userID: UUID,
        query: String?,
        page: Int
    ) async throws -> Paginated<ProfileSummary> {
        let pageSize = ProfileLimits.pageSize
        let from = page * pageSize
        let to = from + pageSize - 1

        // Fetch follow edges then hydrate profiles (keeps query simple across schema versions).
        struct Edge: Decodable {
            let follower_id: UUID
            let following_id: UUID
            let created_at: Date
        }

        let edges: [Edge] = try await client
            .from("followers")
            .select()
            .eq(column, value: userID)
            .order("created_at", ascending: false)
            .range(from: from, to: to)
            .execute()
            .value

        let ids = edges.map { joinColumn == "follower_id" ? $0.follower_id : $0.following_id }
        guard !ids.isEmpty else {
            return Paginated(items: [], page: page, hasMore: false)
        }

        var profiles: [ProfileRow] = try await client
            .from("profiles")
            .select()
            .in("id", values: ids.map(\.uuidString))
            .execute()
            .value

        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = query.lowercased()
            profiles = profiles.filter {
                $0.username.lowercased().contains(q) || $0.displayName.lowercased().contains(q)
            }
        }

        let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let ordered = ids.compactMap { byID[$0]?.profile.summary }

        return Paginated(items: ordered, page: page, hasMore: edges.count == pageSize)
    }
}
