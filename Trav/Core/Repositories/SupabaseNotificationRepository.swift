import Foundation
import Supabase

struct SupabaseNotificationRepository: NotificationRepository {
    private static let pageSize = 30

    private var client: SupabaseClient {
        get throws {
            guard let client = SupabaseManager.client else {
                throw RepositoryError.backendUnavailable
            }
            return client
        }
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
        // Every type except `follow` references an experience.
        let expIDs = rows.filter { $0.type != "follow" }.compactMap { $0.reference_id }
        let experienceTitleMap = await fetchExperienceTitles(ids: expIDs)

        let items: [AppNotification] = rows.compactMap { row in
            guard let type = AppNotificationType(rawValue: row.type),
                  let actor = actorMap[row.actor_id] else { return nil }
            var item = AppNotification(
                id: row.id,
                userID: row.user_id,
                actor: actor,
                type: type,
                referenceID: row.reference_id,
                isRead: row.is_read,
                createdAt: row.created_at
            )
            if let refID = row.reference_id {
                item.experienceTitle = experienceTitleMap[refID]
            }
            return item
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

    func deleteNotification(id: UUID) async throws {
        try await client
            .from("notifications")
            .delete()
            .eq("id", value: id.uuidString.lowercased())
            .execute()
    }

    func registerDeviceToken(_ token: String, userID: UUID) async throws {
        struct Upsert: Encodable {
            let token: String
            let user_id: String
            let platform: String
            let environment: String
        }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        try await client
            .from("device_tokens")
            .upsert(
                Upsert(
                    token: token,
                    user_id: userID.uuidString.lowercased(),
                    platform: "ios",
                    environment: environment
                ),
                onConflict: "token"
            )
            .execute()
    }

    func unregisterDeviceToken(_ token: String) async throws {
        try await client
            .from("device_tokens")
            .delete()
            .eq("token", value: token)
            .execute()
    }

    func observeInserts(userID: UUID) -> AsyncStream<AppNotification> {
        AsyncStream { continuation in
            guard let client = SupabaseManager.client else {
                continuation.finish()
                return
            }
            let channelName = "notifications-inserts-\(userID.uuidString.lowercased())"

            let task = Task {
                let channel = client.channel(channelName)
                let insertions = channel.postgresChange(
                    InsertAction.self,
                    schema: "public",
                    table: "notifications",
                    filter: .eq("user_id", value: userID)
                )

                do {
                    try await channel.subscribeWithError()
                } catch {
                    TravLog.notifications.error("observeInserts subscribe failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish()
                    return
                }

                for await insert in insertions {
                    if Task.isCancelled { break }
                    do {
                        let row = try insert.decodeRecord(
                            as: NotificationRow.self,
                            decoder: AnyJSON.decoder
                        )
                        guard row.user_id == userID else { continue }
                        guard let type = AppNotificationType(rawValue: row.type) else { continue }
                        let actors = await self.fetchActors(ids: [row.actor_id])
                        guard let actor = actors[row.actor_id] else { continue }
                        var notification = AppNotification(
                            id: row.id,
                            userID: row.user_id,
                            actor: actor,
                            type: type,
                            referenceID: row.reference_id,
                            isRead: row.is_read ?? false,
                            createdAt: row.created_at ?? insert.commitTimestamp
                        )
                        if type != .follow, let refID = row.reference_id {
                            let titles = await self.fetchExperienceTitles(ids: [refID])
                            notification.experienceTitle = titles[refID]
                        }
                        continuation.yield(notification)
                    } catch {
                        TravLog.notifications.error("observeInserts decode failed: \(error.localizedDescription, privacy: .public)")
                    }
                }

                await client.removeChannel(channel)
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private struct NotificationRow: Decodable {
        let id: UUID
        let user_id: UUID
        let actor_id: UUID
        let type: String
        let reference_id: UUID?
        let is_read: Bool?
        let created_at: Date?
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
            TravLog.notifications.error("fetchActors failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    private func fetchExperienceTitles(ids: [UUID]) async -> [UUID: String] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [:] }

        struct ExpRow: Decodable {
            let id: UUID
            let title: String
        }

        do {
            let rows: [ExpRow] = try await client
                .from("experiences")
                .select("id, title")
                .in("id", values: unique.map(\.uuidString))
                .execute()
                .value
            var map: [UUID: String] = [:]
            for r in rows {
                map[r.id] = r.title
            }
            return map
        } catch {
            TravLog.notifications.error("fetchExperienceTitles failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }
}
