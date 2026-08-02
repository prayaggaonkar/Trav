import SwiftUI

// MARK: - Animated Purple Splash Screen & Apple "hello"-Style Welcome Screen

struct AnimatedSplashScreenView: View {
    let isLoading: Bool
    let currentUser: Profile?
    @Binding var isFinished: Bool

    // Purple Splash Layer States
    @State private var splashOpacity: Double = 1.0
    @State private var pinScale: CGFloat = 0.2
    @State private var pinOffset: CGFloat = -120
    @State private var rippleScale1: CGFloat = 0.4
    @State private var rippleOpacity1: Double = 0.8
    @State private var rippleScale2: CGFloat = 0.4
    @State private var rippleOpacity2: Double = 0.8

    // Explore-Style Celestial Welcome States
    @State private var celestialWelcomeOpacity: Double = 1.0
    @State private var textMaskWidth: CGFloat = 0
    @State private var subtitleOpacity: Double = 0.0

    private var userName: String {
        guard let user = currentUser else { return "Traveler" }
        let name = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "@\(user.username)" : name
    }

    private var helloMessage: String {
        "hello \(userName)"
    }

    // Multilingual greetings matching Apple's iconic setup screen
    private let backgroundGreetingsRows = [
        ["salut", "olá", "cəлəм", "hallo"],
        ["hola", "hej", "ciao", "ahoj", "olá"],
        ["helo", "hello", "hei", "مرحبا"],
        ["привіт", "привет", "bonjour"],
        ["chào", "χαίρετε", "こんにちは"]
    ]

