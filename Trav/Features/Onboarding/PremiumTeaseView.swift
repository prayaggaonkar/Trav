import SwiftUI

struct PremiumTeaseView: View {
    let onViewPlans: () -> Void
    let onDismiss: () -> Void
    
    @State private var pulseSparkle = false

    var body: some View {
        ZStack {
            OnboardingBackground()
            
            VStack(alignment: .leading, spacing: 0) {
                // Header with dismiss X
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(TravColors.primary)
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.top, TravSpacing.md)
                
                // Progress Bar
                OnboardingProgressBar(currentStep: 4)
                    .padding(.bottom, TravSpacing.lg)

                ScrollView {
                    VStack(alignment: .center, spacing: TravSpacing.lg) {
                        Spacer()
                            .frame(height: TravSpacing.xs)

                        // Premium Icon
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.15), Color(red: 1.0, green: 0.3, blue: 0.2).opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 100, height: 100)

                            Image(systemName: "sparkles")
                                .font(.system(size: 44, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.7, blue: 0.1), Color(red: 1.0, green: 0.35, blue: 0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .scaleEffect(pulseSparkle ? 1.1 : 0.95)
                                .rotationEffect(.degrees(pulseSparkle ? 10 : -10))
                                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulseSparkle)
                        }
                        .travAppear()
                        .onAppear { pulseSparkle = true }

                        // Title
                        VStack(spacing: TravSpacing.xs) {
                            Text("Trav Pro")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white, Color(red: 1.0, green: 0.75, blue: 0.5)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            Text("Unlock the full potential of your travels")
                                .font(TravTypography.bodyMedium())
                                .foregroundStyle(TravColors.muted)
                                .multilineTextAlignment(.center)
                        }
                        .travAppear(delay: 0.05)

                        // Features List
                        VStack(spacing: TravSpacing.md) {
                            PremiumFeatureRow(
                                icon: "sparkles",
                                title: "Curated Itineraries",
                                description: "Hand-picked travel plans tailored to your style"
                            )

                            PremiumFeatureRow(
                                icon: "film",
                                title: "TikTok-Inspired Plans",
                                description: "Trending experiences and viral-worthy moments"
                            )

                            PremiumFeatureRow(
                                icon: "map.fill",
                                title: "Unlimited Gems",
                                description: "Access to all hidden local recommendations"
                            )
                        }
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                        .travAppear(delay: 0.1)

                        Spacer()
                    }
                }
            }

            // Fixed bottom buttons
            VStack(spacing: TravSpacing.sm) {
                // Pulsing premium button
                Button(action: onViewPlans) {
                    Text("View Plans")
                        .font(TravTypography.titleMedium())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: TravLayout.buttonHeight)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.6, blue: 0.0), Color(red: 1.0, green: 0.3, blue: 0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                        .shadow(color: Color(red: 1.0, green: 0.4, blue: 0.1).opacity(0.35), radius: 12, y: 5)
                }
                .buttonStyle(TravPressButtonStyle())
                .travAppear(delay: 0.15)

                Button(action: onDismiss) {
                    Text("Start exploring for free")
                        .font(TravTypography.labelMedium())
                        .foregroundStyle(TravColors.muted)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .travAppear(delay: 0.2)
            }
            .padding(TravSpacing.screenHorizontal)
            .padding(.bottom, TravSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarBackButtonHidden()
    }
}

private struct PremiumFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: TravSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 38, height: 38)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [TravColors.accent, Color(red: 1.0, green: 0.65, blue: 0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: TravSpacing.xxs) {
                Text(title)
                    .font(TravTypography.titleMedium())
                    .foregroundStyle(.white)

                Text(description)
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.muted)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(TravSpacing.md)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

#Preview {
    PremiumTeaseView(
        onViewPlans: {},
        onDismiss: {}
    )
}

