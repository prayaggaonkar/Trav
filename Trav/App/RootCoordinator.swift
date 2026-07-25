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
    @Environment(EngagementStore.self) private var engagement

    @State private var feedItems: [ExperienceSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFilter: FeedFilter = .all
    
    // Quick Planner state
    @State private var draftStops: [StopPreview] = []
    @State private var itineraryTitle: String = ""
    @State private var isSavingItinerary = false

    var body: some View {
        ZStack {
            HomeCelestialBackground() // Match Explore Page background
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
                                        .font(.system(size: 12, weight: .bold))
                                    Text(filter.rawValue)
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
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
                        VStack(spacing: 16) {
                            // Top Carousel ("Happening Soon" Popups resembling FB Stories)
                            if !popups.isEmpty && selectedFilter == .all {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Happening Soon")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, TravSpacing.screenHorizontal)
                                        .padding(.top, TravSpacing.xs)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(popups) { popup in
                                                Button {
                                                    router.presentedRoute = .experience(popup.id)
                                                } label: {
                                                    ZStack(alignment: .bottomLeading) {
                                                        // Full-bleed cover image
                                                        if let coverURL = popup.coverImageURL {
                                                            RemoteImage(url: coverURL, height: 160, cornerRadius: 16)
                                                        } else {
                                                            RoundedRectangle(cornerRadius: 16)
                                                                .fill(Color.gray.opacity(0.2))
                                                        }
                                                        
                                                        // Dark gradient overlay
                                                        LinearGradient(
                                                            colors: [.clear, .black.opacity(0.85)],
                                                            startPoint: .top,
                                                            endPoint: .bottom
                                                        )
                                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                                        
                                                        // Top pill badge ("TODAY" / "THIS WKND")
                                                        VStack {
                                                            HStack {
                                                                let isToday = popup.creator.displayName.contains("Today")
                                                                Text(isToday ? "TODAY" : "THIS WKND")
                                                                    .font(.system(size: 8, weight: .black, design: .rounded))
                                                                    .foregroundStyle(.white)
                                                                    .padding(.horizontal, 6)
                                                                    .padding(.vertical, 3)
                                                                    .background(
                                                                        Capsule()
                                                                            .fill(isToday ? Color.red : TravColors.accent)
                                                                    )
                                                                    .padding(8)
                                                                
                                                                Spacer()
                                                            }
                                                            Spacer()
                                                        }
                                                        
                                                        // Host Avatar + Details Overlaid at bottom
                                                        VStack(alignment: .leading, spacing: 4) {
                                                            Image(systemName: "calendar.circle.fill")
                                                                .font(.system(size: 24))
                                                                .foregroundStyle(.white)
                                                                .background(Circle().fill(TravColors.accent))
                                                                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                                                .padding(.leading, 8)
                                                            
                                                            Spacer()
                                                            
                                                            VStack(alignment: .leading, spacing: 2) {
                                                                Text(popup.title)
                                                                    .font(.system(size: 11, weight: .bold))
                                                                    .foregroundStyle(.white)
                                                                    .lineLimit(2)
                                                                    .multilineTextAlignment(.leading)
                                                                
                                                                Text(popup.creator.displayName)
                                                                    .font(.system(size: 9, weight: .semibold))
                                                                    .foregroundStyle(.white.opacity(0.8))
                                                                    .lineLimit(1)
                                                            }
                                                            .padding([.horizontal, .bottom], 8)
                                                        }
                                                    }
                                                    .frame(width: 110, height: 160)
                                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                                    .shadow(color: Color.black.opacity(0.06), radius: 6, y: 3)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.horizontal, TravSpacing.screenHorizontal)
                                    }
                                }
                                .padding(.bottom, TravSpacing.xs)
                            }
                            
                            // Post Feed list
                             LazyVStack(spacing: 0) {
                                 ForEach(mainFeedPosts) { experience in
                                     ExperienceCard(
                                         experience: experience,
                                         isSaved: engagement.isSaved(experience.id),
                                         connectedLayout: true,
                                         onTap: {
                                             router.presentedRoute = .experience(experience.id)
                                         },
                                         onCreatorTap: {
                                             router.openProfile(experience.creator.username)
                                         },
                                         onSave: {
                                             Task {
                                                 await engagement.toggleSave(
                                                     experienceID: experience.id,
                                                     summary: experience,
                                                     using: environment
                                                 )
                                             }
                                         },
                                         onShare: {
                                             // Share action placeholder
                                         }
                                     )
                                     .onDrag {
                                         NSItemProvider(object: experience.id.uuidString as NSString)
                                     }
                                 }
                             }
                             .clipShape(RoundedRectangle(cornerRadius: 18))
                             .overlay(
                                 RoundedRectangle(cornerRadius: 18)
                                     .stroke(Color.white.opacity(0.08), lineWidth: 1)
                             )
                             .padding(.horizontal, TravSpacing.screenHorizontal)
                        }
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
                                        
                                        Image(systemName: sfSymbolForEmojiOrCategory(stop.emoji ?? ""))
                                            .font(.system(size: 11))
                                            .foregroundStyle(TravColors.accent)
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
            if let userID = session.currentUser?.id {
                await engagement.bootstrap(userID: userID, using: environment)
            }
            await loadFeed()
        }
    }

    private var feedTabBarBackdrop: TabBarBackdrop {
        let showingCards = !isLoading && errorMessage == nil && !filteredFeed.isEmpty
        if showingCards { return .dark }
        return appearance.isLightMode ? .light : .dark
    }
    
    private func isUpcomingPopupClose(_ date: Date?) -> Bool {
        guard let date = date else { return false }
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let threeDaysFromNow = Calendar.current.date(byAdding: .day, value: 3, to: now) ?? now
        return date >= startOfToday && date <= threeDaysFromNow
    }

    private var filteredFeed: [ExperienceSummary] {
        var items = feedItems
        
        // Tab Filter
        switch selectedFilter {
        case .all:
            break
        case .itineraries:
            items = items.filter { $0.stops.count > 1 }
        case .singleSpots:
            items = items.filter { $0.stops.count <= 1 }
        case .saved:
            items = items.filter { engagement.isSaved($0.id) }
        }
        
        return items
    }

    private var popups: [ExperienceSummary] {
        feedItems.filter { $0.creator.username.hasPrefix("popup") }
    }
    
    private var mainFeedPosts: [ExperienceSummary] {
        filteredFeed.filter { !$0.creator.username.hasPrefix("popup") }
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
            // Left Side: Brand Logo and Title
            HStack(spacing: TravSpacing.sm) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        appearance.toggle()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(TravColors.accent.opacity(0.15))
                            .frame(width: 46, height: 46)

                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(TravColors.accent)
                    }
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.92))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRAV")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(appearance.isLightMode ? Color.black : .white)

                    Text("What's the move?")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(
                            appearance.isLightMode
                                ? Color.black.opacity(0.55)
                                : .white.opacity(0.5)
                        )
                }
            }            
            
            Spacer()
            
            // Right Side: Auth / Profile Action
            if session.isAuthenticated {
                Button(action: {
                    if let username = session.currentUser?.username {
                        router.openProfile(username)
                    }
                }) {
                    if let avatarURL = session.currentUser?.avatarURL {
                        RemoteImage(url: avatarURL, height: 44, cornerRadius: 22)
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(TravColors.accent)
                            .background(Circle().fill(Color.white.opacity(0.05)))
                    }
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.92))
            } else {
                Button {
                    router.presentAuth()
                } label: {
                    Text("Sign In")
                        .font(TravTypography.bodyMedium())
                        .fontWeight(.bold)
                        .foregroundStyle(appearance.isLightMode ? Color.black : .white)
                        .padding(.horizontal, TravSpacing.lg)
                        .frame(height: 38)
                        .background(
                            Capsule()
                                .fill(TravColors.accent.opacity(appearance.isLightMode ? 0.12 : 0.15))
                        )
                        .overlay {
                            Capsule()
                                .stroke(TravColors.accent.opacity(0.3), lineWidth: 1)
                        }
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.95))
            }
        }
        .padding(.vertical, TravSpacing.sm)
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
                
                let dbPopups: [DBPopup] = (try? await client
                    .from("popups")
                    .select()
                    .execute()
                    .value) ?? []
                
                // Fetch creators profiles in parallel to resolve shared traveler metadata
                let dbProfiles: [DBProfileSummary] = (try? await client
                    .from("profiles")
                    .select("id, username, display_name, avatar_url, is_verified")
                    .execute()
                    .value) ?? []
                let profileMap = Dictionary(uniqueKeysWithValues: dbProfiles.map { ($0.id, $0) })
                
                // 1. Map places (System recommendations)
                let recCreator = ProfileSummary(
                    id: UUID(),
                    username: "rec_by_trav",
                    displayName: "Rec by Trav",
                    avatarURL: nil,
                    isVerified: true
                )
                
                let placeItems: [ExperienceSummary] = dbPlaces.map { dbPlace in
                    let placeID = StableUUID.from(dbPlace.id)
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
                            id: placeID,
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
                            id: placeID,
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
                
                // Map popup events
                let popupItems: [ExperienceSummary] = dbPopups.map { dbPopup in
                    var parsedDate: Date? = nil
                    if let startStr = dbPopup.start_time {
                        let isoFormatter = ISO8601DateFormatter()
                        var date = isoFormatter.date(from: startStr)
                        if date == nil {
                            let fallbackFormatter = DateFormatter()
                            fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
                            date = fallbackFormatter.date(from: startStr)
                        }
                        if date == nil {
                            let fallbackFormatter2 = DateFormatter()
                            fallbackFormatter2.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                            date = fallbackFormatter2.date(from: startStr)
                        }
                        parsedDate = date
                    }
                    
                    let isClose = isUpcomingPopupClose(parsedDate)
                    let creatorUsername = isClose ? "popup_upcoming" : "popup_standard"
                    
                    let dateText: String
                    if let start = parsedDate {
                        if Calendar.current.isDateInToday(start) {
                            dateText = "Today at " + DateFormatter.localizedString(from: start, dateStyle: .none, timeStyle: .short)
                        } else if Calendar.current.isDateInTomorrow(start) {
                            dateText = "Tomorrow at " + DateFormatter.localizedString(from: start, dateStyle: .none, timeStyle: .short)
                        } else {
                            let formatter = DateFormatter()
                            formatter.dateStyle = .medium
                            formatter.timeStyle = .short
                            dateText = formatter.string(from: start)
                        }
                    } else {
                        dateText = "Date/Time TBA"
                    }
                    
                    let popupCreator = ProfileSummary(
                        id: UUID(),
                        username: creatorUsername,
                        displayName: dateText,
                        avatarURL: nil,
                        isVerified: true
                    )
                    
                    let firstStop = StopPreview(
                        id: UUID(),
                        name: dbPopup.address,
                        emoji: "mappin.and.ellipse"
                    )
                    
                    let coverURL = imageForEventTitle(dbPopup.event_name)
                    
                    return ExperienceSummary(
                        id: dbPopup.id,
                        cityID: UUID(),
                        title: dbPopup.event_name,
                        coverImageURL: coverURL,
                        creator: popupCreator,
                        durationMinutes: 120,
                        costLevel: .budget,
                        estimatedCostUSD: 0,
                        saveCount: 0,
                        likeCount: 0,
                        completionCount: 0,
                        stops: [firstStop]
                    )
                }
                
                // Combine and prioritize upcoming popups at the top, followed by user posts and system places
                self.feedItems = popupItems + userExpItems + placeItems
                
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

private func imageForEventTitle(_ title: String) -> URL? {
    let lowerTitle = title.lowercased()
    
    // 1. AI / Tech / Meetup / Software / Hardware / Coding
    if lowerTitle.contains("ai") || lowerTitle.contains("neural") || lowerTitle.contains("openai") || lowerTitle.contains("voice") {
        return URL(string: "https://images.unsplash.com/photo-1677442136019-21780efad99a?w=800&q=80") // AI/Robotics
    }
    if lowerTitle.contains("meetup") || lowerTitle.contains("lounge") || lowerTitle.contains("founders") || lowerTitle.contains("builders") {
        return URL(string: "https://images.unsplash.com/photo-1515187029135-18ee286d815b?w=800&q=80") // Meetup/Networking/Gathering
    }
    if lowerTitle.contains("tech") || lowerTitle.contains("software") || lowerTitle.contains("hardware") || lowerTitle.contains("infra") {
        return URL(string: "https://images.unsplash.com/photo-1517694712202-14dd9538aa97?w=800&q=80") // Developer/Code/Hardware
    }
    if lowerTitle.contains("engineering") || lowerTitle.contains("pitch") {
        return URL(string: "https://images.unsplash.com/photo-1475721027785-f74eccf877e2?w=800&q=80") // Presentation/Talk
    }
    
    // 2. Music / Party / Night / Dance / Sound / Concert / Balkan / SKOTO
    if lowerTitle.contains("music") || lowerTitle.contains("sound") || lowerTitle.contains("concert") || lowerTitle.contains("band") {
        return URL(string: "https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=800&q=80") // Concert/Live Music
    }
    if lowerTitle.contains("party") || lowerTitle.contains("dance") || lowerTitle.contains("bachata") || lowerTitle.contains("night") || lowerTitle.contains("noche") {
        return URL(string: "https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=800&q=80") // Party/Dancing/Night Club
    }
    if lowerTitle.contains("glaom") || lowerTitle.contains("fevr") || lowerTitle.contains("80s") {
        return URL(string: "https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=800&q=80") // DJ/Club Lights
    }
    
    // 3. Art / Creative / Painting / Wine
    if lowerTitle.contains("paint") || lowerTitle.contains("art") || lowerTitle.contains("creative") || lowerTitle.contains("craft") {
        return URL(string: "https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=800&q=80") // Painting/Art
    }
    if lowerTitle.contains("wine") || lowerTitle.contains("winery") {
        return URL(string: "https://images.unsplash.com/photo-1510812431401-41d2bd2722f3?w=800&q=80") // Wine glasses/Winery
    }
    
    // 4. Books / Reading / signing / math
    if lowerTitle.contains("book") || lowerTitle.contains("reading") || lowerTitle.contains("signing") || lowerTitle.contains("math") || lowerTitle.contains("mcluhan") {
        return URL(string: "https://images.unsplash.com/photo-1497633762265-9d179a990aa6?w=800&q=80") // Books/Library/Signing
    }
    
    // 5. Film / Screening / Theater
    if lowerTitle.contains("film") || lowerTitle.contains("screening") || lowerTitle.contains("movie") {
        return URL(string: "https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?w=800&q=80") // Cinema/Theater
    }
    
    // 6. Food / Dinner / Restaurant / Wine / Kitchen
    if lowerTitle.contains("dinner") || lowerTitle.contains("food") || lowerTitle.contains("celebration") || lowerTitle.contains("islander") || lowerTitle.contains("roots") {
        return URL(string: "https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=800&q=80") // Fine dining/Buffet/Food
    }
    
    // 7. Market / Witch / Showcase / Frog
    if lowerTitle.contains("market") || lowerTitle.contains("bazaar") || lowerTitle.contains("showcase") {
        return URL(string: "https://images.unsplash.com/photo-1533900298318-6b8da08a523e?w=800&q=80") // Open-air market
    }
    if lowerTitle.contains("witch") || lowerTitle.contains("cosmic") {
        return URL(string: "https://images.unsplash.com/photo-1519681393784-d120267933ba?w=800&q=80") // Cosmic/Stars/Astrology
    }
    
    // 8. Games / Chess / Tournament
    if lowerTitle.contains("chess") || lowerTitle.contains("game") || lowerTitle.contains("tournament") || lowerTitle.contains("bughouse") {
        return URL(string: "https://images.unsplash.com/photo-1529699211952-734e80c4d42b?w=800&q=80") // Chess board
    }
    
    // 9. Berkeley / Golden Hour / Fourth
    if lowerTitle.contains("berkeley") || lowerTitle.contains("golden") || lowerTitle.contains("hour") {
        return URL(string: "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800&q=80") // Golden hour/Sunset
    }
    
    // Default fallback - High-quality festival/gathering event
    return URL(string: "https://images.unsplash.com/photo-1511578314322-379afb476865?w=800&q=80")
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

private struct DBPopup: Codable, Identifiable {
    let id: UUID
    let event_name: String
    let address: String
    let start_time: String?
    let end_time: String?
}
