import Foundation

struct Comment: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let experienceID: UUID
    var author: ProfileSummary
    var parentID: UUID?
    var body: String
    var createdAt: Date
}

enum CommentLimits {
    static let maxLength = 1000
    static let pageSize = 30
}

enum ReportReason: String, CaseIterable, Sendable, Identifiable {
    case spam
    case inappropriate
    case harassment
    case misinformation
    case copyright
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spam: "Spam"
        case .inappropriate: "Inappropriate content"
        case .harassment: "Harassment or bullying"
        case .misinformation: "False information"
        case .copyright: "Copyright violation"
        case .other: "Something else"
        }
    }
}

enum ReportTarget: Sendable, Equatable {
    case experience(UUID)
    case comment(UUID)
    case user(UUID)
}
