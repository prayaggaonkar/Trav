import AuthenticationServices
import UIKit

enum OAuthPresentationError: LocalizedError {
    case failedToStart
    case missingCallbackURL

    var errorDescription: String? {
        switch self {
        case .failedToStart:
            return "Couldn’t start Google sign-in. Please try again."
        case .missingCallbackURL:
            return "Google sign-in didn’t return a callback. Please try again."
        }
    }
}

/// Presents an OAuth URL with `ASWebAuthenticationSession`, using a retained key-window
/// presentation anchor. Required when starting auth from a SwiftUI sheet — Supabase’s
/// default empty `ASPresentationAnchor()` often cancels the session immediately.
@MainActor
enum OAuthWebSession {
    /// Retained for the lifetime of the active session (ASWebAuthenticationSession
    /// holds `presentationContextProvider` weakly).
    private static var activeSession: ASWebAuthenticationSession?
    private static var activeProvider: KeyWindowPresentationContextProvider?

    static func present(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let contextProvider = KeyWindowPresentationContextProvider()
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                Self.activeSession = nil
                Self.activeProvider = nil

                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: OAuthPresentationError.missingCallbackURL)
                }
            }

            session.presentationContextProvider = contextProvider
            session.prefersEphemeralWebBrowserSession = false
            Self.activeSession = session
            Self.activeProvider = contextProvider

            guard session.start() else {
                Self.activeSession = nil
                Self.activeProvider = nil
                continuation.resume(throwing: OAuthPresentationError.failedToStart)
                return
            }
        }
    }
}

@MainActor
private final class KeyWindowPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return key
        }
        if let first = scenes.flatMap(\.windows).first {
            return first
        }
        return ASPresentationAnchor()
    }
}
