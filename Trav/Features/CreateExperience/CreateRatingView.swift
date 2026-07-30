import SwiftUI
import PhotosUI

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

    private var isEditingExistingRating: Bool { existingRating != nil }

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
            Button("Try Again") { submit() }
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
                        LockedExperiencePreview(summary: target, canChange: router.pendingRatingTarget == nil) {
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
                    title: isEditingExistingRating ? "Update Rating" : "Submit & Complete",
                    isLoading: isSubmitting,
                    isEnabled: canSubmit
                ) {
                    submit()
                }
                .travAppear(delay: 0.19)

                Spacer(minLength: TravSpacing.xxl)
            }
            .padding(.horizontal, TravSpacing.screenHorizontal)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: TravSpacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isEditingExistingRating ? "EDIT RATING" : "CREATE RATING")
                    .font(TravTypography.overline())
                    .tracking(2.5)
                    .foregroundStyle(TravColors.accent)

                Text(isEditingExistingRating ? "Your Rating" : "Rate & Complete")
                    .font(TravTypography.displayMedium())
                    .foregroundStyle(TravColors.primary)
                    .lineLimit(1)
            }

            Text(target == nil
                 ? "Search for the spot or itinerary you finished, then score it."
                 : "Score what you experienced. Submitting marks it completed.")
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

                TextField("Search spots and itineraries", text: $searchText)
                    .font(TravTypography.bodyLarge())
                    .autocorrectionDisabled()
                    .submitLabel(.search)

                if isSearching {
                    ProgressView().controlSize(.small)
                } else if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
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

            if !searchResults.isEmpty {
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
            } else if searchText.count >= 2, !isSearching {
                Text("Nothing matched \"\(searchText)\". Spots come from our place catalog — try the exact name.")
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            let results = (try? await environment.experiences.searchExperiences(
                query: trimmed,
                kind: nil,
                limit: 12
            )) ?? []
            guard !Task.isCancelled else { return }
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        }
    }

    /// Auto-fills the read-only preview once a match is picked.
    private func select(_ summary: ExperienceSummary) {
        target = summary
        searchText = ""
        searchResults = []
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
            if !photoImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TravSpacing.xs) {
                        ForEach(Array(photoImages.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 88, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        removePhoto(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(.white, .black.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(4)
                                }
                        }
                    }
                }
            }

            if photosData.count < RatingDraft.maxPhotos {
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: RatingDraft.maxPhotos,
                    matching: .images
                ) {
                    HStack(spacing: TravSpacing.xs) {
                        Image(systemName: "photo.badge.plus")
                        Text(photosData.isEmpty ? "Add photos" : "Add another")
                    }
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(TravColors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(TravSpacing.md)
                    .background(TravColors.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                }
                .onChange(of: photoItems) { _, items in
                    Task { await loadPhotos(items) }
                }
            }

            Text("Up to \(RatingDraft.maxPhotos) photos.")
                .font(TravTypography.caption())
                .foregroundStyle(TravColors.muted)
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var loaded: [Data] = []
        var images: [UIImage] = []
        for item in items.prefix(RatingDraft.maxPhotos) {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(data)
                images.append(image)
            }
        }
        await MainActor.run {
            photosData = loaded
            photoImages = images
        }
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
            && !radar.scores.isEmpty
            && radar.scores.contains { radar.isEnabled($0.key) }
            && review.count <= 1000
            && !isSubmitting
    }

    private var validationHint: String? {
        if target == nil { return "Pick the experience you finished to start rating." }
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

    /// One rating per user per experience: if they already rated it, this becomes
    /// an edit rather than a second rating.
    private func loadExistingRating(for experienceID: UUID) async {
        guard let userID = session.currentUser?.id else { return }
        let rating = try? await environment.ratings.fetchMyRating(
            userID: userID,
            experienceID: experienceID
        )
        await MainActor.run {
            if let rating {
                existingRating = rating
                radar = rating.radar
                review = rating.review ?? ""
            } else {
                existingRating = nil
            }
        }
    }

    private func submit() {
        guard let target else { return }
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
