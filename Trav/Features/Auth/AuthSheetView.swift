import AuthenticationServices
import SwiftUI

struct AuthSheetView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    enum AuthMode: String, CaseIterable {
        case signIn = "Sign In"
        case signUp = "Sign Up"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TravSpacing.lg) {
                    header
                        .travAppear()

                    modePicker
                        .travAppear(delay: 0.05)

                    formFields
                        .travAppear(delay: 0.1)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(TravTypography.caption())
                            .foregroundStyle(TravColors.error)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    PrimaryButton(title: primaryActionTitle, isLoading: isLoading) {
                        Task { await submit() }
                    }
                    .travAppear(delay: 0.15)

                    SecondaryButton("Continue with Google", icon: "globe") {
                        Task { await signInWithGoogle() }
                    }
                        .travAppear(delay: 0.2)

                    footerLinks
                        .travAppear(delay: 0.25)
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.top, TravSpacing.md)
                .padding(.bottom, TravSpacing.xl)
                .safeAreaPadding(.bottom, TravSpacing.sm)
            }
            .travScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { router.dismissAuth() }
                        .font(TravTypography.labelMedium())
                        .foregroundStyle(TravColors.muted)
                }
            }
        }
        .animation(TravAnimation.quick, value: errorMessage)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: TravSpacing.xs) {
            Text("Welcome to Trav")
                .font(TravTypography.displayMedium())
                .foregroundStyle(TravColors.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
            Text("Discover real experiences from real people.")
                .font(TravTypography.bodyMedium())
                .foregroundStyle(TravColors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(AuthMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var formFields: some View {
        VStack(spacing: TravSpacing.md) {
            TravTextField(
                title: "Email",
                placeholder: "you@example.com",
                text: $email,
                contentType: .emailAddress,
                keyboardType: .emailAddress
            )

            TravTextField(
                title: "Password",
                placeholder: "Enter your password",
                text: $password,
                contentType: mode == .signUp ? .newPassword : .password,
                isSecure: true
            )
        }
    }

    private var footerLinks: some View {
        VStack(spacing: TravSpacing.sm) {
            if mode == .signIn {
                Button("Forgot password?") {}
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(TravColors.accent)
            }
            Text("Verify email or set up 2FA in Settings after signing in.")
                .font(TravTypography.caption())
                .foregroundStyle(TravColors.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var primaryActionTitle: String {
        mode == .signIn ? "Sign In" : "Create Account"
    }

    private func submit() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            switch mode {
            case .signIn:
                let profile = try await environment.auth.signIn(email: email, password: password)
                session.currentUser = profile
                session.phase = .authenticated
                environment.engagement.cache(profile)
                await environment.engagement.bootstrap(userID: profile.id, using: environment)
            case .signUp:
                try await environment.auth.signUp(email: email, password: password)
                session.phase = .onboarding
            }
            router.dismissAuth()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let profile = try await environment.auth.signInWithGoogle()
            session.currentUser = profile
            session.phase = profile.needsOnboarding ? .onboarding : .authenticated
            environment.engagement.cache(profile)
            await environment.engagement.bootstrap(userID: profile.id, using: environment)
            router.dismissAuth()
        } catch {
            let nsError = error as NSError
            if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
               nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}
