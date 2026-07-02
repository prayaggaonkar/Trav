import SwiftUI

enum TravTab: String, CaseIterable {
    case explore = "Explore"
    case create = "Create"
    case profile = "Profile"

    var systemImage: String {
        switch self {
        case .explore: "globe"
        case .create: "plus.circle"
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

        ZStack(alignment: .bottom) {
            Group {
                switch activeTab {
                case .explore:
                    GlobeLandingView()
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
            .ignoresSafeArea()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            customTabBar
                .padding(.bottom, 4)
        }
        .sheet(isPresented: $router.isAuthPresented) {
            AuthSheetView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(TravRadius.xl)
        }
        .fullScreenCover(item: $router.presentedRoute) { route in
            routeDestination(for: route)
        }
        .animation(.spring(duration: 0.4, bounce: 0.12), value: router.presentedRoute?.id)
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(TravTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                        activeTab = tab
                    }
                } label: {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 22, weight: activeTab == tab ? .semibold : .medium))
                        .foregroundStyle(activeTab == tab ? TravColors.accent : .primary.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .padding(.horizontal, 32)
        .environment(\.colorScheme, .dark)
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
        ZStack {
            TravColors.surface.ignoresSafeArea()
            
            VStack(spacing: TravSpacing.xl) {
                Image(systemName: imageName)
                    .font(.system(size: 72))
                    .foregroundStyle(TravColors.accent)
                    .padding(24)
                    .background(TravColors.accentSoft)
                    .clipShape(Circle())
                
                VStack(spacing: TravSpacing.sm) {
                    Text(title)
                        .font(TravTypography.displayMedium())
                        .foregroundStyle(TravColors.primary)
                    
                    Text(description)
                        .font(TravTypography.bodyMedium())
                        .foregroundStyle(TravColors.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                Button {
                    router.presentAuth()
                } label: {
                    Text("Sign In")
                        .font(TravTypography.titleMedium())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(TravColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                }
                .padding(.horizontal, 32)
            }
            .padding(.bottom, 60)
        }
    }
}

