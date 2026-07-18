import SwiftUI

enum TravTab: String, CaseIterable {
    case explore = "Explore"
    case feed = "Feed"
    case create = "Create"
    case rankings = "Rankings"
    case profile = "Profile"

    var systemImage: String {
        switch self {
        case .explore: "globe"
        case .feed: "rectangle.stack.fill"
        case .create: "plus.circle"
        case .rankings: "crown"
        case .profile: "person.circle"
        }
    }
}

struct RootCoordinator: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    @State private var activeTab: TravTab = .explore

    var body: some View {
        @Bindable var router = router

        tabContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TravTabBar(activeTab: $activeTab)
            }
            .sheet(isPresented: $router.isAuthPresented) {
                OnboardingView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(TravRadius.xl)
            }
            .fullScreenCover(item: $router.presentedRoute) { route in
                routeDestination(for: route)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .animation(TravAnimation.modal, value: router.presentedRoute?.id)
            .animation(TravAnimation.tab, value: activeTab)
    }

    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch activeTab {
            case .explore:
                GlobeLandingView()
            case .feed:
                FeedView()
            case .create:
                if session.isAuthenticated {
                    CreateExperienceView()
                } else {
                    UnauthenticatedPlaceholderView(
                        title: "Create Experience",
                        description: "Sign in to document your journeys, add custom stops, and publish your own experiences.",
                        imageName: "plus.circle.fill"
                    )
                }
            case .rankings:
                RankingsView()
            case .profile:
                if let currentUser = session.currentUser {
                    ProfileView(username: currentUser.username, showDismissButton: false)
                } else {
                    UnauthenticatedPlaceholderView(
                        title: "Travel Profile",
                        description: "Sign in to track completed experiences, save favorites, and connect with other travelers.",
                        imageName: "person.circle.fill"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(activeTab)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    @ViewBuilder
    private func routeDestination(for route: TravRoute) -> some View {
        switch route {
        case let .city(cityID):
            CityPageView(cityID: cityID)
        case let .experience(experienceID):
            ExperienceDetailView(experienceID: experienceID)
        case let .profile(username):
            ProfileView(username: username)
        }
    }
}

private struct UnauthenticatedPlaceholderView: View {
    @Environment(AppRouter.self) private var router

    let title: String
    let description: String
    let imageName: String

    var body: some View {
        EmptyStateView(
            icon: imageName,
            title: title,
            description: description,
            actionTitle: "Sign In"
        ) {
            router.presentAuth()
        }
        .travScreenBackground()
    }
}


private struct RankingsView: View {
    var body: some View {
        EmptyStateView(
            icon: "crown",
            title: "Rankings",
            description: "See top-rated experiences and popular creators."
        )
        .travScreenBackground()
    }
}

// MARK: - Feed Section

struct FeedView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(AppEnvironment.self) private var environment

    @State private var feedItems: [ExperienceSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            DottedGridView()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.horizontal, TravSpacing.screenHorizontal)
                    .padding(.top, TravSpacing.sm)
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(TravColors.accent)
                    Spacer()
                } else if let errorMessage = errorMessage {
                    Spacer()
                    VStack(spacing: TravSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(TravColors.accent)
                        Text(errorMessage)
                            .font(TravTypography.bodyMedium())
                            .foregroundStyle(TravColors.muted)
                    }
                    Spacer()
                } else if filteredFeed.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "rectangle.stack.badge.person.crop",
                        title: "No Matching Spots",
                        description: "Try updating your selected vibes in your profile to see tailored hangout recommendations."
                    )
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: TravSpacing.md) {
                            ForEach(filteredFeed) { experience in
                                FeedCardView(experience: experience) {
                                    router.presentedRoute = .experience(experience.id)
                                }
                            }
                        }
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                        .padding(.vertical, TravSpacing.sm)
                        .padding(.bottom, TravSpacing.tabBarBottom + 20)
                    }
                    .refreshable {
                        await loadFeed()
                    }
                }
            }
        }
        .task {
            await loadFeed()
        }
    }

    private var filteredFeed: [ExperienceSummary] {
        guard let selectedVibes = session.currentUser?.selectedVibes, !selectedVibes.isEmpty else {
            return feedItems
        }
        
        let vibeToCategories: [String: [String]] = [
            "Coffee / Cafes": ["cafe", "coffee", "bookstore"],
            "Nightlife / Bars": ["bar", "nightlife", "pub", "lounge"],
            "Hikes / Outdoors": ["hiking_trail", "park", "outdoor", "scenic_viewpoint"],
            "Scenic Views": ["scenic_viewpoint"],
            "Local Shopping": ["shopping", "vintage_store"],
            "Museums / Arts": ["museum", "art_gallery", "gallery"],
            "Bookstores": ["bookstore"],
            "Tacos / Casual Bite": ["restaurant", "food", "tacos", "casual_bite"]
        ]
        
        let vibeKeywords: [String: [String]] = [
            "Coffee / Cafes": ["coffee", "cafe", "crawl", "tartine", "bakery", "brew", "espresso", "latte"],
            "Nightlife / Bars": ["bar", "night", "rooftop", "lounge", "drink", "cocktail", "beer", "club", "wine", "pub"],
            "Hikes / Outdoors": ["hike", "trail", "park", "nature", "outdoor", "peaks", "walk", "mountain", "forest", "dolores"],
            "Scenic Views": ["view", "scenic", "peaks", "rooftop", "coit", "sunset", "golden hour", "horizon", "panorama"],
            "Local Shopping": ["shop", "market", "boutique", "vintage", "ferry", "store", "flea", "craft"],
            "Museums / Arts": ["museum", "art", "gallery", "mural", "muralist", "exhibit", "sculpture", "painting"],
            "Bookstores": ["book", "read", "bookstore", "library", "lights", "literature", "novel"],
            "Tacos / Casual Bite": ["taco", "bite", "food", "bakery", "restaurant", "croissant", "slice", "pizza", "burger", "deli"]
        ]
        
        return feedItems.filter { item in
            // Place category match
            if let category = item.stops.first?.name.lowercased() {
                for vibe in selectedVibes {
                    if let categories = vibeToCategories[vibe], categories.contains(category) {
                        return true
                    }
                }
            }
            
            // Experience keyword match fallback
            let textToSearch = "\(item.title) \(item.stops.map(\.name).joined(separator: " "))".lowercased()
            for vibe in selectedVibes {
                if let keywords = vibeKeywords[vibe] {
                    for keyword in keywords {
                        if textToSearch.contains(keyword) {
                            return true
                        }
                    }
                }
            }
            return false
        }
    }

    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RECOMMENDED")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2.5)
                    .foregroundStyle(TravColors.accent)
                
                Text("Hangout Feed")
                    .font(TravTypography.displayMedium())
                    .foregroundStyle(.white)
            }
            
            Spacer()
            
            // Status Indicator showing if feed is filtered by user vibes
            if let selectedVibes = session.currentUser?.selectedVibes, !selectedVibes.isEmpty {
                HStack(spacing: 4) {
                    Circle()
                        .fill(TravColors.accent)
                        .frame(width: 6, height: 6)
                    Text("Tailored")
                        .font(TravTypography.labelMedium())
                        .foregroundStyle(TravColors.accent)
                }
                .padding(.horizontal, TravSpacing.sm)
                .padding(.vertical, TravSpacing.xxs)
                .background(
                    Capsule()
                        .fill(TravColors.accent.opacity(0.12))
                )
            }
        }
        .padding(.bottom, TravSpacing.xs)
    }

    private func loadMockFeed() {
        self.feedItems = MockData.experiences.map { exp in
            var modifiedExp = exp
            modifiedExp.creator.displayName = "Rec by Trav"
            return modifiedExp
        }
    }

    private func loadFeed() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Attempt to fetch places from Supabase if configured and not in mock mode
            if !environment.configuration.useMockBackend,
               let client = SupabaseManager.client {
                let dbPlaces: [DBPlace] = try await client
                    .from("places")
                    .select()
                    .execute()
                    .value
                
                if dbPlaces.isEmpty {
                    loadMockFeed()
                } else {
                    let recCreator = ProfileSummary(
                        id: UUID(),
                        username: "rec_by_trav",
                        displayName: "Rec by Trav",
                        avatarURL: nil,
                        isVerified: true
                    )
                    
                    self.feedItems = dbPlaces.map { dbPlace in
                        let coverURL = dbPlace.photo_urls?.first.flatMap { URL(string: $0) }
                            ?? defaultCoverForCategory(dbPlace.basic_category)
                        
                        return ExperienceSummary(
                            id: UUID(),
                            cityID: UUID(),
                            title: dbPlace.name,
                            coverImageURL: coverURL,
                            creator: recCreator,
                            durationMinutes: 45,
                            costLevel: .budget,
                            estimatedCostUSD: 0,
                            saveCount: 0,
                            likeCount: 0,
                            completionCount: 0,
                            stops: [
                                StopPreview(
                                    id: UUID(),
                                    name: dbPlace.basic_category,
                                    emoji: emojiForCategory(dbPlace.basic_category)
                                )
                            ]
                        )
                    }
                }
            } else {
                loadMockFeed()
            }
        } catch {
            print("Failed to load Supabase places: \(error), falling back to mock feed.")
            loadMockFeed()
        }
        
        isLoading = false
    }
}

