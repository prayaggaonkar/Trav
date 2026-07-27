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
        ),
        ProfileSummary(
            id: UUID(uuidString: "A1000004-0000-0000-0000-000000000004")!,
            username: "yuki.tanaka",
            displayName: "Yuki Tanaka",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&h=200&fit=crop"),
            isVerified: true
        ),
        ProfileSummary(
            id: UUID(uuidString: "A1000005-0000-0000-0000-000000000005")!,
            username: "kenji.mori",
            displayName: "Kenji Mori",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=200&h=200&fit=crop"),
            isVerified: false
        ),
        ProfileSummary(
            id: UUID(uuidString: "A1000006-0000-0000-0000-000000000006")!,
            username: "aiko.sato",
            displayName: "Aiko Sato",
            avatarURL: URL(string: "https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=200&h=200&fit=crop"),
            isVerified: true
        )
    ]

    /// Follower counts keyed by creator id for trending city rows.
    static let creatorFollowerCounts: [UUID: Int] = [
        creators[0].id: 48_200,
        creators[1].id: 19_840,
        creators[2].id: 31_450,
        creators[3].id: 62_100,
        creators[4].id: 12_780,
        creators[5].id: 27_300
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
            experienceCount: 12_493,
            creatorCount: 4_291
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
            estimatedCostUSD: 35,
            saveCount: 8_231,
            likeCount: 4_102,
            completionCount: 1_482,
            stops: [
                StopPreview(id: UUID(), name: "Blue Bottle", emoji: nil),
                StopPreview(id: UUID(), name: "City Lights Books", emoji: nil),
                StopPreview(id: UUID(), name: "Tartine Manufactory", emoji: nil),
                StopPreview(id: UUID(), name: "Dolores Park", emoji: nil)
            ],
            rating: RadarRating(scores: [
                "Cost": 7.0, "Food": 9.2, "Memorability": 8.5, "Authenticity": 8.8, "Immersion": 8.0
            ]),
            watchlistedBy: [
                WatchlistUser(id: UUID(uuidString: "W1000001-0000-0000-0000-000000000001")!, name: "Vinay", avatarImage: "https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=100&h=100&fit=crop"),
                WatchlistUser(id: UUID(uuidString: "W1000002-0000-0000-0000-000000000002")!, name: "Tanish", avatarImage: "https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?w=100&h=100&fit=crop")
            ]
        ),
        ExperienceSummary(
            id: UUID(uuidString: "E1000002-0000-0000-0000-000000000002")!,
            cityID: cities[0].id,
            title: "Golden Hour Rooftop Trail",
            coverImageURL: URL(string: "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800&q=80"),
            creator: creators[1],
            durationMinutes: 240,
            costLevel: .budget,
            estimatedCostUSD: 18,
            saveCount: 892,
            likeCount: 640,
            completionCount: 256,
            stops: [
                StopPreview(id: UUID(), name: "Salesforce Park", emoji: nil),
                StopPreview(id: UUID(), name: "Ferry Building", emoji: nil),
                StopPreview(id: UUID(), name: "Coit Tower", emoji: nil),
                StopPreview(id: UUID(), name: "Twin Peaks", emoji: nil)
            ],
            rating: RadarRating(scores: [
                "Cost": 8.5, "Food": 6.5, "Memorability": 9.4, "Authenticity": 7.8, "Immersion": 9.0
            ]),
            watchlistedBy: [
                WatchlistUser(id: UUID(uuidString: "W1000001-0000-0000-0000-000000000001")!, name: "Vinay", avatarImage: "https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=100&h=100&fit=crop"),
                WatchlistUser(id: UUID(uuidString: "W1000002-0000-0000-0000-000000000002")!, name: "Tanish", avatarImage: "https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?w=100&h=100&fit=crop"),
                WatchlistUser(id: UUID(uuidString: "W1000003-0000-0000-0000-000000000003")!, name: "Arjun", avatarImage: "https://images.unsplash.com/photo-1527983359383-4758693f760c?w=100&h=100&fit=crop")
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
            estimatedCostUSD: 0,
            saveCount: 2_103,
            likeCount: 1_540,
            completionCount: 612,
            stops: [
                StopPreview(id: UUID(), name: "Clarion Alley", emoji: nil),
                StopPreview(id: UUID(), name: "Balmy Alley", emoji: nil),
                StopPreview(id: UUID(), name: "La Reyna Bakery", emoji: nil)
            ],
            rating: RadarRating(scores: [
                "Cost": 9.5, "Food": 7.0, "Memorability": 8.8, "Authenticity": 9.2, "Immersion": 8.6
            ]),
            watchlistedBy: [
                WatchlistUser(id: UUID(uuidString: "W1000003-0000-0000-0000-000000000003")!, name: "Arjun", avatarImage: "https://images.unsplash.com/photo-1527983359383-4758693f760c?w=100&h=100&fit=crop")
            ]
        ),
        ExperienceSummary(
            id: UUID(uuidString: "E1000004-0000-0000-0000-000000000004")!,
            cityID: cities[1].id,
            title: "Shibuya to Shinjuku Night Walk",
            coverImageURL: URL(string: "https://images.unsplash.com/photo-1542051841857-5f90071e7989?w=800&q=80"),
            creator: creators[3],
            durationMinutes: 270,
            costLevel: .moderate,
            estimatedCostUSD: 42,
            saveCount: 9_841,
            likeCount: 6_220,
            completionCount: 2_104,
            stops: [
                StopPreview(id: UUID(), name: "Shibuya Crossing", emoji: nil),
                StopPreview(id: UUID(), name: "Bookstore Café", emoji: nil),
                StopPreview(id: UUID(), name: "Ramen Alley", emoji: nil),
                StopPreview(id: UUID(), name: "Shinjuku Viewpoint", emoji: nil)
            ],
            rating: RadarRating(scores: [
                "Cost": 6.5, "Food": 9.5, "Memorability": 9.6, "Authenticity": 9.0, "Immersion": 9.4
            ])
        ),
        ExperienceSummary(
            id: UUID(uuidString: "E1000005-0000-0000-0000-000000000005")!,
            cityID: cities[1].id,
            title: "Yanaka Quiet Morning Ritual",
            coverImageURL: URL(string: "https://images.unsplash.com/photo-1524413840807-0c3cb6fa808d?w=800&q=80"),
            creator: creators[4],
            durationMinutes: 150,
            costLevel: .budget,
            estimatedCostUSD: 22,
            saveCount: 4_560,
            likeCount: 2_890,
            completionCount: 980,
            stops: [
                StopPreview(id: UUID(), name: "Nezu Shrine", emoji: nil),
                StopPreview(id: UUID(), name: "Kissaten", emoji: nil),
                StopPreview(id: UUID(), name: "Yanaka Ginza", emoji: nil),
                StopPreview(id: UUID(), name: "Temple Garden", emoji: nil)
            ],
            rating: RadarRating(scores: [
                "Cost": 8.0, "Food": 8.2, "Memorability": 8.0, "Authenticity": 9.5, "Immersion": 9.1
            ])
        ),
        ExperienceSummary(
            id: UUID(uuidString: "E1000006-0000-0000-0000-000000000006")!,
            cityID: cities[1].id,
            title: "Shimokitazawa Vintage Loop",
            coverImageURL: URL(string: "https://images.unsplash.com/photo-1554797589-7241bb691973?w=800&q=80"),
            creator: creators[5],
            durationMinutes: 210,
            costLevel: .moderate,
            estimatedCostUSD: 55,
            saveCount: 3_210,
            likeCount: 1_980,
            completionCount: 744,
            stops: [
                StopPreview(id: UUID(), name: "Record Shop", emoji: nil),
                StopPreview(id: UUID(), name: "Vintage Thrift", emoji: nil),
                StopPreview(id: UUID(), name: "Curry House", emoji: nil),
                StopPreview(id: UUID(), name: "Sunset Bridge", emoji: nil)
            ],
            rating: RadarRating(scores: [
                "Cost": 5.5, "Food": 8.8, "Memorability": 8.2, "Authenticity": 8.5, "Immersion": 8.0
            ])
        ),
        ExperienceSummary(
            id: UUID(uuidString: "E1000007-0000-0000-0000-000000000007")!,
            cityID: cities[1].id,
            title: "Asakusa Temple & Street Food",
            coverImageURL: URL(string: "https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?w=800&q=80"),
            creator: creators[0],
            durationMinutes: 180,
            costLevel: .budget,
            estimatedCostUSD: 28,
            saveCount: 6_720,
            likeCount: 3_410,
            completionCount: 1_650,
            stops: [
                StopPreview(id: UUID(), name: "Senso-ji", emoji: nil),
                StopPreview(id: UUID(), name: "Nakamise Street", emoji: nil),
                StopPreview(id: UUID(), name: "Sumida River", emoji: nil),
                StopPreview(id: UUID(), name: "Skytree View", emoji: nil)
            ],
            rating: RadarRating(scores: [
                "Cost": 7.5, "Food": 9.0, "Memorability": 8.7, "Authenticity": 8.9, "Immersion": 8.4
            ])
        ),
        ExperienceSummary(
            id: UUID(uuidString: "E1000008-0000-0000-0000-000000000008")!,
            cityID: cities[2].id,
            title: "Left Bank Café Afternoon",
            coverImageURL: URL(string: "https://images.unsplash.com/photo-1502602898657-3e91760cbb34?w=800&q=80"),
            creator: creators[2],
            durationMinutes: 200,
            costLevel: .moderate,
            estimatedCostUSD: 48,
            saveCount: 2_840,
            likeCount: 1_620,
            completionCount: 530,
            stops: [
                StopPreview(id: UUID(), name: "Shakespeare & Co", emoji: nil),
                StopPreview(id: UUID(), name: "Café de Flore", emoji: nil),
                StopPreview(id: UUID(), name: "Jardin du Luxembourg", emoji: nil),
                StopPreview(id: UUID(), name: "Seine Sunset", emoji: nil)
            ],
            rating: RadarRating(scores: [
                "Cost": 6.0, "Food": 9.1, "Memorability": 8.3, "Authenticity": 8.0, "Immersion": 7.5
            ])
        )
    ]

    static func profile(for summary: ProfileSummary) -> Profile {
        let home = cities[summary.id == creators[3].id || summary.id == creators[4].id || summary.id == creators[5].id ? 1 : 0]
        return Profile(
            id: summary.id,
            username: summary.username,
            displayName: summary.displayName,
            bio: "Mapping favorite corners of the city — coffee, walks, and golden hour views.",
            avatarURL: summary.avatarURL,
            homeCityID: home.id,
            homeCityName: home.name,
            followerCount: creatorFollowerCounts[summary.id] ?? 1_200,
            followingCount: 280,
            experienceCount: experiences.filter { $0.creator.id == summary.id }.count,
            completionCount: 44,
            isVerified: summary.isVerified,
            selectedVibes: nil,
            onboardingLocation: home.name,
            isFollowing: nil
        )
    }

    static func trendingCreators(for cityID: UUID) -> [Profile] {
        let creatorIDs = Set(experiences.filter { $0.cityID == cityID }.map(\.creator.id))
        let matched = creators
            .filter { creatorIDs.contains($0.id) }
            .map(profile(for:))
            .sorted { $0.followerCount > $1.followerCount }

        if !matched.isEmpty { return matched }

        // Fallback so empty cities still show a compact creators strip in demos.
        return Array(creators.prefix(4).map(profile(for:)))
    }

    static func fullExperience(for summary: ExperienceSummary) -> Experience {
        let city = cities.first(where: { $0.id == summary.cityID }) ?? cities[0]
        let baseLat = city.latitude
        let baseLon = city.longitude

        return Experience(
            id: summary.id,
            cityID: summary.cityID,
            creator: summary.creator,
            title: summary.title,
            description: "Follow this curated route through the city — each stop was picked to flow naturally into the next. Perfect for a spontaneous afternoon or showing friends your favorite hidden gems.",
            coverImageURL: summary.coverImageURL,
            durationMinutes: summary.durationMinutes,
            costLevel: summary.costLevel,
            estimatedCostUSD: summary.estimatedCostUSD ?? 45,
            transportMode: .walking,
            totalDistanceMeters: 4200,
            saveCount: summary.saveCount,
            likeCount: summary.likeCount,
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
                    latitude: baseLat + Double(index) * 0.006 - 0.009,
                    longitude: baseLon + Double(index) * 0.008 - 0.01,
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
