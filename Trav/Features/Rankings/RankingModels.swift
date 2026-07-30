import Foundation

// MARK: - Legacy / Repository Compatibility Models

enum RankingMode: String, CaseIterable, Identifiable, Sendable {
    case experiences
    case creators

    var id: String { rawValue }

    var title: String {
        switch self {
        case .experiences: return "Experiences"
        case .creators: return "Creators"
        }
    }
}

enum RankingAxis: String, CaseIterable, Identifiable, Sendable {
    case overall
    case cost
    case food
    case memorability
    case authenticity
    case immersion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overall: return "Overall"
        case .cost: return "Cost"
        case .food: return "Food"
        case .memorability: return "Memorability"
        case .authenticity: return "Authenticity"
        case .immersion: return "Immersion"
        }
    }

    var radarAxisID: String? {
        switch self {
        case .overall: return nil
        case .cost: return "Cost"
        case .food: return "Food"
        case .memorability: return "Memorability"
        case .authenticity: return "Authenticity"
        case .immersion: return "Immersion"
        }
    }
}

struct RankedCreator: Identifiable, Codable, Sendable, Hashable {
    var id: UUID { profile.id }
    let profile: ProfileSummary
    let averageScore: Double
    let ratedExperienceCount: Int
}

enum RankingScore {
    static func value(from rating: RadarRating, axis: RankingAxis) -> Double? {
        switch axis {
        case .overall:
            let score = rating.overallScore
            return score > 0 ? score : nil
        case .cost, .food, .memorability, .authenticity, .immersion:
            guard let key = axis.radarAxisID, rating.isEnabled(key) else { return nil }
            guard let score = rating.scores[key], score > 0 else { return nil }
            return score
        }
    }

    static func value(from experience: ExperienceSummary, axis: RankingAxis) -> Double? {
        guard let rating = experience.rating else { return nil }
        return value(from: rating, axis: axis)
    }

    static func sortedExperiences(
        _ experiences: [ExperienceSummary],
        axis: RankingAxis
    ) -> [ExperienceSummary] {
        var rated: [(ExperienceSummary, Double)] = []
        var unrated: [ExperienceSummary] = []

        for experience in experiences {
            if let score = value(from: experience, axis: axis) {
                rated.append((experience, score))
            } else {
                unrated.append(experience)
            }
        }

        rated.sort { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
        }
        unrated.sort {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        return rated.map(\.0) + unrated
    }

    static func rankedCreators(
        from experiences: [ExperienceSummary],
        axis: RankingAxis
    ) -> [RankedCreator] {
        var buckets: [UUID: (profile: ProfileSummary, total: Double, count: Int, experienceCount: Int)] = [:]

        for experience in experiences {
            let creator = experience.creator
            var bucket = buckets[creator.id]
                ?? (profile: creator, total: 0, count: 0, experienceCount: 0)
            bucket.experienceCount += 1
            if let score = value(from: experience, axis: axis) {
                bucket.total += score
                bucket.count += 1
            }
            buckets[creator.id] = bucket
        }

        return buckets.values
            .filter { $0.experienceCount >= 1 }
            .map { bucket in
                let average: Double
                if bucket.count > 0 {
                    average = (bucket.total / Double(bucket.count) * 10.0).rounded() / 10.0
                } else {
                    average = 0
                }
                return RankedCreator(
                    profile: bucket.profile,
                    averageScore: average,
                    ratedExperienceCount: bucket.count
                )
            }
            .sorted { lhs, rhs in
                let lhsRated = lhs.ratedExperienceCount > 0
                let rhsRated = rhs.ratedExperienceCount > 0
                if lhsRated != rhsRated { return lhsRated && !rhsRated }
                if lhs.averageScore != rhs.averageScore {
                    return lhs.averageScore > rhs.averageScore
                }
                if lhs.ratedExperienceCount != rhs.ratedExperienceCount {
                    return lhs.ratedExperienceCount > rhs.ratedExperienceCount
                }
                return lhs.profile.displayName.localizedCaseInsensitiveCompare(rhs.profile.displayName)
                    == .orderedAscending
            }
    }

    static var pageSize: Int { 40 }

    static func paginate<T>(_ items: [T], page: Int) -> Paginated<T> {
        let size = pageSize
        let start = max(0, page) * size
        guard start < items.count else {
            return Paginated(items: [], page: page, hasMore: false)
        }
        let end = min(start + size, items.count)
        return Paginated(
            items: Array(items[start..<end]),
            page: page,
            hasMore: end < items.count
        )
    }
}

// MARK: - Leaderboard UI Models

/// Filter for member scope in the leaderboard (All Members vs. Friends).
enum MemberScopeFilter: String, CaseIterable, Identifiable, Sendable {
    case allMembers = "All Members"
    case friends = "Friends"

