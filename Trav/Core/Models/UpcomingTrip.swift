import Foundation

enum TripType: String, Codable, Sendable, CaseIterable, Identifiable {
    case upcomingTrip = "Upcoming Trip"
    case dayTrip = "Day Trip"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .upcomingTrip: return "airplane.departure"
        case .dayTrip: return "car.fill"
        }
    }
}

struct TripRecommendation: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let tripID: UUID
    let user: ProfileSummary
    let spotName: String
    let spotCategory: String?
    let latitude: Double
    let longitude: Double
    let imageURL: URL?
    var upvoteCount: Int
    var isLikedByCurrentUser: Bool = false
    let createdAt: Date

    var isUserUploaded: Bool {
        isUserUploadedImage(imageURL)
    }
}

struct UpcomingTrip: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let user: ProfileSummary
    let destinationName: String
    let destinationCity: String?
    let latitude: Double
    let longitude: Double
    let startDate: Date
    let endDate: Date?
    let note: String?
    var tripType: TripType = .upcomingTrip
    let createdAt: Date
    var recommendations: [TripRecommendation]

    var dateRangeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        let startStr = formatter.string(from: startDate)

        if tripType == .dayTrip {
            return "\(startStr) • Day Trip"
        }

        if let endDate {
            let endFormatter = DateFormatter()
            endFormatter.dateFormat = "MMM d"
            let endStr = endFormatter.string(from: endDate)
            return "\(startStr) – \(endStr)"
        }
        return "\(startStr)"
    }

    var recommendationCount: Int {
        recommendations.count
    }
}

extension UpcomingTrip {
    static let presetRecommendationTags: [String] = [
        "Coffee & Cafes",
        "Food & Dining",
        "Nightlife & Speakeasies",
        "Arts & Culture",
        "Nature & Hikes",
        "Shopping & Boutiques",
        "Scenic Views",
        "Hidden Gems",
        "Live Music",
        "Wellness & Spa",
        "Family Friendly",
        "Classes & Workshops"
    ]

    var categoryTags: [String] {
        guard let note, !note.isEmpty else { return [] }
        return note.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
