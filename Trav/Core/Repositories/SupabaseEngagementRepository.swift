import Foundation
import Supabase

struct SupabaseEngagementRepository: EngagementRepository {
    private var client: SupabaseClient {
        get throws {
            guard let client = SupabaseManager.client else {
                throw RepositoryError.backendUnavailable
            }
            return client
        }
    }

    // MARK: - Bootstrap reads

    func fetchSavedIDs(userID: UUID) async throws -> Set<UUID> {
        struct Row: Decodable { let experience_id: UUID }
        let rows: [Row] = try await client
            .from("experience_saves")
            .select("experience_id")
            .eq("user_id", value: userID.uuidString.lowercased())
            .execute()
            .value
        return Set(rows.map(\.experience_id))
    }

    func fetchCompletedIDs(userID: UUID) async throws -> Set<UUID> {
        struct Row: Decodable { let experience_id: UUID }
        let rows: [Row] = try await client
            .from("experience_completions")
            .select("experience_id")
            .eq("user_id", value: userID.uuidString.lowercased())
            .execute()
            .value
        return Set(rows.map(\.experience_id))
    }

    func fetchLikedIDs(userID: UUID) async throws -> Set<UUID> {
        struct Row: Decodable { let experience_id: UUID }
        let rows: [Row] = try await client
            .from("experience_likes")
            .select("experience_id")
            .eq("user_id", value: userID.uuidString.lowercased())
            .execute()
            .value
        return Set(rows.map(\.experience_id))
    }

    func fetchFollowingIDs(userID: UUID) async throws -> Set<UUID> {
        struct Row: Decodable { let following_id: UUID }
        let rows: [Row] = try await client
            .from("follows")
            .select("following_id")
            .eq("follower_id", value: userID.uuidString.lowercased())
            .execute()
            .value
        return Set(rows.map(\.following_id))
    }

    // MARK: - Point lookups

    func isSaved(userID: UUID, experienceID: UUID) async throws -> Bool {
        struct Row: Decodable { let experience_id: UUID }
        let rows: [Row] = try await client
            .from("experience_saves")
            .select("experience_id")
            .eq("user_id", value: userID.uuidString.lowercased())
            .eq("experience_id", value: experienceID.uuidString.lowercased())
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }

    func isCompleted(userID: UUID, experienceID: UUID) async throws -> Bool {
        struct Row: Decodable { let experience_id: UUID }
        let rows: [Row] = try await client
            .from("experience_completions")
            .select("experience_id")
            .eq("user_id", value: userID.uuidString.lowercased())
            .eq("experience_id", value: experienceID.uuidString.lowercased())
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }

    // MARK: - Toggles

    /// Makes sure an `experiences` row exists before writing a save, rating or
    /// completion that references it.
    ///
    /// Anything discovered through the place provider is a Spot, so it is synced
    /// into the catalog rather than inserted as a private shadow row. That keeps
    /// one canonical row per real-world place, which is what makes ratings and
    /// engagement on spots add up across users.
    private func ensureExperienceExistsInternal(experienceID: UUID, userID: UUID) async {
        guard let client = SupabaseManager.client else { return }
        let idStr = experienceID.uuidString.lowercased()

        struct Existing: Decodable { let id: UUID }
        let existing: [Existing] = (try? await client
            .from("experiences")
            .select("id")
            .eq("id", value: idStr)
            .limit(1)
            .execute()
            .value) ?? []
        if !existing.isEmpty { return }

        let cached = AppleMapsVibeService.shared.cachedExperience(for: experienceID)
        struct ExperienceShadowInsert: Encodable {
            let id: UUID
            let user_id: UUID
            let title: String
            let description: String
            let city: String
            let stops: [String]
            let is_published: Bool
        }
        let spotTitle = (cached?.title.isEmpty == false) ? cached!.title : "Spot"
        let spotCity = (cached?.cityName?.isEmpty == false) ? cached!.cityName! : "San Francisco, CA"
        let shadowInsert = ExperienceShadowInsert(
            id: experienceID,
            user_id: userID,
            title: spotTitle,
            description: "Spot rated by traveler.",
            city: spotCity,
            stops: [spotTitle],
            is_published: true
        )
        _ = try? await client
            .from("experiences")
            .upsert(shadowInsert, onConflict: "id")
            .execute()
    }

