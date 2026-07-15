import SwiftUI

struct LocationContextView: View {
    @Binding var selectedLocation: String?
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void

    @State private var searchText = ""

    let popularCities = [
        "🗽 New York",
        "🗼 Tokyo",
        "🇪🇸 Barcelona",
        "🇫🇷 Paris",
        "🇹🇭 Bangkok",
        "🇬🇧 London",
        "🐫 Dubai",
        "🇳🇱 Amsterdam",
        "🇸🇬 Singapore",
        "🐨 Sydney"
    ]

    var displayedCities: [String] {
        if searchText.isEmpty {
            return popularCities
        } else {
            return popularCities.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var isLocationSelected: Bool {
        selectedLocation != nil
    }

    var body: some View {
        ZStack {
            OnboardingBackground()
            
            VStack(alignment: .leading, spacing: 0) {
                // Unified Header
                OnboardingHeaderView(step: 2, onBack: onBack, onSkip: onSkip)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: TravSpacing.lg) {
                        // Title
                        VStack(alignment: .leading, spacing: TravSpacing.xs) {
                            Text("Where to next?")
                                .font(TravTypography.displayMedium())
                                .foregroundStyle(TravColors.primary)
                            Text("We'll show you the best local spots nearby.")
                                .font(TravTypography.bodyMedium())
                                .foregroundStyle(TravColors.muted)
                        }
                        .padding(.top, TravSpacing.md)
                        .travAppear()

                        // Search Bar
                        HStack(spacing: TravSpacing.sm) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(TravColors.muted)

                            TextField("Search destination...", text: $searchText)
                                .font(TravTypography.bodyMedium())
                                .textInputAutocapitalization(.words)
                                .foregroundStyle(.white)
                        }
                        .padding(TravSpacing.md)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        }
                        .travAppear(delay: 0.08)

                        // Current Location Row
                        Button(action: {
                            withAnimation(TravAnimation.quick) {
                                selectedLocation = "Current Location"
                            }
                        }) {
                            HStack(spacing: TravSpacing.md) {
                                ZStack {
                                    Circle()
                                        .fill(TravColors.accentSoft)
                                        .frame(width: 36, height: 36)
                                    
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(TravColors.accent)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Use my current location")
                                        .font(TravTypography.bodyMedium())
                                        .fontWeight(.semibold)
                                        .foregroundStyle(TravColors.primary)
                                    Text("Find gems around you right now")
                                        .font(TravTypography.caption())
                                        .foregroundStyle(TravColors.muted)
                                }

                                Spacer()

                                if selectedLocation == "Current Location" {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(TravColors.accent)
                                } else {
                                    Circle()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 2)
                                        .frame(width: 22, height: 22)
                                }
                            }
                            .padding(TravSpacing.md)
                            .background(Color.white.opacity(selectedLocation == "Current Location" ? 0.08 : 0.04))
                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                    .stroke(
                                        selectedLocation == "Current Location" ? TravColors.accent : Color.white.opacity(0.1),
                                        lineWidth: 1
                                    )
                            }
                        }
                        .buttonStyle(TravPressButtonStyle(scale: 0.98))
                        .travAppear(delay: 0.12)

                        // Popular Cities Section
                        VStack(alignment: .leading, spacing: TravSpacing.sm) {
                            Text("Popular Destinations")
                                .font(TravTypography.titleMedium())
                                .foregroundStyle(TravColors.primary)
                                .padding(.bottom, TravSpacing.xxs)
                            
                            // 2-column Grid of City Chips
                            let cities = displayedCities
                            VStack(spacing: TravSpacing.md) {
                                ForEach(Array(stride(from: 0, to: cities.count, by: 2)), id: \.self) { index in
                                    HStack(spacing: TravSpacing.md) {
                                        CitySelectionChip(
                                            title: cities[index],
                                            isSelected: selectedLocation == cities[index],
                                            action: {
                                                withAnimation(TravAnimation.quick) {
                                                    selectedLocation = cities[index]
                                                }
                                            }
                                        )

                                        if index + 1 < cities.count {
                                            CitySelectionChip(
                                                title: cities[index + 1],
                                                isSelected: selectedLocation == cities[index + 1],
                                                action: {
                                                    withAnimation(TravAnimation.quick) {
                                                        selectedLocation = cities[index + 1]
                                                    }
                                                }
                                            )
                                        } else {
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }
                        .travAppear(delay: 0.16)
                    }
                    .padding(.horizontal, TravSpacing.screenHorizontal)
                    .padding(.bottom, 120)
                }
            }

            // Fixed bottom button
            VStack(spacing: TravSpacing.sm) {
                PrimaryButton(
                    title: "Continue",
                    isEnabled: isLocationSelected,
                    action: onContinue
                )
                .travAppear(delay: 0.2)

                if let location = selectedLocation {
                    Text("Heading to \(location)")
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                        .frame(maxWidth: .infinity)
                        .travAppear(delay: 0.25)
                } else {
                    Text("Choose where you want to explore")
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                        .frame(maxWidth: .infinity)
                        .travAppear(delay: 0.25)
                }
            }
            .padding(TravSpacing.screenHorizontal)
            .padding(.bottom, TravSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarBackButtonHidden()
    }
}

private struct CitySelectionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(TravTypography.bodyMedium())
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(.white)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, TravSpacing.md)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background {
                if isSelected {
                    LinearGradient(
                        colors: [TravColors.accent, Color(red: 0.45, green: 0.25, blue: 0.95)],
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
    @Previewable @State var selectedLocation: String?
    return LocationContextView(
        selectedLocation: $selectedLocation,
        onContinue: {},
        onSkip: {},
        onBack: {}
    )
}

