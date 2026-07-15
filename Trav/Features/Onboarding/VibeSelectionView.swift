import SwiftUI

struct VibeSelectionView: View {
    @Binding var selectedVibes: Set<String>
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void

    let vibes = [
        "☕️ Hidden Cafes",
        "🌙 Nightlife",
        "🌅 Scenic Views",
        "🛍️ Vintage Shops",
        "🎨 Street Art",
        "🍲 Local Markets",
        "🍷 Rooftop Bars",
        "🥾 Nature Trails"
    ]

    var isSelectionValid: Bool {
        !selectedVibes.isEmpty
    }

    var body: some View {
        ZStack {
            OnboardingBackground()
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: TravSpacing.xxs) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Back")
                                .font(TravTypography.bodyMedium())
                        }
                        .foregroundStyle(TravColors.primary)
                        .frame(height: 44)
                    }
                    
                    Spacer()
                    
                    Button(action: onSkip) {
                        Text("Skip")
                            .font(TravTypography.bodyMedium())
                            .foregroundStyle(TravColors.muted)
                            .frame(height: 44)
                    }
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.top, TravSpacing.md)
                
                // Progress Bar
                OnboardingProgressBar(currentStep: 1)
                    .padding(.bottom, TravSpacing.lg)

                ScrollView {
                    VStack(alignment: .leading, spacing: TravSpacing.lg) {
                        // Title
                        VStack(alignment: .leading, spacing: TravSpacing.xs) {
                            Text("What's your travel style?")
                                .font(TravTypography.displayMedium())
                                .foregroundStyle(TravColors.primary)
                            Text("Select the experiences you love the most.")
                                .font(TravTypography.bodyMedium())
                                .foregroundStyle(TravColors.muted)
                        }
                        .travAppear()

                        Spacer()
                            .frame(height: TravSpacing.xs)

                        // Vibe Grid
                        VStack(spacing: TravSpacing.md) {
                            ForEach(Array(stride(from: 0, to: vibes.count, by: 2)), id: \.self) { index in
                                HStack(spacing: TravSpacing.md) {
                                    VibeSelectionChip(
                                        title: vibes[index],
                                        isSelected: selectedVibes.contains(vibes[index]),
                                        action: {
                                            withAnimation(TravAnimation.quick) {
                                                if selectedVibes.contains(vibes[index]) {
                                                    selectedVibes.remove(vibes[index])
                                                } else {
                                                    selectedVibes.insert(vibes[index])
                                                }
                                            }
                                        }
                                    )

                                    if index + 1 < vibes.count {
                                        VibeSelectionChip(
                                            title: vibes[index + 1],
                                            isSelected: selectedVibes.contains(vibes[index + 1]),
                                            action: {
                                                withAnimation(TravAnimation.quick) {
                                                    if selectedVibes.contains(vibes[index + 1]) {
                                                        selectedVibes.remove(vibes[index + 1])
                                                    } else {
                                                        selectedVibes.insert(vibes[index + 1])
                                                    }
                                                }
                                            }
                                        )
                                    } else {
                                        Spacer()
                                    }
                                }
                                .travAppear(delay: Double(index) * 0.04)
                            }
                        }
                    }
                    .padding(.horizontal, TravSpacing.screenHorizontal)
                    .padding(.bottom, 120)
                }
            }

            // Fixed bottom button
            VStack(spacing: TravSpacing.sm) {
                PrimaryButton(
                    title: "Continue",
                    isEnabled: isSelectionValid,
                    action: onContinue
                )
                .travAppear(delay: 0.2)

                Text(selectedVibes.isEmpty ? "Select at least one style" : "\(selectedVibes.count) vibe\(selectedVibes.count != 1 ? "s" : "") selected")
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
                    .frame(maxWidth: .infinity)
                    .travAppear(delay: 0.25)
            }
            .padding(TravSpacing.screenHorizontal)
            .padding(.bottom, TravSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarBackButtonHidden()
    }
}

private struct VibeSelectionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(TravTypography.bodyMedium())
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background {
                    if isSelected {
                        LinearGradient(
                            colors: [TravColors.accent, Color(red: 1.0, green: 0.5, blue: 0.28)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        Color.white.opacity(0.06)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                        .stroke(
                            isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.1),
                            lineWidth: 1
                        )
                }
                .shadow(color: isSelected ? TravColors.accent.opacity(0.2) : Color.clear, radius: 8, y: 3)
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.96))
    }
}

#Preview {
    @Previewable @State var selectedVibes: Set<String> = []
    return VibeSelectionView(
        selectedVibes: $selectedVibes,
        onContinue: {},
        onSkip: {},
        onBack: {}
    )
}