    func ensureExperienceExists(for summary: ExperienceSummary, ownerID: UUID) async throws {
        guard let client = SupabaseManager.client else { return }
        let idStr = summary.id.uuidString.lowercased()

        struct Existing: Decodable { let id: UUID }
        let existing: [Existing] = (try? await client
            .from("experiences")
            .select("id")
            .eq("id", value: idStr)
            .limit(1)
            .execute()
            .value) ?? []
        if !existing.isEmpty { return }

        // Upsert exact experience row using summary data so place name & city are 100% exact in Supabase!
        struct ExperienceUpsert: Encodable {
            let id: UUID
            let user_id: UUID
            let title: String
            let description: String
            let city: String
            let city_id: UUID?
            let stops: [String]
            let is_published: Bool
            let category: String?
            let latitude: Double?
            let longitude: Double?
            let spot_key: String?
        }

        let stopNames = summary.stops.map(\.name)
        let firstStop = summary.stops.first
        let cityName = (summary.cityName?.isEmpty == false) ? summary.cityName! : "San Francisco, CA"
        let upsertData = ExperienceUpsert(
            id: summary.id,
            user_id: ownerID,
            title: summary.title,
            description: "Spot rated by traveler.",
            city: cityName,
            city_id: summary.cityID,
            stops: stopNames.isEmpty ? [summary.title] : stopNames,
            is_published: true,
            category: summary.category,
            latitude: summary.latitude ?? firstStop?.latitude,
            longitude: summary.longitude ?? firstStop?.longitude,
            spot_key: summary.spotKey
        )

        _ = try? await client
            .from("experiences")
            .upsert(upsertData, onConflict: "id")
            .execute()
    }

    func toggleSave(userID: UUID, experienceID: UUID) async throws -> Bool {
        let client = try client
        let user = userID.uuidString.lowercased()
        let expIDStr = experienceID.uuidString.lowercased()

        await ensureExperienceExistsInternal(experienceID: experienceID, userID: userID)

        if try await isSaved(userID: userID, experienceID: experienceID) {
            try await unsave(userID: userID, experienceID: experienceID)
            return false
        }

        struct Insert: Encodable {
            let user_id: String
            let experience_id: String
        }
        try await client
            .from("experience_saves")
            .upsert(
                Insert(
                    user_id: user,
                    experience_id: expIDStr
                ),
                onConflict: "user_id,experience_id"
            )
            .execute()
        return true
    }

    func unsave(userID: UUID, experienceID: UUID) async throws {
        let client = try client
        try await client
            .from("experience_saves")
            .delete()
            .eq("user_id", value: userID.uuidString.lowercased())
            .eq("experience_id", value: experienceID.uuidString.lowercased())
            .execute()
    }

    /// Completion is derived from the rating, so undoing it means deleting the
    /// rating; the database cascades the completion row away.
    func removeCompletion(userID: UUID, experienceID: UUID) async throws {
        try await SupabaseRatingRepository().deleteRating(userID: userID, experienceID: experienceID)

        // Belt and braces for databases where the cascade trigger is absent.
        let client = try client
        try? await client
            .from("experience_completions")
            .delete()
            .eq("user_id", value: userID.uuidString.lowercased())
            .eq("experience_id", value: experienceID.uuidString.lowercased())
            .execute()
    }

    func toggleLike(userID: UUID, experienceID: UUID) async throws -> Bool {
        let client = try client
        let user = userID.uuidString.lowercased()
        let experience = experienceID.uuidString.lowercased()

        struct Row: Decodable { let experience_id: UUID }
        let existing: [Row] = try await client
            .from("experience_likes")
            .select("experience_id")
            .eq("user_id", value: user)
            .eq("experience_id", value: experience)
            .limit(1)
            .execute()
            .value

        if !existing.isEmpty {
            try await client
                .from("experience_likes")
                .delete()
                .eq("user_id", value: user)
                .eq("experience_id", value: experience)
                .execute()
            return false
        }

        struct Insert: Encodable {
            let user_id: String
            let experience_id: String
        }
        try await client
            .from("experience_likes")
            .upsert(
                Insert(user_id: user, experience_id: experience),
                onConflict: "user_id,experience_id"
            )
            .execute()
        return true
    }



    // MARK: - Comments

