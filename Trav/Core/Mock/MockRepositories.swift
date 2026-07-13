import Foundation

struct MockCityRepository: CityRepository {
    func fetchGlobeCities() async throws -> [City] {
        try await Task.sleep(for: .milliseconds(200))
        return MockData.cities
    }

    func fetchCity(id: UUID) async throws -> City {
        guard let city = MockData.cities.first(where: { $0.id == id }) else {
            throw RepositoryError.notFound
        }
        return city
    }

    func fetchFeaturedExperience(cityID: UUID) async throws -> ExperienceSummary? {
        MockData.experiences.first { $0.cityID == cityID }
    }
}

struct MockExperienceRepository: ExperienceRepository {
    func fetchExperience(id: UUID) async throws -> Experience {
        guard let summary = MockData.experiences.first(where: { $0.id == id }) else {
            throw RepositoryError.notFound
        }
        return MockData.fullExperience(for: summary)
    }

    func fetchCityFeed(cityID: UUID, page: Int) async throws -> Paginated<ExperienceSummary> {
        let items = MockData.experiences.filter { $0.cityID == cityID }
        return Paginated(items: items, page: page, hasMore: false)
    }
}

struct MockAuthRepository: AuthRepository {
    func signIn(email: String, password: String) async throws -> Profile {
        Profile(
            id: MockData.creators[0].id,
            username: MockData.creators[0].username,
            displayName: MockData.creators[0].displayName,
            bio: "Exploring cities one experience at a time.",
            avatarURL: MockData.creators[0].avatarURL,
            homeCityID: MockData.cities[0].id,
            followerCount: 1240,
            followingCount: 342,
            experienceCount: 18,
            completionCount: 67,
            isVerified: true
        )
    }

    func signUp(email: String, password: String) async throws {}

    func signOut() async throws {}

    func resetPassword(email: String) async throws {}

    func signInWithGoogle() async throws -> Profile {
        try await signIn(email: "demo@trav.app", password: "")
    }

    func authStateChanges() -> AsyncStream<Profile?> {
        AsyncStream { continuation in
            continuation.yield(nil)
            continuation.finish()
        }
    }
}

enum RepositoryError: LocalizedError {
    case notFound
    case unauthorized
    case network

    var errorDescription: String? {
        switch self {
        case .notFound: "Content not found."
        case .unauthorized: "Please sign in to continue."
        case .network: "Check your connection and try again."
        }
    }
}
