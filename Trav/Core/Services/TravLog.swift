import Foundation
import OSLog

/// Centralized structured logging. Never writes to disk; DEBUG-gated for verbose categories.
enum TravLog {
    static let auth = Logger(subsystem: "com.trav.app", category: "auth")
    static let network = Logger(subsystem: "com.trav.app", category: "network")
    static let engagement = Logger(subsystem: "com.trav.app", category: "engagement")
    static let notifications = Logger(subsystem: "com.trav.app", category: "notifications")
    static let media = Logger(subsystem: "com.trav.app", category: "media")
    static let push = Logger(subsystem: "com.trav.app", category: "push")
    static let general = Logger(subsystem: "com.trav.app", category: "general")
}
