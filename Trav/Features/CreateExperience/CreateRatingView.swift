import SwiftUI
import PhotosUI
import MapKit

/// Create Rating: the screen every completion flows through.
///
/// Rating is mandatory, so this is where "Complete" lands. Everything describing
/// the experience is read-only — the user is only adding their own scores and up
/// to three photos. Submitting creates the rating, marks the experience completed,
/// and lets the database recompute averages, the profile Completed tab and the feed.
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

    @State private var radar = RadarRating.emptyRating
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
                    createRatingSection(title: "Experience") {
                        LockedExperiencePreview(
                            summary: target,
                            canChange: router.pendingRatingTarget == nil && !hasAlreadyRated
                        ) {
                            clearTarget()
                        }
                    }
                    .travAppear(delay: 0.05)
                } else {
                    createRatingSection(title: "Where did you go?") {
                        searchSection
                    }
                    .travAppear(delay: 0.05)
                }

                if hasAlreadyRated {
                    alreadyRatedBanner
                        .travAppear(delay: 0.08)
                } else {
                    createRatingSection(title: "Your Rating", trailing: { overallScoreBadge }) {
                        VStack(alignment: .leading, spacing: TravSpacing.sm) {
                            InteractiveRadarChartView(rating: $radar, showsHeader: false)
                            Text("Drag each point to rate. Turn off subratings that don't apply.")
                                .font(TravTypography.caption())
                                .foregroundStyle(TravColors.muted)
                        }
                    }
                    .travAppear(delay: 0.1)
                    .opacity(target == nil ? 0.45 : 1)
                    .disabled(target == nil)

                    createRatingSection(title: "Photos (Optional)") {
                        photoSection
                    }
                    .travAppear(delay: 0.13)
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

                Spacer(minLength: TravSpacing.xxl + TravSpacing.xl)
            }
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .padding(.bottom, TravSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Shared section chrome so Experience / Your Rating / Photos titles stay identical.
    private func createRatingSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        createRatingSection(title: title, trailing: { EmptyView() }, content: content)
    }

    private func createRatingSection<Content: View, Trailing: View>(
        title: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            HStack(alignment: .center, spacing: TravSpacing.sm) {
                Text(title)
                    .font(TravTypography.titleMedium())
                    .foregroundStyle(TravColors.primary)

                Spacer(minLength: 0)

                trailing()
            }

            content()
        }
    }

    private var overallScoreBadge: some View {
        CreateOverallScoreBox(score: radar.overallScore, hasActiveScores: radar.hasActiveScores)
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
        VStack(alignment: .leading, spacing: TravSpacing.md) {
            Text(hasAlreadyRated ? "Already Rated" : "Create Rating")
                .font(TravTypography.displayMedium())
                .tracking(hasAlreadyRated ? 0 : 2.5)
                .foregroundStyle(hasAlreadyRated ? TravColors.primary : TravColors.accent)
                .lineLimit(1)

            Text(headerSubtitle)
                .font(TravTypography.bodyMedium())
                .foregroundStyle(TravColors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, TravSpacing.xxs)
        .padding(.bottom, TravSpacing.sm)
        .travAppear()
    }

    private var headerSubtitle: String {
        if hasAlreadyRated {
            return "Each experience can only be rated once."
        }
        if let target {
            return "Rate \(target.title)! Add photos if you'd like. Submitting a rating marks the experience completed."
        }
        return "Search for any destination or creator itinerary you've completed."
    }

    // MARK: - Search

    private var searchSection: some View {
        VStack(spacing: TravSpacing.sm) {
            HStack(spacing: TravSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TravColors.muted)

                TextField("Search destinations or itineraries.", text: $searchText)
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
                            Text("DESTINATIONS")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(1.2)
                                .foregroundStyle(TravColors.muted)
                                .padding(.horizontal, TravSpacing.xs)

                            VStack(spacing: TravSpacing.xxs) {
                                ForEach(appleMapSpots) { spot in
                                    Button {
                                        select(spot.asExperienceSummary())
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
                Text(spot.title)
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(TravColors.primary)
                    .lineLimit(1)

                Text(spot.displayLocation)
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(spot.category.rawValue)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(spot.category.badgeColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(spot.category.badgeColor.opacity(0.18)))
                .lineLimit(1)
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
            try? await Task.sleep(for: .milliseconds(HangoutSpotSearchService.defaultDebounceMilliseconds))
            guard !Task.isCancelled else { return }

            let userCoordinate = LocationManager.shared.coordinateForSearch

            async let mapResults = HangoutSpotSearchService.search(
                query: trimmed,
                userCoordinate: userCoordinate,
                limit: 6
            )

            // Itineraries only (not DB spots) — ranked by Trav popularity + text match
            let itineraryMatches = (try? await environment.experiences.searchExperiences(
                query: trimmed,
                kind: nil,
                limit: 16
            )) ?? []
            let rankedItineraries = IntelligentSearchRanking.rankExperiences(
                itineraryMatches.filter { !$0.isSpot },
                query: trimmed
            )

            let spots = await mapResults
            guard !Task.isCancelled else { return }

            await MainActor.run {
                appleMapSpots = spots
                searchResults = Array(rankedItineraries.prefix(10))
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
        radar = RadarRating.emptyRating
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
            && radar.hasActiveScores
            && !isSubmitting
    }

    private var validationHint: String? {
        if target == nil { return "Pick the experience you finished to start rating." }
        if hasAlreadyRated { return "You've already rated this experience." }
        if !radar.hasActiveScores {
            return "Rate at least one category on the polygon to submit."
        }
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
        guard let target, !hasAlreadyRated, radar.hasActiveScores else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let draft = RatingDraft(
                    experienceID: target.id,
                    radar: radar,
                    review: nil,
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

            VStack(spacing: TravSpacing.xs) {
                ZStack {
                    Circle()
                        .fill(TravColors.accentSoft)
                        .frame(width: 108, height: 108)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(TravColors.accent)
                }

                Text("Completed")
                    .font(TravTypography.displayMedium())
                    .foregroundStyle(TravColors.primary)
            }

            Text("Your rating is live. Displayed on your profile and is part of the community rating.")
                .font(TravTypography.bodyMedium())
                .foregroundStyle(TravColors.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, TravSpacing.sm)

            PrimaryButton(title: "Rate Another Experience") {
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

            RatingSummaryBadge(summary: summary.ratingSummary)
        }
        .padding(TravSpacing.md)
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                .stroke(TravColors.border.opacity(0.5), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if canChange {
                Button(action: onChange) {
                    Text("Choose a different experience")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(TravColors.accent)
                        .clipShape(Capsule())
                        .shadow(color: TravColors.accent.opacity(0.35), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .offset(x: 14, y: -8)
            }
        }
        .padding(.top, canChange ? 10 : 0)
        .padding(.trailing, canChange ? 8 : 0)
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
