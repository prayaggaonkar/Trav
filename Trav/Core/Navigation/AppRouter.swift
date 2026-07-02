import Foundation
import Observation

enum TravRoute: Identifiable, Hashable, Sendable {
    case city(UUID)
    case experience(UUID)
    case profile(String)

    var id: String {
        switch self {
        case let .city(id): "city-\(id.uuidString)"
        case let .experience(id): "experience-\(id.uuidString)"
        case let .profile(username): "profile-\(username)"
        }
    }
}

@Observable
@MainActor
final class AppRouter {
    var presentedRoute: TravRoute?
    var isAuthPresented = false

    func openCity(_ cityID: UUID) {
        presentedRoute = .city(cityID)
    }

    func openExperience(_ experienceID: UUID) {
        presentedRoute = .experience(experienceID)
    }

    func openProfile(_ username: String) {
        presentedRoute = .profile(username)
    }

    func dismiss() {
        presentedRoute = nil
    }

    func presentAuth() {
        isAuthPresented = true
    }

    func dismissAuth() {
        isAuthPresented = false
    }
}

@Observable
@MainActor
final class SessionStore {
    var phase: AuthPhase = .unauthenticated
    var currentUser: Profile?

    var isAuthenticated: Bool {
        phase == .authenticated
    }
}
