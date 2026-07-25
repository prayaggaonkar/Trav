import SwiftUI

// MARK: - Search

struct CitySearchBar: View {
    @Binding var text: String
    let cityName: String

    private var placeholder: String {
        "Search experiences in \(cityName)..."
    }

    var body: some View {
        FeedSearchBar(
            text: $text,
            placeholder: placeholder,
            isFocused: .constant(false)
        )
    }
}

/// Feed / discovery search field with optional focus binding and inline filter tokens.
struct FeedSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search spots, cities, creators..."
    @Binding var isFocused: Bool
    var isLightMode: Bool = false
    var cityToken: City? = nil
    var userToken: ProfileSummary? = nil
    var onClearCity: (() -> Void)? = nil
    var onClearUser: (() -> Void)? = nil

    @FocusState private var fieldFocused: Bool

    private var hasTokens: Bool {
        cityToken != nil || userToken != nil
    }

    private var resolvedPlaceholder: String {
        if hasTokens { return "Add keyword..." }
        return placeholder
    }

    var body: some View {
        HStack(spacing: TravSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TravColors.muted)
                .accessibilityHidden(true)

            if let cityToken {
                FeedSearchToken(
                    icon: "mappin.circle.fill",
                    label: cityToken.name,
                    isLightMode: isLightMode,
                    accessibilityLabel: "Filtering by \(cityToken.name)",
                    onClear: { onClearCity?() }
                )
            }

            if let userToken {
                FeedSearchToken(
                    icon: "person.crop.circle.fill",
                    label: "@\(userToken.username)",
                    isLightMode: isLightMode,
                    accessibilityLabel: "Filtering by @\(userToken.username)",
                    onClear: { onClearUser?() }
                )
            }

            TextField(resolvedPlaceholder, text: $text)
                .font(TravTypography.bodyMedium())
                .foregroundStyle(isLightMode ? Color.black : Color.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .lineLimit(1)
                .focused($fieldFocused)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !text.isEmpty || hasTokens {
                Button {
                    if !text.isEmpty {
                        withAnimation {
                            text = ""
                        }
                    } else {
                        onClearCity?()
                        onClearUser?()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(TravColors.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(text.isEmpty ? "Clear filters" : "Clear search")
            }
        }
        .padding(.horizontal, TravSpacing.md)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: TravRadius.md)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, isLightMode ? .light : .dark)
        )
        .overlay {
            RoundedRectangle(cornerRadius: TravRadius.md)
                .stroke(
                    isLightMode
                        ? Color.black.opacity(0.12)
                        : Color.white.opacity(0.15),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(resolvedPlaceholder)
        .onChange(of: fieldFocused) { _, focused in
            isFocused = focused
        }
        .onChange(of: isFocused) { _, focused in
            if fieldFocused != focused {
                fieldFocused = focused
            }
        }
    }
}

/// Compact removable token rendered inside the search field.
struct FeedSearchToken: View {
    let icon: String
    let label: String
    var isLightMode: Bool = false
    var accessibilityLabel: String
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TravColors.accent)

            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isLightMode ? Color.black : Color.white)
                .lineLimit(1)

            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(TravColors.muted)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(label)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(TravColors.accent.opacity(isLightMode ? 0.12 : 0.2))
        )
        .overlay {
            Capsule()
                .stroke(TravColors.accent.opacity(0.3), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Removable chip for the active Feed city scope (legacy external placement).
struct FeedCityChip: View {
    let city: City
    var isLightMode: Bool = false
    let onClear: () -> Void

    var body: some View {
        FeedSearchToken(
            icon: "mappin.circle.fill",
            label: city.name,
            isLightMode: isLightMode,
            accessibilityLabel: "Filtering by \(city.name)",
            onClear: onClear
        )
    }
}

// MARK: - Featured

struct HeroExperienceCard: View {
    let experience: ExperienceSummary
    let badgeText: String
    var isSaved: Bool = false
    var isLiked: Bool = false
    var onTap: () -> Void
    var onCreatorTap: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    var onLike: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 1. Complex Background canvas: Navy blue to vibrant violet-purple gradient
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.06, blue: 0.18), // Deep navy bottom left
                        Color(red: 0.12, green: 0.08, blue: 0.32), // Transitioning indigo
                        Color(red: 0.38, green: 0.15, blue: 0.72)  // Vibrant violet top right
                    ],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )

                if let imageURL = experience.coverImageURL {
                    RemoteImage(
                        url: imageURL,
                        height: 220,
                        cornerRadius: 0
                    )
                    .opacity(0.28)
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0.06, blue: 0.18).opacity(0.6),
                                Color(red: 0.38, green: 0.15, blue: 0.72).opacity(0.75)
                            ],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        )
                    }
                }

                // Nebula purple glow near top-right / right side
                RadialGradient(
                    colors: [
                        Color(red: 0.65, green: 0.28, blue: 0.98).opacity(0.45),
                        Color(red: 0.45, green: 0.18, blue: 0.85).opacity(0.2),
                        .clear
                    ],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 220
                )

                // Frosted glass material overlay
                Rectangle()
                    .fill(.thinMaterial)
                    .opacity(0.12)
            }

            // 2. Right Side: Circular Rating Progress Bar (moved below action buttons, diameter matching button width)
            HStack {
                Spacer()
                CircularRatingView(rating: displayRating, size: 88)
                    .padding(.trailing, 20)
                    .padding(.top, 74)
            }

            // 3. Card Foreground Layout
            VStack(alignment: .leading, spacing: 0) {
                // Top Row: Badge & Action Buttons
                HStack(alignment: .top) {
                    if !badgeText.isEmpty {
                        FrostedGlassBadge(text: badgeText)
                    } else {
                        Spacer(minLength: 0)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 10) {
                        CityCardActionButton(
                            systemName: isSaved ? "bookmark.fill" : "bookmark",
                            isActive: isSaved
                        ) { onSave?() }

                        CityCardActionButton(
                            systemName: "square.and.arrow.up",
                            isActive: false
                        ) { onShare?() }
                    }
                }

                // Title: Large Bold Crisp White (placed directly below badge)
                Text(experience.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1.5)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                // Author Row
                Button {
                    onCreatorTap?()
                } label: {
                    HStack(spacing: 6) {
                        if let url = experience.creator.avatarURL {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 20, height: 20)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                        }

                        Text("by \(experience.creator.displayName)")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(onCreatorTap == nil)
                .padding(.top, 6)

                Spacer(minLength: 16)

                // Bottom Left City / Subtitle Label
                Text(cityLabel)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(20)
        }
        .frame(minHeight: 220)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.65),
                            .white.opacity(0.2),
                            Color(red: 0.65, green: 0.35, blue: 1.0).opacity(0.4)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: Color(red: 0.20, green: 0.08, blue: 0.45).opacity(0.45), radius: 20, x: 0, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: onTap)
    }

    private var cityLabel: String {
        if let name = experience.cityName, !name.isEmpty { return name }
        return MockData.cities.first(where: { $0.id == experience.cityID })?.name ?? experience.displayCityName
    }

    private var displayRating: Double {
        let hash = abs(experience.id.hashValue)
        let score = 4.3 + Double(hash % 7) * 0.1
        return min(score, 4.9)
    }
}

