import SwiftUI
import PhotosUI

/// "Mark completed" moment: optional note and photos, the emotional payoff
/// after finishing an experience.
struct CompletionSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(EngagementStore.self) private var engagement
    @Environment(\.dismiss) private var dismiss

    let experience: ExperienceSummary
    /// Called with `true` after the completion is saved.
    var onCompleted: ((Bool) -> Void)? = nil

    @State private var note = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var photosData: [Data] = []
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TravSpacing.lg) {
                    VStack(alignment: .leading, spacing: TravSpacing.xxs) {
                        Text("You did it!")
                            .font(TravTypography.displayMedium())
                            .foregroundStyle(TravColors.primary)
                        Text(experience.title)
                            .font(TravTypography.bodyLarge())
                            .foregroundStyle(TravColors.muted)
                            .lineLimit(2)
                    }

                    VStack(alignment: .leading, spacing: TravSpacing.xs) {
                        Text("ADD PHOTOS")
                            .font(TravTypography.overline())
                            .tracking(1.2)
                            .foregroundStyle(TravColors.muted)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: TravSpacing.sm) {
                                PhotosPicker(
                                    selection: $selectedItems,
                                    maxSelectionCount: 4,
                                    matching: .images
                                ) {
                                    VStack(spacing: 6) {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 22))
                                        Text("Add")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundStyle(TravColors.accent)
                                    .frame(width: 88, height: 88)
                                    .background(TravColors.accentSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                                }

                                ForEach(Array(photosData.enumerated()), id: \.offset) { index, data in
                                    if let image = UIImage(data: data) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 88, height: 88)
                                            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                                            .overlay(alignment: .topTrailing) {
                                                Button {
                                                    photosData.remove(at: index)
                                                    if index < selectedItems.count {
                                                        selectedItems.remove(at: index)
                                                    }
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.system(size: 18))
                                                        .foregroundStyle(.white, .black.opacity(0.6))
                                                }
                                                .padding(4)
                                                .accessibilityLabel("Remove photo")
                                            }
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: TravSpacing.xs) {
                        Text("YOUR NOTE")
                            .font(TravTypography.overline())
                            .tracking(1.2)
                            .foregroundStyle(TravColors.muted)

                        TextField(
                            "",
                            text: $note,
                            prompt: Text("What made it memorable? (optional)")
                                .foregroundColor(TravColors.muted),
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                        .padding(TravSpacing.md)
                        .background(TravColors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                        .tint(TravColors.accent)
                    }

                    if let saveError {
                        Text(saveError)
                            .font(TravTypography.caption())
                            .foregroundStyle(TravColors.error)
                    }
                }
                .padding(TravSpacing.lg)
            }
            .travScreenBackground()
            .navigationTitle("Mark Completed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(TravColors.muted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(TravColors.accent)
                        } else {
                            Text("Complete")
                                .fontWeight(.bold)
                                .foregroundStyle(TravColors.accent)
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .onChange(of: selectedItems) { _, items in
            Task {
                var loaded: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        loaded.append(downsampled(data))
                    }
                }
                photosData = loaded
            }
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let completed = await engagement.toggleComplete(
            experienceID: experience.id,
            summary: experience,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            photosData: photosData,
            using: environment
        )
        isSaving = false

        if completed {
            onCompleted?(true)
            dismiss()
        } else {
            saveError = "Couldn't save your completion. Check your connection and try again."
        }
    }

    /// Re-encodes as JPEG capped at ~1600px so uploads stay small.
    private func downsampled(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let maxDimension: CGFloat = 1600
        let largest = max(image.size.width, image.size.height)
        guard largest > maxDimension else {
            return image.jpegData(compressionQuality: 0.82) ?? data
        }
        let scale = maxDimension / largest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.82) ?? data
    }
}
