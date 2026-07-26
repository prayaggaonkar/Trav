import Foundation

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

/// Sort key for rankings — overall average or a single radar axis.
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

    /// Radar axis ID in `RadarRating.scores`, or `nil` for overall.
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
    /// Mean score across rated experiences for the selected axis.
    let averageScore: Double
    let ratedExperienceCount: Int
}

/// Abstraction over how a ranking score is derived from an experience rating.
/// Today: creator-authored radar. Later: can swap to community averages.
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
                // Creators with real ratings sort above those without.
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
