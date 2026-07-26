import PhotosUI
import SwiftUI
import UIKit

struct EditProfileView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let profile: Profile
    var onSaved: (Profile) -> Void

    @State private var displayName: String
    @State private var username: String
    @State private var bio: String
    @State private var selectedHomeCity: String?
    @State private var homeCitySettled = true
    @State private var avatarImage: UIImage?
    @State private var avatarItem: PhotosPickerItem?
    @State private var removeAvatar = false

    @State private var usernameStatus: UsernameAvailability = .idle
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var usernameCheckTask: Task<Void, Never>?

    init(profile: Profile, onSaved: @escaping (Profile) -> Void) {
        self.profile = profile
        self.onSaved = onSaved
        _displayName = State(initialValue: profile.displayName)
        _username = State(initialValue: profile.username)
        _bio = State(initialValue: profile.bio ?? "")
        _selectedHomeCity = State(initialValue: profile.homeCityLabel)
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var usernameChanged: Bool {
        UsernameValidator.normalize(username) != profile.username.lowercased()
    }

    private var canSave: Bool {
        guard !isSaving else { return false }
        guard !trimmedDisplayName.isEmpty,
              trimmedDisplayName.count <= UsernameValidator.displayNameMax else { return false }
        guard bio.count <= UsernameValidator.bioMax else { return false }
        guard homeCitySettled else { return false }
        if let selectedHomeCity, selectedHomeCity.count > UsernameValidator.homeCityMax { return false }
        if usernameChanged {
            guard case .available = usernameStatus else { return false }
        } else if case .invalid = usernameStatus {
            return false
        }
        return hasChanges
    }

    private var hasChanges: Bool {
        trimmedDisplayName != profile.displayName
            || usernameChanged
            || bio != (profile.bio ?? "")
            || selectedHomeCity != profile.homeCityLabel
            || avatarImage != nil
            || removeAvatar
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TravSpacing.lg) {
                    avatarSection
                    fieldsSection
                    if let errorMessage {
                        Text(errorMessage)
                            .font(TravTypography.caption())
                            .foregroundStyle(TravColors.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.top, TravSpacing.lg)
                .padding(.bottom, TravSpacing.xxl)
            }
            .travScreenBackground()
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(TravColors.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSave)
                    .foregroundStyle(canSave ? TravColors.accent : TravColors.muted)
                }
            }
        }
        .presentationDetents([.large])
        .onChange(of: username) { _, newValue in
            scheduleUsernameCheck(newValue)
        }
        .onChange(of: avatarItem) { _, newItem in
            Task { await loadAvatar(from: newItem) }
        }
    }

    private var avatarSection: some View {
        VStack(spacing: TravSpacing.sm) {
            ZStack {
                if let avatarImage {
                    Image(uiImage: avatarImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 104, height: 104)
                        .clipShape(Circle())
                } else if removeAvatar || profile.avatarURL == nil {
                    AvatarView(url: nil, size: 104)
                } else {
                    AvatarView(url: profile.avatarURL, size: 104)
                }
            }
            .overlay {
                Circle()
                    .stroke(TravColors.border, lineWidth: 1)
            }

            HStack(spacing: TravSpacing.md) {
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    Text(hasCurrentAvatarPreview ? "Change Photo" : "Add Photo")
                        .font(TravTypography.labelMedium())
                        .foregroundStyle(TravColors.accent)
                }
                if hasCurrentAvatarPreview {
                    Button("Remove") {
                        avatarImage = nil
                        avatarItem = nil
                        removeAvatar = true
                        errorMessage = nil
                    }
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(TravColors.error)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// True when the preview is showing a real photo (existing or newly picked), not the placeholder.
    private var hasCurrentAvatarPreview: Bool {
        if avatarImage != nil { return true }
        if removeAvatar { return false }
        return profile.avatarURL != nil
    }

    private var fieldsSection: some View {
        VStack(spacing: TravSpacing.md) {
            TravTextField(title: "Display name", placeholder: "Your name", text: $displayName)
            characterHint(displayName.count, max: UsernameValidator.displayNameMax)

            VStack(alignment: .leading, spacing: TravSpacing.xxs) {
                TravTextField(
                    title: "Username",
                    placeholder: "username",
                    text: $username,
                    contentType: .username,
                    keyboardType: .asciiCapable
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                usernameStatusRow
                characterHint(UsernameValidator.normalize(username).count, max: UsernameValidator.maxLength)
            }

            TravTextField(
                title: "Bio",
                placeholder: "Tell people what you explore",
                text: $bio,
                axis: .vertical
            )
            characterHint(bio.count, max: UsernameValidator.bioMax)

            CityAutocompleteField(
                title: "Home city",
                placeholder: "Search for a city",
                selectedCity: $selectedHomeCity,
                isSettled: $homeCitySettled
            )
        }
    }

    @ViewBuilder
    private var usernameStatusRow: some View {
        switch usernameStatus {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: TravSpacing.xs) {
                ProgressView()
                    .controlSize(.mini)
                Text("Checking availability…")
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
            }
        case .available:
            Label("Username is available", systemImage: "checkmark.circle.fill")
                .font(TravTypography.caption())
                .foregroundStyle(TravColors.success)
        case .unavailable(let reason), .invalid(let reason):
            Label(reason, systemImage: "xmark.circle.fill")
                .font(TravTypography.caption())
                .foregroundStyle(TravColors.error)
        }
    }

    private func characterHint(_ count: Int, max: Int) -> some View {
        Text("\(count)/\(max)")
            .font(TravTypography.caption())
            .foregroundStyle(count > max ? TravColors.error : TravColors.muted)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func scheduleUsernameCheck(_ raw: String) {
        usernameCheckTask?.cancel()
        let normalized = UsernameValidator.normalize(raw)
        if normalized == profile.username.lowercased() {
            usernameStatus = .idle
            return
        }
        let format = UsernameValidator.validateFormat(raw)
        if case .invalid = format {
            usernameStatus = format
            return
        }
        usernameStatus = .checking
        usernameCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            do {
                let result = try await environment.profiles.checkUsernameAvailability(
                    normalized,
                    excludingUserID: profile.id
                )
                guard !Task.isCancelled else { return }
                usernameStatus = result
            } catch {
                usernameStatus = .unavailable(reason: "Couldn’t check username. Try again.")
            }
        }
    }

    private func loadAvatar(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            let image = try await Self.loadUIImage(from: item)
            avatarImage = Self.normalizedAvatarImage(image)
            removeAvatar = false
            errorMessage = nil
        } catch {
            errorMessage = "Couldn’t load that photo. Try a different one."
        }
    }

    private static func loadUIImage(from item: PhotosPickerItem) async throws -> UIImage {
        // Prefer a Transferable image representation — `Data.self` often returns nil
        // for PhotosPicker items (especially HEIC) without throwing.
        if let picked = try await item.loadTransferable(type: PickedAvatarImage.self) {
            return picked.image
        }
        if let data = try await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            return image
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    /// Downscale and redraw so JPEG encoding always succeeds (handles HEIC / wide-gamut).
    private static func normalizedAvatarImage(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 1024
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let size = CGSize(width: max(image.size.width * scale, 1), height: max(image.size.height * scale, 1))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            var update = ProfileUpdate()

            if trimmedDisplayName != profile.displayName {
                update.displayName = trimmedDisplayName
            }
            if usernameChanged {
                update.username = UsernameValidator.normalize(username)
            }
            let originalBio = profile.bio ?? ""
            if bio != originalBio {
                let trimmed = bio.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    update.clearBio = true
                } else {
                    update.bio = trimmed
                }
            }
            let originalCity = profile.homeCityLabel
            if selectedHomeCity != originalCity {
                if let selectedHomeCity, !selectedHomeCity.isEmpty {
                    update.homeCityName = selectedHomeCity
                } else {
                    update.clearHomeCity = true
                }
            }

            if removeAvatar {
                update.clearAvatar = true
            } else if let avatarImage {
                guard let data = avatarImage.jpegData(compressionQuality: 0.85) else {
                    errorMessage = "Couldn’t process that photo."
                    return
                }
                let url = try await environment.profiles.uploadAvatar(userID: profile.id, imageData: data)
                update.avatarURL = url
            }

            guard update.hasChanges else {
                dismiss()
                return
            }

            let updated = try await environment.profiles.updateProfile(userID: profile.id, update: update)
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = friendlyAvatarError(error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func friendlyAvatarError(_ error: Error) -> String {
        let text = error.localizedDescription.lowercased()
        if text.contains("bucket") || text.contains("not found") || text.contains("row-level security")
            || text.contains("unauthorized") || text.contains("storage") {
            return "Couldn’t upload your photo. Check that you’re signed in and try again."
        }
        return error.localizedDescription
    }
}

/// PhotosPicker-friendly image transfer — more reliable than `Data.self` alone.
private struct PickedAvatarImage: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            guard let image = UIImage(data: data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return PickedAvatarImage(image: image)
        }
    }
}
