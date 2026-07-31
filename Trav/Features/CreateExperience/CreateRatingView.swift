import SwiftUI
import PhotosUI
import MapKit

/// Create Rating: the screen every completion flows through.
///
/// Rating is mandatory, so this is where "Complete" lands. Everything describing
/// the experience is read-only — the user is only adding their own scores, an
/// optional review and up to three photos. Submitting creates the rating, marks
/// the experience completed, and lets the database recompute averages, the
/// profile Completed tab and the feed.
struct CreateRatingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(EngagementStore.self) private var engagement

    var isActive: Bool = true

    /// Locked-in target when the user arrived from an experience.
    @State private var target: ExperienceSummary?
    @State private var existingRating: Rating?

    @State private var searchText = ""
    @State private var searchResults: [ExperienceSummary] = []
    @State private var appleMapSpots: [SpotSuggestion] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    @State private var radar = RadarRating.defaultRating
    @State private var review = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photosData: [Data] = []
    @State private var photoImages: [UIImage] = []

    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    private var hasAlreadyRated: Bool { existingRating != nil }

    var body: some View {
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
        .alert("Couldn't Save Your Rating", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unexpected error occurred. Please try again.")
        }
        .task(id: router.pendingRatingTarget?.id) {
            await applyPendingTarget()
        }
        .onChange(of: isActive) { _, active in
            if !active, showSuccess { reset() }
        }
        .onChange(of: searchText) { _, query in
            scheduleSearch(query)
        }
    }

    // MARK: - Form

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TravSpacing.lg) {
                header

                if let target {
                    TravFormSection(title: "Experience") {
                        LockedExperiencePreview(
                            summary: target,
                            canChange: router.pendingRatingTarget == nil && !hasAlreadyRated
                        ) {
                            clearTarget()
                        }
                    }
                    .travAppear(delay: 0.05)
                } else {
                    TravFormSection(title: "What did you finish?") {
                        searchSection
                    }
                    .travAppear(delay: 0.05)
                }

                if hasAlreadyRated {
                    alreadyRatedBanner
                        .travAppear(delay: 0.08)
                } else {
                    TravFormSection(title: "Your Rating") {
                        VStack(alignment: .leading, spacing: TravSpacing.sm) {
                            InteractiveRadarChartView(rating: $radar)
                            Text("Drag each corner to score it. Turn off anything that doesn't apply.")
                                .font(TravTypography.caption())
                                .foregroundStyle(TravColors.muted)
                        }
                    }
                    .travAppear(delay: 0.1)
                    .opacity(target == nil ? 0.45 : 1)
                    .disabled(target == nil)

                    TravFormSection(title: "Review (Optional)") {
                        VStack(alignment: .leading, spacing: TravSpacing.xxs) {
                            TextField(
                                "How was it? What should other people know?",
                                text: $review,
                                axis: .vertical
                            )
                            .font(TravTypography.bodyLarge())
                            .lineLimit(3...8)
                            .padding(TravSpacing.md)
                            .background(TravColors.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                    .stroke(TravColors.border.opacity(0.5), lineWidth: 1)
                            }

                            Text("\(review.count)/1000")
                                .font(TravTypography.caption())
                                .foregroundStyle(review.count > 1000 ? .red : TravColors.muted)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .travAppear(delay: 0.13)
                    .opacity(target == nil ? 0.45 : 1)
                    .disabled(target == nil)

                    TravFormSection(title: "Photos (Optional)") {
                        photoSection
                    }
                    .travAppear(delay: 0.16)
                    .opacity(target == nil ? 0.45 : 1)
                    .disabled(target == nil)

                    if let hint = validationHint {
                        Text(hint)
                            .font(TravTypography.caption())
                            .foregroundStyle(TravColors.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    PrimaryButton(
                        title: "Submit & Complete",
                        isLoading: isSubmitting,
                        isEnabled: canSubmit
                    ) {
                        submit()
                    }
                    .travAppear(delay: 0.19)
                }

                Spacer(minLength: TravSpacing.xxl)
            }
            .padding(.horizontal, TravSpacing.screenHorizontal)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var alreadyRatedBanner: some View {
        VStack(alignment: .leading, spacing: TravSpacing.md) {
            HStack(spacing: TravSpacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(TravColors.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Already Rated")
                        .font(TravTypography.titleMedium())
                        .foregroundStyle(TravColors.primary)
                    Text("You've already rated this experience, so it can't be rated again.")
                        .font(TravTypography.bodyMedium())
                        .foregroundStyle(TravColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(TravSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TravColors.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))

            if router.pendingRatingTarget == nil {
                Button {
                    clearTarget()
                } label: {
                    Text("Pick a different experience")
                        .font(TravTypography.labelMedium())
                        .fontWeight(.bold)
                        .foregroundStyle(TravColors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, TravSpacing.sm)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: TravSpacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CREATE RATING")
                    .font(TravTypography.overline())
                    .tracking(2.5)
                    .foregroundStyle(TravColors.accent)

                Text(hasAlreadyRated ? "Already Rated" : "Rate & Complete")
                    .font(TravTypography.displayMedium())
                    .foregroundStyle(TravColors.primary)
                    .lineLimit(1)
            }

            Text(
                hasAlreadyRated
                    ? "Each experience can only be rated once."
                    : (target == nil
                        ? "Search for any spot, cafe, or creator itinerary you finished, then score it."
                        : "Score what you experienced. Submitting marks it completed.")
            )
                .font(TravTypography.bodyMedium())
                .foregroundStyle(TravColors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, TravSpacing.md)
        .travAppear()
    }

    // MARK: - Search

    private var searchSection: some View {
        VStack(spacing: TravSpacing.sm) {
            HStack(spacing: TravSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TravColors.muted)

                TextField("Search spots, cafes, and itineraries", text: $searchText)
                    .font(TravTypography.bodyLarge())
                    .autocorrectionDisabled()
                    .submitLabel(.search)

                if isSearching {
                    ProgressView().controlSize(.small)
                } else if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                        appleMapSpots = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
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

            if !appleMapSpots.isEmpty || !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: TravSpacing.sm) {
                    // Apple Maps Spots & Cafes Section
                    if !appleMapSpots.isEmpty {
                        VStack(alignment: .leading, spacing: TravSpacing.xs) {
                            Text("APPLE MAPS PLACES & CAFES")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(1.2)
                                .foregroundStyle(TravColors.muted)
                                .padding(.horizontal, TravSpacing.xs)

                            VStack(spacing: TravSpacing.xxs) {
                                ForEach(appleMapSpots) { spot in
                                    Button {
                                        select(spot.asExperienceSummary(creator: session.currentUser?.summary))
                                    } label: {
                                        appleMapSpotRow(spot)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Other Users' Itineraries Section
                    if !searchResults.isEmpty {
                        VStack(alignment: .leading, spacing: TravSpacing.xs) {
                            Text("ITINERARIES BY CREATORS")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(1.2)
                                .foregroundStyle(TravColors.muted)
                                .padding(.horizontal, TravSpacing.xs)

                            VStack(spacing: TravSpacing.xxs) {
                                ForEach(searchResults) { result in
                                    Button {
                                        select(result)
                                    } label: {
                                        searchResultRow(result)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            } else if searchText.count >= 2, !isSearching {
                Text("Nothing matched \"\(searchText)\". Try searching for a spot name, cafe, or creator itinerary.")
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func appleMapSpotRow(_ spot: SpotSuggestion) -> some View {
        HStack(spacing: TravSpacing.sm) {
            ZStack {
                Circle()
                    .fill(spot.category.badgeColor.opacity(0.18))
                    .frame(width: 36, height: 36)
                Text(spot.category.emoji)
                    .font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(spot.title)
                        .font(TravTypography.labelMedium())
                        .foregroundStyle(TravColors.primary)
                        .lineLimit(1)

                    Text(spot.category.rawValue)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(spot.category.badgeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(spot.category.badgeColor.opacity(0.18))
                        .clipShape(Capsule())
                }

                Text(spot.displayLocation)
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Rate")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(TravColors.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(TravColors.accent.opacity(0.18)))
        }
        .padding(TravSpacing.sm)
        .background(TravColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
    }

    private func searchResultRow(_ result: ExperienceSummary) -> some View {
        HStack(spacing: TravSpacing.sm) {
            RemoteImage(url: result.coverImageURL)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: TravRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(TravColors.primary)
                    .lineLimit(1)

                HStack(spacing: TravSpacing.xxs) {
                    Image(systemName: result.kind.symbolName)
                        .font(.system(size: 9))
                    Text(result.kind.displayName)
                    if let city = result.cityName, !city.isEmpty {
                        Text("· \(city)")
                    }
                    Text("· by @\(result.creator.username)")
                }
                .font(TravTypography.caption())
                .foregroundStyle(TravColors.muted)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TravColors.muted)
        }
        .padding(TravSpacing.sm)
        .background(TravColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
    }

    private static let straightFoodKeywords = [
        "restaurant", "pizza", "burger", "tacos", "sushi", "diner", "bistro",
        "bar", "pub", "grill", "eatery", "kitchen", "noodle", "ramen", "steak", "bbq"
    ]

    private func isStraightFoodPlace(title: String, subtitle: String) -> Bool {
        let combined = "\(title) \(subtitle)".lowercased()
        return Self.straightFoodKeywords.contains { combined.contains($0) }
    }

    private func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            appleMapSpots = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }

            // 1. Apple Maps search (spots, cafes, viewpoints, landmarks, parks)
            let mapReq = MapKit.MKLocalSearch.Request()
            mapReq.naturalLanguageQuery = trimmed
            mapReq.resultTypes = [.pointOfInterest, .address]

            var mapResults: [SpotSuggestion] = []
            do {
                let mapSearch = MapKit.MKLocalSearch(request: mapReq)
                let mapResp = try await mapSearch.start()
                var seen = Set<String>()

                for item in mapResp.mapItems {
                    guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
                    let subtitle = item.placemark.title ?? ""

                    // Avoid heavy/straight food, but keep cafes, coffee shops, viewpoints, hikes, landmarks & spots
                    if isStraightFoodPlace(title: name, subtitle: subtitle) { continue }

                    let category = SpotCategory.infer(title: name, subtitle: subtitle)
                    let coord = item.placemark.coordinate
                    let suggestion = SpotSuggestion(
                        id: "spot|\(name)|\(subtitle)|\(coord.latitude),\(coord.longitude)",
                        title: name,
                        subtitle: subtitle,
                        category: category,
                        latitude: coord.latitude,
                        longitude: coord.longitude
                    )

                    let key = "\(name.lowercased())|\(subtitle.lowercased())"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    mapResults.append(suggestion)

                    if mapResults.count >= 6 { break }
                }
            } catch {}

            guard !Task.isCancelled else { return }

            // 2. Search other users' itineraries in database
            let results = (try? await environment.experiences.searchExperiences(
                query: trimmed,
                kind: nil,
                limit: 10
            )) ?? []

            guard !Task.isCancelled else { return }

            await MainActor.run {
                appleMapSpots = mapResults
                searchResults = results
                isSearching = false
            }
        }
    }

    /// Auto-fills the read-only preview once a match is picked.
    private func select(_ summary: ExperienceSummary) {
        if engagement.isCompleted(summary.id) {
            errorMessage = ContentModelError.alreadyRated.errorDescription
            showErrorAlert = true
            return
        }
        target = summary
        existingRating = nil
        searchText = ""
        searchResults = []
        appleMapSpots = []
        Task { await loadExistingRating(for: summary.id) }
    }

    private func clearTarget() {
        target = nil
        existingRating = nil
        radar = RadarRating.defaultRating
        review = ""
        photoItems = []
        photosData = []
        photoImages = []
    }

    // MARK: - Photos

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            if photoImages.isEmpty {
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: RatingDraft.maxPhotos,
                    matching: .images
                ) {
                    VStack(spacing: TravSpacing.xs) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 32))
                            .foregroundStyle(TravColors.accent)
                        Text("Add Media")
                            .font(TravTypography.labelMedium())
                            .foregroundStyle(TravColors.primary)
                        Text("Up to \(RatingDraft.maxPhotos) photos (Optional)")
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
                        ForEach(Array(photoImages.enumerated()), id: \.offset) { index, img in
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
                                        removePhoto(at: index)
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

                        if photoImages.count < RatingDraft.maxPhotos {
                            PhotosPicker(
                                selection: $photoItems,
                                maxSelectionCount: RatingDraft.maxPhotos,
                                matching: .images
                            ) {
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
                }

                Text("\(photoImages.count) photo\(photoImages.count == 1 ? "" : "s") added")
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
            }
        }
        .onChange(of: photoItems) { _, items in
            Task { await loadPhotos(items) }
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var loaded: [Data] = []
        var images: [UIImage] = []
        for item in items.prefix(RatingDraft.maxPhotos) {
            if let image = await Self.loadUIImage(from: item),
               let data = image.jpegData(compressionQuality: 0.85) {
                loaded.append(data)
                images.append(image)
            }
        }
        await MainActor.run {
            photosData = loaded
            photoImages = images
        }
    }

    private static func loadUIImage(from item: PhotosPickerItem) async -> UIImage? {
        if let picked = try? await item.loadTransferable(type: PickedRatingPhotoTransferable.self) {
            return picked.image
        }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }

    private func removePhoto(at index: Int) {
        guard photosData.indices.contains(index) else { return }
        photosData.remove(at: index)
        photoImages.remove(at: index)
        if photoItems.indices.contains(index) {
            photoItems.remove(at: index)
        }
    }

    // MARK: - Validation

    private var canSubmit: Bool {
        target != nil
            && !hasAlreadyRated
            && !radar.scores.isEmpty
            && radar.scores.contains { radar.isEnabled($0.key) }
            && review.count <= 1000
            && !isSubmitting
    }

    private var validationHint: String? {
        if target == nil { return "Pick the experience you finished to start rating." }
        if hasAlreadyRated { return "You've already rated this experience." }
        if !radar.scores.contains(where: { radar.isEnabled($0.key) }) {
            return "Keep at least one category on to submit a rating."
        }
        if review.count > 1000 { return "Reviews are limited to 1000 characters." }
        return nil
    }

    // MARK: - Actions

    private func applyPendingTarget() async {
        guard let pending = router.pendingRatingTarget else { return }
        target = pending.summary
        await loadExistingRating(for: pending.id)
    }

    /// One rating per user per experience — existing ratings cannot be edited or replaced.
    private func loadExistingRating(for experienceID: UUID) async {
        guard let userID = session.currentUser?.id else { return }
        let rating = try? await environment.ratings.fetchMyRating(
            userID: userID,
            experienceID: experienceID
        )
        await MainActor.run {
            existingRating = rating
        }
    }

    private func submit() {
        guard let target, !hasAlreadyRated else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let draft = RatingDraft(
                    experienceID: target.id,
                    radar: radar,
                    review: review.trimmingCharacters(in: .whitespacesAndNewlines),
                    photosData: photosData
                )
                try await engagement.submitRating(draft, summary: target, using: environment)

                await MainActor.run {
                    isSubmitting = false
                    router.clearPendingRatingTarget()
                    withAnimation(TravAnimation.enter) { showSuccess = true }
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

    private func reset() {
        clearTarget()
        searchText = ""
        showSuccess = false
        isSubmitting = false
    }

    // MARK: - Success

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
                Text("Completed")
                    .font(TravTypography.displayMedium())
                    .foregroundStyle(TravColors.primary)

                Text("Your rating is live. It's on your profile and counts toward the community score.")
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryButton(title: "Rate Something Else") {
                reset()
            }

            Spacer(minLength: TravSpacing.lg)
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Read-only summary of the experience being rated. Nothing here is editable —
/// the user is contributing an opinion, not changing the experience.
private struct LockedExperiencePreview: View {
    let summary: ExperienceSummary
    let canChange: Bool
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            HStack(spacing: TravSpacing.sm) {
                RemoteImage(url: summary.coverImageURL)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: TravSpacing.xxs) {
                        Image(systemName: summary.kind.symbolName)
                            .font(.system(size: 9, weight: .semibold))
                        Text(summary.kind.displayName.uppercased())
                            .font(TravTypography.overline())
                            .tracking(1.5)
                    }
                    .foregroundStyle(TravColors.accent)

                    Text(summary.title)
                        .font(TravTypography.titleMedium())
                        .foregroundStyle(TravColors.primary)
                        .lineLimit(2)

                    HStack(spacing: TravSpacing.xxs) {
                        Text("@\(summary.creator.username)")
                        if let city = summary.cityName, !city.isEmpty {
                            Text("· \(city)")
                        }
                    }
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(TravColors.muted)
                    .accessibilityLabel("Experience details are locked")
            }

            if !summary.stops.isEmpty {
                Text(summary.stops.map(\.name).joined(separator: " → "))
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
                    .lineLimit(2)
            }

            RatingSummaryBadge(summary: summary.ratingSummary)

            if canChange {
                Button("Choose a different experience", action: onChange)
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.accent)
            }
        }
        .padding(TravSpacing.md)
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                .stroke(TravColors.border.opacity(0.5), lineWidth: 1)
        }
    }
}

private struct PickedRatingPhotoTransferable: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            guard let image = UIImage(data: data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return PickedRatingPhotoTransferable(image: image)
        }
    }
}
