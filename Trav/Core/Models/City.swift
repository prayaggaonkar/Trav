import Foundation

struct City: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var slug: String
    var countryCode: String
    var latitude: Double
    var longitude: Double
    var heroImageURL: URL?
    var timezone: String
    var experienceCount: Int
    var creatorCount: Int

    var coordinate: (latitude: Double, longitude: Double) {
        (latitude, longitude)
    }
}

struct CitySummary: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var slug: String
    var heroImageURL: URL?
    var experienceCount: Int
    var creatorCount: Int
}