/// Circular progress bar displaying experience rating out of 5.
struct CircularRatingView: View {
    let rating: Double // e.g. 4.8
    var maxRating: Double = 5.0
    var size: CGFloat = 88 // Diameter equals width of the two top action buttons

    var body: some View {
        let progress = min(max(rating / maxRating, 0.0), 1.0)

        ZStack {
            // Glass background disk
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.20, green: 0.12, blue: 0.45).opacity(0.4),
                                    Color(red: 0.10, green: 0.06, blue: 0.28).opacity(0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )

            // Outer track ring
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 6)

            // Circular progress bar filled up proportionately to the rating out of 5
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.78, green: 0.38, blue: 1.0), // Glowing violet
                            Color(red: 0.38, green: 0.68, blue: 1.0)  // Glowing cyan
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Color(red: 0.70, green: 0.35, blue: 1.0).opacity(0.85), radius: 8, x: 0, y: 0)

            // Glass rim border
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .white.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )

            // Rating number only (no star, no /5)
            Text(String(format: "%.1f", rating))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1.5)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.15, green: 0.08, blue: 0.35).opacity(0.4), radius: 12, x: 0, y: 6)
    }
}

/// Refined, translucent purple pill-shaped badge with sparkles icon and soft edge glow.
struct FrostedGlassBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Text(text)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.58, green: 0.28, blue: 0.98),
                                Color(red: 0.42, green: 0.16, blue: 0.88)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Capsule()
                    .fill(.ultraThinMaterial.opacity(0.2))
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.85), Color(red: 0.75, green: 0.45, blue: 1.0).opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: Color(red: 0.65, green: 0.35, blue: 1.0).opacity(0.75), radius: 10, x: 0, y: 0)
    }
}

