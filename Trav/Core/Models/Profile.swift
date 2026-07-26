import CryptoKit
import Foundation

struct Profile: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var username: String
    var displayName: String
    var bio: String?
    var avatarURL: URL?
    var homeCityID: UUID?
    /// Display name for home city when the cities table is not joined.
    var homeCityName: String?
    var followerCount: Int
    var followingCount: Int
    var experienceCount: Int
    var completionCount: Int
    var isVerified: Bool

    // Onboarding selections
    var selectedVibes: [String]?
    var onboardingLocation: String?

    /// Populated client-side when viewing another user's profile.
    var isFollowing: Bool?

    /// Resolved home city label for UI.
    var homeCityLabel: String? {
        if let homeCityName, !homeCityName.isEmpty { return homeCityName }
        if let onboardingLocation, !onboardingLocation.isEmpty { return onboardingLocation }
        return nil
    }

    /// True until the user has completed at least one onboarding signal.
    var needsOnboarding: Bool {
        let hasVibes = !(selectedVibes ?? []).isEmpty
        let hasLocation = !(onboardingLocation ?? "").isEmpty
        let hasHomeCity = !(homeCityName ?? "").isEmpty
        return !(hasVibes || hasLocation || hasHomeCity)
    }

    var summary: ProfileSummary {
        ProfileSummary(
            id: id,
            username: username,
            displayName: displayName,
            avatarURL: avatarURL,
            isVerified: isVerified
        )
    }
}

struct ProfileSummary: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var username: String
    var displayName: String
    var avatarURL: URL?
    var isVerified: Bool
}

/// Partial profile update — only non-nil fields are persisted.
struct ProfileUpdate: Sendable, Equatable {
    var displayName: String?
    var username: String?
    var bio: String?
    var homeCityName: String?
    var avatarURL: URL?
    var clearBio: Bool = false
    var clearHomeCity: Bool = false
    var clearAvatar: Bool = false

    var hasChanges: Bool {
        displayName != nil
            || username != nil
            || bio != nil
            || homeCityName != nil
            || avatarURL != nil
            || clearBio
            || clearHomeCity
            || clearAvatar
    }
}

struct CompletedExperienceItem: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var experience: ExperienceSummary
    var completedAt: Date
    var note: String?
}

enum ProfileContentTab: String, CaseIterable, Identifiable, Sendable {
    case created
    case saved
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .created: "Created"
        case .saved: "Saved"
        case .completed: "Watchlist"
        }
    }

    /// Extension point for future tabs (Liked, Drafts, Collections, Achievements, Badges).
    static var defaultTabs: [ProfileContentTab] { [.created, .saved, .completed] }
}

enum UsernameAvailability: Equatable, Sendable {
    case idle
    case checking
    case available
    case unavailable(reason: String)
    case invalid(reason: String)

    var isSaveAllowed: Bool {
        switch self {
        case .available, .idle: true
        default: false
        }
    }
}

enum UsernameValidator {
    static let minLength = 3
    static let maxLength = 30
    static let displayNameMax = 50
    static let bioMax = 160
    static let homeCityMax = 60

    static let reserved: Set<String> = [
        "admin", "support", "trav", "api", "help", "root", "system",
        "moderator", "mod", "staff", "official", "null", "undefined",
        "me", "you", "settings", "edit", "login", "signup", "auth",
        "www", "about", "privacy", "terms", "status", "billing", "payment"
    ]

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Local format validation before hitting the network.
    static func validateFormat(_ raw: String) -> UsernameAvailability {
        let value = normalize(raw)
        if value.count < minLength {
            return .invalid(reason: "Username must be at least \(minLength) characters.")
        }
        if value.count > maxLength {
            return .invalid(reason: "Username must be \(maxLength) characters or fewer.")
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._")
        if value.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return .invalid(reason: "Use only letters, numbers, periods, and underscores.")
        }
        if reserved.contains(value) {
            return .invalid(reason: "That username is reserved.")
        }
        return .available
    }
}

enum ProfileLimits {
    static let pageSize = 20
    /// Written into `experiences.description` when a feed place is bookmarked so it can
    /// satisfy the `experience_saves` FK without appearing in the Created tab.
    static let bookmarkDescriptionSentinel = "__trav_bookmark__"
}

enum StableUUID {
    /// Prefers parsing a real UUID; otherwise derives a deterministic id from SHA256
    /// so feed places keep the same id across launches (required for saves).
    static func from(_ raw: String) -> UUID {
        if let uuid = UUID(uuidString: raw) {
            return uuid
        }

        let digest = SHA256.hash(data: Data(raw.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
