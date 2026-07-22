import CoreLocation
import SwiftUI
import UIKit

/// Search field that only accepts real places via MapKit autocomplete suggestions.
struct CityAutocompleteField: View {
    let title: String
    let placeholder: String
    @Binding var selectedCity: String?
    /// Becomes `false` while the user is typing an unconfirmed query.
    @Binding var isSettled: Bool
    var allowsClear: Bool = true
    var style: Style = .form

    enum Style {
        case form
        case onboarding
    }

    /// ~6 visible rows before the list scrolls internally.
    private static let suggestionRowHeight: CGFloat = 52
    private static let maxVisibleSuggestions = 6

    @State private var controller = CityAutocompleteController()
    @State private var draft = ""
    @State private var showSuggestions = false
    @FocusState private var isFocused: Bool

    init(
        title: String,
        placeholder: String,
        selectedCity: Binding<String?>,
        isSettled: Binding<Bool> = .constant(true),
        allowsClear: Bool = true,
        style: Style = .form
    ) {
        self.title = title
        self.placeholder = placeholder
        self._selectedCity = selectedCity
        self._isSettled = isSettled
        self.allowsClear = allowsClear
        self.style = style
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TravSpacing.xxs) {
            if !title.isEmpty {
                Text(title)
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(TravColors.muted)
            }

            HStack(spacing: TravSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TravColors.muted)

                TextField(placeholder, text: $draft)
                    .font(TravTypography.bodyLarge())
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .onChange(of: draft) { _, newValue in
                        controller.query = newValue
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        showSuggestions = !trimmed.isEmpty && selectedCity != trimmed
                        if let selectedCity, newValue != selectedCity {
                            self.selectedCity = nil
                        }
                        refreshSettled()
                    }

                if allowsClear, selectedCity != nil || !draft.isEmpty {
                    Button {
                        draft = ""
                        selectedCity = nil
                        controller.clear()
                        showSuggestions = false
                        refreshSettled()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(TravColors.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(TravSpacing.md)
            .background(fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }

            if showSuggestions, !controller.suggestions.isEmpty {
                let boxHeight = Self.suggestionRowHeight * CGFloat(Self.maxVisibleSuggestions)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(controller.suggestions) { suggestion in
                            Button {
                                Task { await select(suggestion) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title.asPlainPlaceName())
                                        .font(TravTypography.bodyMedium())
                                        .foregroundStyle(TravColors.primary)
                                        .lineLimit(1)
                                        .multilineTextAlignment(.leading)
                                    if !suggestion.subtitle.asPlainPlaceName().isEmpty {
                                        Text(suggestion.subtitle.asPlainPlaceName())
                                            .font(TravTypography.caption())
                                            .foregroundStyle(TravColors.muted)
                                            .lineLimit(1)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: Self.suggestionRowHeight - 1, alignment: .center)
                                .padding(.horizontal, TravSpacing.md)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if suggestion.id != controller.suggestions.last?.id {
                                Divider().opacity(0.35)
                            }
                        }
                    }
                }
                .frame(height: boxHeight)
                .scrollBounceBehavior(.basedOnSize)
                .background(fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                }
            } else if showSuggestions, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Select a city from the suggestions")
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
                    .padding(.horizontal, TravSpacing.xxs)
            }

            if let selectedCity {
                Text(selectedCity.asPlainPlaceName())
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
            }
        }
        .onAppear {
            if let selectedCity {
                draft = selectedCity.asPlainPlaceName()
            }
            refreshSettled()
        }
        .onChange(of: selectedCity) { _, newValue in
            if let newValue {
                let plain = newValue.asPlainPlaceName()
                if draft != plain { draft = plain }
                if newValue != plain { selectedCity = plain }
            }
            refreshSettled()
        }
    }

    private var fieldBackground: Color {
        switch style {
        case .form: TravColors.surfaceElevated
        case .onboarding: Color.white.opacity(0.06)
        }
    }

    private var borderColor: Color {
        switch style {
        case .form: TravColors.border.opacity(0.5)
        case .onboarding: Color.white.opacity(0.1)
        }
    }

    private func refreshSettled() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isSettled = trimmed.isEmpty || selectedCity == trimmed
    }

    private func select(_ suggestion: CitySuggestion) async {
        let label = (await controller.resolve(suggestion) ?? suggestion.displayLabel)
            .asPlainPlaceName()
        guard !label.isEmpty else { return }
        selectedCity = label
        draft = label
        showSuggestions = false
        controller.dismissSuggestions()
        isFocused = false
        refreshSettled()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// Resolves device GPS into a real city label.
@MainActor
final class CurrentCityLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private let autocomplete = CityAutocompleteController()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestCityLabel() async -> String? {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            try? await Task.sleep(for: .milliseconds(600))
        }

        guard manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways else {
            return nil
        }

        let coordinate = await withCheckedContinuation { (cont: CheckedContinuation<CLLocationCoordinate2D?, Never>) in
            self.continuation = cont
            self.manager.requestLocation()
        }
        guard let coordinate else { return nil }
        return await autocomplete.resolveCurrentLocation(coordinate: coordinate)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.first?.coordinate
        Task { @MainActor in
            continuation?.resume(returning: coordinate)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }
}
