import Foundation
import Observation
import SwiftUI

struct AppConfiguration: Sendable {
    var useMockBackend: Bool
    var supabaseURL: URL?
    var supabaseAnonKey: String?
    var googleClientID: String?

    /// Custom URL scheme used to receive OAuth and email-link callbacks from Supabase Auth.
    /// Must be registered under `CFBundleURLTypes` in Info.plist.
    static let oauthRedirectURL = URL(string: "trav://auth-callback")

    static let current: AppConfiguration = {
        let bundle = Bundle.main
        let urlString = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let key = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        let googleID = bundle.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String

        // A URL with no host (e.g. "https:" — which happens if "//" gets swallowed as an
        // .xcconfig comment) is not usable; treat it the same as a missing URL.
        let supabaseURL = urlString
            .flatMap(URL.init(string:))
            .flatMap { $0.host?.isEmpty == false ? $0 : nil }

        let hasBackend = supabaseURL != nil && key?.isEmpty == false
        return AppConfiguration(
            useMockBackend: !hasBackend,
            supabaseURL: supabaseURL,
            supabaseAnonKey: key,
            googleClientID: googleID
        )
    }()
}

@Observable
@MainActor
final class AppearanceStore {
    private static let storageKey = "trav.appearance.mode"

    /// Persisted appearance: `"dark"` (default) or `"light"`.
    var modeRaw: String {
        didSet { UserDefaults.standard.set(modeRaw, forKey: Self.storageKey) }
    }

    init() {
        modeRaw = UserDefaults.standard.string(forKey: Self.storageKey) ?? "dark"
    }

    var preferredColorScheme: ColorScheme? {
        modeRaw == "light" ? .light : .dark
    }

    var isLightMode: Bool { modeRaw == "light" }

    func toggle() {
        modeRaw = isLightMode ? "dark" : "light"
    }
}

@Observable
@MainActor
final class AppEnvironment {
    let configuration: AppConfiguration
    let router: AppRouter
    let session: SessionStore
    let appearance: AppearanceStore
    let engagement: EngagementStore
    let notificationStore: NotificationStore
    let cities: any CityRepository
    let experiences: any ExperienceRepository
    let auth: any AuthRepository
    let profiles: any ProfileRepository
    let engagementRepo: any EngagementRepository
    let notifications: any NotificationRepository

    init(
        configuration: AppConfiguration,
        router: AppRouter,
        session: SessionStore,
        appearance: AppearanceStore = AppearanceStore(),
        engagement: EngagementStore = EngagementStore(),
        notificationStore: NotificationStore = NotificationStore(),
        cities: any CityRepository,
        experiences: any ExperienceRepository,
        auth: any AuthRepository,
        profiles: any ProfileRepository,
        engagementRepo: any EngagementRepository,
        notifications: any NotificationRepository
    ) {
        self.configuration = configuration
        self.router = router
        self.session = session
        self.appearance = appearance
        self.engagement = engagement
        self.notificationStore = notificationStore
        self.cities = cities
        self.experiences = experiences
        self.auth = auth
        self.profiles = profiles
        self.engagementRepo = engagementRepo
        self.notifications = notifications
    }

    static let live: AppEnvironment = {
        let config = AppConfiguration.current
        let router = AppRouter()
        let session = SessionStore()
        let engagement = EngagementStore()
        let notificationStore = NotificationStore()

        let profiles: any ProfileRepository = config.useMockBackend
            ? MockProfileRepository()
            : SupabaseProfileRepository()
        let engagementRepo: any EngagementRepository = config.useMockBackend
            ? MockEngagementRepository()
            : SupabaseEngagementRepository()
        let notifications: any NotificationRepository = config.useMockBackend
            ? MockNotificationRepository()
            : SupabaseNotificationRepository()

        return AppEnvironment(
            configuration: config,
            router: router,
            session: session,
            appearance: AppearanceStore(),
            engagement: engagement,
            notificationStore: notificationStore,
            cities: MockCityRepository(),
            experiences: config.useMockBackend ? MockExperienceRepository() : SupabaseExperienceRepository(),
            auth: config.useMockBackend ? MockAuthRepository() : SupabaseAuthRepository(),
            profiles: profiles,
            engagementRepo: engagementRepo,
            notifications: notifications
        )
    }()

    /// Restores any persisted Supabase session and keeps `SessionStore` in sync with
    /// subsequent sign-in, sign-out, and token-refresh events. Call once at app launch;
    /// the underlying stream lives for the lifetime of the app.
    func observeAuthState() async {
        debugLog("AppEnvironment.observeAuthState started")
        guard !configuration.useMockBackend else {
            debugLog("AppEnvironment.observeAuthState: using mock backend, setting unauthenticated")
            session.phase = .unauthenticated
            return
        }

        for await profile in auth.authStateChanges() {
            debugLog("AppEnvironment.observeAuthState: received profile update: \(profile?.displayName ?? "nil") (\(profile?.id.uuidString ?? "nil"))")
            session.currentUser = profile
            if let profile {
                session.phase = .authenticated
                engagement.cache(profile)
                await engagement.bootstrap(userID: profile.id, using: self)
                await notificationStore.refreshUnreadCount(userID: profile.id, using: self)
            } else {
                session.phase = .unauthenticated
                engagement.reset()
                notificationStore.reset()
            }
        }
    }
}

extension View {
    func injectAppEnvironment(_ environment: AppEnvironment) -> some View {
        self
            .environment(environment)
            .environment(environment.router)
            .environment(environment.session)
            .environment(environment.appearance)
            .environment(environment.engagement)
            .environment(environment.notificationStore)
    }
}
