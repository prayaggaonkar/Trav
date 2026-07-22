import Foundation
import Supabase

struct SupabaseEngagementRepository: EngagementRepository {
    private var client: SupabaseClient {
        guard let client = SupabaseManager.client else {
            preconditionFailure("SupabaseEngagementRepository used without a configured SupabaseClient.")
        }
        return client
    }

    func fetchSavedIDs(userID: UUID) async throws -> Set<UUID> {
        struct Row: Decodable { let experience_id: UUID }
        let rows: [Row] = try await client
            .from("experience_saves")
            .select("experience_id")
            .eq("user_id", value: userID)
            .execute()
            .value
        return Set(rows.map(\.experience_id))
    }

    func fetchCompletedIDs(userID: UUID) async throws -> Set<UUID> {
        struct Row: Decodable { let experience_id: UUID }
        let rows: [Row] = try await client
            .from("experience_completions")
            .select("experience_id")
            .eq("user_id", value: userID)
            .execute()
            .value
        return Set(rows.map(\.experience_id))
    }

    func fetchFollowingIDs(userID: UUID) async throws -> Set<UUID> {
        struct Row: Decodable { let following_id: UUID }
        let rows: [Row] = try await client
            .from("follows")
            .select("following_id")
            .eq("follower_id", value: userID)
            .execute()
            .value
        return Set(rows.map(\.following_id))
    }

    func isSaved(userID: UUID, experienceID: UUID) async throws -> Bool {
        struct Row: Decodable { let experience_id: UUID }
        let rows: [Row] = try await client
            .from("experience_saves")
            .select("experience_id")
            .eq("user_id", value: userID)
            .eq("experience_id", value: experienceID)
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
            .eq("user_id", value: userID)
            .eq("experience_id", value: experienceID)
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }

    func toggleSave(userID: UUID, experienceID: UUID) async throws -> Bool {
        if try await isSaved(userID: userID, experienceID: experienceID) {
            try await client
                .from("experience_saves")
                .delete()
                .eq("user_id", value: userID)
                .eq("experience_id", value: experienceID)
                .execute()
            return false
        }

        struct Insert: Encodable {
            let user_id: UUID
            let experience_id: UUID
        }
        try await client
            .from("experience_saves")
            .insert(Insert(user_id: userID, experience_id: experienceID))
            .execute()
        return true
    }

    func toggleComplete(userID: UUID, experienceID: UUID) async throws -> Bool {
        if try await isCompleted(userID: userID, experienceID: experienceID) {
            try await client
                .from("experience_completions")
                .delete()
                .eq("user_id", value: userID)
                .eq("experience_id", value: experienceID)
                .execute()
            return false
        }

        struct Insert: Encodable {
            let user_id: UUID
            let experience_id: UUID
        }
        try await client
            .from("experience_completions")
            .insert(Insert(user_id: userID, experience_id: experienceID))
            .execute()
        return true
    }
}
