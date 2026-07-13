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
final class AppEnvironment {
    let configuration: AppConfiguration
    let router: AppRouter
    let session: SessionStore
    let cities: any CityRepository
    let experiences: any ExperienceRepository
    let auth: any AuthRepository

    init(
        configuration: AppConfiguration,
        router: AppRouter,
        session: SessionStore,
        cities: any CityRepository,
        experiences: any ExperienceRepository,
        auth: any AuthRepository
    ) {
        self.configuration = configuration
        self.router = router
        self.session = session
        self.cities = cities
        self.experiences = experiences
        self.auth = auth
    }

    static let live: AppEnvironment = {
        let config = AppConfiguration.current
        let router = AppRouter()
        let session = SessionStore()

        return AppEnvironment(
            configuration: config,
            router: router,
            session: session,
            cities: MockCityRepository(),
            experiences: MockExperienceRepository(),
            auth: config.useMockBackend ? MockAuthRepository() : SupabaseAuthRepository()
        )
    }()

    /// Restores any persisted Supabase session and keeps `SessionStore` in sync with
    /// subsequent sign-in, sign-out, and token-refresh events. Call once at app launch;
    /// the underlying stream lives for the lifetime of the app.
    func observeAuthState() async {
        guard !configuration.useMockBackend else {
            session.phase = .unauthenticated
            return
        }

        for await profile in auth.authStateChanges() {
            session.currentUser = profile
            session.phase = profile != nil ? .authenticated : .unauthenticated
        }
    }
}

extension View {
    func injectAppEnvironment(_ environment: AppEnvironment) -> some View {
        self
            .environment(environment)
            .environment(environment.router)
            .environment(environment.session)
    }
}
