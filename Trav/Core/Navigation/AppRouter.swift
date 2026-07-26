import Foundation
import Observation

enum TravRoute: Identifiable, Hashable, Sendable {
    case experience(UUID)
    case profile(String)
    case notifications

    var id: String {
        switch self {
        case let .experience(id): "experience-\(id.uuidString)"
        case let .profile(username): "profile-\(username)"
        case .notifications: "notifications"
        }
    }
}

@Observable
@MainActor
final class AppRouter {
    var presentedRoute: TravRoute?
    var isAuthPresented = false

    /// Strict city scope for the Feed tab (catalog city only — never free-typed).
    var selectedFeedCity: City?
    /// Strict creator scope for the Feed tab (from people suggestions).
    var selectedFeedUser: ProfileSummary?
    /// Free-text keyword filter for Feed (title, people, stops, location text).
    var feedKeyword: String = ""
    /// Bumped whenever navigation should switch to the Feed tab (e.g. globe city tap).
    private(set) var feedNavigationToken: UInt = 0
    /// Bumped whenever the Explore tab becomes active so the globe can reset framing.
    private(set) var exploreActivationToken: UInt = 0

    /// Opens Feed with a strict city filter applied (globe pin / city suggestion).
    func openCity(_ city: City) {
        selectedFeedCity = city
        feedKeyword = ""
        feedNavigationToken &+= 1
    }

    /// Switches to Feed, optionally applying a city chip.
    func openFeed(city: City?) {
        selectedFeedCity = city
        if city != nil {
            feedKeyword = ""
        }
        feedNavigationToken &+= 1
    }

    func clearFeedCity() {
        selectedFeedCity = nil
    }

    func clearFeedUser() {
        selectedFeedUser = nil
    }

    func clearFeedSearch() {
        selectedFeedCity = nil
        selectedFeedUser = nil
        feedKeyword = ""
    }

    func noteExploreActivated() {
        exploreActivationToken &+= 1
    }

    func openExperience(_ experienceID: UUID) {
        presentedRoute = .experience(experienceID)
    }

    func openProfile(_ username: String) {
        presentedRoute = .profile(username)
    }

    func openNotifications() {
        presentedRoute = .notifications
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
