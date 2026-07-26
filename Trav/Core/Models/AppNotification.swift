import Foundation

enum AppNotificationType: String, Codable, Sendable, Hashable {
    case follow
    case save
    case newExperience = "new_experience"
    case watchlist = "watchlist"
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
            return "\(name) started following you"
        case .save:
            return "\(name) saved your experience"
        case .newExperience:
            if let title = experienceTitle {
                return "\(name) posted a new experience \"\(title)\""
            }
            return "\(name) posted a new experience"
        case .watchlist:
            if let title = experienceTitle {
                return "\(name) added \(title) to the watchlist"
            }
            return "\(name) added an experience to the watchlist"
        }
    }
}
