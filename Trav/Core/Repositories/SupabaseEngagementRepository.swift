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
        var ids = Set<UUID>()

        struct ExperienceSaveRow: Decodable { let experience_id: UUID }
        if let rows: [ExperienceSaveRow] = try? await client
            .from("experience_saves")
            .select("experience_id")
            .eq("user_id", value: userID.uuidString.lowercased())
            .execute()
            .value {
            ids.formUnion(rows.map(\.experience_id))
        }

        // Legacy feed bookmarks (`saves.place_id`) — keep reading so older rows still count.
        struct LegacySaveRow: Decodable { let place_id: String }
        if let legacy: [LegacySaveRow] = try? await client
            .from("saves")
            .select("place_id")
            .eq("user_id", value: userID.uuidString.lowercased())
            .execute()
            .value {
            for row in legacy {
                ids.insert(StableUUID.from(row.place_id))
            }
        }

        return ids
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

    func isSaved(userID: UUID, experienceID: UUID) async throws -> Bool {
        let ids = try await fetchSavedIDs(userID: userID)
        return ids.contains(experienceID)
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

    func toggleSave(userID: UUID, experienceID: UUID) async throws -> Bool {
        let user = userID.uuidString.lowercased()
        let experience = experienceID.uuidString.lowercased()
        let currentlySaved = try await isSaved(userID: userID, experienceID: experienceID)

        if currentlySaved {
            _ = try? await client
                .from("experience_saves")
                .delete()
                .eq("user_id", value: user)
                .eq("experience_id", value: experience)
                .execute()
            _ = try? await client
                .from("saves")
                .delete()
                .eq("user_id", value: user)
                .eq("place_id", value: experience)
                .execute()
            return false
        }

        var persisted = false

        struct ExperienceSaveInsert: Encodable {
            let user_id: String
            let experience_id: String
        }
        do {
            try await client
                .from("experience_saves")
                .upsert(
                    ExperienceSaveInsert(user_id: user, experience_id: experience),
                    onConflict: "user_id,experience_id"
                )
                .execute()
            persisted = true
        } catch {
            print("experience_saves upsert failed: \(error)")
        }

        // Always dual-write legacy `saves` so bookmarks persist even if experience_saves
        // is missing / blocked by RLS.
        struct LegacySaveInsert: Encodable {
            let user_id: String
            let place_id: String
        }
        do {
            try await client
                .from("saves")
                .upsert(
                    LegacySaveInsert(user_id: user, place_id: experience),
                    onConflict: "user_id,place_id"
                )
                .execute()
            persisted = true
        } catch {
            print("legacy saves upsert failed: \(error)")
        }

        guard persisted else {
            throw EngagementPersistenceError.saveFailed
        }
        return true
    }

    func toggleComplete(userID: UUID, experienceID: UUID) async throws -> Bool {
        let user = userID.uuidString.lowercased()
        let experience = experienceID.uuidString.lowercased()

        if try await isCompleted(userID: userID, experienceID: experienceID) {
            try await client
                .from("experience_completions")
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
            .from("experience_completions")
            .insert(Insert(user_id: user, experience_id: experience))
            .execute()
        return true
    }

    func ensureExperienceExists(for summary: ExperienceSummary, ownerID: UUID) async throws {
        let id = summary.id.uuidString.lowercased()

        struct Existing: Decodable { let id: UUID }
        let existing: [Existing] = (try? await client
            .from("experiences")
            .select("id")
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value) ?? []
        if !existing.isEmpty { return }

        // Minimal insert first (matches core schema). Optional columns added afterward.
        struct CoreInsert: Encodable {
            let id: String
            let user_id: String
            let title: String
            let description: String
            let city: String
            let stops: [String]
        }

        let core = CoreInsert(
            id: id,
            user_id: ownerID.uuidString.lowercased(),
            title: summary.title,
            description: ProfileLimits.bookmarkDescriptionSentinel,
            city: summary.displayCityName.isEmpty ? "Unknown" : summary.displayCityName,
            stops: summary.stops.map(\.name)
        )

        do {
            try await client.from("experiences").insert(core).execute()
        } catch {
            let again: [Existing] = (try? await client
                .from("experiences")
                .select("id")
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value) ?? []
            if again.isEmpty {
                print("ensureExperienceExists failed: \(error)")
                // Non-fatal — legacy `saves` path can still persist the bookmark.
                return
            }
        }

        if let imageURL = summary.coverImageURL?.absoluteString {
            struct ImagePatch: Encodable { let image: String }
            _ = try? await client
                .from("experiences")
                .update(ImagePatch(image: imageURL))
                .eq("id", value: id)
                .execute()
        }
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
