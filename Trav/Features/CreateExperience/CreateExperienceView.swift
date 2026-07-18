import SwiftUI
import PhotosUI

struct CreateExperienceView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session

    @State private var title = ""
    @State private var description = ""
    @State private var selectedCity: City?
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var selectedUIImage: UIImage? = nil
    @State private var cities: [City] = []
    @State private var stops: [StopPreview] = []
    @State private var newStopName = ""
    @State private var newStopEmoji = "📍"

    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    let emojis = ["📍", "☕", "📚", "🍜", "🌃", "🍕", "🌳", "🏛️", "🍷", "🏖️", "🛍️", "🏨"]

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
            .task {
                do {
                    cities = try await environment.cities.fetchGlobeCities()
                } catch {}
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
                        TravTextField(
                            title: "Description",
                            placeholder: "What makes this experience special?",
                            text: $description,
                            axis: .vertical
                        )
                    }
                }
                .travAppear(delay: 0.05)

                TravFormSection(title: "Cover Photo") {
                    VStack(alignment: .center, spacing: TravSpacing.sm) {
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            if let selectedUIImage {
                                Image(uiImage: selectedUIImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 180)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.md))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: TravRadius.md)
                                            .stroke(TravColors.primary.opacity(0.15), lineWidth: 1)
                                    )
                                    .overlay(
                                        Text("Change Cover Photo")
                                            .font(TravTypography.labelMedium())
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, TravSpacing.md)
                                            .padding(.vertical, TravSpacing.xs)
                                            .background(.black.opacity(0.58))
                                            .clipShape(Capsule())
                                    )
                            } else {
                                VStack(spacing: TravSpacing.xs) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 28))
                                        .foregroundStyle(TravColors.accent)
                                    Text("Add Cover Photo")
                                        .font(TravTypography.labelMedium())
                                        .foregroundStyle(TravColors.primary)
                                    Text("Upload an image of a place you visited")
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
                        }
                        .buttonStyle(.plain)
                    }
                    .onChange(of: selectedItem) { _, newItem in
                        Task {
                            if let newItem {
                                if let data = try? await newItem.loadTransferable(type: Data.self) {
                                    selectedImageData = data
                                    selectedUIImage = UIImage(data: data)
                                }
                            }
                        }
                    }
                }
                .travAppear(delay: 0.08)

                TravFormSection(title: "Destination City") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: TravSpacing.sm) {
                            ForEach(cities) { city in
                                SelectionChip(
                                    title: city.name,
                                    isSelected: selectedCity?.id == city.id
                                ) {
                                    selectedCity = city
                                }
                            }
                        }
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                    }
                    .padding(.horizontal, -TravSpacing.screenHorizontal)
                }
                .travAppear(delay: 0.1)

                TravFormSection(title: "Stops Along the Way") {
                    VStack(spacing: TravSpacing.sm) {
                        if !stops.isEmpty {
                            VStack(spacing: TravSpacing.xs) {
                                ForEach(stops) { stop in
                                    HStack(spacing: TravSpacing.sm) {
                                        Text(stop.emoji ?? "📍")
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

                        HStack(spacing: TravSpacing.xs) {
                            Menu {
                                ForEach(emojis, id: \.self) { emoji in
                                    Button(emoji) { newStopEmoji = emoji }
                                }
                            } label: {
                                Text(newStopEmoji)
                                    .font(.title2)
                                    .frame(width: TravLayout.minTouchTarget, height: TravLayout.minTouchTarget)
                                    .background(TravColors.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.sm, style: .continuous))
                            }

                            TextField("Add a new stop name...", text: $newStopName)
                                .font(TravTypography.bodyLarge())
                                .padding(TravSpacing.md)
                                .frame(minHeight: TravLayout.minTouchTarget)
                                .background(TravColors.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))

                            Button(action: addStop) {
                                Image(systemName: "plus")
                                    .font(.system(size: TravIcon.sm, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: TravLayout.minTouchTarget, height: TravLayout.minTouchTarget)
                                    .background(TravColors.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.sm, style: .continuous))
                            }
                            .buttonStyle(TravPressButtonStyle())
                        }
                    }
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
                .travAppear(delay: 0.2)
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
                Text("Your itinerary \"\(title)\" is now live on the globe of \(selectedCity?.name ?? "the world")!")
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
        selectedCity != nil &&
        !stops.isEmpty
    }

    private func addStop() {
        guard !newStopName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(TravAnimation.enter) {
            stops.append(StopPreview(id: UUID(), name: newStopName, emoji: newStopEmoji))
            newStopName = ""
            newStopEmoji = "📍"
        }
    }

    private func submit() {
        guard let selectedCity = selectedCity else { return }

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

                try await environment.experiences.publishExperience(
                    title: title,
                    description: description,
                    cityID: selectedCity.id,
                    creatorID: creatorID,
                    stops: stops,
                    imageData: selectedImageData
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
        description = ""
        selectedItem = nil
        selectedImageData = nil
        selectedUIImage = nil
        selectedCity = nil
        stops = []
        showSuccess = false
    }
}
