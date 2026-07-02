import Foundation

enum MockData {
    static let creators: [ProfileSummary] = [
        ProfileSummary(
            id: UUID(uuidString: "A1000001-0000-0000-0000-000000000001")!,
            username: "maya.chen",
            displayName: "Maya Chen",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&h=200&fit=crop"),
            isVerified: true
        ),
        ProfileSummary(
            id: UUID(uuidString: "A1000002-0000-0000-0000-000000000002")!,
            username: "jordan.lee",
            displayName: "Jordan Lee",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&h=200&fit=crop"),
            isVerified: false
        ),
        ProfileSummary(
            id: UUID(uuidString: "A1000003-0000-0000-0000-000000000003")!,
            username: "sam.okafor",
            displayName: "Sam Okafor",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=200&h=200&fit=crop"),
            isVerified: true
        )
    ]

    static let cities: [City] = [
        City(
            id: UUID(uuidString: "C1000001-0000-0000-0000-000000000001")!,
            name: "San Francisco",
            slug: "san-francisco",
            countryCode: "US",
            latitude: 37.7749,
            longitude: -122.4194,
            heroImageURL: URL(string: "https://images.unsplash.com/photo-1501594907352-04cda38ebc29?w=1200&q=80"),
            timezone: "America/Los_Angeles",
            experienceCount: 842,
            creatorCount: 312
        ),
        City(
            id: UUID(uuidString: "C1000002-0000-0000-0000-000000000002")!,
            name: "Tokyo",
            slug: "tokyo",
            countryCode: "JP",
            latitude: 35.6762,
            longitude: 139.6503,
            heroImageURL: URL(string: "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=1200&q=80"),
            timezone: "Asia/Tokyo",
            experienceCount: 1204,
            creatorCount: 489
        ),
        City(
            id: UUID(uuidString: "C1000003-0000-0000-0000-000000000003")!,
            name: "Paris",
            slug: "paris",
            countryCode: "FR",
            latitude: 48.8566,
            longitude: 2.3522,
            heroImageURL: URL(string: "https://images.unsplash.com/photo-1502602898657-3e91760cbb34?w=1200&q=80"),
            timezone: "Europe/Paris",
            experienceCount: 967,
            creatorCount: 401
        ),
        City(
            id: UUID(uuidString: "C1000004-0000-0000-0000-000000000004")!,
            name: "New York",
            slug: "new-york",
            countryCode: "US",
            latitude: 40.7128,
            longitude: -74.0060,
            heroImageURL: URL(string: "https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?w=1200&q=80"),
            timezone: "America/New_York",
            experienceCount: 1532,
            creatorCount: 578
        ),
        City(
            id: UUID(uuidString: "C1000005-0000-0000-0000-000000000005")!,
            name: "London",
            slug: "london",
            countryCode: "GB",
            latitude: 51.5074,
            longitude: -0.1278,
            heroImageURL: URL(string: "https://images.unsplash.com/photo-1513635269975-59663e0ac1ad?w=1200&q=80"),
            timezone: "Europe/London",
            experienceCount: 891,
            creatorCount: 334
        ),
        City(
            id: UUID(uuidString: "C1000006-0000-0000-0000-000000000006")!,
            name: "Barcelona",
            slug: "barcelona",
            countryCode: "ES",
            latitude: 41.3874,
            longitude: 2.1686,
            heroImageURL: URL(string: "https://images.unsplash.com/photo-1583422409516-2895a77efded?w=1200&q=80"),
            timezone: "Europe/Madrid",
            experienceCount: 654,
            creatorCount: 267
        ),
        City(
            id: UUID(uuidString: "C1000007-0000-0000-0000-000000000007")!,
            name: "Sydney",
            slug: "sydney",
            countryCode: "AU",
            latitude: -33.8688,
            longitude: 151.2093,
            heroImageURL: URL(string: "https://images.unsplash.com/photo-1506973035872-a4ec16b8e8d9?w=1200&q=80"),
            timezone: "Australia/Sydney",
            experienceCount: 523,
            creatorCount: 198
        ),
        City(
            id: UUID(uuidString: "C1000008-0000-0000-0000-000000000008")!,
            name: "Seoul",
            slug: "seoul",
            countryCode: "KR",
            latitude: 37.5665,
            longitude: 126.9780,
            heroImageURL: URL(string: "https://images.unsplash.com/photo-1517154421773-0529f29ea451?w=1200&q=80"),
            timezone: "Asia/Seoul",
            experienceCount: 778,
            creatorCount: 301
        )
    ]