    var id: String { rawValue }
    var title: String { rawValue }

    var subtitle: String {
        switch self {
        case .allMembers: return "Show rankings for all community members"
        case .friends: return "Show rankings for people you follow"
        }
    }

    var iconName: String {
        switch self {
        case .allMembers: return "person.3.fill"
        case .friends: return "person.2.fill"
        }
    }
}

/// Representation of a user on the Leaderboard.
struct LeaderboardEntry: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let username: String
    let displayName: String
    let avatarURL: URL?
    let experienceCount: Int
    let cityName: String?
    let cityID: UUID?
    let isFriend: Bool
}

/// Catalog location option for the location filter pill.
struct LocationOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let subtitle: String?

    static let allLocations = LocationOption(id: "all", name: "Worldwide", subtitle: "Global")
}

enum MockLeaderboardData {
    static let defaultLocation = LocationOption(id: "dublin_ca", name: "Dublin, CA", subtitle: "California, USA")

    static let entries: [LeaderboardEntry] = [
        LeaderboardEntry(
            id: UUID(uuidString: "B1000001-0000-0000-0000-000000000001")!,
            username: "daniellkang",
            displayName: "Daniel Kang",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&h=200&fit=crop"),
            experienceCount: 124,
            cityName: "Dublin, CA",
            cityID: UUID(uuidString: "C1000001-0000-0000-0000-000000000001"),
            isFriend: true
        ),
        LeaderboardEntry(
            id: UUID(uuidString: "B1000002-0000-0000-0000-000000000002")!,
            username: "KevinKngows",
            displayName: "Kevin Kngows",
            avatarURL: nil,
            experienceCount: 85,
            cityName: "Dublin, CA",
            cityID: UUID(uuidString: "C1000001-0000-0000-0000-000000000001"),
            isFriend: true
        ),
        LeaderboardEntry(
            id: UUID(uuidString: "B1000003-0000-0000-0000-000000000003")!,
            username: "prachiti415",
            displayName: "Prachiti",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1517841905240-472988babdf9?w=200&h=200&fit=crop"),
            experienceCount: 82,
            cityName: "Dublin, CA",
            cityID: UUID(uuidString: "C1000001-0000-0000-0000-000000000001"),
            isFriend: false
        ),
        LeaderboardEntry(
            id: UUID(uuidString: "B1000004-0000-0000-0000-000000000004")!,
            username: "Yezybear",
            displayName: "Yezy Bear",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=200&h=200&fit=crop"),
            experienceCount: 72,
            cityName: "Dublin, CA",
            cityID: UUID(uuidString: "C1000001-0000-0000-0000-000000000001"),
            isFriend: true
        ),
        LeaderboardEntry(
            id: UUID(uuidString: "B1000005-0000-0000-0000-000000000005")!,
            username: "adityakatkol",
            displayName: "Aditya Katkol",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&h=200&fit=crop"),
            experienceCount: 69,
            cityName: "Dublin, CA",
            cityID: UUID(uuidString: "C1000001-0000-0000-0000-000000000001"),
            isFriend: false
        ),
        LeaderboardEntry(
            id: UUID(uuidString: "B1000006-0000-0000-0000-000000000006")!,
            username: "preson",
            displayName: "Preson",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1492562080023-ab3db95bfbce?w=200&h=200&fit=crop"),
            experienceCount: 65,
            cityName: "Dublin, CA",
            cityID: UUID(uuidString: "C1000001-0000-0000-0000-000000000001"),
            isFriend: true
        ),
        LeaderboardEntry(
            id: UUID(uuidString: "B1000007-0000-0000-0000-000000000007")!,
            username: "nikkingvyen",
            displayName: "Nikki Nguyen",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=200&h=200&fit=crop"),
            experienceCount: 65,
            cityName: "San Francisco, CA",
            cityID: UUID(uuidString: "C1000001-0000-0000-0000-000000000001"),
            isFriend: false
        ),
        LeaderboardEntry(
            id: UUID(uuidString: "B1000008-0000-0000-0000-000000000008")!,
            username: "kaylinhoang",
            displayName: "Kaylin Hoang",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=200&h=200&fit=crop"),
            experienceCount: 58,
            cityName: "Dublin, CA",
            cityID: UUID(uuidString: "C1000001-0000-0000-0000-000000000001"),
            isFriend: true
        ),
        LeaderboardEntry(
            id: UUID(uuidString: "A1000001-0000-0000-0000-000000000001")!,
            username: "maya.chen",
            displayName: "Maya Chen",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&h=200&fit=crop"),
            experienceCount: 48,
            cityName: "San Francisco, CA",
            cityID: UUID(uuidString: "C1000001-0000-0000-0000-000000000001"),
            isFriend: true
        ),
        LeaderboardEntry(
            id: UUID(uuidString: "A1000002-0000-0000-0000-000000000002")!,
            username: "jordan.lee",
            displayName: "Jordan Lee",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=200&h=200&fit=crop"),
            experienceCount: 39,
            cityName: "New York, NY",
            cityID: UUID(uuidString: "C1000004-0000-0000-0000-000000000004"),
            isFriend: false
        ),
        LeaderboardEntry(
            id: UUID(uuidString: "A1000003-0000-0000-0000-000000000003")!,
            username: "sam.okafor",
            displayName: "Sam Okafor",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=200&h=200&fit=crop"),
            experienceCount: 31,
            cityName: "Tokyo, Japan",
            cityID: UUID(uuidString: "C1000002-0000-0000-0000-000000000002"),
            isFriend: true
        ),
        LeaderboardEntry(
            id: UUID(uuidString: "A1000004-0000-0000-0000-000000000004")!,
            username: "yuki.tanaka",
            displayName: "Yuki Tanaka",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&h=200&fit=crop"),
            experienceCount: 27,
            cityName: "Tokyo, Japan",
            cityID: UUID(uuidString: "C1000002-0000-0000-0000-000000000002"),
            isFriend: false
        )
    ]

