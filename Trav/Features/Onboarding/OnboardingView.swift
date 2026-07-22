import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session
    @State private var navigationPath = NavigationPath()
    @State private var selectedVibes: Set<String> = []
    @State private var selectedLocation: String?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            AuthEntryView(
                onAuthSuccess: { isNewUser in
                    if isNewUser {
                        withAnimation(TravAnimation.enter) {
                            navigationPath.append(OnboardingStep.vibeSelection)
                        }
                    } else {
                        dismiss()
                    }
                },
                onDismiss: {
                    dismiss()
                }
            )
            .navigationDestination(for: OnboardingStep.self) { step in
                switch step {
                case .vibeSelection:
                    VibeSelectionView(
                        selectedVibes: $selectedVibes,
                        onContinue: {
                            navigationPath.append(OnboardingStep.locationContext)
                        },
                        onSkip: {
                            navigationPath.append(OnboardingStep.locationContext)
                        },
                        onBack: {
                            navigationPath.removeLast()
                        }
                    )
                case .locationContext:
                    LocationContextView(
                        selectedLocation: $selectedLocation,
                        onContinue: {
                            navigationPath.append(OnboardingStep.socialSync)
                        },
                        onSkip: {
                            navigationPath.append(OnboardingStep.socialSync)
                        },
                        onBack: {
                            navigationPath.removeLast()
                        }
                    )
                case .socialSync:
                    SocialSyncView(
                        onContinue: {
                            navigationPath.append(OnboardingStep.premiumTease)
                        },
                        onSkip: {
                            navigationPath.append(OnboardingStep.premiumTease)
                        },
                        onBack: {
                            navigationPath.removeLast()
                        }
                    )
                case .premiumTease:
                    PremiumTeaseView(
                        onViewPlans: {
                            Task {
                                await saveAndCompleteOnboarding()
                            }
                        },
                        onDismiss: {
                            Task {
                                await saveAndCompleteOnboarding()
                            }
                        }
                    )
                }
            }
        }
    }

    private func saveAndCompleteOnboarding() async {
        guard let currentUser = session.currentUser else {
            dismiss()
            return
        }
        
        let vibesList = Array(selectedVibes)
        let locationName = selectedLocation
        
        do {
            let updatedProfile = try await environment.auth.saveOnboardingData(
                userID: currentUser.id,
                vibes: vibesList,
                location: locationName
            )
            session.currentUser = updatedProfile
            session.phase = .authenticated
            environment.engagement.cache(updatedProfile)
            await environment.engagement.bootstrap(userID: updatedProfile.id, using: environment)
        } catch {
            print("Failed to save onboarding data: \(error)")
        }
        dismiss()
    }
}

enum OnboardingStep: Hashable {
    case vibeSelection
    case locationContext
    case socialSync
    case premiumTease
}

// MARK: - Shared Onboarding UI Components

struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.03, blue: 0.04)
                .ignoresSafeArea()
            
            // Subtle Dotted Grid Background
            DottedGridView()
                .ignoresSafeArea()
            
            // Top-right orange glow
            RadialGradient(
                colors: [TravColors.accent.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()
            
            // Bottom-left blue glow
            RadialGradient(
                colors: [Color(red: 0.2, green: 0.45, blue: 0.95).opacity(0.08), .clear],
                center: .bottomLeading,
                startRadius: 50,
                endRadius: 450
            )
            .ignoresSafeArea()
        }
    }
}

struct OnboardingProgressBar: View {
    let currentStep: Int // 1 to 4
    let totalSteps = 4
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? TravColors.accent : Color.white.opacity(0.12))
                    .frame(height: 5)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.vertical, TravSpacing.sm)
    }
}

struct OnboardingHeaderView: View {
    let step: Int? // 1 to 4, or nil
    var showCloseLeft = false
    var showCloseRight = false
    var onBack: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: TravSpacing.xs) {
            HStack(alignment: .center) {
                // Left Side
                if let onBack {
                    Button(action: onBack) {
                        HStack(spacing: TravSpacing.xxs) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .bold))
                            Text("Back")
                                .font(TravTypography.labelMedium())
                        }
                        .foregroundStyle(TravColors.primary)
                    }
                    .buttonStyle(TravPressButtonStyle(scale: 0.96))
                } else if showCloseLeft, let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(TravColors.primary)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer()
                        .frame(width: 44, height: 36)
                }
                
                Spacer()
                
                // Right Side
                if let onSkip {
                    Button(action: onSkip) {
                        Text("Skip")
                            .font(TravTypography.labelMedium())
                            .foregroundStyle(TravColors.muted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(TravPressButtonStyle(scale: 0.95))
                } else if showCloseRight, let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(TravColors.primary)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer()
                        .frame(width: 44, height: 36)
                }
            }
            .frame(height: 44)
            .padding(.horizontal, TravSpacing.screenHorizontal)
            
            if let step {
                OnboardingProgressBar(currentStep: step)
            }
        }
        .padding(.top, TravSpacing.md)
    }
}

#Preview {
    OnboardingView()
        .environment(AppRouter())
}