// Subview: Feed Card
private struct FeedCardView: View {
    let experience: ExperienceSummary
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // Cover Image
                ZStack(alignment: .bottomLeading) {
                    if let coverURL = experience.coverImageURL {
                        AsyncImage(url: coverURL) { image in
                            image.resizable()
                                 .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.white.opacity(0.05)
                        }
                        .frame(height: 200)
                        .clipped()
                    } else {
                        Color.white.opacity(0.05)
                            .frame(height: 200)
                    }
                    
                    // Dark overlay for text readability
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                    // Badges overlay
                    HStack {
                        // Rec by Trav Author Badge
                        HStack(spacing: TravSpacing.xxs) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(TravColors.accent)
                            Text(experience.creator.displayName)
                                .font(TravTypography.caption())
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, TravSpacing.xs)
                        .padding(.vertical, TravSpacing.xxs)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.6))
                        )
                        
                        Spacer()
                        
                        // Cost & Duration Badges
                        HStack(spacing: TravSpacing.xxs) {
                            Text(experience.costLevel.rawValue.capitalized)
                            Text("•")
                            Text("\(experience.durationMinutes)m")
                        }
                        .font(TravTypography.caption())
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, TravSpacing.xs)
                        .padding(.vertical, TravSpacing.xxs)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                        )
                    }
                    .padding(TravSpacing.md)
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: TravRadius.lg)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
                
                // Content Description
                VStack(alignment: .leading, spacing: 4) {
                    Text(experience.title)
                        .font(TravTypography.titleMedium())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    if !experience.stops.isEmpty {
                        Text(experience.stops.map { "\($0.emoji ?? "📍") \($0.name)" }.joined(separator: "   "))
                            .font(TravTypography.caption())
                            .foregroundStyle(TravColors.muted)
                            .lineLimit(1)
                    } else {
                        Text("Explore local spots and neighborhood favorites.")
                            .font(TravTypography.caption())
                            .foregroundStyle(TravColors.muted)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, TravSpacing.sm)
                .padding(.horizontal, TravSpacing.xxs)
            }
            .background(Color.clear)
        }
        .buttonStyle(.plain)
        .travAppear()
    }
}

