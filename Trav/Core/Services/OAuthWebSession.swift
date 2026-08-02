import AuthenticationServices
import UIKit
import WebKit

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

/// Coordinates a single in-flight OAuth callback.
///
/// iOS often delivers `trav://auth-callback` both to `ASWebAuthenticationSession`
/// and to `onOpenURL`. Only the first delivery wins; `session(from:)` runs once.
@MainActor
enum OAuthLoginFlow {
    private static var continuation: CheckedContinuation<URL, Error>?
    /// True from `run` until `end()` — covers presentation + PKCE exchange.
    private static var isActive = false
    /// True after a callback URL (or terminal error) has already resumed `run`.
    private static var didResume = false

    /// True while Google OAuth is waiting for / exchanging a callback.
    static var isInProgress: Bool { isActive }

    static func isAuthCallback(_ url: URL) -> Bool {
        guard let redirect = AppConfiguration.oauthRedirectURL else { return false }
        return url.scheme?.lowercased() == redirect.scheme?.lowercased()
            && url.host?.lowercased() == redirect.host?.lowercased()
    }

    /// Runs an OAuth presentation and returns the first callback URL from either
    /// the web-auth session or `onOpenURL`.
    static func run(presenting: @escaping () async throws -> Void) async throws -> URL {
        // Cancel any stuck prior attempt.
        if continuation != nil {
            continuation?.resume(throwing: CancellationError())
            continuation = nil
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            continuation = cont
            isActive = true
            didResume = false

            Task { @MainActor in
                do {
                    try await presenting()
                    // Some iOS versions dismiss ASWebAuthenticationSession with
                    // "cancel" and deliver the real callback via onOpenURL a
                    // moment later — wait briefly before treating it as cancel.
                    if !didResume {
                        try? await Task.sleep(for: .milliseconds(800))
                    }
                    if !didResume {
                        resumeOnce(with: .failure(
                            NSError(
                                domain: ASWebAuthenticationSessionError.errorDomain,
                                code: ASWebAuthenticationSessionError.canceledLogin.rawValue
                            )
                        ))
                    }
                } catch {
                    resumeOnce(with: .failure(error))
                }
            }
        }
    }

    /// Consumes an incoming app URL if it completes the active OAuth flow.
    @discardableResult
    static func consumeOpenURL(_ url: URL) -> Bool {
        guard isActive, !didResume, isAuthCallback(url) else { return false }
        resumeOnce(with: .success(url))
        return true
    }

    static func fulfill(_ url: URL) {
        guard isActive, !didResume else { return }
        resumeOnce(with: .success(url))
    }

    static func fail(_ error: Error) {
        guard isActive, !didResume else { return }
        resumeOnce(with: .failure(error))
    }

    /// Clears the in-progress flag after PKCE exchange finishes.
    static func end() {
        isActive = false
        didResume = false
        continuation = nil
    }

    private static func resumeOnce(with result: Result<URL, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        didResume = true
        // Leave `isActive == true` until `end()` so a late onOpenURL cannot
        // trigger a second PKCE exchange while `session(from:)` is running.
        cont.resume(with: result)
    }
}

/// Presents an OAuth URL with `ASWebAuthenticationSession`, using a retained
/// foreground-window presentation anchor. Required when auth UI is modal —
/// Supabase’s default empty `ASPresentationAnchor()` often cancels immediately.
@MainActor
enum OAuthWebSession {
    private static var activeSession: ASWebAuthenticationSession?
    private static var activeProvider: ForegroundWindowPresentationContextProvider?

    static func present(url: URL, callbackScheme: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let contextProvider = ForegroundWindowPresentationContextProvider()
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                Self.activeSession = nil
                Self.activeProvider = nil

                if let callbackURL {
                    OAuthLoginFlow.fulfill(callbackURL)
                    continuation.resume(returning: ())
                } else if let error {
                    // Cancelled sessions often still get the callback via onOpenURL
                    // a moment later — don't fail the flow on cancel here; let
                    // `OAuthLoginFlow.run` decide after presentation returns.
                    let nsError = error as NSError
                    let isCancel = nsError.domain == ASWebAuthenticationSessionError.errorDomain
                        && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                    if !isCancel {
                        OAuthLoginFlow.fail(error)
                    }
                    continuation.resume(returning: ())
                } else {
                    OAuthLoginFlow.fail(OAuthPresentationError.missingCallbackURL)
                    continuation.resume(returning: ())
                }
            }

            session.presentationContextProvider = contextProvider
            // Ephemeral avoids sticky Safari/cookie state that can bounce the
            // session closed on some devices when started from SwiftUI modals.
            session.prefersEphemeralWebBrowserSession = true
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

    /// Clears shared cookies and WKWebsiteDataStore web data to prevent Google/OAuth from auto-logging into previous accounts
    @MainActor
    static func clearSessionCookies() {
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: dataTypes) { records in
            WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, for: records, completionHandler: {})
        }
    }
}

@MainActor
private final class ForegroundWindowPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        let windows = (scenes.isEmpty
            ? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            : scenes)
            .flatMap(\.windows)

        if let key = windows.first(where: \.isKeyWindow) {
            return key
        }
        if let largest = windows.max(by: {
            $0.bounds.size.width * $0.bounds.size.height
                < $1.bounds.size.width * $1.bounds.size.height
        }) {
            return largest
        }
        return ASPresentationAnchor()
    }
}
