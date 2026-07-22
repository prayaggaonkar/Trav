import SwiftUI
import UniformTypeIdentifiers

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
    @Environment(AppearanceStore.self) private var appearance

    @State private var activeTab: TravTab = .explore
    @State private var tabBarBackdrop: TabBarBackdrop = .dark

    var body: some View {
        @Bindable var router = router

        tabContent
            .onPreferenceChange(TabBarBackdropPreferenceKey.self) { tabBarBackdrop = $0 }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TravTabBar(activeTab: $activeTab, backdrop: tabBarBackdrop)
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
            .onAppear {
                tabBarBackdrop = defaultBackdrop(for: activeTab)
            }
            .onChange(of: activeTab) { _, tab in
                // Reset to a safe default until the new tab reports its backdrop.
                tabBarBackdrop = defaultBackdrop(for: tab)
            }
    }

    private func defaultBackdrop(for tab: TravTab) -> TabBarBackdrop {
        switch tab {
        case .feed:
            // Feed cards are dark image tiles — keep bar readable over them.
            return .dark
        case .explore:
            return appearance.isLightMode ? .light : .dark
        case .create, .rankings, .profile:
            return appearance.isLightMode ? .light : .dark
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch activeTab {
            case .explore:
                GlobeLandingView()
                    .tabBarBackdrop(appearance.isLightMode ? .light : .dark)
            case .feed:
                FeedView()
            case .create:
                if session.isAuthenticated {
                    CreateExperienceView()
                        .tabBarBackdrop(appearance.isLightMode ? .light : .dark)
                } else {
                    UnauthenticatedPlaceholderView(
                        title: "Create Experience",
                        description: "Sign in to document your journeys, add custom stops, and publish your own experiences.",
                        imageName: "plus.circle.fill"
                    )
                    .tabBarBackdrop(appearance.isLightMode ? .light : .dark)
                }
            case .rankings:
                RankingsView()
                    .tabBarBackdrop(appearance.isLightMode ? .light : .dark)
            case .profile:
                if let currentUser = session.currentUser {
                    ProfileView(username: currentUser.username, showDismissButton: false)
                        .tabBarBackdrop(appearance.isLightMode ? .light : .dark)
                } else {
                    UnauthenticatedPlaceholderView(
                        title: "Travel Profile",
                        description: "Sign in to track completed experiences, save favorites, and connect with other travelers.",
                        imageName: "person.circle.fill"
                    )
                    .tabBarBackdrop(appearance.isLightMode ? .light : .dark)
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

enum FeedFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case itineraries = "Itineraries"
    case singleSpots = "Single Spots"
    case saved = "Saved"
    
    var id: String { self.rawValue }
    var iconName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .itineraries: return "map"
        case .singleSpots: return "pin"
        case .saved: return "bookmark.fill"
        }
    }
}

struct QuickPlannerDropDelegate: DropDelegate {
    @Binding var draftStops: [StopPreview]
    let feedItems: [ExperienceSummary]
    
    func performDrop(info: DropInfo) -> Bool {
        guard let itemProvider = info.itemProviders(for: [.text]).first else { return false }
        
        itemProvider.loadItem(forTypeIdentifier: "public.text", options: nil) { (textData, error) in
            guard let data = textData as? Data,
                  let idString = String(data: data, encoding: .utf8),
                  let experienceUUID = UUID(uuidString: idString) else {
                return
            }
            
            if let matched = feedItems.first(where: { $0.id == experienceUUID }) {
                DispatchQueue.main.async {
                    let stop = StopPreview(
                        id: UUID(),
                        name: matched.title,
                        emoji: matched.stops.first?.emoji ?? "📍"
                    )
                    draftStops.append(stop)
                }
            }
        }
        return true
    }
}

struct FeedView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppearanceStore.self) private var appearance

    @State private var feedItems: [ExperienceSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFilter: FeedFilter = .all
    @State private var savedPlaceIDs: Set<String> = []
    
    // Quick Planner state
    @State private var draftStops: [StopPreview] = []
    @State private var itineraryTitle: String = ""
    @State private var isSavingItinerary = false

    var body: some View {
        ZStack {
            DottedGridView()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.horizontal, TravSpacing.screenHorizontal)
                    .padding(.top, TravSpacing.sm)
                
                // Filter bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TravSpacing.xs) {
                        ForEach(FeedFilter.allCases) { filter in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedFilter = filter
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: filter.iconName)
                                        .font(.system(size: 13, weight: .bold))
                                    Text(filter.rawValue)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                }
                                .padding(.horizontal, TravSpacing.md)
                                .padding(.vertical, TravSpacing.xs)
                                .background(
                                    Capsule()
                                        .fill(selectedFilter == filter ? TravColors.accent : Color.white.opacity(0.08))
                                )
                                .foregroundStyle(selectedFilter == filter ? Color.black : .white)
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, TravSpacing.screenHorizontal)
                    .padding(.vertical, TravSpacing.xs)
                }
                
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
                        description: "Try updating your selected vibes or your filter to see tailored hangout recommendations."
                    )
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: TravSpacing.md) {
                            ForEach(filteredFeed) { experience in
                                FeedCardView(
                                    experience: experience,
                                    isSaved: savedPlaceIDs.contains(experience.id.uuidString.lowercased()),
                                    onSaveToggle: {
                                        Task {
                                            await toggleSave(for: experience)
                                        }
                                    },
                                    onAddToItinerary: {
                                        withAnimation(.spring()) {
                                            let stop = StopPreview(
                                                id: UUID(),
                                                name: experience.title,
                                                emoji: experience.stops.first?.emoji ?? "📍"
                                            )
                                            draftStops.append(stop)
                                        }
                                    }
                                ) {
                                    router.presentedRoute = .experience(experience.id)
                                }
                                .onDrag {
                                    NSItemProvider(object: experience.id.uuidString as NSString)
                                }
                            }
                        }
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                        .padding(.vertical, TravSpacing.sm)
                        .padding(.bottom, draftStops.isEmpty ? TravSpacing.tabBarBottom + 20 : TravSpacing.tabBarBottom + 120)
                    }
                    .refreshable {
                        await loadFeed()
                    }
                }
            }
            
            // Bottom Quick Planner Panel
            VStack {
                Spacer()
                
                if !draftStops.isEmpty {
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("QUICK PLANNER")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .tracking(2.0)
                                    .foregroundStyle(TravColors.accent)
                                
                                Text("\(draftStops.count) stops selected")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            
                            Spacer()
                            
                            Button {
                                withAnimation(.spring()) {
                                    draftStops.removeAll()
                                    itineraryTitle = ""
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(TravColors.muted)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                        .padding(.vertical, TravSpacing.sm)
                        
                        Divider()
                            .background(Color.white.opacity(0.1))
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(draftStops.enumerated()), id: \.offset) { index, stop in
                                    HStack(spacing: 6) {
                                        Text("\(index + 1)")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(5)
                                            .background(TravColors.accent)
                                            .clipShape(Circle())
                                            .foregroundStyle(.black)
                                        
                                        Text(stop.emoji ?? "📍")
                                        Text(stop.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.white)
                                        
                                        Button {
                                            draftStops.remove(at: index)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.red.opacity(0.8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, TravSpacing.sm)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                                }
                            }
                            .padding(.horizontal, TravSpacing.screenHorizontal)
                            .padding(.vertical, TravSpacing.sm)
                        }
                        
                        HStack(spacing: TravSpacing.sm) {
                            TextField("", text: $itineraryTitle, prompt: Text("Itinerary Name...").foregroundColor(Color.white.opacity(0.3)))
                                .padding(.horizontal, TravSpacing.md)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                                .foregroundStyle(.white)
                                .tint(TravColors.accent)
                            
                            Button {
                                Task {
                                    await saveDraftItinerary()
                                }
                            } label: {
                                HStack {
                                    if isSavingItinerary {
                                        ProgressView()
                                            .tint(.black)
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("Save Route")
                                    }
                                }
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .padding(.horizontal, TravSpacing.md)
                                .padding(.vertical, 10)
                                .background(TravColors.accent)
                                .foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                            }
                            .disabled(isSavingItinerary)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                        .padding(.bottom, TravSpacing.sm + 10)
                    }
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .padding(.horizontal, TravSpacing.sm)
                    .padding(.bottom, TravSpacing.tabBarBottom + 5)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onDrop(of: [.text], delegate: QuickPlannerDropDelegate(draftStops: $draftStops, feedItems: feedItems))
                }
            }
        }
        .tabBarBackdrop(feedTabBarBackdrop)
        .task {
            await loadFeed()
        }
    }

    private var feedTabBarBackdrop: TabBarBackdrop {
        let showingCards = !isLoading && errorMessage == nil && !filteredFeed.isEmpty
        if showingCards { return .dark }
        return appearance.isLightMode ? .light : .dark
    }

    private var filteredFeed: [ExperienceSummary] {
        var items = feedItems
        
        // 1. Vibes-based filter (if any are selected in onboarding)
        if let selectedVibes = session.currentUser?.selectedVibes, !selectedVibes.isEmpty {
            let vibeToEmojis: [String: [String]] = [
                "☕️ Hidden Cafes": ["☕"],
                "🌙 Nightlife": ["🍻", "🍷", "🍺"],
                "🌅 Scenic Views": ["🌅", "🌄"],
                "🛍️ Vintage Shops": ["🛍️", "🧥", "🛒"],
                "🎨 Street Art": ["🖼️", "🎨", "🎭"],
                "🍲 Local Markets": ["🍲", "🥞", "🍳", "🍽️"],
                "🍷 Rooftop Bars": ["🍷", "🍻", "🍹"],
                "🥾 Nature Trails": ["🥾", "🌳", "🌲"]
            ]
            let vibeKeywords: [String: [String]] = [
                "☕️ Hidden Cafes": ["coffee", "cafe", "crawl", "tartine", "bakery", "brew", "espresso", "latte"],
                "🌙 Nightlife": ["bar", "night", "rooftop", "lounge", "drink", "cocktail", "beer", "club", "wine", "pub"],
                "🌅 Scenic Views": ["view", "scenic", "peaks", "rooftop", "coit", "sunset", "golden hour", "horizon", "panorama"],
                "🛍️ Vintage Shops": ["shop", "market", "boutique", "vintage", "ferry", "store", "flea", "craft"],
                "🎨 Street Art": ["museum", "art", "gallery", "mural", "muralist", "exhibit", "sculpture", "painting"],
                "🍲 Local Markets": ["market", "food", "taco", "bite", "restaurant", "slice", "pizza", "burger", "deli"],
                "🍷 Rooftop Bars": ["bar", "rooftop", "drink", "cocktail", "wine", "beer"],
                "🥾 Nature Trails": ["hike", "trail", "park", "nature", "outdoor", "peaks", "walk", "mountain", "forest"]
            ]
            
            items = items.filter { item in
                for stop in item.stops {
                    if let emoji = stop.emoji {
                        for vibe in selectedVibes {
                            if let emojis = vibeToEmojis[vibe], emojis.contains(emoji) {
                                return true
                            }
                        }
                    }
                }
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
        
        // 2. Tab Filter
        switch selectedFilter {
        case .all:
            break
        case .itineraries:
            items = items.filter { $0.stops.count > 1 }
        case .singleSpots:
            items = items.filter { $0.stops.count <= 1 }
        case .saved:
            items = items.filter { savedPlaceIDs.contains($0.id.uuidString.lowercased()) }
        }
        
        return items
    }

    private func toggleSave(for experience: ExperienceSummary) async {
        guard let currentUser = session.currentUser else {
            router.presentAuth()
            return
        }
        
        let placeID = experience.id.uuidString.lowercased()
        let isSaved = savedPlaceIDs.contains(placeID)
        
        do {
            if let client = SupabaseManager.client {
                if isSaved {
                    savedPlaceIDs.remove(placeID)
                    try await client
                        .from("saves")
                        .delete()
                        .eq("user_id", value: currentUser.id)
                        .eq("place_id", value: placeID)
                        .execute()
                } else {
                    savedPlaceIDs.insert(placeID)
                    let record = DBSave(user_id: currentUser.id, place_id: placeID)
                    try await client
                        .from("saves")
                        .insert(record)
                        .execute()
                }
            }
        } catch {
            print("Failed to toggle bookmark save: \(error)")
            if isSaved {
                savedPlaceIDs.insert(placeID)
            } else {
                savedPlaceIDs.remove(placeID)
            }
        }
    }

    private func saveDraftItinerary() async {
        guard let currentUser = session.currentUser else {
            router.presentAuth()
            return
        }
        guard !draftStops.isEmpty else { return }
        
        isSavingItinerary = true
        
        do {
            if let client = SupabaseManager.client {
                let encoder = JSONEncoder()
                let stopsJSONStrings: [String] = draftStops.enumerated().compactMap { (index, item) in
                    let dbStop = DBStop(
                        id: UUID(),
                        name: item.name,
                        emoji: item.emoji,
                        description: "Stop curated via Quick Planner.",
                        latitude: 0.0,
                        longitude: 0.0,
                        place_id: item.id.uuidString,
                        orderIndex: index
                    )
                    if let data = try? encoder.encode(dbStop),
                       let jsonStr = String(data: data, encoding: .utf8) {
                        return jsonStr
                    }
                    return nil
                }
                
                let title = itineraryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalTitle = title.isEmpty ? "My Custom Route" : title
                
                let newExp = DBExperienceInsert(
                    id: UUID(),
                    user_id: currentUser.id,
                    title: finalTitle,
                    description: "A custom route created via Trav Quick Planner.",
                    city: "Berkeley",
                    stops: stopsJSONStrings,
                    created_at: Date()
                )
                
                try await client
                    .from("experiences")
                    .insert(newExp)
                    .execute()
                
                withAnimation(.spring()) {
                    draftStops.removeAll()
                    itineraryTitle = ""
                }
                
                await loadFeed()
            }
        } catch {
            print("Failed to save draft itinerary: \(error)")
            errorMessage = "Failed to save itinerary: \(error.localizedDescription)"
        }
        
        isSavingItinerary = false
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
                    .foregroundStyle(appearance.isLightMode ? Color.black : Color.white)
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
            if !environment.configuration.useMockBackend,
               let client = SupabaseManager.client {
                
                // Fetch databases sequentially to ensure explicit generic type inference compiles successfully
                let dbPlaces: [DBPlace] = try await client
                    .from("places")
                    .select()
                    .execute()
                    .value
                
                let dbExps: [DBUserExperience] = try await client
                    .from("experiences")
                    .select()
                    .execute()
                    .value
                
                // Fetch creators profiles in parallel to resolve shared traveler metadata
                let dbProfiles: [DBProfileSummary] = (try? await client
                    .from("profiles")
                    .select("id, username, display_name, avatar_url, is_verified")
                    .execute()
                    .value) ?? []
                let profileMap = Dictionary(uniqueKeysWithValues: dbProfiles.map { ($0.id, $0) })
                
                // Load saves/bookmarks
                let dbSaves: [DBSave]
                if let currentUserID = session.currentUser?.id {
                    do {
                        dbSaves = try await client
                            .from("saves")
                            .select()
                            .eq("user_id", value: currentUserID)
                            .execute()
                            .value
                    } catch {
                        print("Saves table fetch failed: \(error)")
                        dbSaves = []
                    }
                } else {
                    dbSaves = []
                }
                
                self.savedPlaceIDs = Set(dbSaves.map { $0.place_id.lowercased() })
                
                // 1. Map places (System recommendations)
                let recCreator = ProfileSummary(
                    id: UUID(),
                    username: "rec_by_trav",
                    displayName: "Rec by Trav",
                    avatarURL: nil,
                    isVerified: true
                )
                
                let placeItems: [ExperienceSummary] = dbPlaces.map { dbPlace in
                    if let stopsArray = dbPlace.stops, !stopsArray.isEmpty {
                        let decodedStops: [StopPreview] = stopsArray.compactMap { stopStr in
                            guard let data = stopStr.data(using: .utf8),
                                  let dbStop = try? JSONDecoder().decode(DBStop.self, from: data) else {
                                return nil
                            }
                            return StopPreview(
                                id: dbStop.id,
                                name: dbStop.name,
                                emoji: dbStop.emoji
                            )
                        }
                        
                        let firstStopName = decodedStops.first?.name ?? "park"
                        let coverURL = defaultCoverForCategory(firstStopName)
                        
                        return ExperienceSummary(
                            id: UUID(uuidString: dbPlace.id) ?? UUID(),
                            cityID: UUID(),
                            title: dbPlace.name,
                            coverImageURL: coverURL,
                            creator: recCreator,
                            durationMinutes: 120,
                            costLevel: .moderate,
                            estimatedCostUSD: nil,
                            saveCount: 0,
                            likeCount: 0,
                            completionCount: 0,
                            stops: decodedStops
                        )
                    } else {
                        let coverURL = defaultCoverForCategory(dbPlace.name)
                        let stop = StopPreview(
                            id: UUID(),
                            name: dbPlace.name,
                            emoji: emojiForCategory(dbPlace.basic_category)
                        )
                        
                        return ExperienceSummary(
                            id: UUID(uuidString: dbPlace.id) ?? UUID(),
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
                            stops: [stop]
                        )
                    }
                }
                
                // 2. Map user posts (from experiences table)
                let userExpItems: [ExperienceSummary] = dbExps.map { dbExp in
                    let decodedStops: [StopPreview] = dbExp.stops.compactMap { stopStr in
                        guard let data = stopStr.data(using: .utf8),
                              let dbStop = try? JSONDecoder().decode(DBStop.self, from: data) else {
                            // Fallback to name and resolve category emoji dynamically
                            let stopEmoji = emojiForCategory(stopStr)
                            return StopPreview(id: UUID(), name: stopStr, emoji: stopEmoji)
                        }
                        return StopPreview(
                            id: dbStop.id,
                            name: dbStop.name,
                            emoji: dbStop.emoji
                        )
                    }
                    
                    let dbProfile = profileMap[dbExp.user_id]
                    let userCreator = ProfileSummary(
                        id: dbExp.user_id,
                        username: dbProfile?.username ?? "traveler",
                        displayName: dbProfile?.display_name ?? "Shared by Traveler",
                        avatarURL: dbProfile?.avatar_url.flatMap { URL(string: $0) },
                        isVerified: dbProfile?.is_verified ?? false
                    )
                    
                    let firstStopName = decodedStops.first?.name ?? "park"
                    return ExperienceSummary(
                        id: dbExp.id,
                        cityID: UUID(),
                        title: dbExp.title,
                        coverImageURL: defaultCoverForCategory(firstStopName),
                        creator: userCreator,
                        durationMinutes: dbExp.stops.count * 30,
                        costLevel: .moderate,
                        estimatedCostUSD: nil,
                        saveCount: 0,
                        likeCount: 0,
                        completionCount: 0,
                        stops: decodedStops
                    )
                }
                
                // Combine and prioritize user posts at the top, followed by Recs from Trav
                self.feedItems = userExpItems + placeItems
                
                if self.feedItems.isEmpty {
                    loadMockFeed()
                }
            } else {
                loadMockFeed()
            }
        } catch {
            let errMsg = "Failed to load Supabase places: \(error)"
            print(errMsg)
            self.errorMessage = errMsg
        }
        
        isLoading = false
    }
}

