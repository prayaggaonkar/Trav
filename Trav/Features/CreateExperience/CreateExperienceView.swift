import SwiftUI
import PhotosUI

struct CreateExperienceView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session

    @State private var title = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImagesData: [Data] = []
    @State private var selectedUIImages: [UIImage] = []
    @State private var stops: [StopPreview] = []
    @State private var rating = RadarRating.defaultRating

    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                if showSuccess {
                    successView
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    formContent
                        .transition(.opacity)
                }
            }
            .travScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .animation(TravAnimation.enter, value: showSuccess)
            .alert("Publish Failed", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unexpected error occurred. Please try again.")
            }
        }
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TravSpacing.lg) {
                VStack(alignment: .leading, spacing: TravSpacing.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CREATE EXPERIENCE")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(2.5)
                            .foregroundStyle(TravColors.accent)
                        
                        Text("New Route")
                            .font(TravTypography.displayMedium())
                            .foregroundStyle(TravColors.primary)
                            .lineLimit(1)
                    }
                    
                    Text("Map your favorite stops and share them with the world.")
                        .font(TravTypography.bodyMedium())
                        .foregroundStyle(TravColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, TravSpacing.md)
                .travAppear()

                TravFormSection(title: "Basic Info") {
                    VStack(spacing: TravSpacing.md) {
                        TravTextField(
                            title: "Experience Title",
                            placeholder: "e.g. SF Coffee & Books Tour",
                            text: $title
                        )
                    }
                }
                .travAppear(delay: 0.05)

                TravFormSection(title: "Add Media") {
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
                                    Text("Upload photos of your experience")
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
                                if let data = try? await item.loadTransferable(type: Data.self),
                                   let uiImage = UIImage(data: data) {
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
                .travAppear(delay: 0.08)

                TravFormSection(title: "Stops Along the Way") {
                    VStack(spacing: TravSpacing.sm) {
                        if !stops.isEmpty {
                            VStack(spacing: TravSpacing.xs) {
                                ForEach(stops) { stop in
                                    HStack(spacing: TravSpacing.sm) {
                                        Image(systemName: sfSymbolForEmojiOrCategory(stop.emoji ?? stop.name))
                                            .font(.system(size: 12))
                                            .foregroundStyle(TravColors.accent)
                                        Text(stop.name)
                                            .font(TravTypography.bodyMedium())
                                            .foregroundStyle(TravColors.primary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.9)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Button {
                                            withAnimation(TravAnimation.quick) {
                                                stops.removeAll { $0.id == stop.id }
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
                            }
                        }

                        StopAutocompleteField(stops: $stops)
                    }
                }
                .travAppear(delay: 0.12)

                TravFormSection(title: "Experience Ratings") {
                    InteractiveRadarChartView(rating: $rating)
                }
                .travAppear(delay: 0.15)

                PrimaryButton(
                    title: "Publish Experience",
                    isLoading: isSubmitting,
                    isEnabled: canPublish
                ) {
                    submit()
                }
                .padding(.top, TravSpacing.sm)
                .travAppear(delay: 0.18)
            }
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .padding(.bottom, TravSpacing.xl)
            .safeAreaPadding(.bottom, TravSpacing.sm)
        }
    }

    private var successView: some View {
        VStack(spacing: TravSpacing.xl) {
            Spacer(minLength: TravSpacing.lg)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(TravColors.success)
                .symbolEffect(.bounce, value: showSuccess)

            VStack(spacing: TravSpacing.sm) {
                Text("Experience Published!")
                    .font(TravTypography.displayMedium())
                    .foregroundStyle(TravColors.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                Text("Your itinerary \"\(title)\" is now live!")
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

    private var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !stops.isEmpty
    }

    private func submit() {
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let creatorID: UUID
                if environment.configuration.useMockBackend {
                    creatorID = session.currentUser?.id ?? MockData.creators[0].id
                } else {
                    guard let userId = session.currentUser?.id else {
                        throw RepositoryError.unauthorized
                    }
                    creatorID = userId
                }

                let defaultCityID = MockData.cities.first?.id ?? UUID()

                try await environment.experiences.publishExperience(
                    title: title,
                    cityID: defaultCityID,
                    creatorID: creatorID,
                    stops: stops,
                    rating: rating,
                    imagesData: selectedImagesData
                )

                await MainActor.run {
                    isSubmitting = false
                    withAnimation(TravAnimation.enter) {
                        showSuccess = true
                    }
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
        selectedItems = []
        selectedImagesData = []
        selectedUIImages = []
        stops = []
        showSuccess = false
    }
}
