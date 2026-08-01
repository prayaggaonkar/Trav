import CoreLocation
import MapKit
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

    func requestLocationCoordinate() async -> CLLocationCoordinate2D? {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            try? await Task.sleep(for: .milliseconds(600))
        }

        guard manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways else {
            return nil
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<CLLocationCoordinate2D?, Never>) in
            self.continuation = cont
            self.manager.requestLocation()
        }
    }

    func requestCityLabel() async -> String? {
        guard let coordinate = await requestLocationCoordinate() else { return nil }
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

// MARK: - Stop Autocomplete

struct StopSuggestion: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    var latitude: Double?
    var longitude: Double?

    var displayLabel: String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanSubtitle.isEmpty { return cleanTitle }
        if cleanTitle.lowercased().contains(cleanSubtitle.lowercased()) {
            return cleanTitle
        }
        return "\(cleanTitle), \(cleanSubtitle)"
    }
}

/// Stop search controller utilizing direct Apple Maps Search API (MKLocalSearch) with location biasing and natural language query support.
@Observable
@MainActor
final class StopAutocompleteController: NSObject, MKLocalSearchCompleterDelegate, CLLocationManagerDelegate {
    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            searchTask?.cancel()
            if trimmed.isEmpty {
                suggestions = []
                completer.queryFragment = ""
                isSearching = false
            } else if trimmed != lastQueried {
                lastQueried = trimmed
                isSearching = true
                completer.queryFragment = trimmed

                // Ranked hangout search replaces completer results when ready
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(HangoutSpotSearchService.defaultDebounceMilliseconds))
                    guard !Task.isCancelled else { return }
                    await self.performAppleMapsSearch(for: trimmed)
                }
            }
        }
    }

    private(set) var suggestions: [StopSuggestion] = []
    private(set) var isSearching = false

    private let completer = MKLocalSearchCompleter()
    private let locationManager = CLLocationManager()
    private var lastQueried = ""
    private var searchTask: Task<Void, Never>?
    private var userCoordinate: CLLocationCoordinate2D?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .pointOfInterest
        completer.pointOfInterestFilter = HangoutSpotFilter.pointOfInterestFilter

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        if let location = locationManager.location {
            userCoordinate = location.coordinate
            updateRegion(location.coordinate)
        }
        locationManager.requestLocation()
        locationManager.startUpdatingLocation()
    }

    private func updateRegion(_ coordinate: CLLocationCoordinate2D) {
        userCoordinate = coordinate
        let radius = SearchIntent.classify(query).localRadiusMeters
        completer.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radius,
            longitudinalMeters: radius
        )
    }

    func clear() {
        searchTask?.cancel()
        query = ""
        suggestions = []
        lastQueried = ""
        isSearching = false
    }

    func dismissSuggestions() {
        searchTask?.cancel()
        suggestions = []
        isSearching = false
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.updateRegion(location.coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let snapshots: [(title: String, subtitle: String)] = completer.results.map {
            ($0.title, $0.subtitle)
        }
        Task { @MainActor in
            // Fast prefix completion while ranked search is loading
            if self.suggestions.isEmpty {
                self.applyCompleter(snapshots: snapshots)
            }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}

    private func applyCompleter(snapshots: [(title: String, subtitle: String)]) {
        var mapped: [StopSuggestion] = []
        var seen = Set<String>()

        for snapshot in snapshots {
            let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = snapshot.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            guard HangoutSpotFilter.isEligibleText(title: title, subtitle: subtitle) else { continue }

            let suggestion = StopSuggestion(
                id: "completer|\(title)|\(subtitle)",
                title: title,
                subtitle: subtitle
            )
            let key = suggestion.displayLabel.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            mapped.append(suggestion)
            if mapped.count >= 15 { break }
        }

        if self.suggestions.isEmpty {
            self.suggestions = mapped
        }
    }

    /// Resolves coordinates for a suggestion that came from the fast prefix
    /// completer (which carries no placemark).
    func resolveCoordinates(for suggestion: StopSuggestion) async -> (latitude: Double, longitude: Double)? {
        if let lat = suggestion.latitude, let lng = suggestion.longitude {
            return (lat, lng)
        }
        let ranked = await HangoutSpotSearchService.search(
            query: suggestion.displayLabel,
            userCoordinate: userCoordinate ?? locationManager.location?.coordinate,
            limit: 1
        )
        if let first = ranked.first, let lat = first.latitude, let lng = first.longitude {
            return (lat, lng)
        }
        return nil
    }

    /// Primary search via shared intelligent hangout spot pipeline.
    private func performAppleMapsSearch(for queryText: String) async {
        let spots = await HangoutSpotSearchService.search(
            query: queryText,
            userCoordinate: userCoordinate ?? locationManager.location?.coordinate,
            limit: 15
        )
        guard !Task.isCancelled else { return }

        let apiSuggestions: [StopSuggestion] = spots.map { spot in
            StopSuggestion(
                id: "maps_api|\(spot.title)|\(spot.subtitle)",
                title: spot.title,
                subtitle: spot.displayLocation,
                latitude: spot.latitude,
                longitude: spot.longitude
            )
        }

        if !apiSuggestions.isEmpty {
            self.suggestions = apiSuggestions
        }
        self.isSearching = false
    }
}

/// Search and autocomplete field for adding experience stops using Apple Maps API.
/// Selected suggestions are geocoded so published stops carry real coordinates.
struct StopAutocompleteField: View {
    @Binding var stops: [Stop]
    var placeholder: String = "Search places (e.g. Blue Bottle, Dolores Park)..."

    private static let suggestionRowHeight: CGFloat = 52
    private static let maxVisibleSuggestions = 5

    @State private var controller = StopAutocompleteController()
    @State private var draft = ""
    @State private var showSuggestions = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: TravSpacing.xs) {
            HStack(spacing: TravSpacing.xs) {
                HStack(spacing: TravSpacing.sm) {
                    if controller.isSearching {
                        ProgressView()
                            .controlSize(.small)
                            .tint(TravColors.accent)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(TravColors.muted)
                    }

                    TextField(placeholder, text: $draft)
                        .font(TravTypography.bodyLarge())
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        .onSubmit {
                            addCustomStop()
                        }
                        .onChange(of: draft) { _, newValue in
                            controller.query = newValue
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            showSuggestions = !trimmed.isEmpty
                        }

                    if !draft.isEmpty {
                        Button {
                            draft = ""
                            controller.clear()
                            showSuggestions = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(TravColors.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(TravSpacing.md)
                .background(TravColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                        .stroke(TravColors.border.opacity(0.5), lineWidth: 1)
                }

                Button(action: addCustomStop) {
                    Image(systemName: "plus")
                        .font(.system(size: TravIcon.sm, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: TravLayout.minTouchTarget, height: TravLayout.minTouchTarget)
                        .background(TravColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.sm, style: .continuous))
                }
                .buttonStyle(TravPressButtonStyle())
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            }

            if showSuggestions, !controller.suggestions.isEmpty {
                let count = min(controller.suggestions.count, Self.maxVisibleSuggestions)
                let boxHeight = Self.suggestionRowHeight * CGFloat(count)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(controller.suggestions) { suggestion in
                            Button {
                                select(suggestion)
                            } label: {
                                HStack(spacing: TravSpacing.sm) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(TravColors.accent)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.title)
                                            .font(TravTypography.bodyMedium())
                                            .foregroundStyle(TravColors.primary)
                                            .lineLimit(1)
                                            .multilineTextAlignment(.leading)
                                        if !suggestion.subtitle.isEmpty {
                                            Text(suggestion.subtitle)
                                                .font(TravTypography.caption())
                                                .foregroundStyle(TravColors.muted)
                                                .lineLimit(1)
                                                .multilineTextAlignment(.leading)
                                        }
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
                .background(TravColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                        .stroke(TravColors.border.opacity(0.5), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
            }
        }
    }

    private func select(_ suggestion: StopSuggestion) {
        let name = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        appendStop(name: name, description: suggestion.subtitle, latitude: suggestion.latitude, longitude: suggestion.longitude)

        // Resolve coordinates in the background for prefix-completer suggestions.
        if suggestion.latitude == nil {
            let stopName = name
            Task {
                guard let coords = await controller.resolveCoordinates(for: suggestion) else { return }
                if let index = stops.lastIndex(where: { $0.name == stopName && $0.latitude == 0 && $0.longitude == 0 }) {
                    stops[index].latitude = coords.latitude
                    stops[index].longitude = coords.longitude
                }
            }
        }
        clearField()
    }

    private func addCustomStop() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Prefer the top suggestion (has coordinates) over a raw text stop.
        if let top = controller.suggestions.first,
           top.title.lowercased().hasPrefix(trimmed.lowercased()) || top.latitude != nil {
            select(top)
            return
        }
        appendStop(name: trimmed, description: "", latitude: nil, longitude: nil)
        clearField()
    }

    private func appendStop(name: String, description: String, latitude: Double?, longitude: Double?) {
        withAnimation(TravAnimation.enter) {
            stops.append(Stop(
                id: UUID(),
                orderIndex: stops.count,
                name: name,
                description: description,
                creatorNotes: nil,
                latitude: latitude ?? 0,
                longitude: longitude ?? 0,
                placeID: nil,
                recommendedTime: nil,
                durationMinutes: 30,
                emoji: nil,
                media: []
            ))
        }
    }

    private func clearField() {
        draft = ""
        controller.clear()
        showSuggestions = false
        isFocused = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