// Subview: Feed Card
private struct FeedCardView: View {
    @Environment(AppearanceStore.self) private var appearance
    
    let experience: ExperienceSummary
    let isSaved: Bool
    let onSaveToggle: () -> Void
    let onAddToItinerary: () -> Void
    let action: () -> Void
    
    private var coverImageView: some View {
        ZStack {
            if let coverURL = experience.coverImageURL {
                AsyncImage(url: coverURL) { image in
                    image.resizable()
                         .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.white.opacity(0.05)
                }
            } else {
                Color.white.opacity(0.05)
            }
        }
        .frame(height: 200)
        .clipped()
    }
    
    private var gradientOverlay: some View {
        LinearGradient(
            gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.85)]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var topOverlayControls: some View {
        let isItinerary = experience.stops.count > 1
        return HStack {
            Text(isItinerary ? "ROUTE" : "SPOT")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.5)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isItinerary ? TravColors.accent.opacity(0.9) : Color.blue.opacity(0.9))
                )
                .foregroundStyle(Color.black)
            
            Spacer()
            
            Button(action: onAddToItinerary) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TravColors.accent)
                    .padding(8)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            Button(action: onSaveToggle) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isSaved ? Color.yellow : Color.white)
                    .padding(8)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(TravSpacing.sm)
    }
    
    private var titleAndCreatorMetadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(TravColors.muted)
                
                Text(experience.creator.displayName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(TravColors.muted)
                
                if experience.creator.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.green)
                }
            }
            
            Text(experience.title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
        .padding(TravSpacing.md)
    }
    
    private var stopsSequenceStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(experience.stops) { stop in
                    HStack(spacing: 4) {
                        Text(stop.emoji ?? "📍")
                        Text(stop.name)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(appearance.isLightMode ? Color.black : Color.white)
                    }
                    .padding(.horizontal, TravSpacing.sm)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, TravSpacing.md)
            .padding(.vertical, TravSpacing.sm)
        }
        .background(Color.black.opacity(0.15))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                coverImageView
                gradientOverlay
                
                VStack {
                    topOverlayControls
                    Spacer()
                }
                
                titleAndCreatorMetadata
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg))
            .onTapGesture(perform: action)
            
            if !experience.stops.isEmpty {
                stopsSequenceStrip
            }
        }
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: TravRadius.lg)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .travAppear()
    }
}

