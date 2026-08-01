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
            .overlay(alignment: .top) {
                OfflineBanner()
            }
            .task { await environment.observeAuthState() }
            .onOpenURL { url in
                // Google OAuth: prefer the in-flight ASWebAuthenticationSession
                // coordinator so we never PKCE-exchange the same code twice.
                if OAuthLoginFlow.consumeOpenURL(url) {
                    return
                }
                // Magic link / password reset, then app deep links.
                SupabaseManager.handle(url)
                _ = environment.router.handleDeepLink(url)
            }
    }
}
