import Foundation
import Supabase

struct SupabaseProfileRepository: ProfileRepository {
    private var client: SupabaseClient {
        get throws {
            guard let client = SupabaseManager.client else {
                throw RepositoryError.backendUnavailable
            }
            return client
        }
    }

    func fetchProfile(username: String) async throws -> Profile {
        let normalized = UsernameValidator.normalize(username)
        var row: ProfileRow = try await client
            .from("profiles")
            .select()
            .eq("username", value: normalized)
            .single()
            .execute()
            .value

        let followerCount: Int = (try? await client
            .from("follows")
            .select("*", head: true, count: .exact)
            .eq("following_id", value: row.id)
            .execute()
            .count) ?? row.followerCount

        let followingCount: Int = (try? await client
            .from("follows")
            .select("*", head: true, count: .exact)
            .eq("follower_id", value: row.id)
            .execute()
            .count) ?? row.followingCount

        row.followerCount = followerCount
        row.followingCount = followingCount
        return row.profile
    }

    func fetchProfile(id: UUID) async throws -> Profile {
        var row: ProfileRow = try await client
            .from("profiles")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value

        let followerCount: Int = (try? await client
            .from("follows")
            .select("*", head: true, count: .exact)
            .eq("following_id", value: id)
            .execute()
            .count) ?? row.followerCount

        let followingCount: Int = (try? await client
            .from("follows")
            .select("*", head: true, count: .exact)
            .eq("follower_id", value: id)
            .execute()
            .count) ?? row.followingCount

        row.followerCount = followerCount
        row.followingCount = followingCount
        return row.profile
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
        let client = try client
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
        // Strip characters with meaning in the PostgREST `or`/`ilike` syntax so
        // user input can never restructure the filter expression.
        let sanitized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "_" || $0 == " " || $0 == "-" }
            .map(String.init)
            .joined()
            .prefix(30)
        guard !sanitized.isEmpty else { return [] }

