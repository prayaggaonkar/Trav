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
    @Environment(AppearanceStore.self) private var appearance
    @Environment(NotificationStore.self) private var notificationStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var activeTab: TravTab = .explore
    @State private var tabBarBackdrop: TabBarBackdrop = .dark
    /// Tabs stay mounted after first visit so Explore's SceneKit globe is not rebuilt.
    @State private var retainedTabs: Set<TravTab> = [.explore]
    @State private var isSplashFinished: Bool = false

    var body: some View {
        @Bindable var router = router

        ZStack {
            tabContent
        }
        .modifier(RootChromeModifier(
            environment: environment,
            router: router,
            session: session,
            notificationStore: notificationStore,
            scenePhase: scenePhase,
            activeTab: $activeTab,
            tabBarBackdrop: $tabBarBackdrop,
            retainedTabs: $retainedTabs,
            isSplashFinished: isSplashFinished,
            defaultBackdrop: defaultBackdrop(for:)
        ))
        .purplePinSplashScreen(isLoading: session.phase == .loading, isFinished: $isSplashFinished)
    }

    private func defaultBackdrop(for tab: TravTab) -> TabBarBackdrop {
        switch tab {
        case .feed:
            return appearance.isLightMode ? .light : .dark
        case .explore:
            return appearance.isLightMode ? .light : .dark
        case .create, .rankings, .profile:
            return appearance.isLightMode ? .light : .dark
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            if retainedTabs.contains(.explore) {
                tabPane(.explore) {
                    GlobeLandingView(isActive: activeTab == .explore)
                        .tabBarBackdrop(appearance.isLightMode ? .light : .dark)
                }
            }
            if retainedTabs.contains(.feed) {
                tabPane(.feed) {
                    FeedView(isActive: activeTab == .feed)
                }
            }
            if retainedTabs.contains(.create) {
                tabPane(.create) {
                    if session.isAuthenticated {
                        CreateHubView(isActive: activeTab == .create)
                            .tabBarBackdrop(appearance.isLightMode ? .light : .dark)
                    } else {
                        UnauthenticatedPlaceholderView(
                            title: "Rate & Create",
                            description: "Sign in to rate the places you finish and publish itineraries of your own.",
                            imageName: "plus.circle.fill"
                        )
                        .tabBarBackdrop(appearance.isLightMode ? .light : .dark)
                    }
                }
            }
            if retainedTabs.contains(.rankings) {
                tabPane(.rankings) {
                    RankingsView()
                        .tabBarBackdrop(appearance.isLightMode ? .light : .dark)
                }
            }
            if retainedTabs.contains(.profile) {
                tabPane(.profile) {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func tabPane<Content: View>(_ tab: TravTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(activeTab == tab ? 1 : 0)
            .allowsHitTesting(activeTab == tab)
            .accessibilityHidden(activeTab != tab)
            .zIndex(activeTab == tab ? 1 : 0)
    }
}

/// Breaks chrome modifiers out of `RootCoordinator.body` so the type-checker can finish.
private struct RootChromeModifier: ViewModifier {
    let environment: AppEnvironment
    @Bindable var router: AppRouter
    let session: SessionStore
    let notificationStore: NotificationStore
    let scenePhase: ScenePhase
    @Binding var activeTab: TravTab
    @Binding var tabBarBackdrop: TabBarBackdrop
    @Binding var retainedTabs: Set<TravTab>
    let isSplashFinished: Bool
    let defaultBackdrop: (TravTab) -> TabBarBackdrop

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(TabBarBackdropPreferenceKey.self) { tabBarBackdrop = $0 }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSplashFinished && session.phase != .loading {
                    TravTabBar(activeTab: $activeTab, backdrop: tabBarBackdrop)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
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
                    .overlay(alignment: .top) {
                        InAppNotificationBannerHost()
                            .environment(environment.notificationStore)
                            .environment(environment.router)
                    }
            }
            .animation(TravAnimation.modal, value: router.presentedRoute?.id)
            .animation(TravAnimation.tab, value: activeTab)
            .overlay(alignment: .top) {
                InAppNotificationBannerHost()
                    .zIndex(999)
            }
            .onOpenURL { url in
                router.handleDeepLink(url)
            }
            .onAppear {
                tabBarBackdrop = defaultBackdrop(activeTab)
                if let userID = session.currentUser?.id {
                    notificationStore.startListening(userID: userID, using: environment)
                }
            }
            .onChange(of: activeTab) { _, tab in
                retainedTabs.insert(tab)
                tabBarBackdrop = defaultBackdrop(tab)
                if tab == .explore {
                    router.noteExploreActivated()
                }
            }
            .onChange(of: router.feedNavigationToken) { _, _ in
                activeTab = .feed
            }
            .onChange(of: router.pendingCreateSpot) { _, spot in
                if spot != nil {
                    activeTab = .create
                }
            }
            // Tapping Complete anywhere routes straight into Create Rating.
            .onChange(of: router.createNavigationToken) { _, _ in
                activeTab = .create
            }
            .onChange(of: router.presentedRoute) { previous, current in
                guard current == nil, case .notifications = previous else { return }
                guard let userID = session.currentUser?.id else { return }
                Task {
                    await notificationStore.endInboxSessionIfNeeded(userID: userID, using: environment)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                notificationStore.handleScenePhase(phase, using: environment)
            }
    }

    @ViewBuilder
    private func routeDestination(for route: TravRoute) -> some View {
        switch route {
        case let .experience(experienceID):
            ExperienceDetailView(experienceID: experienceID)
        case let .profile(username):
            ProfileView(username: username)
        case let .city(cityID):
            CityPageView(cityID: cityID)
        case .notifications:
            NotificationsView()
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

/// Solid purple splash screen with white pin icon and TRAV text that smoothly fades out when app finishes loading.
struct PurplePinSplashScreenModifier: ViewModifier {
    let isLoading: Bool
    @Binding var isFinished: Bool

    @State private var splashOpacity: Double = 1.0

    func body(content: Content) -> some View {
        ZStack {
            content

            if !isFinished {
                ZStack {
                    // Logo Purple Background (#B368FF)
                    Color(red: 0.700, green: 0.409, blue: 0.997)
                        .ignoresSafeArea()

                    // Pure White Map Pin Icon + TRAV branding text
                    VStack(spacing: 16) {
                        Image(systemName: "mappin.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .foregroundStyle(.white)
                            .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 4)

                        Text("TRAV")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .tracking(3.5)
                            .foregroundStyle(.white)
                            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 2)
                    }
                }
                .opacity(splashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .zIndex(999_999)
            }
        }
        .onChange(of: isLoading, initial: true) { _, loading in
            if !loading {
                dismissSplash()
            }
        }
    }

    private func dismissSplash() {
        // Wait 0.2s to guarantee main tab view & globe renderer finish initial layout mounting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeInOut(duration: 0.5)) {
                splashOpacity = 0.0
            }
            // ONLY after opacity reaches 0.0 completely (0.55s later), mark isFinished = true so bottom tabs load!
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.easeOut(duration: 0.25)) {
                    isFinished = true
                }
            }
        }
    }
}

extension View {
    /// Applies a purple splash screen with a white pin icon & TRAV title that fades out smoothly when loading finishes.
    func purplePinSplashScreen(isLoading: Bool, isFinished: Binding<Bool>) -> some View {
        self.modifier(PurplePinSplashScreenModifier(isLoading: isLoading, isFinished: isFinished))
    }
}