struct FeaturedExperienceCard: View {
    let experience: ExperienceSummary
    var isSaved: Bool = false
    var isLiked: Bool = false
    var onTap: () -> Void
    var onCreatorTap: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    var onLike: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil

    var body: some View {
        StandardExperienceCard(
            experience: experience,
            badgeText: "Featured",
            isSaved: isSaved,
            isLiked: isLiked,
            onTap: onTap,
            onCreatorTap: onCreatorTap,
            onSave: onSave,
            onLike: onLike,
            onShare: onShare
        )
    }
}

struct UserCreatedExperienceCard: View {
    let experience: ExperienceSummary
    var isSaved: Bool = false
    var isLiked: Bool = false
    var onTap: () -> Void
    var onCreatorTap: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    var onLike: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil

    var body: some View {
        HeroExperienceCard(
            experience: experience,
            badgeText: "Created by Me",
            isSaved: isSaved,
            isLiked: isLiked,
            onTap: onTap,
            onCreatorTap: onCreatorTap,
            onSave: onSave,
            onLike: onLike,
            onShare: onShare
        )
    }
}

// MARK: - Creators

struct TrendingCreatorsSection: View {
    let creators: [Profile]
    var onSelect: (Profile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            Text("Trending Creators")
                .font(TravTypography.titleMedium())
                .foregroundStyle(TravColors.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TravSpacing.screenHorizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TravSpacing.md) {
                    ForEach(creators) { creator in
                        Button {
                            onSelect(creator)
                        } label: {
                            TrendingCreatorCard(creator: creator)
                        }
                        .buttonStyle(TravPressButtonStyle(scale: 0.96))
                    }
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
            }
        }
    }
}

private struct TrendingCreatorCard: View {
    let creator: Profile

    var body: some View {
        VStack(spacing: TravSpacing.xs) {
            AvatarView(url: creator.avatarURL, size: 56)

            Text(creator.displayName)
                .font(TravTypography.labelMedium())
                .foregroundStyle(TravColors.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)

            Text("\(TravFormatters.count(creator.followerCount)) followers")
                .font(TravTypography.caption())
                .foregroundStyle(TravColors.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
        }
        .frame(width: TravLayout.creatorCardWidth)
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(creator.displayName), \(creator.followerCount) followers")
    }
}

// MARK: - Compact card actions

struct CityCardActionButton: View {
    let systemName: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .fill(
                        isActive
                            ? Color(red: 0.63, green: 0.28, blue: 1.0).opacity(0.45)
                            : Color.white.opacity(0.12)
                    )
            }
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: isActive
                                ? [.white.opacity(0.7), Color(red: 0.75, green: 0.45, blue: 1.0)]
                                : [.white.opacity(0.45), .white.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isActive ? Color(red: 0.63, green: 0.28, blue: 1.0).opacity(0.6) : .black.opacity(0.25),
                radius: isActive ? 8 : 4,
                x: 0,
                y: 2
            )
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.92))
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.92))
        .frame(width: TravLayout.minTouchTarget, height: TravLayout.minTouchTarget)
        .contentShape(Rectangle())
    }
}

// MARK: - Navigation chrome

struct CityBackButton: View {
    let action: () -> Void
    var prominent = true

    private let size: CGFloat = 36

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(prominent ? .white : TravColors.primary)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(
                        prominent
                            ? Color.black.opacity(0.5)
                            : TravColors.surfaceElevated
                    )
                )
        }
        .buttonStyle(.plain)
        .frame(width: TravLayout.minTouchTarget, height: TravLayout.minTouchTarget)
        .contentShape(Circle())
        .accessibilityLabel("Back to globe")
    }
}

// MARK: - Scroll offset

struct CityScrollOffsetKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
