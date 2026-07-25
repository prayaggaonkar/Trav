import Foundation
import Observation

/// Unread badge + refresh for the notifications bell.
@Observable
@MainActor
final class NotificationStore {
    private(set) var unreadCount: Int = 0
    private var lastUserID: UUID?

    func reset() {
        unreadCount = 0
        lastUserID = nil
    }

    func refreshUnreadCount(userID: UUID, using environment: AppEnvironment) async {
        lastUserID = userID
        do {
            unreadCount = try await environment.notifications.unreadCount(userID: userID)
        } catch {
            print("NotificationStore.refreshUnreadCount failed: \(error)")
        }
    }

    func markAllReadLocally() {
        unreadCount = 0
    }

    func setUnreadCount(_ count: Int) {
        unreadCount = max(0, count)
    }
}
