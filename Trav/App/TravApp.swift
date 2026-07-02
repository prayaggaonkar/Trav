import SwiftUI

@main
struct TravApp: App {
    @State private var environment = AppEnvironment.live

    var body: some Scene {
        WindowGroup {
            RootCoordinator()
                .injectAppEnvironment(environment)
                .preferredColorScheme(.dark)
        }
    }
}
