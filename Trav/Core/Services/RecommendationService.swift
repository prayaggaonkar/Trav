import Foundation
import NaturalLanguage
import Supabase

/// Native, zero-cost AI recommendation service powered by Apple NaturalLanguage framework sentence vector embeddings
/// and Supabase `pgvector` vector similarity search.
final class RecommendationService: Sendable {
    static let shared = RecommendationService()

    private var supabase: SupabaseClient? {
        SupabaseManager.client
    }

    private init() {}

    /// Generates a 512-dimensional vector embedding for a given text using Apple's NLEmbedding model.
    ///
    /// - Parameter text: The text string to embed.
    /// - Returns: An array of 512 Doubles representing the vector embedding, or nil if embedding unavailable.
    func generateVector(forText text: String) -> [Double]? {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            return nil
        }

        let vector = embedding.vector(for: text)
        guard let vector = vector, vector.count == 512 else {
            return nil
        }

        return vector
    }

    /// Generates a combined user preference vector embedding based on selected vibe tags.
    ///
    /// - Parameter vibes: An array of vibe tag strings.
    /// - Returns: A 512-dimensional vector embedding representing user preferences.
    func generateUserPreferenceVector(from vibes: [String]) -> [Double]? {
        let combinedText = vibes.isEmpty ? "travel local explore spots cafe culture" : vibes.joined(separator: " ")
        return generateVector(forText: combinedText)
    }

    /// Backfills missing 512D vector embeddings for experiences in Supabase.
    func backfillMissingEmbeddingsIfNeeded() {
        Task {
            guard let client = supabase else { return }
            struct ExpRow: Decodable {
                let id: UUID
                let title: String
                let description: String?
                let city: String?
                let stops: [String]?
            }

            guard let rows: [ExpRow] = try? await client
                .from("experiences")
                .select("id, title, description, city, stops")
                .is("embedding", value: nil)
                .limit(20)
                .execute()
                .value, !rows.isEmpty else { return }

            for row in rows {
                let fullText = "\(row.title). \(row.description ?? "") Stops: \((row.stops ?? []).joined(separator: ", ")). City: \(row.city ?? "")."
                if let vector = generateVector(forText: fullText) {
                    struct UpdateEmbedding: Encodable {
                        let embedding: [Double]
                    }
                    _ = try? await client
                        .from("experiences")
                        .update(UpdateEmbedding(embedding: vector))
                        .eq("id", value: row.id.uuidString.lowercased())
                        .execute()
                }
            }
        }
    }

    /// Fetches AI-recommended experiences matching the user's vibe preferences vector via Supabase `pgvector`.
    /// Guaranteed to include posts from followed users, real users, and curated Rec by Trav experiences.
    ///
    /// - Parameter vibes: Array of user vibe preference strings.
    /// - Returns: An array of recommended `Experience` items.
    func fetchRecommendedFeed(for vibes: [String]) async throws -> [Experience] {
        backfillMissingEmbeddingsIfNeeded()

        let vector = generateUserPreferenceVector(from: vibes)

        guard let vector = vector, let client = supabase else {
            return try await fallbackChronologicalFetch()
        }

        struct RPCParams: Encodable {
            let user_profile_vector: [Double]
            let match_limit: Int
        }

        do {
            let repository = SupabaseExperienceRepository()

            // 1. Fetch posts from users the current user follows
            var followingExps: [Experience] = []
            if let activeUser = try? await client.auth.session.user {
                struct FollowRow: Decodable { let following_id: UUID }
                if let followRows: [FollowRow] = try? await client
                    .from("follows")
                    .select("following_id")
                    .eq("follower_id", value: activeUser.id.uuidString.lowercased())
                    .execute()
                    .value {
                    let followingIDs = Set(followRows.map { $0.following_id })
                    if !followingIDs.isEmpty {
                        let followingRows: [SupabaseExperienceRepository.DBExperienceRow] = (try? await client
                            .from("experiences")
                            .select(SupabaseExperienceRepository.experienceSelect)
                            .in("user_id", values: Array(followingIDs).map { $0.uuidString.lowercased() })
                            .eq("is_published", value: true)
                            .order("created_at", ascending: false)
                            .limit(20)
                            .execute()
                            .value) ?? []

                        if !followingRows.isEmpty {
                            let creators = await repository.fetchCreators(for: followingRows)
                            followingExps = followingRows.map { repository.experience(from: $0, creators: creators) }
                        }
                    }
                }
            }

            // 2. Call Supabase pgvector RPC function get_recommended_feed
            let rows: [SupabaseExperienceRepository.DBExperienceRow] = try await client
                .rpc("get_recommended_feed", params: RPCParams(user_profile_vector: vector, match_limit: 20))
                .execute()
                .value

            let creators = await repository.fetchCreators(for: rows)
            var experiences = rows.map { repository.experience(from: $0, creators: creators) }

            // Prepend followed users' posts
            for fExp in followingExps.reversed() {
                if !experiences.contains(where: { $0.id == fExp.id }) {
                    experiences.insert(fExp, at: 0)
                }
            }

            // Include curated "Rec by Trav" places from places table
            if let placesFeed = try? await repository.fetchPlacesFeed(page: 0) {
                let placeExps = placesFeed.items.map { Experience(summary: $0) }
                for p in placeExps {
                    if !experiences.contains(where: { $0.id == p.id }) {
                        experiences.append(p)
                    }
                }
            }

            if experiences.isEmpty {
                return try await fallbackChronologicalFetch()
            }

            return sortWithRealUserPriority(experiences)
        } catch {
            return try await fallbackChronologicalFetch()
        }
    }

    /// Standard chronological fetch fallback constructing real Apple Maps & NaturalLanguage itineraries if database is empty.
    func fallbackChronologicalFetch() async throws -> [Experience] {
        guard let client = supabase else {
            return await generateDynamicAppleMapsFallbacks()
        }

        do {
            let repository = SupabaseExperienceRepository()
            async let expRowsTask = client
                .from("experiences")
                .select(SupabaseExperienceRepository.experienceSelect)
                .eq("is_published", value: true)
                .order("created_at", ascending: false)
                .limit(25)
                .execute()
                .value as [SupabaseExperienceRepository.DBExperienceRow]

            async let placesTask = repository.fetchPlacesFeed(page: 0)

            let rows = (try? await expRowsTask) ?? []
            let placesPaginated = (try? await placesTask)?.items ?? []

            let creators = await repository.fetchCreators(for: rows)
            var fetched = rows.map { repository.experience(from: $0, creators: creators) }

            let placeExperiences = placesPaginated.map { Experience(summary: $0) }
            for placeExp in placeExperiences {
                if !fetched.contains(where: { $0.id == placeExp.id }) {
                    fetched.append(placeExp)
                }
            }

            if fetched.isEmpty {
                return await generateDynamicAppleMapsFallbacks()
            }

            return sortWithRealUserPriority(fetched)
        } catch {
            return await generateDynamicAppleMapsFallbacks()
        }
    }

    /// Generates dynamic "Rec by Trav" itineraries using Apple MapKit and Apple NaturalLanguage vector embeddings.
    private func generateDynamicAppleMapsFallbacks() async -> [Experience] {
        let cities = ["San Francisco", "Tokyo", "Paris", "New York"]
        var results: [Experience] = []
        for city in cities {
            if let exp = await AutoSeedManager.shared.generateAppleMapsItinerary(city: city) {
                results.append(exp)
            }
        }
        return sortWithRealUserPriority(results)
    }

    private func sortWithRealUserPriority(_ list: [Experience]) -> [Experience] {
        list.sorted { a, b in
            let aIsTrav = a.creator.id == ExperienceInsert.travAdminID
                || a.creator.username.lowercased() == "trav"
                || a.creator.displayName.lowercased().contains("trav")
            let bIsTrav = b.creator.id == ExperienceInsert.travAdminID
                || b.creator.username.lowercased() == "trav"
                || b.creator.displayName.lowercased().contains("trav")

            if aIsTrav != bIsTrav {
                return !aIsTrav // Real user posts come first!
            }
            return false
        }
    }
}
