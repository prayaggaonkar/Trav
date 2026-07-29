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

    func toggleSave(userID: UUID, experienceID: UUID) async throws -> Bool {
        struct ExpOwnerRow: Decodable {
            let user_id: UUID
        }
        let expOwner: [ExpOwnerRow] = (try? await client
            .from("experiences")
            .select("user_id")
            .eq("id", value: experienceID.uuidString.lowercased())
            .execute()
            .value) ?? []

        if let owner = expOwner.first, owner.user_id == userID {
            return false
        }

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
                    user_id: userID.uuidString.lowercased(),
                    experience_id: experienceID.uuidString.lowercased()
                ),
                onConflict: "user_id,experience_id"
            )
            .execute()
        return true
    }

    func unsave(userID: UUID, experienceID: UUID) async throws {
        try await client
            .from("experience_saves")
            .delete()
            .eq("user_id", value: userID.uuidString.lowercased())
            .eq("experience_id", value: experienceID.uuidString.lowercased())
            .execute()
    }

    func toggleComplete(userID: UUID, experienceID: UUID, note: String?, photosData: [Data]) async throws -> Bool {
        let client = try client
        let user = userID.uuidString.lowercased()
        let experience = experienceID.uuidString.lowercased()

        struct ExpOwnerRow: Decodable {
            let user_id: UUID
        }
        let expOwner: [ExpOwnerRow] = (try? await client
            .from("experiences")
            .select("user_id")
            .eq("id", value: experience)
            .execute()
            .value) ?? []

        if let owner = expOwner.first, owner.user_id == userID {
            return false
        }

        if try await isCompleted(userID: userID, experienceID: experienceID) {
            try await client
                .from("experience_completions")
                .delete()
                .eq("user_id", value: user)
                .eq("experience_id", value: experience)
                .execute()
            return false
        }

        let completionID = UUID()
        var photoURLs: [String] = []
        for (index, data) in photosData.enumerated() {
            let path = "\(user)/\(completionID.uuidString.lowercased())/photo_\(index).jpg"
            _ = try? await client.storage
                .from("completions")
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
            if let url = try? client.storage.from("completions").getPublicURL(path: path) {
                photoURLs.append(url.absoluteString)
            }
        }

        struct Insert: Encodable {
            let id: String
            let user_id: String
            let experience_id: String
            let note: String?
            let photo_urls: [String]
        }
        try await client
            .from("experience_completions")
            .insert(Insert(
                id: completionID.uuidString.lowercased(),
                user_id: user,
                experience_id: experience,
                note: note,
                photo_urls: photoURLs
            ))
            .execute()
        return true
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

    /// Creates an unpublished shadow experience row for a curated feed place so
    /// save/completion foreign keys are satisfied. Shadow rows never surface in
    /// feeds, profiles, or notifications (`is_published = false`).
    func ensureExperienceExists(for summary: ExperienceSummary, ownerID: UUID) async throws {
        let client = try client
        let id = summary.id.uuidString.lowercased()

        struct Existing: Decodable { let id: UUID }
        let existing: [Existing] = try await client
            .from("experiences")
            .select("id")
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        if !existing.isEmpty { return }

        struct ShadowInsert: Encodable {
            let id: String
            let user_id: String
            let title: String
            let description: String
            let city: String
            let stops: [String]
            let image: [String]?
            let is_published: Bool
        }

        let insert = ShadowInsert(
            id: id,
            user_id: ownerID.uuidString.lowercased(),
            title: summary.title,
            description: "",
            city: summary.displayCityName.isEmpty ? "Unknown" : summary.displayCityName,
            stops: summary.stops.map(\.name),
            image: summary.coverImageURL.map { [$0.absoluteString] },
            is_published: false
        )

        do {
            try await client.from("experiences").insert(insert).execute()
        } catch {
            // Another user may have created the shadow row concurrently — fine.
            let again: [Existing] = (try? await client
                .from("experiences")
                .select("id")
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value) ?? []
            if again.isEmpty { throw error }
        }
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
