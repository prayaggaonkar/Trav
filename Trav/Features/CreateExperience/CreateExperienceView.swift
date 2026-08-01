import SwiftUI
import PhotosUI
import CoreLocation

/// Text fields persisted between sessions so an interrupted creation resumes.
private struct CreateDraft: Codable {
    var title = ""
    var description = ""
    var citySlug: String?
    var stops: [Stop] = []
    var ratingScores: [String: Double]?

    var isEmpty: Bool {
        title.isEmpty && description.isEmpty && stops.isEmpty
    }

    static let storageKey = "trav.createDraft.v1"

    static func load() -> CreateDraft? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(CreateDraft.self, from: data)
    }

    func save() {
        if isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.storageKey)
            return
        }
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

struct CreateExperienceView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router

    /// When false (user left the Create tab), clear any success screen so the form is ready next time.
    var isActive: Bool = true

    @State private var title = ""
    @State private var descriptionText = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImagesData: [Data] = []
    @State private var selectedUIImages: [UIImage] = []
    @State private var stops: [Stop] = []
    @State private var rating = RadarRating.defaultRating

    @State private var cities: [City] = []
    @State private var selectedCity: City?

    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var didRestoreDraft = false

    var body: some View {
        // Chrome (navigation stack, background, tab picker) belongs to
        // CreateHubView so both create tabs share it.
        ZStack {
            if showSuccess {
                successView
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                formContent
                    .transition(.opacity)
            }
        }
        .animation(TravAnimation.enter, value: showSuccess)
            .alert("Publish Failed", isPresented: $showErrorAlert) {
                Button("Try Again") { submit() }
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unexpected error occurred. Please try again.")
            }
            .task {
                await loadCities()
                applyPendingSpotIfNeeded()
            }
            .onAppear {
                restoreDraftIfNeeded()
                applyPendingSpotIfNeeded()
            }
            .onChange(of: isActive) { _, active in
                if !active, showSuccess {
                    resetForm()
                }
            }
            .onChange(of: router.pendingCreateSpot) { _, _ in
                applyPendingSpotIfNeeded()
            }
            .onChange(of: title) { autosaveDraft() }
            .onChange(of: descriptionText) { autosaveDraft() }
            .onChange(of: stops) {
                handleStopsChanged()
                autosaveDraft()
            }
            .onChange(of: selectedCity) { autosaveDraft() }
            .onChange(of: rating) { autosaveDraft() }
    }

    private func handleStopsChanged() {
        // Suggest a title from the first stop, but leave it editable: an
        // itinerary is never named after a single place.
        if title.trimmingCharacters(in: .whitespaces).isEmpty, let first = stops.first {
            title = "\(first.name) route"
        }
        Task {
            _ = await resolveCityFromStops()
        }
    }

    /// Resolves the city for the experience strictly from the first spot entered by the user
    @discardableResult
    private func resolveCityFromStops() async -> City {
        // 1. If stops exist, use the first stop added by the user
        if let firstStop = stops.first {
            // A. Try reverse geocoding via Apple Maps CLGeocoder for the first stop's coordinates
            if firstStop.latitude != 0 && firstStop.longitude != 0 {
                let location = CLLocation(latitude: firstStop.latitude, longitude: firstStop.longitude)
                let geocoder = CLGeocoder()
                if let placemarks = try? await geocoder.reverseGeocodeLocation(location),
                   let placemark = placemarks.first,
                   let localityName = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea {
                    let city = buildCity(name: localityName, latitude: firstStop.latitude, longitude: firstStop.longitude)
                    await MainActor.run { self.selectedCity = city }
                    return city
                }
            }

            // B. Try pending spot city name if available
            if let pendingCity = router.pendingCreateSpot?.cityName, !pendingCity.isEmpty {
                let city = buildCity(name: pendingCity)
                await MainActor.run { self.selectedCity = city }
                return city
            }

            // C. Fallback: Parse city name from first stop's description/address string
            let descParts = firstStop.description.components(separatedBy: ",")
            if descParts.count >= 2 {
                let potentialCity = descParts[0].trimmingCharacters(in: .whitespaces)
                if !potentialCity.isEmpty {
                    let city = buildCity(name: potentialCity)
                    await MainActor.run { self.selectedCity = city }
                    return city
                }
            }
        }

        // 2. Default fallback if no stops added yet
        let defaultCity = cities.first ?? buildCity(name: "San Francisco")
        return defaultCity
    }

    private func buildCity(name: String, latitude: Double = 37.7749, longitude: Double = -122.4194) -> City {
        if let matched = cities.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return matched
        }
        let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
        return City(
            id: UUID(),
            name: name,
            slug: slug,
            countryCode: "US",
            latitude: latitude,
            longitude: longitude,
            heroImageURL: nil,
            timezone: "America/Los_Angeles",
            experienceCount: 1,
            creatorCount: 1
        )
    }

    private func applyPendingSpotIfNeeded() {
        guard let pending = router.pendingCreateSpot else { return }
        title = pending.title
        stops = [
            Stop(
                id: UUID(),
                orderIndex: 0,
                name: pending.title,
                description: pending.subtitle,
                creatorNotes: nil,
                latitude: pending.latitude ?? 0,
                longitude: pending.longitude ?? 0,
                placeID: nil,
                recommendedTime: nil,
                durationMinutes: 60,
                emoji: pending.emoji,
                media: []
            )
        ]
        rating = SpotRatingAxes.defaultRating

        Task {
            _ = await resolveCityFromStops()
        }

        router.pendingCreateSpot = nil
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TravSpacing.lg) {
                VStack(alignment: .leading, spacing: TravSpacing.md) {
                    Text("Create Itinerary")
                        .font(TravTypography.displayMedium())
                        .tracking(2.5)
                        .foregroundStyle(TravColors.accent)
                        .lineLimit(1)

                    Text("Chain multiple spots into an itinerary and share it with the world.")
                        .font(TravTypography.bodyMedium())
                        .foregroundStyle(TravColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, TravSpacing.xxs)
                .padding(.bottom, TravSpacing.sm)
                .travAppear()

                TravFormSection(title: "Basic Info") {
                    VStack(spacing: TravSpacing.md) {
                        VStack(alignment: .leading, spacing: 4) {
                            TravTextField(
                                title: "Experience Title",
                                placeholder: "e.g. SF Coffee & Books Tour",
                                text: $title
                            )
                            .onChange(of: title) { _, newValue in
                                if newValue.count > 100 {
                                    title = String(newValue.prefix(100))
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: TravSpacing.xxs) {
                            Text("Description")
                                .font(TravTypography.labelMedium())
                                .foregroundStyle(TravColors.muted)
                            TextField(
                                "What makes this itinerary special?",
                                text: $descriptionText,
                                axis: .vertical
                            )
                            .font(TravTypography.bodyLarge())
                            .lineLimit(2...12)
                            .padding(.horizontal, TravSpacing.md)
                            .padding(.vertical, TravSpacing.sm)
                            .background(TravColors.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                    .stroke(TravColors.border.opacity(0.5), lineWidth: 1)
                            }
                            .onChange(of: descriptionText) { _, newValue in
                                if newValue.count > 1000 {
                                    descriptionText = String(newValue.prefix(1000))
                                }
                            }
                        }
                    }
                }
                .travAppear(delay: 0.05)

                TravFormSection(title: "Destinations Along the Way") {
                    VStack(spacing: TravSpacing.sm) {
                        if !stops.isEmpty {
                            VStack(spacing: TravSpacing.xs) {
                                ForEach(stops) { stop in
                                    stopRow(stop)
                                }
                            }
                        }

                        StopAutocompleteField(stops: $stops)
                    }
                }
                .travAppear(delay: 0.08)

                TravFormSection(title: "Add Media") {
                    mediaSection
                }
                .travAppear(delay: 0.12)

                VStack(alignment: .leading, spacing: TravSpacing.sm) {
                    HStack(alignment: .center, spacing: TravSpacing.sm) {
                        Text("Creator Rating")
                            .font(TravTypography.titleMedium())
                            .foregroundStyle(TravColors.primary)

                        Spacer(minLength: 0)

                        CreateOverallScoreBox(score: rating.overallScore)
                    }

                    InteractiveRadarChartView(rating: $rating, showsHeader: false)
                    Text("Drag each point to rate. Turn off subratings that don't apply.")
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                }
                .travAppear(delay: 0.15)

                PrimaryButton(
                    title: "Publish Experience",
                    isLoading: isSubmitting,
                    isEnabled: canPublish
                ) {
                    submit()
                }
                .travAppear(delay: 0.18)

                if let validationHint {
                    Text(validationHint)
                        .font(TravTypography.caption())
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Spacer(minLength: TravSpacing.xxl + TravSpacing.xl)
            }
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .padding(.bottom, TravSpacing.xl)
        }
    }



    // MARK: - Media

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            if selectedUIImages.isEmpty {
                PhotosPicker(selection: $selectedItems, matching: .images) {
                    VStack(spacing: TravSpacing.xs) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 32))
                            .foregroundStyle(TravColors.accent)
                        Text("Add Media")
                            .font(TravTypography.labelMedium())
                            .foregroundStyle(TravColors.primary)
                        Text("At least 1 photo required")
                            .font(TravTypography.caption())
                            .foregroundStyle(TravColors.muted)
                    }
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .background(TravColors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: TravRadius.md)
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                            .foregroundStyle(TravColors.primary.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TravSpacing.sm) {
                        ForEach(Array(selectedUIImages.enumerated()), id: \.offset) { index, img in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 110, height: 110)
                                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: TravRadius.md)
                                            .stroke(TravColors.primary.opacity(0.15), lineWidth: 1)
                                    )

                                Button {
                                    withAnimation(TravAnimation.quick) {
                                        if index < selectedItems.count { selectedItems.remove(at: index) }
                                        if index < selectedImagesData.count { selectedImagesData.remove(at: index) }
                                        if index < selectedUIImages.count { selectedUIImages.remove(at: index) }
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.white, Color.black.opacity(0.75))
                                        .padding(4)
                                }
                                .accessibilityLabel("Remove photo \(index + 1)")
                            }
                        }

                        PhotosPicker(selection: $selectedItems, matching: .images) {
                            VStack(spacing: TravSpacing.xxs) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(TravColors.accent)
                                Text("Add More")
                                    .font(TravTypography.caption())
                                    .foregroundStyle(TravColors.primary)
                            }
                            .frame(width: 110, height: 110)
                            .background(TravColors.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: TravRadius.md)
                                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                    .foregroundStyle(TravColors.accent.opacity(0.4))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("\(selectedUIImages.count) photo\(selectedUIImages.count == 1 ? "" : "s") added")
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
            }
        }
        .onChange(of: selectedItems) { _, newItems in
            Task {
                var datas: [Data] = []
                var uiImages: [UIImage] = []
                for item in newItems {
                    if let uiImage = await Self.loadUIImage(from: item),
                       let data = uiImage.jpegData(compressionQuality: 0.85) {
                        datas.append(data)
                        uiImages.append(uiImage)
                    }
                }
                await MainActor.run {
                    self.selectedImagesData = datas
                    self.selectedUIImages = uiImages
                }
            }
        }
    }

    private func stopRow(_ stop: Stop) -> some View {
        HStack(spacing: TravSpacing.sm) {
            Image(systemName: sfSymbolForEmojiOrCategory(stop.emoji ?? stop.name))
                .font(.system(size: 12))
                .foregroundStyle(TravColors.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(stop.name)
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                if !stop.description.isEmpty {
                    Text(stop.description)
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                withAnimation(TravAnimation.quick) {
                    stops.removeAll { $0.id == stop.id }
                    reindexStops()
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(TravColors.error.opacity(0.85))
                    .frame(width: TravLayout.minTouchTarget, height: TravLayout.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Remove \(stop.name)")
        }
        .padding(TravSpacing.md)
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.sm, style: .continuous))
    }

    private var successView: some View {
        VStack(spacing: TravSpacing.lg) {
            Spacer(minLength: TravSpacing.xxl)

            ZStack {
                Circle()
                    .fill(TravColors.accentSoft)
                    .frame(width: 108, height: 108)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(TravColors.accent)
            }

            VStack(spacing: TravSpacing.xs) {
                Text("Experience Published!")
                    .font(TravTypography.displayMedium())
                    .foregroundStyle(TravColors.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)

                Text("Your itinerary \"\(title)\" is now live on your profile and in the community feed.")
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryButton(title: "Create Another") {
                resetForm()
            }

            Spacer(minLength: TravSpacing.lg)
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Validation

    /// Identity keys for the current stops, matching the server's spot identity
    /// so duplicate stops are caught while typing.
    private var stopIdentityKeys: [String] {
        stops
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { SpotIdentity.key(placeID: $0.placeID, name: $0.name, latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var distinctStopCount: Int {
        Set(stopIdentityKeys).count
    }

    private var duplicateStopName: String? {
        var seen: Set<String> = []
        for stop in stops.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            let key = SpotIdentity.key(
                placeID: stop.placeID,
                name: stop.name,
                latitude: stop.latitude,
                longitude: stop.longitude
            )
            if !seen.insert(key).inserted { return stop.name }
        }
        return nil
    }

    /// An itinerary is 2+ distinct spots. A single place is a Spot, and spots
    /// come from the place catalog rather than being authored here.
    private var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && distinctStopCount >= ExperienceKind.itinerary.minimumStops
            && duplicateStopName == nil
            && !selectedImagesData.isEmpty
            && !isSubmitting
    }

    private var validationHint: String? {
        if title.trimmingCharacters(in: .whitespaces).isEmpty { return "Add a title to publish." }
        if let duplicateStopName {
            return "\(duplicateStopName) is already a stop — every stop has to be a different spot."
        }
        if stops.count < 2 {
            let remaining = 2 - stops.count
            return "Add \(remaining) more stop\(remaining == 1 ? "" : "s") — an itinerary needs at least 2 spots."
        }
        if distinctStopCount < 2 { return "An itinerary needs at least 2 different spots." }
        if selectedImagesData.isEmpty { return "Add at least one photo to publish." }
        return nil
    }

    // MARK: - Actions

    private func loadCities() async {
        guard cities.isEmpty else { return }
        do {
            let loaded = try await environment.cities.fetchGlobeCities()
            await MainActor.run {
                cities = loaded
                restoreCityFromDraft()
            }
        } catch {
            // Retry on next open; hint shown by the disabled state.
            TravLog.general.error("loadCities failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func submit() {
        guard !selectedImagesData.isEmpty else {
            errorMessage = "Add at least one photo to publish."
            showErrorAlert = true
            return
        }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                guard let creatorID = session.currentUser?.id else {
                    throw RepositoryError.unauthorized
                }

                let city = await resolveCityFromStops()

                let draft = ExperienceDraft(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                    city: city,
                    creatorID: creatorID,
                    stops: stops,
                    rating: rating,
                    imagesData: selectedImagesData
                )

                try await environment.experiences.publishExperience(draft)

                await MainActor.run {
                    isSubmitting = false
                    CreateDraft.clear()
                    withAnimation(TravAnimation.enter) {
                        showSuccess = true
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    if var user = session.currentUser {
                        user.experienceCount += 1
                        session.currentUser = user
                        environment.engagement.cache(user)
                    }
                    router.noteExperiencePublished()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }

    private func resetForm() {
        title = ""
        descriptionText = ""
        selectedItems = []
        selectedImagesData = []
        selectedUIImages = []
        stops = []
        selectedCity = nil
        rating = RadarRating.defaultRating
        showSuccess = false
        CreateDraft.clear()
    }

    private func reindexStops() {
        for index in stops.indices {
            stops[index].orderIndex = index
        }
    }

    // MARK: - Draft persistence

    private func restoreDraftIfNeeded() {
        guard !didRestoreDraft else { return }
        didRestoreDraft = true
        guard let draft = CreateDraft.load() else { return }
        title = draft.title
        descriptionText = draft.description
        stops = draft.stops
        if let scores = draft.ratingScores {
            rating = RadarRating(scores: scores)
        }
        restoreCityFromDraft()
    }

    private func restoreCityFromDraft() {
        guard selectedCity == nil,
              let slug = CreateDraft.load()?.citySlug else { return }
        selectedCity = cities.first { $0.slug == slug }
    }

    private func autosaveDraft() {
        var draft = CreateDraft()
        draft.title = title
        draft.description = descriptionText
        draft.citySlug = selectedCity?.slug
        draft.stops = stops
        draft.ratingScores = rating.scores
        draft.save()
    }

    private static func loadUIImage(from item: PhotosPickerItem) async -> UIImage? {
        if let picked = try? await item.loadTransferable(type: PickedCreateExperiencePhotoTransferable.self) {
            return picked.image
        }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }
}

private struct PickedCreateExperiencePhotoTransferable: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            guard let image = UIImage(data: data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return PickedCreateExperiencePhotoTransferable(image: image)
        }
    }
}
