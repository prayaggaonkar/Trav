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

        profile.followerCount = followersCount
        profile.followingCount = followingCount
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

        profile.followerCount = followersCount
        profile.followingCount = followingCount
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
        let path = "\(userID.uuidString.lowercased())/avatar.jpg"
        _ = try await client.storage
            .from("avatars")
            .upload(
                path,
                data: imageData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
        return try client.storage.from("avatars").getPublicURL(path: path)
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

        let items = rows.map { row -> ExperienceSummary in
            let cityID = MockData.cities.first { $0.name.caseInsensitiveCompare(row.city) == .orderedSame }?.id ?? UUID()
            return ExperienceSummary(
                id: row.id,
                cityID: cityID,
                title: row.title,
                coverImageURL: row.image.flatMap(URL.init(string:)),
                creator: creator,
                durationMinutes: max(row.stops.count, 1) * 30,
                costLevel: .budget,
                estimatedCostUSD: nil,
                saveCount: row.save_count ?? 0,
                likeCount: 0,
                completionCount: row.completion_count ?? 0,
                stops: row.stops.map { StopPreview(id: UUID(), name: $0, emoji: nil) },
                cityName: row.city
            )
        }

        return Paginated(items: items, page: page, hasMore: items.count == pageSize)
    }

    func fetchSavedExperiences(userID: UUID, page: Int) async throws -> Paginated<ExperienceSummary> {
        let pageSize = ProfileLimits.pageSize
        let from = page * pageSize
        let to = from + pageSize - 1
        let user = userID.uuidString.lowercased()

        struct SaveJoin: Decodable {
            let created_at: Date?
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

        var items: [ExperienceSummary] = []
        var seen = Set<UUID>()

        let rows: [SaveJoin] = (try? await client
            .from("experience_saves")
            .select("created_at, experience:experiences(*)")
            .eq("user_id", value: user)
            .order("created_at", ascending: false)
            .range(from: from, to: to)
            .execute()
            .value) ?? []

        for row in rows {
            guard let exp = row.experience, seen.insert(exp.id).inserted else { continue }
            let cityID = MockData.cities.first { $0.name.caseInsensitiveCompare(exp.city) == .orderedSame }?.id ?? UUID()
            items.append(
                ExperienceSummary(
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
            )
        }

        // Merge legacy `saves` bookmarks that may not have an experience_saves row yet.
        if page == 0 {
            struct LegacySave: Decodable { let place_id: String }
            let legacy: [LegacySave] = (try? await client
                .from("saves")
                .select("place_id")
                .eq("user_id", value: user)
                .execute()
                .value) ?? []

            for row in legacy {
                let id = StableUUID.from(row.place_id)
                guard seen.insert(id).inserted else { continue }

                if let exp: ExperienceJoin = try? await client
                    .from("experiences")
                    .select("id, title, city, stops, image, save_count, completion_count, user_id")
                    .eq("id", value: id.uuidString.lowercased())
                    .single()
                    .execute()
                    .value {
                    let cityID = MockData.cities.first { $0.name.caseInsensitiveCompare(exp.city) == .orderedSame }?.id ?? UUID()
                    items.append(
                        ExperienceSummary(
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
                    )
                    continue
                }

                // Fall back to a place row when the bookmark was a feed place.
                struct PlaceRow: Decodable {
                    let id: String
                    let name: String
                    let basic_category: String?
                    let stops: [String]?
                }
                if let place: PlaceRow = try? await client
                    .from("places")
                    .select("id, name, basic_category, stops")
                    .eq("id", value: row.place_id)
                    .single()
                    .execute()
                    .value {
                    let stopNames: [String]
                    if let stops = place.stops, !stops.isEmpty {
                        stopNames = stops
                    } else {
                        stopNames = [place.name]
                    }
                    items.append(
                        ExperienceSummary(
                            id: id,
                            cityID: UUID(),
                            title: place.name,
                            coverImageURL: nil,
                            creator: ProfileSummary(
                                id: userID,
                                username: "traveler",
                                displayName: "Rec by Trav",
                                avatarURL: nil,
                                isVerified: true
                            ),
                            durationMinutes: max(stopNames.count, 1) * 30,
                            costLevel: .budget,
                            estimatedCostUSD: nil,
                            saveCount: 1,
                            likeCount: 0,
                            completionCount: 0,
                            stops: stopNames.map { StopPreview(id: UUID(), name: $0, emoji: nil) },
                            cityName: nil
                        )
                    )
                }
            }
        }

        return Paginated(items: items, page: page, hasMore: rows.count == pageSize)
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