        let rows: [ProfileRow] = try await client
            .from("profiles")
            .select()
            .or("username.ilike.%\(sanitized)%,display_name.ilike.%\(sanitized)%")
            .limit(20)
            .execute()
            .value
        return rows.map { $0.profile.summary }
    }

    func isFollowing(followerID: UUID, followingID: UUID) async throws -> Bool {
        struct FollowRow: Decodable { let follower_id: UUID }
        let rows: [FollowRow] = try await client
            .from("follows")
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
        try await client
            .from("follows")
            .upsert(
                FollowInsert(follower_id: followerID, following_id: followingID),
                onConflict: "follower_id,following_id",
                ignoreDuplicates: true
            )
            .execute()
    }

    func unfollow(followerID: UUID, followingID: UUID) async throws {
        try await client
            .from("follows")
            .delete()
            .eq("follower_id", value: followerID)
            .eq("following_id", value: followingID)
            .execute()
    }

    func syncContactHashes(_ hashes: [ContactHash]) async throws {
        struct HashPayload: Encodable {
            let hash: String
            let kind: String
        }
        struct Params: Encodable {
            let p_hashes: [HashPayload]
        }

        var merged = hashes
        if let email = try? await client.auth.session.user.email,
           let own = ContactSyncService.hashEmail(email) {
            if !merged.contains(where: { $0.hash == own.hash }) {
                merged.append(own)
            }
        }

        let payload = merged.map { HashPayload(hash: $0.hash, kind: $0.kind.rawValue) }
        try await client
            .rpc("sync_contact_hashes", params: Params(p_hashes: payload))
            .execute()
    }

    func fetchSuggestedUsers(limit: Int) async throws -> [SuggestedUser] {
        struct Params: Encodable {
            let p_limit: Int
        }
        struct SuggestedRow: Decodable {
            let id: UUID
            let username: String
            let display_name: String
            let bio: String?
            let avatar_url: String?
            let home_city_id: UUID?
            let follower_count: Int
            let following_count: Int
            let experience_count: Int
            let completion_count: Int
            let is_verified: Bool
            let selected_vibes: [String]?
            let onboarding_location: String?
            let source: String
            let mutual_count: Int
            let sample_mutual_name: String?
        }

        let rows: [SuggestedRow] = try await client
            .rpc("fetch_suggested_users", params: Params(p_limit: limit))
            .execute()
            .value

        return rows.map { row in
            let profile = Profile(
                id: row.id,
                username: row.username,
                displayName: row.display_name,
                bio: row.bio,
                avatarURL: row.avatar_url.flatMap(URL.init(string:)),
                homeCityID: row.home_city_id,
                homeCityName: row.onboarding_location,
                followerCount: row.follower_count,
                followingCount: row.following_count,
                experienceCount: row.experience_count,
                completionCount: row.completion_count,
                isVerified: row.is_verified,
                selectedVibes: row.selected_vibes,
                onboardingLocation: row.onboarding_location,
                isFollowing: false
            )
            return SuggestedUser(
                profile: profile,
                source: SuggestedUserSource(rawValue: row.source) ?? .popular,
                mutualCount: row.mutual_count,
                sampleMutualName: row.sample_mutual_name
            )
        }
    }

    func fetchCreatedExperiences(userID: UUID, page: Int) async throws -> Paginated<ExperienceSummary> {
        let client = try client
        let pageSize = ProfileLimits.pageSize
        let from = page * pageSize
        let to = from + pageSize - 1

        let rows: [SupabaseExperienceRepository.DBExperienceRow] = try await client
            .from("experiences")
            .select(SupabaseExperienceRepository.experienceSelect)
            .eq("user_id", value: userID)
            .eq("is_published", value: true)
            .order("created_at", ascending: false)
            .range(from: from, to: to)
            .execute()
            .value

        let mapper = SupabaseExperienceRepository()
        return Paginated(
            items: rows.map { mapper.summary(from: $0) },
            page: page,
            hasMore: rows.count == pageSize
        )
    }

    func fetchSavedExperiences(userID: UUID, page: Int) async throws -> Paginated<ExperienceSummary> {
        let client = try client
        let pageSize = ProfileLimits.pageSize
        let from = page * pageSize
        let to = from + pageSize - 1

        struct SaveRow: Decodable { let experience_id: UUID }
        let rows: [SaveRow] = try await client
            .from("experience_saves")
            .select("experience_id")
            .eq("user_id", value: userID.uuidString.lowercased())
            .order("created_at", ascending: false)
            .range(from: from, to: to)
            .execute()
            .value

        guard !rows.isEmpty else {
            return Paginated(items: [], page: page, hasMore: false)
        }

        let expIDs = rows.map { $0.experience_id.uuidString.lowercased() }

        // Hydrate: real/published + shadow rows both live in experiences.
        let exps: [SupabaseExperienceRepository.DBExperienceRow] = try await client
            .from("experiences")
            .select(SupabaseExperienceRepository.experienceSelect)
            .in("id", values: expIDs)
            .execute()
            .value

        let mapper = SupabaseExperienceRepository()
        let byID = Dictionary(uniqueKeysWithValues: exps.map { ($0.id, mapper.summary(from: $0)) })
        let ordered = rows.compactMap { byID[$0.experience_id] }

        return Paginated(items: ordered, page: page, hasMore: rows.count == pageSize)
    }

    func fetchCompletedExperiences(userID: UUID, page: Int) async throws -> Paginated<CompletedExperienceItem> {
        let client = try client
        let pageSize = ProfileLimits.pageSize
        let from = page * pageSize
        let to = from + pageSize - 1

        struct CompletionRow: Decodable {
            let id: UUID
            let experience_id: UUID
            let completed_at: Date
            let note: String?
        }

        let rows: [CompletionRow] = try await client
            .from("experience_completions")
            .select("id, experience_id, completed_at, note")
            .eq("user_id", value: userID)
            .order("completed_at", ascending: false)
            .range(from: from, to: to)
            .execute()
            .value

        guard !rows.isEmpty else {
            return Paginated(items: [], page: page, hasMore: false)
        }

        let expIDs = rows.map { $0.experience_id.uuidString.lowercased() }
        let exps: [SupabaseExperienceRepository.DBExperienceRow] = try await client
            .from("experiences")
            .select(SupabaseExperienceRepository.experienceSelect)
            .in("id", values: expIDs)
            .execute()
            .value

        let mapper = SupabaseExperienceRepository()
        let byID = Dictionary(uniqueKeysWithValues: exps.map { ($0.id, mapper.summary(from: $0)) })

        let items = rows.compactMap { row -> CompletedExperienceItem? in
            guard let summary = byID[row.experience_id] else { return nil }
            return CompletedExperienceItem(id: row.id, experience: summary, completedAt: row.completed_at, note: row.note)
        }

        return Paginated(items: items, page: page, hasMore: rows.count == pageSize)
    }

    // MARK: - Private

    private func fetchFollowList(
        column: String,
        joinColumn: String,
        userID: UUID,
        query: String?,
        page: Int
    ) async throws -> Paginated<ProfileSummary> {
        let client = try client
        let pageSize = ProfileLimits.pageSize
        let from = page * pageSize
        let to = from + pageSize - 1

        struct Edge: Decodable {
            let follower_id: UUID
            let following_id: UUID
            let created_at: Date
        }

        let edges: [Edge] = try await client
            .from("follows")
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
