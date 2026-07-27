import Foundation
import Network
import Observation

/// App-wide connectivity monitor. Surfaces an offline banner when the path is unsatisfied.
@Observable
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.trav.app.network")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}
