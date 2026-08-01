import Foundation

/// Data model representing an experience insertion record for Supabase `experiences` table schema.
struct ExperienceInsert: Encodable, Sendable {
    static let travAdminID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// Canonical Trav profile for destinations and system-owned experiences.
    static var travCreator: ProfileSummary {
        ProfileSummary(
            id: travAdminID,
            username: "trav",
            displayName: "Trav",
            avatarURL: nil,
            isVerified: true
        )
    }

    static func isTravOwned(creatorID: UUID, username: String, displayName: String) -> Bool {
        if creatorID == travAdminID { return true }
        let user = username.lowercased()
        let name = displayName.lowercased()
        return user == "trav" || name == "trav" || name == "rec by trav"
    }

    var id: UUID
    var user_id: UUID
    var title: String
    var city: String
    var stops: [String]
    var description: String
    var image: [String: String]?
    var rating: [String: Double]?
    var city_id: UUID?
    var save_count: Int
    var like_count: Int
    var completion_count: Int
    var comment_count: Int
    var is_published: Bool
    var source_place_id: String?

    init(
        id: UUID = UUID(),
        user_id: UUID = ExperienceInsert.travAdminID,
        title: String,
        city: String,
        stops: [String],
        description: String,
        image: [String: String]? = ["url": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e"],
        rating: [String: Double]? = ["average": 4.9],
        city_id: UUID? = nil,
        save_count: Int = 0,
        like_count: Int = 0,
        completion_count: Int = 0,
        comment_count: Int = 0,
        is_published: Bool = true,
        source_place_id: String? = nil
    ) {
        self.id = id
        self.user_id = user_id
        self.title = title
        self.city = city
        self.stops = stops
        self.description = description
        self.image = image
        self.rating = rating
        self.city_id = city_id
        self.save_count = save_count
        self.like_count = like_count
        self.completion_count = completion_count
        self.comment_count = comment_count
        self.is_published = is_published
        self.source_place_id = source_place_id
    }

    enum CodingKeys: String, CodingKey {
        case id
        case user_id
        case title
        case city
        case stops
        case description
        case image
        case rating
        case city_id
        case save_count
        case like_count
        case completion_count
        case comment_count
        case is_published
        case source_place_id
    }
}
