import Foundation
import Supabase

/// Production `AuthRepository` backed by Supabase Auth and the `profiles` table.
struct SupabaseAuthRepository: AuthRepository {
    private var client: SupabaseClient {
        guard let client = SupabaseManager.client else {
            preconditionFailure("SupabaseAuthRepository used without a configured SupabaseClient.")
        }
        return client
    }

    func signIn(email: String, password: String) async throws -> Profile {
        let session = try await client.auth.signIn(email: email, password: password)
        return try await fetchOrCreateProfile(for: session.user)
    }

    func signUp(email: String, password: String) async throws {
        _ = try await client.auth.signUp(email: email, password: password)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email, redirectTo: AppConfiguration.oauthRedirectURL)
    }

    func signInWithGoogle() async throws -> Profile {
        let session = try await client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: AppConfiguration.oauthRedirectURL
        )
        return try await fetchOrCreateProfile(for: session.user)
    }

    /// Emits the current session immediately, then every subsequent sign-in/out/refresh event.
    /// Mirrors `AuthClient.authStateChanges`, resolving each session into an app `Profile`.
    func authStateChanges() -> AsyncStream<Profile?> {
        AsyncStream { continuation in
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

    /// Looks up the `profiles` row for a Supabase Auth user. Onboarding is expected to have
    /// created this row already; if it's missing (e.g. testing before onboarding ships) a
    /// minimal placeholder profile is provisioned so authentication still succeeds end to end.
    ///
    /// This can legitimately be called concurrently for the same brand-new user — e.g. the
    /// explicit call from `signIn`/`signInWithGoogle` races with the `authStateChanges()`
    /// listener reacting to the same `.signedIn` event. Creation is done as an idempotent
    /// upsert (ignoring conflicts on the primary key) so that race never throws a duplicate
    /// key error; whichever call wins, both end up returning the same persisted row.
    private func fetchOrCreateProfile(for user: User) async throws -> Profile {
        if let row = try await fetchProfileRow(id: user.id) {
            return row.profile
        }

        let placeholder = ProfileRow.placeholder(for: user)
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
        
        let update = OnboardingUpdate(selected_vibes: vibes, onboarding_location: location)
        
        try await client
            .from("profiles")
            .update(update)
            .eq("id", value: userID)
            .execute()
            
        if let row = try await fetchProfileRow(id: userID) {
            return row.profile
        }
        throw NSError(domain: "SupabaseAuthRepository", code: 404, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch updated profile"])
    }

    private func fetchProfileRow(id: UUID) async throws -> ProfileRow? {
        do {
            return try await client
                .from("profiles")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value
        } catch {
            return nil
        }
    }
}

/// `profiles` table row, mapped to the app's `Profile` model. See `docs/DATABASE_SCHEMA.md`.
private struct ProfileRow: Codable {
    var id: UUID
    var username: String
    var displayName: String
    var bio: String?
    var avatarURL: URL?
    var homeCityID: UUID?
    var followerCount: Int
    var followingCount: Int
    var experienceCount: Int
    var completionCount: Int
    var isVerified: Bool
    var selectedVibes: [String]?
    var onboardingLocation: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case bio
        case avatarURL = "avatar_url"
        case homeCityID = "home_city_id"
        case followerCount = "follower_count"
        case followingCount = "following_count"
        case experienceCount = "experience_count"
        case completionCount = "completion_count"
        case isVerified = "is_verified"
        case selectedVibes = "selected_vibes"
        case onboardingLocation = "onboarding_location"
    }

    var profile: Profile {
        Profile(
            id: id,
            username: username,
            displayName: displayName,
            bio: bio,
            avatarURL: avatarURL,
            homeCityID: homeCityID,
            followerCount: followerCount,
            followingCount: followingCount,
            experienceCount: experienceCount,
            completionCount: completionCount,
            isVerified: isVerified,
            selectedVibes: selectedVibes,
            onboardingLocation: onboardingLocation
        )
    }

    static func placeholder(for user: User) -> ProfileRow {
        let localPart = user.email?.split(separator: "@").first.map(String.init) ?? "traveler"
        let suffix = String(user.id.uuidString.prefix(4)).lowercased()
        return ProfileRow(
            id: user.id,
            username: "\(localPart.lowercased())\(suffix)",
            displayName: localPart.capitalized,
            bio: nil,
            avatarURL: nil,
            homeCityID: nil,
            followerCount: 0,
            followingCount: 0,
            experienceCount: 0,
            completionCount: 0,
            isVerified: false,
            selectedVibes: [],
            onboardingLocation: nil
        )
    }
}
