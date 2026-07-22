import Foundation

/// Shared Codable row for the `profiles` table.
struct ProfileRow: Codable, Sendable {
    var id: UUID
    var username: String
    var displayName: String
    var bio: String?
    var avatarURL: URL?
    var homeCityID: UUID?
    var homeCityName: String?
    var followerCount: Int
    var followingCount: Int
    var experienceCount: Int
    var completionCount: Int
    var isVerified: Bool
    var selectedVibes: [String]?
    var onboardingLocation: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case bio
        case avatarURL = "avatar_url"
        case homeCityID = "home_city_id"
        case homeCityName = "home_city_name"
        case followerCount = "follower_count"
        case followingCount = "following_count"
        case experienceCount = "experience_count"
        case completionCount = "completion_count"
        case isVerified = "is_verified"
        case selectedVibes = "selected_vibes"
        case onboardingLocation = "onboarding_location"
    }

    init(
        id: UUID,
        username: String,
        displayName: String,
        bio: String?,
        avatarURL: URL?,
        homeCityID: UUID?,
        homeCityName: String?,
        followerCount: Int,
        followingCount: Int,
        experienceCount: Int,
        completionCount: Int,
        isVerified: Bool,
        selectedVibes: [String]?,
        onboardingLocation: String?
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.bio = bio
        self.avatarURL = avatarURL
        self.homeCityID = homeCityID
        self.homeCityName = homeCityName
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.experienceCount = experienceCount
        self.completionCount = completionCount
        self.isVerified = isVerified
        self.selectedVibes = selectedVibes
        self.onboardingLocation = onboardingLocation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        displayName = try c.decode(String.self, forKey: .displayName)
        bio = try c.decodeIfPresent(String.self, forKey: .bio)
        if let urlString = try c.decodeIfPresent(String.self, forKey: .avatarURL) {
            avatarURL = URL(string: urlString)
        } else {
            avatarURL = nil
        }
        homeCityID = try c.decodeIfPresent(UUID.self, forKey: .homeCityID)
        // `home_city_name` may not exist on older schemas; fall back to onboarding_location.
        let explicitCity = try c.decodeIfPresent(String.self, forKey: .homeCityName)
        onboardingLocation = try c.decodeIfPresent(String.self, forKey: .onboardingLocation)
        homeCityName = explicitCity ?? onboardingLocation
        followerCount = try c.decodeIfPresent(Int.self, forKey: .followerCount) ?? 0
        followingCount = try c.decodeIfPresent(Int.self, forKey: .followingCount) ?? 0
        experienceCount = try c.decodeIfPresent(Int.self, forKey: .experienceCount) ?? 0
        completionCount = try c.decodeIfPresent(Int.self, forKey: .completionCount) ?? 0
        isVerified = try c.decodeIfPresent(Bool.self, forKey: .isVerified) ?? false
        selectedVibes = try c.decodeIfPresent([String].self, forKey: .selectedVibes)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(username, forKey: .username)
        try c.encode(displayName, forKey: .displayName)
        try c.encodeIfPresent(bio, forKey: .bio)
        try c.encodeIfPresent(avatarURL?.absoluteString, forKey: .avatarURL)
        try c.encodeIfPresent(homeCityID, forKey: .homeCityID)
        // Persist city on the column that exists in production today.
        try c.encodeIfPresent(homeCityName ?? onboardingLocation, forKey: .onboardingLocation)
        try c.encode(followerCount, forKey: .followerCount)
        try c.encode(followingCount, forKey: .followingCount)
        try c.encode(experienceCount, forKey: .experienceCount)
        try c.encode(completionCount, forKey: .completionCount)
        try c.encode(isVerified, forKey: .isVerified)
        try c.encodeIfPresent(selectedVibes, forKey: .selectedVibes)
    }

    var profile: Profile {
        let city = homeCityName ?? onboardingLocation
        return Profile(
            id: id,
            username: username,
            displayName: displayName,
            bio: bio,
            avatarURL: avatarURL,
            homeCityID: homeCityID,
            homeCityName: city,
            followerCount: followerCount,
            followingCount: followingCount,
            experienceCount: experienceCount,
            completionCount: completionCount,
            isVerified: isVerified,
            selectedVibes: selectedVibes,
            onboardingLocation: onboardingLocation ?? city,
            isFollowing: nil
        )
    }

    static func placeholder(for userID: UUID, email: String?) -> ProfileRow {
        let localPart = email?.split(separator: "@").first.map(String.init) ?? "traveler"
        let sanitized = localPart
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").contains($0) }
            .map(String.init)
            .joined()
        let base = sanitized.isEmpty ? "traveler" : String(sanitized.prefix(20))
        let suffix = String(userID.uuidString.prefix(4)).lowercased()
        return ProfileRow(
            id: userID,
            username: "\(base)\(suffix)",
            displayName: localPart.capitalized,
            bio: nil,
            avatarURL: nil,
            homeCityID: nil,
            homeCityName: nil,
            followerCount: 0,
            followingCount: 0,
            experienceCount: 0,
            completionCount: 0,
            isVerified: false,
            selectedVibes: [],
            onboardingLocation: nil
        )
    }
}
