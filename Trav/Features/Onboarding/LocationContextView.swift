import SwiftUI
import UIKit

struct LocationContextView: View {
    @Binding var selectedLocation: String?
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void

    @State private var searchCity: String?
    @State private var searchSettled = true
    @State private var isResolvingCurrent = false
    @State private var locationError: String?
    @State private var locator = CurrentCityLocator()

    private var popularCities: [String] {
        // Plain city names only — no flags/emojis, no country chrome.
        [
            "New York",
            "Tokyo",
            "Barcelona",
            "Paris",
            "Bangkok",
            "London",
            "Dubai",
            "Amsterdam",
            "Singapore",
            "Sydney"
        ]
    }

    var isLocationSelected: Bool {
        selectedLocation != nil
    }

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(alignment: .leading, spacing: 0) {
                OnboardingHeaderView(step: 2, onBack: onBack, onSkip: onSkip)

                ScrollView {
                    VStack(alignment: .leading, spacing: TravSpacing.lg) {
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

                        CityAutocompleteField(
                            title: "",
                            placeholder: "Search for a city",
                            selectedCity: $searchCity,
                            isSettled: $searchSettled,
                            style: .onboarding
                        )
                        .onChange(of: searchCity) { _, newValue in
                            if let newValue {
                                withAnimation(TravAnimation.quick) {
                                    selectedLocation = newValue
                                }
                            }
                        }
                        .travAppear(delay: 0.06)

                        Button {
                            Task { await useCurrentLocation() }
                        } label: {
                            HStack(spacing: TravSpacing.md) {
                                ZStack {
                                    Circle()
                                        .fill(TravColors.accentSoft)
                                        .frame(width: 36, height: 36)

                                    if isResolvingCurrent {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(TravColors.accent)
                                    } else {
                                        Image(systemName: "location.fill")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(TravColors.accent)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Use my current location")
                                        .font(TravTypography.bodyMedium())
                                        .fontWeight(.semibold)
                                        .foregroundStyle(TravColors.primary)
                                    Text("We’ll resolve your city automatically")
                                        .font(TravTypography.caption())
                                        .foregroundStyle(TravColors.muted)
                                }

                                Spacer()

                                if isCurrentLocationSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(TravColors.accent)
                                }
                            }
                            .padding(TravSpacing.md)
                            .background(Color.white.opacity(isCurrentLocationSelected ? 0.08 : 0.04))
                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                    .stroke(
                                        isCurrentLocationSelected ? TravColors.accent : Color.white.opacity(0.1),
                                        lineWidth: 1
                                    )
                            }
                        }
                        .buttonStyle(TravPressButtonStyle(scale: 0.98))
                        .disabled(isResolvingCurrent)
                        .travAppear(delay: 0.1)

                        if let locationError {
                            Text(locationError)
                                .font(TravTypography.caption())
                                .foregroundStyle(TravColors.error)
                        }

                        VStack(alignment: .leading, spacing: TravSpacing.sm) {
                            Text("Popular destinations")
                                .font(TravTypography.titleMedium())
                                .foregroundStyle(TravColors.primary)
                                .padding(.bottom, TravSpacing.xxs)

                            VStack(spacing: TravSpacing.sm) {
                                ForEach(Array(stride(from: 0, to: popularCities.count, by: 2)), id: \.self) { index in
                                    HStack(spacing: TravSpacing.sm) {
                                        CitySelectionChip(
                                            title: popularCities[index],
                                            isSelected: selectedLocation == popularCities[index],
                                            action: {
                                                withAnimation(TravAnimation.quick) {
                                                    let city = popularCities[index].strippingEmojiAndSymbols()
                                                    selectedLocation = city
                                                    searchCity = city
                                                }
                                            }
                                        )

                                        if index + 1 < popularCities.count {
                                            CitySelectionChip(
                                                title: popularCities[index + 1],
                                                isSelected: selectedLocation == popularCities[index + 1],
                                                action: {
                                                    withAnimation(TravAnimation.quick) {
                                                        let city = popularCities[index + 1].strippingEmojiAndSymbols()
                                                        selectedLocation = city
                                                        searchCity = city
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
                        .travAppear(delay: 0.14)
                    }
                    .padding(.horizontal, TravSpacing.screenHorizontal)
                    .padding(.bottom, 120)
                }
            }

            VStack(spacing: TravSpacing.sm) {
                PrimaryButton(
                    title: "Continue",
                    isEnabled: isLocationSelected,
                    action: onContinue
                )

                if let location = selectedLocation {
                    Text("Heading to \(location)")
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Choose where you want to explore")
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(TravSpacing.screenHorizontal)
            .padding(.bottom, TravSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarBackButtonHidden()
        .onAppear {
            searchCity = selectedLocation
        }
    }

    private var isCurrentLocationSelected: Bool {
        guard let selectedLocation else { return false }
        return popularCities.contains(selectedLocation) == false
            && searchCity == selectedLocation
            && !isResolvingCurrent
    }

    private func useCurrentLocation() async {
        isResolvingCurrent = true
        locationError = nil
        defer { isResolvingCurrent = false }

        guard let label = await locator.requestCityLabel() else {
            locationError = "Couldn't find your city. Try searching instead."
            return
        }

        withAnimation(TravAnimation.quick) {
            selectedLocation = label
            searchCity = label
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private struct CitySelectionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title.asPlainPlaceName())
                    .font(TravTypography.bodyMedium())
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

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
                    TravColors.accent
                } else {
                    Color.white.opacity(0.06)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
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
