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

    func fetchTrendingCreators(cityID: UUID) async throws -> [Profile] {
        MockData.trendingCreators(for: cityID)
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

    func publishExperience(
        title: String,
        description: String,
        cityID: UUID,
        creatorID: UUID,
        stops: [StopPreview]
    ) async throws {
        print("--- MockExperienceRepository.publishExperience called (using Mock Backend) ---")
        try await Task.sleep(for: .milliseconds(500))
    }
}

struct MockAuthRepository: AuthRepository {
    func signIn(email: String, password: String) async throws -> Profile {
        MockData.profile(for: MockData.creators[0])
    }

    func signUp(email: String, password: String) async throws {}

    func signOut() async throws {}

    func resetPassword(email: String) async throws {}

    func signInWithGoogle() async throws -> Profile {
        try await signIn(email: "demo@trav.app", password: "")
    }

    func saveOnboardingData(userID: UUID, vibes: [String], location: String?) async throws -> Profile {
        var profile = MockData.profile(for: MockData.creators[0])
        profile.selectedVibes = vibes
        profile.onboardingLocation = location
        return profile
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
