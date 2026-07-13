import Foundation
import Supabase

/// Owns the shared `SupabaseClient` used across the app.
///
/// The client is only created when valid Supabase credentials are present in
/// `AppConfiguration`. When running against mock data (`useMockBackend == true`),
/// `client` is `nil` and callers should fall back to mock repositories.
enum SupabaseManager {
    static let client: SupabaseClient? = {
        let configuration = AppConfiguration.current
        guard
            let url = configuration.supabaseURL,
            url.host?.isEmpty == false,
            let key = configuration.supabaseAnonKey,
            !key.isEmpty
        else {
            return nil
        }

        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    redirectToURL: AppConfiguration.oauthRedirectURL
                )
            )
        )
    }()

    /// Forwards an incoming deep link (OAuth callback, magic link, password reset) to Supabase Auth.
    /// Safe to call even when no client is configured (mock backend).
    static func handle(_ url: URL) {
        client?.handle(url)
    }
}
