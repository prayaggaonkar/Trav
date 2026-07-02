import Foundation

protocol CityRepository: Sendable {
    func fetchGlobeCities() async throws -> [City]
    func fetchCity(id: UUID) async throws -> City
    func fetchFeaturedExperience(cityID: UUID) async throws -> ExperienceSummary?
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
}
