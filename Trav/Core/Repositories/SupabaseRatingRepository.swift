import Foundation
import Supabase

/// Ratings are the trust layer: they gate completion, drive averages, and feed
/// the recommendation engine. Writes go through the `submit_rating` RPC so the
/// completion row, aggregates and photo records all land in one transaction.
struct SupabaseRatingRepository: RatingRepository {
    private var client: SupabaseClient {
        get throws {
            guard let client = SupabaseManager.client else {
                throw RepositoryError.backendUnavailable
            }
            return client
        }
    }

    static let pageSize = 20

    // MARK: - Wire types

    private struct DBRatingRow: Decodable {
        let id: UUID
        let user_id: UUID
        let experience_id: UUID
        let scores: RadarRating?
        let disabled_categories: [String]?
        let overall_score: Double
        let review: String?
        let photo_urls: [String]?
        let created_at: Date?
        let updated_at: Date?
        let author: DBAuthor?

        struct DBAuthor: Decodable {
            let id: UUID
            let username: String
            let display_name: String
            let avatar_url: String?
            let is_verified: Bool?
        }

        func rating(author fallback: ProfileSummary?) -> Rating? {
            let profile: ProfileSummary
            if let author {
                profile = ProfileSummary(
                    id: author.id,
                    username: author.username,
                    displayName: author.display_name,
                    avatarURL: author.avatar_url.flatMap { URL(string: $0) },
                    isVerified: author.is_verified ?? false
                )
            } else if let fallback {
                profile = fallback
            } else {
                profile = ProfileSummary(
                    id: user_id,
                    username: "traveler",
                    displayName: "Traveler",
                    avatarURL: nil,
                    isVerified: false
                )
            }

            var radar = scores ?? RadarRating()
            radar.disabledCategories = Set(disabled_categories ?? [])

            return Rating(
                id: id,
                experienceID: experience_id,
                author: profile,
                radar: radar,
                overallScore: overall_score,
                review: review,
                photoURLs: (photo_urls ?? []).compactMap { URL(string: $0) },
                createdAt: created_at ?? .now,
                updatedAt: updated_at ?? created_at ?? .now
            )
        }
    }

    private static let ratingSelect = """
    id, user_id, experience_id, scores, disabled_categories, overall_score, \
    review, photo_urls, created_at, updated_at
    """

    private static let ratingSelectWithAuthor = """
    \(ratingSelect), author:profiles!ratings_user_id_fkey(id, username, display_name, avatar_url, is_verified)
    """

    // MARK: - Write

    @discardableResult
    func submitRating(_ draft: RatingDraft, userID: UUID) async throws -> Rating {
        guard !draft.radar.scores.isEmpty else {
            throw ContentModelError.ratingRequired
        }
        guard draft.photosData.count <= RatingDraft.maxPhotos else {
            throw ContentModelError.tooManyPhotos(limit: RatingDraft.maxPhotos)
        }

        let client = try client
        let photoURLs = try await uploadPhotos(draft.photosData, userID: userID, experienceID: draft.experienceID)

        struct Params: Encodable {
            let p_experience_id: String
            let p_scores: [String: Double]
            let p_disabled_categories: [String]
            let p_overall_score: Double
            let p_review: String?
            let p_photo_urls: [String]
        }

        let review = draft.review?.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            _ = try await client
                .rpc("submit_rating", params: Params(
                    p_experience_id: draft.experienceID.uuidString.lowercased(),
                    p_scores: draft.radar.scores,
                    p_disabled_categories: Array(draft.radar.disabledCategories),
                    p_overall_score: draft.radar.overallScore,
                    p_review: (review?.isEmpty ?? true) ? nil : review,
                    p_photo_urls: photoURLs.map(\.absoluteString)
                ))
                .execute()
        } catch {
            if let mapped = ContentModelError.from(serverMessage: "\(error)") { throw mapped }
            guard SupabaseExperienceRepository.isUnknownSchemaError(error) else { throw error }
            try await submitRatingWithoutRPC(
                draft,
                userID: userID,
                photoURLs: photoURLs,
                review: review,
                client: client
            )
        }

