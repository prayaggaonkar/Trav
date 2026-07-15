import Foundation

protocol CityRepository: Sendable {
    func fetchGlobeCities() async throws -> [City]
    func fetchCity(id: UUID) async throws -> City
    func fetchFeaturedExperience(cityID: UUID) async throws -> ExperienceSummary?
    func fetchTrendingCreators(cityID: UUID) async throws -> [Profile]
}

protocol ExperienceRepository: Sendable {
    func fetchExperience(id: UUID) async throws -> Experience
    func fetchCityFeed(cityID: UUID, page: Int) async throws -> Paginated<ExperienceSummary>
}

protocol AuthRepository: Sendable {
    func signIn(email: String, password: String) async throws -> Profile
    func signUp(email: String, password: String) async throws
    func signOut() async throws
    func resetPassword(email: String) async throws
    func signInWithGoogle() async throws -> Profile
    func saveOnboardingData(userID: UUID, vibes: [String], location: String?) async throws -> Profile

    /// Emits the signed-in profile whenever the auth session changes, starting with the
    /// current session (or `nil`) as soon as the stream is created. Used to restore and
    /// keep `SessionStore` in sync across app launches, sign-outs, and token refreshes.
    func authStateChanges() -> AsyncStream<Profile?>
}
