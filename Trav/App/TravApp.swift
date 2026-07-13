import SwiftUI

@main
struct TravApp: App {
    @State private var environment = AppEnvironment.live

    var body: some Scene {
        WindowGroup {
            RootCoordinator()
                .injectAppEnvironment(environment)
                .preferredColorScheme(.dark)
                .task { await environment.observeAuthState() }
                .onOpenURL { url in
                    SupabaseManager.handle(url)
                }
        }
    }
}
