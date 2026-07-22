import SwiftUI

@main
struct TravApp: App {
    @State private var environment = AppEnvironment.live

    var body: some Scene {
        WindowGroup {
            RootContent(environment: environment)
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
            .task { await environment.observeAuthState() }
            .onOpenURL { url in
                SupabaseManager.handle(url)
            }
    }
}