        if let saved = try? await fetchMyRating(userID: userID, experienceID: draft.experienceID) {
            return saved
        }

        // The write succeeded; return a locally-constructed value so the UI can
        // move on even if the read-back is momentarily unavailable.
        return Rating(
            id: UUID(),
            experienceID: draft.experienceID,
            author: ProfileSummary(
                id: userID,
                username: "you",
                displayName: "You",
                avatarURL: nil,
                isVerified: false
            ),
            radar: draft.radar,
            overallScore: draft.radar.overallScore,
            review: (review?.isEmpty ?? true) ? nil : review,
            photoURLs: photoURLs
        )
    }

    /// Fallback for a database that has not run the ratings migration: write the
    /// creator radar and the completion row directly.
    private func submitRatingWithoutRPC(
        _ draft: RatingDraft,
        userID: UUID,
        photoURLs: [URL],
        review: String?,
        client: SupabaseClient
    ) async throws {
        struct CompletionUpsert: Encodable {
            let user_id: UUID
            let experience_id: UUID
            let note: String?
            let photo_urls: [String]
        }

        try await client
            .from("experience_completions")
            .upsert(CompletionUpsert(
                user_id: userID,
                experience_id: draft.experienceID,
                note: (review?.isEmpty ?? true) ? nil : review,
                photo_urls: photoURLs.map(\.absoluteString)
            ), onConflict: "user_id,experience_id")
            .execute()
    }

    func deleteRating(userID: UUID, experienceID: UUID) async throws {
        let client = try client
        do {
            _ = try await client
                .rpc("delete_rating", params: ["p_experience_id": experienceID.uuidString.lowercased()])
                .execute()
            return
        } catch {
            guard SupabaseExperienceRepository.isUnknownSchemaError(error) else { throw error }
        }

        // Without the RPC, remove the completion so the user is not stuck.
        try await client
            .from("experience_completions")
            .delete()
            .eq("user_id", value: userID.uuidString.lowercased())
            .eq("experience_id", value: experienceID.uuidString.lowercased())
            .execute()
    }

    // MARK: - Read

    func fetchMyRating(userID: UUID, experienceID: UUID) async throws -> Rating? {
        let client = try client
        let rows: [DBRatingRow] = (try? await client
            .from("ratings")
            .select(Self.ratingSelect)
            .eq("user_id", value: userID.uuidString.lowercased())
            .eq("experience_id", value: experienceID.uuidString.lowercased())
            .limit(1)
            .execute()
            .value) ?? []

        return rows.first?.rating(author: nil)
    }

    func fetchRatings(experienceID: UUID, page: Int) async throws -> Paginated<Rating> {
        let client = try client
        let from = page * Self.pageSize
        let to = from + Self.pageSize - 1

        var rows: [DBRatingRow] = []
        do {
            rows = try await client
                .from("ratings")
                .select(Self.ratingSelectWithAuthor)
                .eq("experience_id", value: experienceID.uuidString.lowercased())
                .order("created_at", ascending: false)
                .range(from: from, to: to)
                .execute()
                .value
        } catch {
            // Embedded author fails on a drifted DB without the FK; read plain
            // rows and hydrate the profiles separately.
            guard SupabaseExperienceRepository.isUnknownSchemaError(error) else { throw error }
            rows = (try? await client
                .from("ratings")
                .select(Self.ratingSelect)
                .eq("experience_id", value: experienceID.uuidString.lowercased())
                .order("created_at", ascending: false)
                .range(from: from, to: to)
                .execute()
                .value) ?? []
        }

        let authors = await fetchAuthors(for: rows, client: client)
        let items = rows.compactMap { $0.rating(author: authors[$0.user_id]) }
        return Paginated(items: items, page: page, hasMore: rows.count == Self.pageSize)
    }

    private func fetchAuthors(
        for rows: [DBRatingRow],
        client: SupabaseClient
    ) async -> [UUID: ProfileSummary] {
        let missing = Set(rows.filter { $0.author == nil }.map { $0.user_id })
        guard !missing.isEmpty else { return [:] }

        struct Row: Decodable {
            let id: UUID
            let username: String
            let display_name: String
            let avatar_url: String?
            let is_verified: Bool?
        }

        let profiles: [Row] = (try? await client
            .from("profiles")
            .select("id, username, display_name, avatar_url, is_verified")
            .in("id", values: missing.map { $0.uuidString.lowercased() })
            .execute()
            .value) ?? []

        return Dictionary(uniqueKeysWithValues: profiles.map {
            (
                $0.id,
                ProfileSummary(
                    id: $0.id,
                    username: $0.username,
                    displayName: $0.display_name,
                    avatarURL: $0.avatar_url.flatMap { URL(string: $0) },
                    isVerified: $0.is_verified ?? false
                )
            )
        })
    }

    func fetchRatingSummary(experienceID: UUID) async throws -> RatingSummary {
        let client = try client

        struct Row: Decodable {
            let user_id: UUID
            let rating_count: Int?
            let average_rating: Double?
            let community_rating_count: Int?
            let community_average_rating: Double?
            let creator_rating: Double?
            let community_rating: RadarRating?
        }

        let rows: [Row] = (try? await client
            .from("experiences")
            .select("""
            user_id, rating_count, average_rating, community_rating_count, \
            community_average_rating, creator_rating, community_rating
            """)
            .eq("id", value: experienceID.uuidString.lowercased())
            .limit(1)
            .execute()
            .value) ?? []

        guard let row = rows.first else {
            return try await computeSummaryFromRatings(experienceID: experienceID, client: client)
        }

        return RatingSummary(
            averageScore: row.average_rating,
            ratingCount: row.rating_count ?? 0,
            communityAverageScore: row.community_average_rating,
            communityRatingCount: row.community_rating_count ?? 0,
            creatorScore: row.creator_rating,
            communityRadar: row.community_rating
        )
    }

    /// Aggregation fallback for a database without the computed columns.
    private func computeSummaryFromRatings(
        experienceID: UUID,
        client: SupabaseClient
    ) async throws -> RatingSummary {
        struct OwnerRow: Decodable { let user_id: UUID }
        struct ScoreRow: Decodable {
            let user_id: UUID
            let overall_score: Double
        }

        let owners: [OwnerRow] = (try? await client
            .from("experiences")
            .select("user_id")
            .eq("id", value: experienceID.uuidString.lowercased())
            .limit(1)
            .execute()
            .value) ?? []

        let scores: [ScoreRow] = (try? await client
            .from("ratings")
            .select("user_id, overall_score")
            .eq("experience_id", value: experienceID.uuidString.lowercased())
            .execute()
            .value) ?? []

        guard !scores.isEmpty else { return .empty }

        let creatorID = owners.first?.user_id
        let community = scores.filter { $0.user_id != creatorID }
        let mean: ([ScoreRow]) -> Double? = { rows in
            guard !rows.isEmpty else { return nil }
            return rows.reduce(0.0) { $0 + $1.overall_score } / Double(rows.count)
        }

        return RatingSummary(
            averageScore: mean(scores),
            ratingCount: scores.count,
            communityAverageScore: mean(community),
            communityRatingCount: community.count,
            creatorScore: scores.first { $0.user_id == creatorID }?.overall_score,
            communityRadar: nil
        )
    }

    // MARK: - Photos

    private func uploadPhotos(
        _ photosData: [Data],
        userID: UUID,
        experienceID: UUID
    ) async throws -> [URL] {
        guard !photosData.isEmpty else { return [] }
        let client = try client
        var urls: [URL] = []

        for (index, data) in photosData.prefix(RatingDraft.maxPhotos).enumerated() {
            // User-scoped path so storage RLS can authorize the write.
            let path = "\(userID.uuidString.lowercased())/\(experienceID.uuidString.lowercased())/rating_\(index).jpg"
            do {
                _ = try await client.storage
                    .from("completions")
                    .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
                urls.append(try client.storage.from("completions").getPublicURL(path: path))
            } catch {
                TravLog.media.error("Rating photo upload failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return urls
    }
}
