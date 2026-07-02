import SwiftUI

enum TravTab: String, CaseIterable {
    case explore = "Explore"
    case search = "Search"
    case create = "Create"
    case rankings = "Rankings"
    case profile = "Profile"

    var systemImage: String {
        switch self {
        case .explore: "globe"
        case .search: "magnifyingglass"
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
                AuthSheetView()
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
            case .search:
                SearchView()
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

private struct SearchView: View {
    var body: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "Search Experiences",
            description: "Find your next adventure by city, creator, or topic."
        )
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