// Helpers for Places mapping

private func defaultCoverForCategory(_ text: String) -> URL? {
    let textLower = text.lowercased()
    if textLower.contains("bar") || textLower.contains("pub") || textLower.contains("drink") || textLower.contains("lounge") {
        return URL(string: "https://images.unsplash.com/photo-1514933651103-005eec06c04b?w=800&q=80")
    }
    if textLower.contains("coffee") || textLower.contains("cafe") || textLower.contains("brew") || textLower.contains("espresso") {
        return URL(string: "https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=800&q=80")
    }
    if textLower.contains("shop") || textLower.contains("store") || textLower.contains("market") || textLower.contains("vintage") {
        return URL(string: "https://images.unsplash.com/photo-1483985988355-763728e1935b?w=800&q=80")
    }
    if textLower.contains("hike") || textLower.contains("trail") || textLower.contains("mountain") || textLower.contains("climb") {
        return URL(string: "https://images.unsplash.com/photo-1501555088652-021faa106b9b?w=800&q=80")
    }
    if textLower.contains("park") || textLower.contains("garden") || textLower.contains("lawn") || textLower.contains("field") {
        return URL(string: "https://images.unsplash.com/photo-1502082553048-f009c37129b9?w=800&q=80")
    }
    if textLower.contains("view") || textLower.contains("sunset") || textLower.contains("scenic") || textLower.contains("vista") {
        return URL(string: "https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=800&q=80")
    }
    if textLower.contains("museum") || textLower.contains("art") || textLower.contains("gallery") {
        return URL(string: "https://images.unsplash.com/photo-1545987796-200677ee1011?w=800&q=80")
    }
    if textLower.contains("book") || textLower.contains("read") || textLower.contains("library") {
        return URL(string: "https://images.unsplash.com/photo-1521587760476-6c12a4b040da?w=800&q=80")
    }
    return URL(string: "https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=800&q=80")
}

