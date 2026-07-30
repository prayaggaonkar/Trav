import Foundation

enum AppNotificationType: String, Codable, Sendable, Hashable {
    case follow
    case save
    case newExperience = "new_experience"
    /// Someone finished an experience. Rows written before completions replaced
    /// the watchlist carry the `watchlist` value, so both decode to this case.
    case completion
    case rating
    case like
    case comment

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "watchlist", "completion":
            self = .completion
        default:
            guard let value = AppNotificationType(rawValue: raw) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Unknown notification type \(raw)")
                )
            }
            self = value
        }
    }
}

struct AppNotification: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let userID: UUID
    let actor: ProfileSummary
    let type: AppNotificationType
    let referenceID: UUID?
    var isRead: Bool
    let createdAt: Date
    var experienceTitle: String?

    var message: String {
        let name = actor.displayName
        switch type {
        case .follow:
            return "\(name) started following you."
        case .save:
            if let title = experienceTitle {
                return "\(name) saved \"\(title)\"."
            }
            return "\(name) saved your experience."
        case .newExperience:
            if let title = experienceTitle {
                return "\(name) posted a new experience: \"\(title)\"."
            }
            return "\(name) posted a new experience."
        case .completion:
            if let title = experienceTitle {
                return "\(name) completed \"\(title)\"."
            }
            return "\(name) completed an experience."
        case .rating:
            if let title = experienceTitle {
                return "\(name) rated \"\(title)\"."
            }
            return "\(name) rated your experience."
        case .like:
            if let title = experienceTitle {
                return "\(name) liked \"\(title)\"."
            }
            return "\(name) liked your experience."
        case .comment:
            if let title = experienceTitle {
                return "\(name) commented on \"\(title)\"."
            }
            return "\(name) commented on your experience."
        }
    }

    /// Destination when tapping the notification body / toast (not the avatar).
    var primaryDestinationIsProfile: Bool {
        switch type {
        case .follow, .completion:
            return true
        case .save, .newExperience, .rating, .like, .comment:
            return referenceID == nil
        }
    }
}
