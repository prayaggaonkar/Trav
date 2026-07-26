import SwiftUI

struct AuthEntryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session
    
    let onAuthSuccess: (Bool) -> Void
    let onDismiss: () -> Void

    @State private var showEmailForm = false
    @State private var isSignUpMode = true
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var isInputValid: Bool {
        email.contains("@") && password.count >= 6
    }

    var body: some View {
        ZStack {
            OnboardingBackground()
            
            VStack(alignment: .leading, spacing: 0) {
                // Unified Header
                OnboardingHeaderView(step: nil, showCloseLeft: true, onDismiss: onDismiss)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: TravSpacing.lg) {
                        // Title / Intro visual
                        VStack(alignment: .leading, spacing: TravSpacing.xs) {
                            Text("WELCOME TO TRAV")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(3)
                                .foregroundStyle(TravColors.accent)
                                
                            Text(showEmailForm ? (isSignUpMode ? "Create your account" : "Welcome back") : "Discover new local spots")
                                .font(TravTypography.displayMedium())
                                .foregroundStyle(TravColors.primary)
                                .id(showEmailForm ? "form-title-\(isSignUpMode)" : "intro-title")
                        }
                        .padding(.top, TravSpacing.md)
                        .travAppear()
                        
                        // Local Hangout Polaroid Snapshot Stack
                        HStack {
                            Spacer()
                            PolaroidStack(isSignUpMode: isSignUpMode, email: email)
                            Spacer()
                        }
                        .travAppear(delay: 0.05)
                        
                        if isLoading {
                            ProgressView()
                                .tint(TravColors.accent)
                                .frame(maxWidth: .infinity)
                                .frame(height: 100)
                        } else {
                            VStack(spacing: TravSpacing.md) {
                                if !showEmailForm {
                                    // STAGE 1: Choice buttons
                                    VStack(spacing: TravSpacing.md) {
                                        // Google Sign In Button
                                        Button(action: { Task { await handleGoogleSignIn() } }) {
                                            HStack(spacing: TravSpacing.sm) {
                                                Image(systemName: "g.circle.fill")
                                                    .font(.system(size: 20, weight: .bold))
                                                Text("Continue with Google")
                                                    .font(TravTypography.titleMedium())
                                            }
                                            .foregroundStyle(.white)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: TravLayout.buttonHeight)
                                            .background(Color.white.opacity(0.08))
                                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                            }
                                        }
                                        .buttonStyle(TravPressButtonStyle())
                                        
                                        // Email Button
                                        Button(action: {
                                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                                showEmailForm = true
                                            }
                                        }) {
                                            HStack(spacing: TravSpacing.sm) {
                                                Image(systemName: "envelope.fill")
                                                    .font(.system(size: 16, weight: .bold))
                                                Text("Continue with Email")
                                                    .font(TravTypography.titleMedium())
                                            }
                                            .foregroundStyle(.white)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: TravLayout.buttonHeight)
                                            .background(TravColors.accent)
                                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                                        }
                                        .buttonStyle(TravPressButtonStyle())
                                    }
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .leading).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)
                                    ))
                                } else {
                                    // STAGE 2: Email & Password Form
                                    VStack(spacing: TravSpacing.md) {
                                        // Mode Picker (Sign Up vs Sign In)
                                        HStack(spacing: 0) {
                                            Button(action: { 
                                                withAnimation(TravAnimation.quick) { 
                                                    isSignUpMode = true 
                                                    errorMessage = nil
                                                } 
                                            }) {
                                                Text("New Crew")
                                                    .font(TravTypography.labelMedium())
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(isSignUpMode ? .white : TravColors.muted)
                                                    .frame(maxWidth: .infinity)
                                                    .frame(height: 38)
                                            }
                                            
                                            Button(action: { 
                                                withAnimation(TravAnimation.quick) { 
                                                    isSignUpMode = false 
                                                    errorMessage = nil
                                                } 
                                            }) {
                                                Text("Sign In")
                                                    .font(TravTypography.labelMedium())
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(!isSignUpMode ? .white : TravColors.muted)
                                                    .frame(maxWidth: .infinity)
                                                    .frame(height: 38)
                                            }
                                        }
                                        .padding(2)
                                        .background {
                                            GeometryReader { geo in
                                                RoundedRectangle(cornerRadius: TravRadius.sm, style: .continuous)
                                                    .fill(TravColors.accent)
                                                    .frame(width: geo.size.width / 2)
                                                    .offset(x: isSignUpMode ? 0 : geo.size.width / 2)
                                            }
                                        }
                                        .background(TravColors.surfaceElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.sm, style: .continuous))
                                        .padding(.bottom, TravSpacing.sm)
                                        
                                        // Form fields
                                        VStack(spacing: TravSpacing.md) {
                                            TravTextField(
                                                title: "Email Address",
                                                placeholder: "you@example.com",
                                                text: $email,
                                                contentType: .emailAddress,
                                                keyboardType: .emailAddress
                                            )
                                            
                                            VStack(alignment: .leading, spacing: TravSpacing.xxs) {
                                                Text("Password")
                                                    .font(TravTypography.labelMedium())
                                                    .foregroundStyle(TravColors.muted)
                                                
                                                HStack {
                                                    if isPasswordVisible {
                                                        TextField("At least 6 characters", text: $password)
                                                    } else {
                                                        SecureField("At least 6 characters", text: $password)
                                                    }
                                                    
                                                    Button(action: { isPasswordVisible.toggle() }) {
                                                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                                            .font(.system(size: 14, weight: .medium))
                                                            .foregroundStyle(TravColors.muted)
                                                    }
                                                }
                                                .font(TravTypography.bodyLarge())
                                                .textInputAutocapitalization(.never)
                                                .autocorrectionDisabled()
                                                .padding(TravSpacing.md)
                                                .frame(minHeight: TravLayout.minTouchTarget)
                                                .background(TravColors.surfaceElevated)
                                                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                                        .stroke(TravColors.border.opacity(0.5), lineWidth: 1)
                                                }
                                            }
                                        }
                                        
                                        if let errorMessage {
                                            Text(errorMessage)
                                                .font(TravTypography.caption())
                                                .foregroundStyle(TravColors.error)
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal, TravSpacing.xs)
                                        }
                                        
                                        // Actions
                                        VStack(spacing: TravSpacing.sm) {
                                            PrimaryButton(
                                                title: isSignUpMode ? "Create Account" : "Sign In",
                                                isEnabled: isInputValid,
                                                action: { Task { await handleAuth() } }
                                            )
                                            
                                            Button(action: { 
                                                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { 
                                                    showEmailForm = false 
                                                    errorMessage = nil
                                                } 
                                            }) {
                                                Text("Back to options")
                                                    .font(TravTypography.labelMedium())
                                                    .foregroundStyle(TravColors.muted)
                                            }
                                            .frame(height: 44)
                                        }
                                        .padding(.top, TravSpacing.sm)
                                    }
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .trailing).combined(with: .opacity)
                                    ))
                                }
                            }
                            .travAppear(delay: 0.15)
                        }
                        
                        Text("By continuing, you agree to our Terms and Privacy Policy.")
                            .font(TravTypography.caption())
                            .foregroundStyle(TravColors.muted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, TravSpacing.xs)
                            .travAppear(delay: 0.25)
                    }
                    .padding(.horizontal, TravSpacing.screenHorizontal)
                    .padding(.bottom, 120)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: showEmailForm)
    }

    private func isProfileNewUser(_ profile: Profile) -> Bool {
        let hasVibes = profile.selectedVibes != nil && !profile.selectedVibes!.isEmpty
        let hasLocation = profile.onboardingLocation != nil && !profile.onboardingLocation!.isEmpty
        let hasHomeCity = profile.homeCityName != nil && !profile.homeCityName!.isEmpty
        return !(hasVibes || hasLocation || hasHomeCity)
    }

    private func handleAuth() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            if isSignUpMode {
                try await environment.auth.signUp(email: email, password: password)
                session.phase = .onboarding
                onAuthSuccess(true)
            } else {
                let profile = try await environment.auth.signIn(email: email, password: password)
                session.currentUser = profile
                session.phase = .authenticated
                environment.engagement.cache(profile)
                await environment.engagement.bootstrap(userID: profile.id, using: environment)
                onAuthSuccess(false)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleGoogleSignIn() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let profile = try await environment.auth.signInWithGoogle()
            session.currentUser = profile
            let isNew = isProfileNewUser(profile)
            session.phase = isNew ? .onboarding : .authenticated
            environment.engagement.cache(profile)
            await environment.engagement.bootstrap(userID: profile.id, using: environment)
            onAuthSuccess(isNew)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Polaroid Stack Component

struct PolaroidStack: View {
    let isSignUpMode: Bool
    let email: String
    
    var body: some View {
        ZStack {
            // Night Lounge Polaroid (Back when SignUp, Front when SignIn)
            PolaroidView(
                title: "LOUNGE",
                iconName: "wineglass.fill",
                caption: "🍷 Lounge Vibes / Member Pass",
                email: email,
                themeGradient: LinearGradient(
                    colors: [Color(red: 0.48, green: 0.18, blue: 0.95), Color(red: 0.06, green: 0.03, blue: 0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .rotationEffect(.degrees(isSignUpMode ? -8 : 0))
            .offset(x: isSignUpMode ? -15 : 0, y: isSignUpMode ? 10 : 0)
            .scaleEffect(isSignUpMode ? 0.92 : 1.0)
            .zIndex(isSignUpMode ? 0 : 1)
            
            // Day Cafe Polaroid (Front when SignUp, Back when SignIn)
            PolaroidView(
                title: "CAFE",
                iconName: "cup.and.saucer.fill",
                caption: "☕️ Cafe Vibes / Crew Pass",
                email: email,
                themeGradient: LinearGradient(
                    colors: [Color(red: 0.12, green: 0.58, blue: 0.68), Color(red: 0.25, green: 0.18, blue: 0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .rotationEffect(.degrees(isSignUpMode ? 0 : 8))
            .offset(x: isSignUpMode ? 0 : 15, y: isSignUpMode ? 0 : 10)
            .scaleEffect(isSignUpMode ? 1.0 : 0.92)
            .zIndex(isSignUpMode ? 1 : 0)
        }
        .frame(height: 195)
        .padding(.vertical, TravSpacing.md)
        .animation(.spring(response: 0.55, dampingFraction: 0.75), value: isSignUpMode)
    }
}

struct PolaroidView: View {
    let title: String
    let iconName: String
    let caption: String
    let email: String
    let themeGradient: LinearGradient
    
    var body: some View {
        VStack(spacing: 0) {
            // Photo Area
            ZStack {
                themeGradient
                
                Image(systemName: iconName)
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(0.5), radius: 8, y: 4)
            }
            .frame(height: 110)
            .clipped()
            .padding(10)
            
            // Bottom Polaroid caption area
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundStyle(Color.black)
                
                Text(email.isEmpty ? "Captured by: guest explorer" : "Captured by: \(email)")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.6))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white) // Classic white Polaroid paper
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: Color.black.opacity(0.3), radius: 8, y: 4)
        .frame(width: 200)
    }
}

#Preview {
    AuthEntryView(
        onAuthSuccess: { _ in },
        onDismiss: {}
    )
    .environment(AppEnvironment.live)
}



