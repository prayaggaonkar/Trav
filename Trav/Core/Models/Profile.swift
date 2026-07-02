import Foundation

struct Profile: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var username: String
    var displayName: String
    var bio: String?
    var avatarURL: URL?
    var homeCityID: UUID?
    var followerCount: Int
    var followingCount: Int
    var experienceCount: Int
    var completionCount: Int
    var isVerified: Bool
}

struct ProfileSummary: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var username: String
    var displayName: String
    var avatarURL: URL?
    var isVerified: Bool
}
