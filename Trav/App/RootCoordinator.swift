import SwiftUI

struct RootCoordinator: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    var body: some View {
        @Bindable var router = router

        ZStack {
            GlobeLandingView()
                .ignoresSafeArea()

            if session.phase == .unauthenticated && router.isAuthPresented {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
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