private func emojiForCategory(_ text: String) -> String {
    let textLower = text.lowercased()
    if textLower.contains("bar") || textLower.contains("pub") || textLower.contains("drink") || textLower.contains("lounge") || textLower.contains("nightlife") {
        return "🍻"
    }
    if textLower.contains("coffee") || textLower.contains("cafe") || textLower.contains("brew") || textLower.contains("espresso") {
        return "☕"
    }
    if textLower.contains("shop") || textLower.contains("store") || textLower.contains("market") || textLower.contains("vintage") {
        return "🛍️"
    }
    if textLower.contains("hike") || textLower.contains("trail") || textLower.contains("mountain") || textLower.contains("climb") {
        return "🥾"
    }
    if textLower.contains("park") || textLower.contains("garden") || textLower.contains("lawn") || textLower.contains("field") {
        return "🌳"
    }
    if textLower.contains("view") || textLower.contains("sunset") || textLower.contains("scenic") || textLower.contains("vista") {
        return "🌅"
    }
    if textLower.contains("museum") || textLower.contains("art") || textLower.contains("gallery") {
        return "🖼️"
    }
    if textLower.contains("book") || textLower.contains("read") || textLower.contains("library") {
        return "📚"
    }
    return "📍"
}

// Database representation struct for Overture Places
private struct DBPlace: Codable, Identifiable {
    let id: String
    let name: String
    let basic_category: String
    let latitude: Double
    let longitude: Double
    let stops: [String]?
}

private struct DBStop: Codable {
    let id: UUID
    let name: String
    let emoji: String?
    let description: String
    let latitude: Double
    let longitude: Double
    let place_id: String?
    let orderIndex: Int
}

private struct DBUserExperience: Codable {
    let id: UUID
    let user_id: UUID
    let title: String
    let description: String
    let city: String
    let stops: [String]
}

private struct DBExperienceInsert: Codable {
    let id: UUID
    let user_id: UUID
    let title: String
    let description: String
    let city: String
    let stops: [String]
    let created_at: Date
}

private struct DBSave: Codable {
    let user_id: UUID
    let place_id: String
}

private struct DBProfileSummary: Codable {
    let id: UUID
    let username: String
    let display_name: String
    let avatar_url: String?
    let is_verified: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case display_name = "display_name"
        case avatar_url = "avatar_url"
        case is_verified = "is_verified"
    }
}
