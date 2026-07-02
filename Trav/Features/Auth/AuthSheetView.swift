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
                    modePicker
                    formFields
                    if let errorMessage {
                        Text(errorMessage)
                            .font(TravTypography.caption())
                            .foregroundStyle(.red)
                    }
                    PrimaryButton(title: primaryActionTitle, isLoading: isLoading) {
                        Task { await submit() }
                    }
                    googleButton
                    footerLinks
                }
                .padding(TravSpacing.screenHorizontal)
                .padding(.top, TravSpacing.md)
            }
            .background(TravColors.surface)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome to Trav")
                .font(TravTypography.displayMedium())
                .foregroundStyle(TravColors.primary)
            Text("Discover real experiences from real people.")
                .font(TravTypography.bodyMedium())
                .foregroundStyle(TravColors.muted)
        }
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
        VStack(spacing: TravSpacing.sm) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding()
                .background(TravColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))

            SecureField("Password", text: $password)
                .textContentType(mode == .signUp ? .newPassword : .password)
                .padding()
                .background(TravColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
        }
    }

    private var googleButton: some View {
        Button {} label: {
            HStack {
                Image(systemName: "globe")
                Text("Continue with Google")
                    .font(TravTypography.titleMedium())
            }
            .foregroundStyle(TravColors.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(TravColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var footerLinks: some View {
        VStack(spacing: TravSpacing.sm) {
            if mode == .signIn {
                Button("Forgot password?") {}
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(TravColors.accent)
            }
            Button("Verify email or set up 2FA in Settings after signing in.") {}
                .font(TravTypography.caption())
                .foregroundStyle(TravColors.muted)
                .multilineTextAlignment(.center)
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
            case .signUp:
                try await environment.auth.signUp(email: email, password: password)
                session.phase = .onboarding
            }
            router.dismissAuth()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
