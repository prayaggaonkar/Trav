import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
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
                            dismiss()
                        },
                        onDismiss: {
                            dismiss()
                        }
                    )
                }
            }
        }
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

#Preview {
    OnboardingView()
        .environment(AppRouter())
}

