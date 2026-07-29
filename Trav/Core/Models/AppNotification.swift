import Foundation

enum AppNotificationType: String, Codable, Sendable, Hashable {
    case follow
    case save
    case newExperience = "new_experience"
    case watchlist = "watchlist"
    case like
    case comment
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
        case .watchlist:
            if let title = experienceTitle {
                return "\(name) added \"\(title)\" to the watchlist."
            }
            return "\(name) added an experience to the watchlist."
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
        case .follow, .watchlist:
            return true
        case .save, .newExperience, .like, .comment:
            return referenceID == nil
        }
    }
}
