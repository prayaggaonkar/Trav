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

    var body: some View {
        @Bindable var router = router

        ZStack {
            if session.phase == .loading {
                loadingSplash
            } else {
                tabContent
            }
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
            defaultBackdrop: defaultBackdrop(for:)
        ))
    }

    private var loadingSplash: some View {
        ZStack {
            TravColors.globeBackground.ignoresSafeArea()
            ProgressView()
                .tint(TravColors.accent)
                .controlSize(.large)
        }
        .accessibilityLabel("Loading Trav")
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
    let defaultBackdrop: (TravTab) -> TabBarBackdrop

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(TabBarBackdropPreferenceKey.self) { tabBarBackdrop = $0 }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if session.phase != .loading {
                    TravTabBar(activeTab: $activeTab, backdrop: tabBarBackdrop)
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
