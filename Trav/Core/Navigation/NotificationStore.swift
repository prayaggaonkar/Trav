import Foundation
import Observation
import SwiftUI

/// Toast payload for the Instagram-style top banner.
struct InAppToast: Identifiable, Equatable, Sendable {
    let id: UUID
    let notification: AppNotification

    static func == (lhs: InAppToast, rhs: InAppToast) -> Bool {
        lhs.id == rhs.id
    }
}

/// Unread badge, Realtime inserts, and toast queue.
/// Foreground refresh on scene activation replaces the old 6s backup poll.
@Observable
@MainActor
final class NotificationStore {
    private(set) var unreadCount: Int = 0
    /// Unread ids frozen for the current inbox visit (drives purple dots).
    private(set) var sessionUnreadIDs: Set<UUID> = []
    private(set) var isInboxPresented = false
    /// Currently visible top banner toast (nil when none).
    private(set) var currentToast: InAppToast?

    private var lastUserID: UUID?
    private var hasCapturedUnreadSnapshot = false
    private var isPersistingExit = false

    private var toastQueue: [InAppToast] = []
    private var seenToastIDs: Set<UUID> = []
    private var autoDismissTask: Task<Void, Never>?

    private var listenTask: Task<Void, Never>?
    private var isAppActive = true
    private var isListening = false
    private var didSeedKnownNotifications = false

    private static let toastDisplayNanoseconds: UInt64 = 3_500_000_000
    private static let toastGapNanoseconds: UInt64 = 280_000_000
    private static let realtimeRetryNanoseconds: UInt64 = 2_500_000_000
    private static let maxQueuedToasts = 12

    func reset() {
        stopListening()
        unreadCount = 0
        lastUserID = nil
        sessionUnreadIDs = []
        isInboxPresented = false
        hasCapturedUnreadSnapshot = false
        isPersistingExit = false
        didSeedKnownNotifications = false
        clearToasts()
        seenToastIDs = []
    }

    func refreshUnreadCount(userID: UUID, using environment: AppEnvironment) async {
        lastUserID = userID
        do {
            unreadCount = try await environment.notifications.unreadCount(userID: userID)
        } catch {
            TravLog.notifications.error("refreshUnreadCount failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Live listening

    func startListening(userID: UUID, using environment: AppEnvironment) {
        lastUserID = userID
        if isListening { return }
        isListening = true
        startRealtime(userID: userID, using: environment)
        Task { [weak self] in
            await self?.seedKnownNotifications(userID: userID, using: environment)
        }
    }

    func stopListening() {
        isListening = false
        listenTask?.cancel()
        listenTask = nil
    }

    func handleScenePhase(_ phase: ScenePhase, using environment: AppEnvironment) {
        switch phase {
        case .active:
            isAppActive = true
            guard let userID = lastUserID ?? environment.session.currentUser?.id else { return }
            startListening(userID: userID, using: environment)
            Task {
                await refreshUnreadCount(userID: userID, using: environment)
            }
        case .inactive, .background:
            isAppActive = false
        @unknown default:
            break
        }
    }

    /// Marks existing unread rows as already-seen so we don't toast history on launch.
    private func seedKnownNotifications(userID: UUID, using environment: AppEnvironment) async {
        guard !didSeedKnownNotifications else { return }
        didSeedKnownNotifications = true
        do {
            let page = try await environment.notifications.fetchNotifications(userID: userID, page: 0)
            for item in page.items {
                seenToastIDs.insert(item.id)
            }
            unreadCount = try await environment.notifications.unreadCount(userID: userID)
        } catch {
            didSeedKnownNotifications = false
            TravLog.notifications.error("seedKnownNotifications failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startRealtime(userID: UUID, using environment: AppEnvironment) {
        listenTask?.cancel()
        listenTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let stream = environment.notifications.observeInserts(userID: userID)
                for await notification in stream {
                    guard !Task.isCancelled else { return }
                    await self.handleIncoming(notification, bumpUnread: true, using: environment)
                }
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: Self.realtimeRetryNanoseconds)
            }
        }
    }

    private func handleIncoming(
        _ notification: AppNotification,
        bumpUnread: Bool,
        using environment: AppEnvironment? = nil
    ) async {
        if bumpUnread, !notification.isRead, !seenToastIDs.contains(notification.id) {
            unreadCount += 1
        }
        if notification.type == .follow, let environment {
            environment.engagement.handleFollowNotification(notification: notification, using: environment)
        }
        guard !isInboxPresented else {
            seenToastIDs.insert(notification.id)
            return
        }
        enqueueToast(for: notification)
    }

    // MARK: - Toast queue

    private func enqueueToast(for notification: AppNotification) {
        guard UserDefaults.standard.bool(forKey: "trav.settings.notificationsEnabled") else { return }
        guard !seenToastIDs.contains(notification.id) else { return }
        if currentToast?.id == notification.id { return }
        if toastQueue.contains(where: { $0.id == notification.id }) { return }

        seenToastIDs.insert(notification.id)
        if seenToastIDs.count > 200 {
            seenToastIDs = Set(seenToastIDs.suffix(100))
        }

        let toast = InAppToast(id: notification.id, notification: notification)
        if currentToast == nil {
            present(toast)
            return
        }

        toastQueue.append(toast)
        if toastQueue.count > Self.maxQueuedToasts {
            toastQueue = Array(toastQueue.suffix(Self.maxQueuedToasts))
        }
    }

    private func present(_ toast: InAppToast) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            currentToast = toast
        }
        autoDismissTask?.cancel()
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.toastDisplayNanoseconds)
            guard let self, !Task.isCancelled else { return }
            self.dismissCurrentToast()
        }
    }

    func dismissCurrentToast() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            currentToast = nil
        }
        guard !toastQueue.isEmpty else { return }
        let next = toastQueue.removeFirst()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.toastGapNanoseconds)
            guard let self, !Task.isCancelled, self.currentToast == nil else { return }
            self.present(next)
        }
    }

    func clearToasts() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        currentToast = nil
        toastQueue = []
    }

    // MARK: - Inbox session

    func beginInboxSession() {
        if !isInboxPresented {
            sessionUnreadIDs = []
            hasCapturedUnreadSnapshot = false
            isPersistingExit = false
        }
        isInboxPresented = true
        clearToasts()
    }

    func captureUnreadSnapshot(from notifications: [AppNotification]) {
        guard isInboxPresented else { return }
        let unread = Set(notifications.filter { !$0.isRead }.map(\.id))
        if !hasCapturedUnreadSnapshot {
            sessionUnreadIDs = unread
            hasCapturedUnreadSnapshot = true
        } else {
            sessionUnreadIDs.formUnion(unread)
        }
        for id in unread {
            seenToastIDs.insert(id)
        }
    }

    func showsUnreadDot(for id: UUID) -> Bool {
        sessionUnreadIDs.contains(id)
    }

    func endInboxSessionIfNeeded(userID: UUID, using environment: AppEnvironment) async {
        guard isInboxPresented, !isPersistingExit else { return }
        isPersistingExit = true
        isInboxPresented = false
        do {
            try await environment.notifications.markAllRead(userID: userID)
            unreadCount = 0
            sessionUnreadIDs = []
            hasCapturedUnreadSnapshot = false
        } catch {
            isInboxPresented = true
            isPersistingExit = false
            TravLog.notifications.error("endInboxSession failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func markAllReadLocally() {
        unreadCount = 0
    }

    func setUnreadCount(_ count: Int) {
        unreadCount = max(0, count)
    }
}