    static let experiences: [ExperienceSummary] = [
        ExperienceSummary(
            id: UUID(uuidString: "E1000001-0000-0000-0000-000000000001")!,
            cityID: cities[0].id,
            title: "Mission District Coffee Crawl",
            coverImageURL: URL(string: "https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=800&q=80"),
            creator: creators[0],
            durationMinutes: 180,
            costLevel: .moderate,
            saveCount: 1240,
            completionCount: 387,
            stops: [
                StopPreview(id: UUID(), name: "Blue Bottle", emoji: "☕"),
                StopPreview(id: UUID(), name: "City Lights Books", emoji: "📚"),
                StopPreview(id: UUID(), name: "Tartine Manufactory", emoji: "🥐"),
                StopPreview(id: UUID(), name: "Dolores Park", emoji: "🌳")
            ]
        ),
        ExperienceSummary(
            id: UUID(uuidString: "E1000002-0000-0000-000000000002")!,
            cityID: cities[0].id,
            title: "Golden Hour Rooftop Trail",
            coverImageURL: URL(string: "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800&q=80"),
            creator: creators[1],
            durationMinutes: 240,
            costLevel: .budget,
            saveCount: 892,
            completionCount: 256,
            stops: [
                StopPreview(id: UUID(), name: "Salesforce Park", emoji: "🏙️"),
                StopPreview(id: UUID(), name: "Ferry Building", emoji: "⛴️"),
                StopPreview(id: UUID(), name: "Coit Tower", emoji: "🗼"),
                StopPreview(id: UUID(), name: "Twin Peaks", emoji: "🌃")
            ]
        ),
        ExperienceSummary(
            id: UUID(uuidString: "E1000003-0000-0000-0000-000000000003")!,
            cityID: cities[0].id,
            title: "Hidden Alley Murals Walk",
            coverImageURL: URL(string: "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=800&q=80"),
            creator: creators[2],
            durationMinutes: 120,
            costLevel: .free,
            saveCount: 2103,
            completionCount: 612,
            stops: [
                StopPreview(id: UUID(), name: "Clarion Alley", emoji: "🎨"),
                StopPreview(id: UUID(), name: "Balmy Alley", emoji: "🖌️"),
                StopPreview(id: UUID(), name: "La Reyna Bakery", emoji: "🧁")
            ]
        ),
        ExperienceSummary(
            id: UUID(uuidString: "E1000004-0000-0000-0000-000000000004")!,
            cityID: cities[1].id,
            title: "Shibuya to Shinjuku Night Walk",
            coverImageURL: URL(string: "https://images.unsplash.com/photo-1542051841857-5f90071e7989?w=800&q=80"),
            creator: creators[0],
            durationMinutes: 300,
            costLevel: .moderate,
            saveCount: 3421,
            completionCount: 891,
            stops: [
                StopPreview(id: UUID(), name: "Shibuya Crossing", emoji: "🚶"),
                StopPreview(id: UUID(), name: "Omoide Yokocho", emoji: "🍢"),
                StopPreview(id: UUID(), name: "Golden Gai", emoji: "🏮"),
                StopPreview(id: UUID(), name: "Kabukicho", emoji: "🌃")
            ]
        )
    ]

    static func fullExperience(for summary: ExperienceSummary) -> Experience {
        Experience(
            id: summary.id,
            cityID: summary.cityID,
            creator: summary.creator,
            title: summary.title,
            description: "Follow this curated route through the city — each stop was picked to flow naturally into the next. Perfect for a spontaneous afternoon or showing friends your favorite hidden gems.",
            coverImageURL: summary.coverImageURL,
            durationMinutes: summary.durationMinutes,
            costLevel: summary.costLevel,
            estimatedCostUSD: 45,
            transportMode: .walking,
            totalDistanceMeters: 4200,
            saveCount: summary.saveCount,
            likeCount: summary.saveCount / 2,
            completionCount: summary.completionCount,
            commentCount: 48,
            isPublished: true,
            publishedAt: Date().addingTimeInterval(-86400 * 14),
            stops: summary.stops.enumerated().map { index, preview in
                Stop(
                    id: preview.id,
                    orderIndex: index,
                    name: preview.name,
                    description: "A must-visit spot on this route.",
                    creatorNotes: "Go early to beat the crowds.",
                    latitude: 37.77 + Double(index) * 0.01,
                    longitude: -122.42 + Double(index) * 0.008,
                    placeID: nil,
                    recommendedTime: index == 0 ? "Morning" : "Afternoon",
                    durationMinutes: 30 + index * 15,
                    emoji: preview.emoji,
                    media: []
                )
            },
            routeSegments: []
        )
    }
}
