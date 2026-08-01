import SwiftUI

@main
struct TravApp: App {
    @UIApplicationDelegateAdaptor(TravAppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment.live

    var body: some Scene {
        WindowGroup {
            RootContent(environment: environment)
                .onAppear { TravAppDelegate.environment = environment }
        }
    }
}

/// Isolates observation of `AppearanceStore` so light/dark toggles always refresh the window scheme.
private struct RootContent: View {
    let environment: AppEnvironment

    var body: some View {
        @Bindable var appearance = environment.appearance

        RootCoordinator()
            .injectAppEnvironment(environment)
            .preferredColorScheme(appearance.isLightMode ? .light : .dark)
            .environment(\.colorScheme, appearance.isLightMode ? .light : .dark)
            .overlay(alignment: .top) {
                OfflineBanner()
            }
            .task { await environment.observeAuthState() }
            .onOpenURL { url in
                // Auth callbacks (OAuth, magic link, password reset) first;
                // then app deep links (experience / profile / city).
                SupabaseManager.handle(url)
                _ = environment.router.handleDeepLink(url)
            }
    }
}
