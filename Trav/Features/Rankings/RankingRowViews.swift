import SwiftUI

// MARK: - Leaderboard User Row View

struct LeaderboardUserRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TravSpacing.md) {
                // Rank number
                Text("\(rank)")
                    .font(TravTypography.bodyLarge())
                    .fontWeight(.bold)
                    .foregroundStyle(rank <= 3 ? TravColors.primary : TravColors.muted.opacity(0.8))
                    .frame(width: 24, alignment: .leading)

                // Avatar / Initials badge fallback
                LeaderboardAvatarView(
                    url: entry.avatarURL,
                    name: entry.displayName,
                    size: 42
                )

                // Username handle
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(entry.username)")
                        .font(TravTypography.bodyLarge())
                        .fontWeight(.semibold)
                        .foregroundStyle(TravColors.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: TravSpacing.xs)

                // Count of experiences created
                Text("\(entry.experienceCount)")
                    .font(TravTypography.titleMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(TravColors.primary)
                    .monospacedDigit()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .contentShape(Rectangle())
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.98))
    }
}

// MARK: - Leaderboard Avatar View with Initials Fallback

struct LeaderboardAvatarView: View {
    let url: URL?
    let name: String
    let size: CGFloat

    private var initials: String {
        let parts = name.split(separator: " ").compactMap { $0.first }
        if parts.count >= 2 {
            return String([parts[0], parts[1]]).uppercased()
        } else if let first = name.first {
            return String(first).uppercased()
        }
        return "U"
    }

    var body: some View {
        if let url {
            RemoteImage(url: url, height: size, cornerRadius: size / 2)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(TravColors.surfaceElevated)
                    .overlay(
                        Circle().stroke(TravColors.border.opacity(0.5), lineWidth: 1)
                    )
                Text(initials)
                    .font(TravTypography.caption())
                    .fontWeight(.bold)
                    .foregroundStyle(TravColors.muted)
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Filter Pill Button View

struct FilterPillButton: View {
    let title: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(title)
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(TravColors.primary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TravColors.primary.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(TravColors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(TravColors.border.opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.96))
    }
}

// MARK: - Member Scope Modal Sheet

struct MemberFilterModalSheet: View {
    let selectedScope: MemberScopeFilter
    let onSelect: (MemberScopeFilter) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: TravSpacing.md) {
            HStack {
                Text("Filter Members")
                    .font(TravTypography.titleLarge())
                    .foregroundStyle(TravColors.primary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(TravColors.muted.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, TravSpacing.md)

            VStack(spacing: TravSpacing.sm) {
                ForEach(MemberScopeFilter.allCases) { scope in
                    Button {
                        onSelect(scope)
                        dismiss()
                    } label: {
                        HStack(spacing: TravSpacing.md) {
                            ZStack {
                                Circle()
                                    .fill(selectedScope == scope ? TravColors.accent.opacity(0.18) : TravColors.surfaceElevated)
                                    .frame(width: 40, height: 40)
                                Image(systemName: scope.iconName)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(selectedScope == scope ? TravColors.accent : TravColors.muted)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(scope.title)
                                    .font(TravTypography.bodyLarge())
                                    .fontWeight(.semibold)
                                    .foregroundStyle(TravColors.primary)
                                Text(scope.subtitle)
                                    .font(TravTypography.caption())
                                    .foregroundStyle(TravColors.muted)
                            }

                            Spacer()

                            if selectedScope == scope {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(TravColors.accent)
                            }
                        }
                        .padding(TravSpacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                .fill(selectedScope == scope ? TravColors.surfaceElevated : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                .stroke(selectedScope == scope ? TravColors.accent.opacity(0.4) : TravColors.border.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .travScreenBackground()
        .presentationDetents([.height(280), .medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(TravRadius.xl)
    }
}

// MARK: - Location Filter Modal Sheet (With MapKit City Search)

struct LocationFilterModalSheet: View {
    let availableLocations: [LocationOption]
    let selectedLocation: LocationOption
    let onSelect: (LocationOption) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var customCityName: String? = nil
    @State private var isSettled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: TravSpacing.md) {
            HStack {
                Text("Select Location")
                    .font(TravTypography.titleLarge())
                    .foregroundStyle(TravColors.primary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(TravColors.muted.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, TravSpacing.md)

            // Autocomplete city search (same MapKit search as profile page)
            CityAutocompleteField(
                title: "",
                placeholder: "Search for any city worldwide...",
                selectedCity: $customCityName,
                isSettled: $isSettled
            )
            .onChange(of: customCityName) { _, newCity in
                if let newCity, !newCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let option = LocationOption(id: "city_\(newCity.lowercased())", name: newCity, subtitle: nil)
                    onSelect(option)
                    dismiss()
                }
            }

            Text("POPULAR LOCATIONS")
                .font(TravTypography.overline())
                .tracking(2.0)
                .foregroundStyle(TravColors.muted)
                .padding(.top, TravSpacing.xs)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(availableLocations) { location in
                        Button {
                            onSelect(location)
                            dismiss()
                        } label: {
                            HStack(spacing: TravSpacing.md) {
                                ZStack {
                                    Circle()
                                        .fill(selectedLocation.id == location.id ? TravColors.accent.opacity(0.18) : TravColors.surfaceElevated)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: location.id == LocationOption.allLocations.id ? "globe" : "mappin.circle.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(selectedLocation.id == location.id ? TravColors.accent : TravColors.muted)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(location.name)
                                        .font(TravTypography.bodyLarge())
                                        .foregroundStyle(TravColors.primary)
                                    if let sub = location.subtitle {
                                        Text(sub)
                                            .font(TravTypography.caption())
                                            .foregroundStyle(TravColors.muted)
                                    }
                                }

                                Spacer()

                                if selectedLocation.id == location.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(TravColors.accent)
                                }
                            }
                            .padding(.horizontal, TravSpacing.md)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                    .fill(selectedLocation.id == location.id ? TravColors.surfaceElevated : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .travScreenBackground()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(TravRadius.xl)
    }
}
