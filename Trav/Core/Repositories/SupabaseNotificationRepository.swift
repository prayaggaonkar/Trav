import Foundation
import Supabase

struct SupabaseNotificationRepository: NotificationRepository {
    private static let pageSize = 30

    private var client: SupabaseClient {
        guard let client = SupabaseManager.client else {
            preconditionFailure("SupabaseNotificationRepository used without a configured SupabaseClient.")
        }
        return client
    }

    func fetchNotifications(userID: UUID, page: Int) async throws -> Paginated<AppNotification> {
        struct Row: Decodable {
            let id: UUID
            let user_id: UUID
            let actor_id: UUID
            let type: String
            let reference_id: UUID?
            let is_read: Bool
            let created_at: Date
        }

        let from = page * Self.pageSize
        let to = from + Self.pageSize - 1

        let rows: [Row] = try await client
            .from("notifications")
            .select("id, user_id, actor_id, type, reference_id, is_read, created_at")
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .range(from: from, to: to)
            .execute()
            .value

        let actorMap = await fetchActors(ids: rows.map(\.actor_id))
        let items: [AppNotification] = rows.compactMap { row in
            guard let type = AppNotificationType(rawValue: row.type),
                  let actor = actorMap[row.actor_id] else { return nil }
            return AppNotification(
                id: row.id,
                userID: row.user_id,
                actor: actor,
                type: type,
                referenceID: row.reference_id,
                isRead: row.is_read,
                createdAt: row.created_at
            )
        }

        return Paginated(items: items, page: page, hasMore: rows.count == Self.pageSize)
    }

    func unreadCount(userID: UUID) async throws -> Int {
        let response = try await client
            .from("notifications")
            .select("id", count: .exact)
            .eq("user_id", value: userID)
            .eq("is_read", value: false)
            .execute()
        return response.count ?? 0
    }

    func markRead(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        struct Patch: Encodable { let is_read: Bool }
        try await client
            .from("notifications")
            .update(Patch(is_read: true))
            .in("id", values: ids.map(\.uuidString))
            .execute()
    }

    func markAllRead(userID: UUID) async throws {
        struct Patch: Encodable { let is_read: Bool }
        try await client
            .from("notifications")
            .update(Patch(is_read: true))
            .eq("user_id", value: userID)
            .eq("is_read", value: false)
            .execute()
    }

    private func fetchActors(ids: [UUID]) async -> [UUID: ProfileSummary] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [:] }

        struct DBProfile: Decodable {
            let id: UUID
            let username: String
            let display_name: String
            let avatar_url: String?
            let is_verified: Bool
        }

        do {
            let profiles: [DBProfile] = try await client
                .from("profiles")
                .select("id, username, display_name, avatar_url, is_verified")
                .in("id", values: unique.map(\.uuidString))
                .execute()
                .value
            var map: [UUID: ProfileSummary] = [:]
            for p in profiles {
                map[p.id] = ProfileSummary(
                    id: p.id,
                    username: p.username,
                    displayName: p.display_name,
                    avatarURL: p.avatar_url.flatMap(URL.init(string:)),
                    isVerified: p.is_verified
                )
            }
            return map
        } catch {
            print("SupabaseNotificationRepository.fetchActors failed: \(error)")
            return [:]
        }
    }
}
