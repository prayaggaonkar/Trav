import Foundation
import UIKit
import UserNotifications

/// Registers for APNs and syncs device tokens to Supabase `device_tokens`.
@MainActor
final class PushNotificationService: NSObject {
    static let shared = PushNotificationService()

    private var pendingToken: String?
    private var registeredUserID: UUID?

    private override init() {
        super.init()
    }

    /// Request permission and register for remote notifications when the setting is on.
    func registerIfNeeded(userID: UUID, using environment: AppEnvironment) async {
        guard UserDefaults.standard.bool(forKey: "trav.settings.notificationsEnabled") else { return }

        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
        } catch {
            TravLog.push.error("notification permission failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        UIApplication.shared.registerForRemoteNotifications()
        registeredUserID = userID

        if let token = pendingToken {
            await syncToken(token, userID: userID, using: environment)
        }
    }

    func didRegister(deviceToken data: Data) {
        let token = data.map { String(format: "%02.2hhx", $0) }.joined()
        pendingToken = token
        TravLog.push.debug("APNs token received (\(token.prefix(8), privacy: .public)…)")

        guard
            let environment = TravAppDelegate.environment,
            let userID = registeredUserID ?? environment.session.currentUser?.id
        else { return }

        Task {
            await syncToken(token, userID: userID, using: environment)
        }
    }

    func didFailToRegister(error: Error) {
        TravLog.push.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func unregister(using environment: AppEnvironment) async {
        guard let token = pendingToken else { return }
        do {
            try await environment.notifications.unregisterDeviceToken(token)
        } catch {
            TravLog.push.error("unregister token failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func syncToken(_ token: String, userID: UUID, using environment: AppEnvironment) async {
        do {
            try await environment.notifications.registerDeviceToken(token, userID: userID)
            TravLog.push.debug("device token synced")
        } catch {
            TravLog.push.error("register token failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// UIKit app delegate bridge for APNs callbacks.
final class TravAppDelegate: NSObject, UIApplicationDelegate {
    /// Set from SwiftUI so token sync can reach repositories.
    @MainActor static var environment: AppEnvironment?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = PushNotificationCenterDelegate.shared
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationService.shared.didRegister(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationService.shared.didFailToRegister(error: error)
        }
    }
}

/// Nonisolated notification center delegate to satisfy Swift 6 Sendable rules.
final class PushNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = PushNotificationCenterDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let deepLink = userInfo["deep_link"] as? String, let url = URL(string: deepLink) {
            Task { @MainActor in
                _ = TravAppDelegate.environment?.router.handleDeepLink(url)
            }
        }
        completionHandler()
    }
}
