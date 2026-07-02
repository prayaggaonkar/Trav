import Foundation
import Observation
import SwiftUI

struct AppConfiguration: Sendable {
    var useMockBackend: Bool
    var supabaseURL: URL?
    var supabaseAnonKey: String?
    var googleClientID: String?

    static let current: AppConfiguration = {
        let bundle = Bundle.main
        let urlString = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let key = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        let googleID = bundle.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String
        let hasBackend = urlString.flatMap(URL.init(string:)) != nil && key?.isEmpty == false
        return AppConfiguration(
            useMockBackend: !hasBackend,
            supabaseURL: urlString.flatMap(URL.init(string:)),
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
            auth: MockAuthRepository()
        )
    }()
}

extension View {
    func injectAppEnvironment(_ environment: AppEnvironment) -> some View {
        self
            .environment(environment)
            .environment(environment.router)
            .environment(environment.session)
    }
}