    static let locationOptions: [LocationOption] = [
        LocationOption.allLocations,
        defaultLocation,
        LocationOption(id: "sf_ca", name: "San Francisco, CA", subtitle: "California, USA"),
        LocationOption(id: "ny_ny", name: "New York, NY", subtitle: "New York, USA"),
        LocationOption(id: "tokyo", name: "Tokyo, Japan", subtitle: "Kanto, Japan"),
        LocationOption(id: "paris", name: "Paris, France", subtitle: "Île-de-France"),
        LocationOption(id: "london", name: "London, UK", subtitle: "England, UK"),
        LocationOption(id: "sydney", name: "Sydney, Australia", subtitle: "NSW, Australia"),
        LocationOption(id: "barcelona", name: "Barcelona, Spain", subtitle: "Catalonia, Spain")
    ]
}

// MARK: - Heat Streak Models

import SwiftUI

/// Data model representing an experience stored in Supabase with location verification flags.
struct HeatStreakExperience: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let userID: UUID
    let createdAt: Date
    let title: String
    let description: String?
    let rating: RadarRating?
    let latitude: Double?
    let longitude: Double?
    let isLocationVerified: Bool
    let locationOptOut: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case createdAt = "created_at"
        case title
        case description
        case rating
        case latitude
        case longitude
        case isLocationVerified = "is_location_verified"
        case locationOptOut = "location_opt_out"
    }
}