    var body: some View {
        ZStack {
            if !isFinished {
                // Layer 1: Explore Celestial Background with Apple "hello" Cursive Script (Logged In Users)
                if currentUser != nil {
                    ZStack {
                        // Explore Page Celestial Background (Dark purple gradient + dot grid)
                        HomeCelestialBackground()
                            .ignoresSafeArea()

                        // Apple "hello" Multilingual Background Wallpaper Grid (Subtle translucency)
                        VStack(spacing: 36) {
                            ForEach(0..<backgroundGreetingsRows.count, id: \.self) { rowIndex in
                                HStack(spacing: 32) {
                                    ForEach(backgroundGreetingsRows[rowIndex], id: \.self) { word in
                                        Text(word)
                                            .font(appleHelloBackgroundFont)
                                            .foregroundStyle(Color.white.opacity(word == "hello" ? 0.0 : 0.12))
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()

                        // Foreground Centerpiece: Subtitle + Bright Glowing Apple "hello" Calligraphy
                        VStack(spacing: 16) {
                            // Subtitle: WELCOME BACK
                            Text("WELCOME BACK")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(6)
                                .foregroundStyle(Color.white.opacity(0.55))
                                .opacity(subtitleOpacity)

                            // Apple "hello" Iconic Cursive Calligraphy with Smooth Writing Unroll
                            ZStack(alignment: .leading) {
                                Text(helloMessage)
                                    .font(appleHelloFont)
                                    .foregroundStyle(.white)
                                    .shadow(color: Color.white.opacity(0.8), radius: 20, x: 0, y: 0)
                                    .mask(
                                        HStack(spacing: 0) {
                                            Rectangle()
                                                .frame(width: textMaskWidth)
                                            Spacer(minLength: 0)
                                        }
                                    )
                            }
                        }
                        .padding(.horizontal, 36)
                    }
                    .opacity(celestialWelcomeOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(999_998)
                }

                // Layer 2: Purple Pin Animated Splash (Top Layer)
                ZStack {
                    // Logo Purple Background (#B368FF)
                    Color(red: 0.700, green: 0.409, blue: 0.997)
                        .ignoresSafeArea()

                    // Radar Ripple Waves
                    Circle()
                        .stroke(Color.white.opacity(rippleOpacity1), lineWidth: 2)
                        .frame(width: 140, height: 140)
                        .scaleEffect(rippleScale1)

                    Circle()
                        .stroke(Color.white.opacity(rippleOpacity2), lineWidth: 1.5)
                        .frame(width: 140, height: 140)
                        .scaleEffect(rippleScale2)

                    // Pin & Branding
                    VStack(spacing: 20) {
                        Image(systemName: "mappin.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 84, height: 84)
                            .foregroundStyle(.white)
                            .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 6)
                            .scaleEffect(pinScale)
                            .offset(y: pinOffset)

                        VStack(spacing: 6) {
                            Text("TRAV")
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .tracking(6)
                                .foregroundStyle(.white)
                                .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 3)

                            Text("EXPLORE • RECOMMEND • EXPERIENCE")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(2.5)
                                .foregroundStyle(Color.white.opacity(0.85))
                        }
                        .opacity(pinScale > 0.8 ? 1 : 0)
                    }
                }
                .opacity(splashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .zIndex(999_999)
            }
        }
        .onAppear {
            startSplashAnimations()
        }
        .onChange(of: isLoading, initial: true) { _, loading in
            if !loading {
                handleLoadingComplete()
            }
        }
    }

    private var appleHelloFont: Font {
        if UIFont(name: "SignPainter-HouseScript", size: 48) != nil {
            return .custom("SignPainter-HouseScript", size: 48)
        } else if UIFont(name: "BradleyHandITCTT-Bold", size: 46) != nil {
            return .custom("BradleyHandITCTT-Bold", size: 46)
        } else if UIFont(name: "Noteworthy-Bold", size: 44) != nil {
            return .custom("Noteworthy-Bold", size: 44)
        } else if UIFont(name: "ChalkboardSE-Regular", size: 44) != nil {
            return .custom("ChalkboardSE-Regular", size: 44)
        } else if UIFont(name: "SnellRoundhand-Bold", size: 48) != nil {
            return .custom("SnellRoundhand-Bold", size: 48)
        } else {
            return .system(size: 46, weight: .medium, design: .serif).italic()
        }
    }

    private var appleHelloBackgroundFont: Font {
        if UIFont(name: "SignPainter-HouseScript", size: 28) != nil {
            return .custom("SignPainter-HouseScript", size: 28)
        } else if UIFont(name: "BradleyHandITCTT-Bold", size: 26) != nil {
            return .custom("BradleyHandITCTT-Bold", size: 26)
        } else if UIFont(name: "Noteworthy-Bold", size: 24) != nil {
            return .custom("Noteworthy-Bold", size: 24)
        } else {
            return .system(size: 26, weight: .medium, design: .serif).italic()
        }
    }

    private func startSplashAnimations() {
        // Pin Drop & Spring Bounce
        withAnimation(.spring(response: 0.6, dampingFraction: 0.55)) {
            pinScale = 1.0
            pinOffset = 0
        }

        // Radar Ripple Loop
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
            rippleScale1 = 2.2
            rippleOpacity1 = 0.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
                rippleScale2 = 2.2
                rippleOpacity2 = 0.0
            }
        }
    }

    private func handleLoadingComplete() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if currentUser != nil {
                // User IS logged in -> Dissolve purple splash layer smoothly to reveal Explore celestial background
                withAnimation(.easeInOut(duration: 0.5)) {
                    splashOpacity = 0.0
                }

                // Animate WELCOME BACK subtitle and Apple "hello" handwriting mask reveal
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        subtitleOpacity = 1.0
                    }
                    withAnimation(.easeInOut(duration: 1.3)) {
                        textMaskWidth = 500
                    }
                }

                // Hold welcome screen for 0.8s, then smoothly dissolve to reveal main Explore page
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.95) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        celestialWelcomeOpacity = 0.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isFinished = true
                        }
                    }
                }
            } else {
                // User NOT logged in -> Dissolve purple splash layer directly into main app
                withAnimation(.easeInOut(duration: 0.5)) {
                    splashOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isFinished = true
                    }
                }
            }
        }
    }
}

// MARK: - View Modifier Extension

extension View {
    /// Applies animated purple pin splash screen and Apple "hello"-style celestial welcome screen overlay.
    func animatedSplashScreen(isLoading: Bool, currentUser: Profile?, isFinished: Binding<Bool>) -> some View {
        self.overlay {
            AnimatedSplashScreenView(isLoading: isLoading, currentUser: currentUser, isFinished: isFinished)
        }
    }
}
