import Foundation
import Observation

enum TravRoute: Identifiable, Hashable, Sendable {
    case experience(UUID)
    case profile(String)
    case city(UUID)
    case notifications

    var id: String {
        switch self {
        case let .experience(id): "experience-\(id.uuidString)"
        case let .profile(username): "profile-\(username)"
        case let .city(id): "city-\(id.uuidString)"
        case .notifications: "notifications"
        }
    }
}

/// Builds shareable `trav://` links. Swap the scheme for a Universal Link
/// domain once web share pages exist.
enum TravLinks {
    static let scheme = "trav"

    static func experience(_ id: UUID) -> URL {
        URL(string: "\(scheme)://experience/\(id.uuidString.lowercased())")!
    }

    static func profile(_ username: String) -> URL {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return URL(string: "\(scheme)://profile/\(encoded)")!
    }

    static func city(_ id: UUID) -> URL {
        URL(string: "\(scheme)://city/\(id.uuidString.lowercased())")!
    }

    /// Parses a deep link into a route. Returns nil for unrecognized URLs.
    static func route(for url: URL) -> TravRoute? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let target = url.host?.lowercased() ?? ""
        let value = url.pathComponents.count > 1 ? url.pathComponents[1] : ""

        switch target {
        case "experience":
            guard let id = UUID(uuidString: value) else { return nil }
            return .experience(id)
        case "profile":
            guard !value.isEmpty else { return nil }
            return .profile(value.removingPercentEncoding ?? value)
        case "city":
            guard let id = UUID(uuidString: value) else { return nil }
            return .city(id)
        case "notifications":
            return .notifications
        default:
            return nil
        }
    }
}

struct PrefilledSpot: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let subtitle: String
    let emoji: String
    let latitude: Double?
    let longitude: Double?
    let cityName: String?
}

/// The two halves of the Create screen.
enum CreateTab: String, CaseIterable, Identifiable, Sendable {
    /// Rate an experience you finished. Completing anything lands here.
    case rating
    /// Build a new itinerary.
    case experience

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rating: "Rate"
        case .experience: "Create"
        }
    }

    var symbolName: String {
        switch self {
        case .rating: "hexagon.fill"
        case .experience: "map.fill"
        }
    }
}

/// The experience a Create Rating session is locked to.
///
/// When a user taps Complete we already know exactly what they finished, so the
/// preview is read-only. Arriving at the Create tab directly leaves this nil and
/// the user searches for the spot or itinerary instead.
struct RatingTarget: Identifiable, Equatable, Sendable {
    let id: UUID
    let summary: ExperienceSummary

    init(summary: ExperienceSummary) {
        self.id = summary.id
        self.summary = summary
    }
}

@Observable
@MainActor
final class AppRouter {
    var presentedRoute: TravRoute?
    var isAuthPresented = false

    /// Spot payload when transferring from Feed search to Create page with autocompleted spot.
    var pendingCreateSpot: PrefilledSpot? = nil

    /// Which half of the Create screen is showing.
    var createTab: CreateTab = .rating
    /// Experience locked into Create Rating, set by tapping Complete anywhere.
    var pendingRatingTarget: RatingTarget? = nil
    /// Bumped when the Create tab should be brought forward.
    private(set) var createNavigationToken: UInt = 0

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
    /// Bumped after an experience is published so Feed / Profile can reload without a restart.
    private(set) var experienceCatalogRevision: UInt = 0

    func openCreateWithSpot(title: String, subtitle: String, emoji: String, latitude: Double?, longitude: Double?, cityName: String?) {
        createTab = .experience
        pendingCreateSpot = PrefilledSpot(
            title: title,
            subtitle: subtitle,
            emoji: emoji,
            latitude: latitude,
            longitude: longitude,
            cityName: cityName
        )
    }

    /// Opens Create Rating with `summary` locked in. This is the completion flow:
    /// no confirmation sheet, straight to the rating the user has to give.
    func presentRating(for summary: ExperienceSummary) {
        presentedRoute = nil
        createTab = .rating
        pendingRatingTarget = RatingTarget(summary: summary)
        createNavigationToken &+= 1
    }

    /// Opens Create Rating with nothing preselected, so the user searches for
    /// what they finished.
    func openCreateRating() {
        createTab = .rating
        pendingRatingTarget = nil
        createNavigationToken &+= 1
    }

    func clearPendingRatingTarget() {
        pendingRatingTarget = nil
    }

    /// Opens the immersive City Page (deep links / explicit city-page entry).
    /// Globe pin taps use `openFeed(city:)` so Feed gets the city search tag.
    func openCity(_ city: City) {
        presentedRoute = .city(city.id)
    }

    func openCityPage(_ cityID: UUID) {
        presentedRoute = .city(cityID)
    }

    /// Handles a `trav://` deep link. Returns true when routed.
    @discardableResult
    func handleDeepLink(_ url: URL) -> Bool {
        guard let route = TravLinks.route(for: url) else { return false }
        presentedRoute = route
        return true
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

    func noteExperiencePublished() {
        experienceCatalogRevision &+= 1
    }

    /// Ratings, completions and new itineraries all change what feeds, profiles
    /// and detail aggregates should show.
    func noteExperienceCatalogChanged() {
        experienceCatalogRevision &+= 1
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
    /// Starts in `.loading` so the first frame doesn't flash the signed-out UI
    /// while we restore a Supabase session.
    var phase: AuthPhase = .loading
    var currentUser: Profile?

    var isAuthenticated: Bool {
        phase == .authenticated
    }
}
