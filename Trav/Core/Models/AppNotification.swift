import Foundation

enum AppNotificationType: String, Codable, Sendable, Hashable {
    case follow
    case save
    case newExperience = "new_experience"
}

struct AppNotification: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let userID: UUID
    let actor: ProfileSummary
    let type: AppNotificationType
    let referenceID: UUID?
    var isRead: Bool
    let createdAt: Date

    var message: String {
        let name = actor.displayName
        switch type {
        case .follow:
            return "\(name) started following you"
        case .save:
            return "\(name) saved your experience"
        case .newExperience:
            return "\(name) posted a new experience"
        }
    }
}
