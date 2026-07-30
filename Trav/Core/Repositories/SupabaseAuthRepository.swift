import Foundation
import Supabase

/// Production `AuthRepository` backed by Supabase Auth and the `profiles` table.
struct SupabaseAuthRepository: AuthRepository {
    private var client: SupabaseClient {
        get throws {
            guard let client = SupabaseManager.client else {
                throw RepositoryError.backendUnavailable
            }
            return client
        }
    }

    func signIn(email: String, password: String) async throws -> Profile {
        let session = try await client.auth.signIn(email: email, password: password)
        return try await fetchOrCreateProfile(for: session.user)
    }

    /// Returns the profile immediately when Supabase issues a session on sign-up
    /// (email confirmation disabled). Returns `nil` when the user must confirm
    /// their email first — callers should show a "check your inbox" state.
    @discardableResult
    func signUp(email: String, password: String) async throws -> Profile? {
        let response = try await client.auth.signUp(email: email, password: password)
        guard response.session != nil else { return nil }
        return try await fetchOrCreateProfile(for: response.user)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email, redirectTo: AppConfiguration.oauthRedirectURL)
    }

    func signInWithGoogle() async throws -> Profile {
        let callbackScheme = AppConfiguration.oauthRedirectURL?.scheme ?? "trav"
        let session = try await client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: AppConfiguration.oauthRedirectURL
        ) { @MainActor url in
            // Present from the key window with a retained anchor so sheet-hosted
            // auth UI does not cancel ASWebAuthenticationSession immediately.
            try await OAuthWebSession.present(url: url, callbackScheme: callbackScheme)
        }
        return try await fetchOrCreateProfile(for: session.user)
    }

    /// Emits the current session immediately, then every subsequent sign-in/out/refresh event.
    /// Mirrors `AuthClient.authStateChanges`, resolving each session into an app `Profile`.
    func authStateChanges() -> AsyncStream<Profile?> {
        AsyncStream { continuation in
            guard let client = SupabaseManager.client else {
                continuation.yield(nil)
                continuation.finish()
                return
            }
            let task = Task {
                for await (event, session) in client.auth.authStateChanges {
                    switch event {
                    case .signedOut:
                        continuation.yield(nil)
                    case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                        guard let session else {
                            continuation.yield(nil)
                            continue
                        }
                        let profile = try? await fetchOrCreateProfile(for: session.user)
                        continuation.yield(profile)
                    default:
                        break
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Profiles table

    private func fetchOrCreateProfile(for user: User) async throws -> Profile {
        if let row = try await fetchProfileRow(id: user.id) {
            return row.profile
        }

        let placeholder = ProfileRow.placeholder(for: user.id, email: user.email)
        try await client
            .from("profiles")
            .upsert(placeholder, onConflict: "id", ignoreDuplicates: true)
            .execute()

        if let row = try await fetchProfileRow(id: user.id) {
            return row.profile
        }
        return placeholder.profile
    }

    func saveOnboardingData(userID: UUID, vibes: [String], location: String?) async throws -> Profile {
        struct OnboardingUpdate: Codable {
            let selected_vibes: [String]
            let onboarding_location: String?
        }

        let update = OnboardingUpdate(
            selected_vibes: vibes,
            onboarding_location: location
        )

        try await client
            .from("profiles")
            .update(update)
            .eq("id", value: userID)
            .execute()

        if let row = try await fetchProfileRow(id: userID) {
            return row.profile
        }
        throw NSError(
            domain: "SupabaseAuthRepository",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "Failed to fetch updated profile"]
        )
    }

    /// Returns `nil` only when the profile genuinely does not exist. Network or
    /// decoding failures propagate so callers never mistake an outage for a
    /// missing profile (which previously triggered spurious placeholder upserts).
    private func fetchProfileRow(id: UUID) async throws -> ProfileRow? {
        let rows: [ProfileRow] = try await client
            .from("profiles")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        guard var row = rows.first else { return nil }

        let followerCount: Int = (try? await client
            .from("follows")
            .select("*", head: true, count: .exact)
            .eq("following_id", value: id)
            .execute()
            .count) ?? row.followerCount

        let followingCount: Int = (try? await client
            .from("follows")
            .select("*", head: true, count: .exact)
            .eq("follower_id", value: id)
            .execute()
            .count) ?? row.followingCount

        row.followerCount = followerCount
        row.followingCount = followingCount
        return row
    }
}