    private static let commentSelect = """
    id, experience_id, author_id, parent_id, body, created_at, \
    author:profiles(id, username, display_name, avatar_url, is_verified)
    """

    private struct DBComment: Decodable {
        let id: UUID
        let experience_id: UUID
        let author_id: UUID
        let parent_id: UUID?
        let body: String
        let created_at: Date
        let author: SupabaseExperienceRepository.DBProfileSummary?

        var comment: Comment {
            Comment(
                id: id,
                experienceID: experience_id,
                author: author?.summary ?? SupabaseExperienceRepository.fallbackCreator(id: author_id),
                parentID: parent_id,
                body: body,
                createdAt: created_at
            )
        }
    }

    func fetchComments(experienceID: UUID, page: Int) async throws -> Paginated<Comment> {
        let from = page * CommentLimits.pageSize
        let to = from + CommentLimits.pageSize - 1

        let rows: [DBComment] = try await client
            .from("comments")
            .select(Self.commentSelect)
            .eq("experience_id", value: experienceID.uuidString.lowercased())
            .order("created_at", ascending: false)
            .range(from: from, to: to)
            .execute()
            .value

        return Paginated(
            items: rows.map(\.comment),
            page: page,
            hasMore: rows.count == CommentLimits.pageSize
        )
    }

    func addComment(experienceID: UUID, authorID: UUID, body: String, parentID: UUID?) async throws -> Comment {
        struct Insert: Encodable {
            let experience_id: String
            let author_id: String
            let parent_id: String?
            let body: String
        }
        let rows: [DBComment] = try await client
            .from("comments")
            .insert(Insert(
                experience_id: experienceID.uuidString.lowercased(),
                author_id: authorID.uuidString.lowercased(),
                parent_id: parentID?.uuidString.lowercased(),
                body: body
            ))
            .select(Self.commentSelect)
            .execute()
            .value

        guard let comment = rows.first?.comment else {
            throw RepositoryError.notFound
        }
        return comment
    }

    func deleteComment(id: UUID) async throws {
        try await client
            .from("comments")
            .delete()
            .eq("id", value: id.uuidString.lowercased())
            .execute()
    }

    // MARK: - Moderation

    func report(target: ReportTarget, reporterID: UUID, reason: ReportReason, details: String?) async throws {
        struct Insert: Encodable {
            let reporter_id: String
            let experience_id: String?
            let comment_id: String?
            let reported_user_id: String?
            let reason: String
            let details: String?
        }

        var experienceID: String?
        var commentID: String?
        var reportedUserID: String?
        switch target {
        case .experience(let id): experienceID = id.uuidString.lowercased()
        case .comment(let id): commentID = id.uuidString.lowercased()
        case .user(let id): reportedUserID = id.uuidString.lowercased()
        }

        try await client
            .from("reports")
            .insert(Insert(
                reporter_id: reporterID.uuidString.lowercased(),
                experience_id: experienceID,
                comment_id: commentID,
                reported_user_id: reportedUserID,
                reason: reason.rawValue,
                details: details
            ))
            .execute()
    }

    func block(blockerID: UUID, blockedID: UUID) async throws {
        struct Insert: Encodable {
            let blocker_id: String
            let blocked_id: String
        }
        try await client
            .from("blocks")
            .upsert(
                Insert(
                    blocker_id: blockerID.uuidString.lowercased(),
                    blocked_id: blockedID.uuidString.lowercased()
                ),
                onConflict: "blocker_id,blocked_id"
            )
            .execute()
    }

    func unblock(blockerID: UUID, blockedID: UUID) async throws {
        try await client
            .from("blocks")
            .delete()
            .eq("blocker_id", value: blockerID.uuidString.lowercased())
            .eq("blocked_id", value: blockedID.uuidString.lowercased())
            .execute()
    }

    func fetchBlockedIDs(userID: UUID) async throws -> Set<UUID> {
        struct Row: Decodable { let blocked_id: UUID }
        let rows: [Row] = try await client
            .from("blocks")
            .select("blocked_id")
            .eq("blocker_id", value: userID.uuidString.lowercased())
            .execute()
            .value
        return Set(rows.map(\.blocked_id))
    }
}

enum EngagementPersistenceError: LocalizedError {
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Couldn't save this experience. Check your connection and try again."
        }
    }
}