/// Data model representing a user entry on the Heat Streak Leaderboard.
struct HeatStreakEntry: Identifiable, Codable, Sendable, Hashable {
    let id: UUID // User Profile ID
    let username: String
    let displayName: String
    let avatarURL: URL?
    let count30Days: Int
    let consecutiveDays: Int
    let isLocationVerified: Bool
    let rank: Int

    /// Formatted text string: "x posts/y days" (e.g. "8 posts/4 days", "1 post/1 day")
    var streakLabel: String {
        "\(postsLabel)/\(daysLabel)"
    }

    var postsLabel: String {
        count30Days == 1 ? "1 post" : "\(count30Days) posts"
    }

    var daysLabel: String {
        consecutiveDays == 1 ? "1 day" : "\(consecutiveDays) days"
    }

    /// Flame icon color based on streak count:
    /// Standard Orange for 1-3 posts, Blue-Hot Cyan for 4+ posts.
    var flameColor: Color {
        consecutiveDays >= 4 || count30Days >= 4 ? Color.cyan : Color.orange
    }

    /// Flame icon name
    var flameIcon: String {
        "flame.fill"
    }

    init(
        id: UUID,
        username: String,
        displayName: String,
        avatarURL: URL?,
        count30Days: Int,
        consecutiveDays: Int = 1,
        isLocationVerified: Bool = true,
        rank: Int
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.count30Days = count30Days
        self.consecutiveDays = consecutiveDays
        self.isLocationVerified = isLocationVerified
        self.rank = rank
    }
}

enum MockHeatStreakData {
    static let entries: [HeatStreakEntry] = [
        HeatStreakEntry(
            id: UUID(uuidString: "B1000001-0000-0000-0000-000000000001")!,
            username: "daniellkang",
            displayName: "Daniel Kang",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&h=200&fit=crop"),
            count30Days: 14,
            consecutiveDays: 6,
            isLocationVerified: true,
            rank: 1
        ),
        HeatStreakEntry(
            id: UUID(uuidString: "B1000002-0000-0000-0000-000000000002")!,
            username: "KevinKngows",
            displayName: "Kevin Knows",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&h=200&fit=crop"),
            count30Days: 6,
            consecutiveDays: 4,
            isLocationVerified: true,
            rank: 2
        ),
        HeatStreakEntry(
            id: UUID(uuidString: "B1000003-0000-0000-0000-000000000003")!,
            username: "sarah_explores",
            displayName: "Sarah Chen",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&h=200&fit=crop"),
            count30Days: 3,
            consecutiveDays: 2,
            isLocationVerified: true,
            rank: 3
        ),
        HeatStreakEntry(
            id: UUID(uuidString: "B1000004-0000-0000-0000-000000000004")!,
            username: "alex_travels",
            displayName: "Alex Rivera",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=200&h=200&fit=crop"),
            count30Days: 2,
            consecutiveDays: 2,
            isLocationVerified: true,
            rank: 4
        ),
        HeatStreakEntry(
            id: UUID(uuidString: "B1000005-0000-0000-0000-000000000005")!,
            username: "yuki.tanaka",
            displayName: "Yuki Tanaka",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&h=200&fit=crop"),
            count30Days: 1,
            consecutiveDays: 1,
            isLocationVerified: true,
            rank: 5
        )
    ]
}

/// Data model representing a user entry on the Impact Leaderboard.
struct ImpactEntry: Identifiable, Codable, Sendable, Hashable {
    let id: UUID // User Profile ID
    let username: String
    let displayName: String
    let avatarURL: URL?
    let totalImpactCount: Int // Total completions + saves across all published experiences
    let rank: Int
}