// Helpers for Places mapping

private func defaultCoverForCategory(_ category: String) -> URL? {
    let urls: [String: String] = [
        "bar": "https://images.unsplash.com/photo-1514933651103-005eec06c04b?w=800&q=80",
        "shopping": "https://images.unsplash.com/photo-1483985988355-763728e1935b?w=800&q=80",
        "vintage_store": "https://images.unsplash.com/photo-1489987707025-afc232f7ea0f?w=800&q=80",
        "hiking_trail": "https://images.unsplash.com/photo-1501555088652-021faa106b9b?w=800&q=80",
        "park": "https://images.unsplash.com/photo-1502082553048-f009c37129b9?w=800&q=80",
        "scenic_viewpoint": "https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=800&q=80",
        "museum": "https://images.unsplash.com/photo-1545987796-200677ee1011?w=800&q=80",
        "bookstore": "https://images.unsplash.com/photo-1521587760476-6c12a4b040da?w=800&q=80"
    ]
    return URL(string: urls[category.lowercased()] ?? "https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=800&q=80")
}

private func emojiForCategory(_ category: String) -> String {
    let emojis: [String: String] = [
        "bar": "🍻",
        "shopping": "🛍️",
        "vintage_store": "🧥",
        "hiking_trail": "🥾",
        "park": "🌳",
        "scenic_viewpoint": "🌅",
        "museum": "🖼️",
        "bookstore": "📚"
    ]
    return emojis[category.lowercased()] ?? "📍"
}

// Database representation struct for Overture Places
private struct DBPlace: Codable, Identifiable {
    let id: String
    let name: String
    let basic_category: String
    let latitude: Double
    let longitude: Double
    let photo_urls: [String]?
}