enum MockImpactData {
    static let entries: [ImpactEntry] = [
        ImpactEntry(
            id: UUID(uuidString: "B1000001-0000-0000-0000-000000000001")!,
            username: "daniellkang",
            displayName: "Daniel Kang",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&h=200&fit=crop"),
            totalImpactCount: 14200,
            rank: 1
        ),
        ImpactEntry(
            id: UUID(uuidString: "B1000002-0000-0000-0000-000000000002")!,
            username: "KevinKngows",
            displayName: "Kevin Knows",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&h=200&fit=crop"),
            totalImpactCount: 9840,
            rank: 2
        ),
        ImpactEntry(
            id: UUID(uuidString: "B1000003-0000-0000-0000-000000000003")!,
            username: "sarah_explores",
            displayName: "Sarah Chen",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&h=200&fit=crop"),
            totalImpactCount: 6720,
            rank: 3
        ),
        ImpactEntry(
            id: UUID(uuidString: "B1000004-0000-0000-0000-000000000004")!,
            username: "alex_travels",
            displayName: "Alex Rivera",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=200&h=200&fit=crop"),
            totalImpactCount: 4560,
            rank: 4
        ),
        ImpactEntry(
            id: UUID(uuidString: "B1000005-0000-0000-0000-000000000005")!,
            username: "yuki.tanaka",
            displayName: "Yuki Tanaka",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&h=200&fit=crop"),
            totalImpactCount: 2840,
            rank: 5
        )
    ]
}

// MARK: - Main Leaderboard Models

/// Data model representing a user entry on the Main Leaderboard.
/// Point Formula: Total Score = (Impact * 5) + (Experiences * 25) + (Streak Days * 15) + (Streak Posts * 5)
struct MainLeaderboardEntry: Identifiable, Codable, Sendable, Hashable {
    let id: UUID // User Profile ID
    let username: String
    let displayName: String
    let avatarURL: URL?
    let impactCount: Int
    let experienceCount: Int
    let streakDays: Int
    let streakPosts: Int
    let totalScore: Int
    let rank: Int

    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case impactCount = "impact_count"
        case experienceCount = "experience_count"
        case streakDays = "streak_days"
        case streakPosts = "streak_posts"
        case totalScore = "total_score"
        case rank
    }

    init(
        id: UUID,
        username: String,
        displayName: String,
        avatarURL: URL?,
        impactCount: Int,
        experienceCount: Int,
        streakDays: Int,
        streakPosts: Int,
        totalScore: Int? = nil,
        rank: Int
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.impactCount = impactCount
        self.experienceCount = experienceCount
        self.streakDays = streakDays
        self.streakPosts = streakPosts
        self.rank = rank
        if let totalScore {
            self.totalScore = totalScore
        } else {
            self.totalScore = (impactCount * 5) + (experienceCount * 25) + (streakDays * 15) + (streakPosts * 5)
        }
    }
}

enum MockMainLeaderboardData {
    static let entries: [MainLeaderboardEntry] = [
        MainLeaderboardEntry(
            id: UUID(uuidString: "B1000001-0000-0000-0000-000000000001")!,
            username: "daniellkang",
            displayName: "Daniel Kang",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&h=200&fit=crop"),
            impactCount: 14,
            experienceCount: 12,
            streakDays: 6,
            streakPosts: 8,
            rank: 1
        ),
        MainLeaderboardEntry(
            id: UUID(uuidString: "B1000002-0000-0000-0000-000000000002")!,
            username: "KevinKngows",
            displayName: "Kevin Knows",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&h=200&fit=crop"),
            impactCount: 10,
            experienceCount: 8,
            streakDays: 4,
            streakPosts: 5,
            rank: 2
        ),
        MainLeaderboardEntry(
            id: UUID(uuidString: "B1000003-0000-0000-0000-000000000003")!,
            username: "sarah_explores",
            displayName: "Sarah Chen",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&h=200&fit=crop"),
            impactCount: 7,
            experienceCount: 5,
            streakDays: 2,
            streakPosts: 3,
            rank: 3
        )
    ]
}

