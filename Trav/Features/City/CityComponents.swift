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
    var connectedLayout: Bool = false
    var onTap: () -> Void
    var onCreatorTap: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    var onLike: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    var onComment: (() -> Void)? = nil

    @Environment(EngagementStore.self) private var engagement
    @State private var resolvedLocation: String?

    /// Reserved leading slot — same width with or without a cover photo.
    private let coverWidth: CGFloat = 96
    /// Fixed height so "Created by You" never grows the card.
    private let cardHeight: CGFloat = 128
    private let cardCornerRadius: CGFloat = 18

    private var showRating: Bool {
        true
    }

    private var hasCoverImage: Bool {
        experience.coverImageURL != nil
    }

    private var isCreatedByYou: Bool {
        !badgeText.isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear
                .frame(width: coverWidth)
                .frame(height: cardHeight)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(experience.title)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(TravColors.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)

                        Text(locationLabel)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(TravColors.muted)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        // Visited by / Completed by badge & Author line at very bottom
                        VStack(alignment: .leading, spacing: 6) {
                            let isSpotCard = experience.isSpot
                            let systemNames = ["rec by trav", "system", "trav editorial", "editorial", "trav"]
                            let creatorName = experience.creator.displayName.lowercased()
                            let isRecByTrav = experience.isTravOwned || systemNames.contains(creatorName)

                            // 1. Visited by / Completed by badge — ONLY displayed if current user follows a friend who completed it!
                            let followedCompleters = experience.completedBy.filter { user in
                                user.id != experience.creator.id && engagement.isFollowing(user.id)
                            }

                            if let friendVisitor = followedCompleters.first {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color(red: 0.2, green: 0.85, blue: 0.45))

                                    AvatarView(url: URL(string: friendVisitor.avatarImage), size: 14)

                                    Group {
                                        Text(isSpotCard ? "Visited by " : "Completed by ")
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .foregroundStyle(TravColors.muted) +
                                        Text(friendVisitor.name)
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .foregroundStyle(TravColors.primary)
                                    }
                                    .lineLimit(1)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Color(red: 0.2, green: 0.85, blue: 0.45).opacity(0.12))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(Color(red: 0.2, green: 0.85, blue: 0.45).opacity(0.25), lineWidth: 1)
                                )
                                .padding(.bottom, 5)
                            }

                            // 2. Author line — ALWAYS displayed at the VERY BOTTOM of the card
                            HStack(spacing: 4) {
                                if isRecByTrav {
                                    Button {
                                        onCreatorTap?()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text("by Trav")
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .foregroundStyle(TravColors.muted)
                                            Image(systemName: "checkmark.seal.fill")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(TravColors.accent)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(onCreatorTap == nil)
                                } else if isCreatedByYou && !isSpotCard {
                                    Text(badgeText)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(TravColors.muted)
                                        .lineLimit(1)
                                } else {
                                    Button {
                                        onCreatorTap?()
                                    } label: {
                                        HStack(spacing: 5) {
                                            AvatarView(url: experience.creator.avatarURL, size: 18)
                                            Text("by \(experience.creator.displayName)")
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                                .foregroundStyle(TravColors.muted)
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(onCreatorTap == nil)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    // Bookmark + share + rating — group midpoint centered on the card.
                    VStack(alignment: .center, spacing: 16) {
                        HStack(spacing: 8) {
                            Button {
                                onSave?()
                            } label: {
                                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(isSaved ? Color.yellow : TravColors.muted)
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isSaved ? "Remove bookmark" : "Bookmark")

                            Button {
                                onShare?()
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(TravColors.muted)
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Share")
                        }

                        let isSpotCard = experience.isSpot
                        let resolvedScore = experience.ratingSummary.displayScore ?? experience.rating?.overallScore
                        let hasAnyRating = experience.ratingSummary.ratingCount > 0
                            || experience.ratingSummary.communityRatingCount > 0
                            || (resolvedScore ?? 0) > 0

                        if isSpotCard && !hasAnyRating {
                            // Destinations start unrated — grey circle with dashes.
                            CircularRatingView(unratedSize: 40)
                        } else if let score = resolvedScore, score > 0 {
                            CircularRatingView(
                                rating: score,
                                size: 40,
                                isCommunityValidated: experience.showsCommunityValidatedScore
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 15)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: cardHeight)
        .background(alignment: .leading) {
            // Paint photo cover or stops map cover in the reserved slot; crop to width.
            coverImage
                .frame(width: coverWidth, height: cardHeight)
                .clipped()
        }
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: connectedLayout ? 0 : cardCornerRadius, style: .continuous))
        .overlay {
            if connectedLayout {
                VStack {
                    Spacer()
                    Divider()
                        .background(TravColors.border.opacity(0.3))
                }
            } else {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .stroke(TravColors.border.opacity(0.4), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: connectedLayout ? 0 : cardCornerRadius, style: .continuous))
        .onTapGesture(perform: onTap)
        .task(id: experience.id) {
            resolvedLocation = await resolveLocationLabel()
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        ZStack {
            if let imageURL = experience.coverImageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: coverWidth, height: cardHeight)
                            .clipped()
                    default:
                        ExperienceStopsMapView(experience: experience)
                            .frame(width: coverWidth, height: cardHeight)
                    }
                }
            } else {
                ExperienceStopsMapView(experience: experience)
                    .frame(width: coverWidth, height: cardHeight)
            }
        }
        .frame(width: coverWidth, height: cardHeight)
        .clipped()
        .allowsHitTesting(false)
    }

    private var locationLabel: String {
        if let resolvedLocation, !resolvedLocation.isEmpty {
            return resolvedLocation
        }
        return fallbackLocationLabel
    }

    private var fallbackLocationLabel: String {
        if let city = MockData.cities.first(where: { $0.id == experience.cityID }) {
            return city.locationLabel
        }
        if let name = experience.cityName, !name.isEmpty {
            if let city = MockData.cities.first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }) {
                return city.locationLabel
            }
            return name
        }
        return experience.displayCityName
    }

    private func resolveLocationLabel() async -> String {
        if let city = try? await CityCatalog.shared.city(id: experience.cityID) {
            return city.locationLabel
        }
        if let name = experience.cityName,
           let city = try? await CityCatalog.shared.city(named: name) {
            return city.locationLabel
        }
        return fallbackLocationLabel
    }

}

/// Circular progress bar displaying experience rating out of 10.0.
/// Ring purple scales hard with score — dull at ~5, strong glowing at 10.
/// A creator-only score renders grey: it is a claim, not community validation.
/// Pass `rating: nil` for an unrated placeholder (grey ring + dashes).
struct CircularRatingView: View {
    let rating: Double?
    var maxRating: Double = 10.0
    var size: CGFloat = 88
    var isCommunityValidated: Bool = true

    init(
        rating: Double,
        maxRating: Double = 10.0,
        size: CGFloat = 88,
        isCommunityValidated: Bool = true
    ) {
        self.rating = rating
        self.maxRating = maxRating
        self.size = size
        self.isCommunityValidated = isCommunityValidated
    }

    /// Grey ring with dashes — used for spots before anyone has rated.
    init(unratedSize size: CGFloat, maxRating: Double = 10.0) {
        self.rating = nil
        self.maxRating = maxRating
        self.size = size
        self.isCommunityValidated = false
    }

    var body: some View {
        let isUnrated = rating == nil
        let score = rating ?? 0
        // Unrated uses a full muted ring so it matches creator-only chrome (not a faint empty track).
        let progress = isUnrated ? 1.0 : min(max(score / maxRating, 0.0), 1.0)
        let intensity = pow(progress, 1.65)
        let strokeWidth = max(2.5, size * (0.07 + 0.04 * intensity))
        let fontSize = size * 0.3
        let showPurple = isCommunityValidated && !isUnrated
        let ringColor = showPurple ? Self.purple(intensity: intensity) : TravColors.muted
        let glowOpacity = showPurple ? (0.08 + 0.85 * intensity) : 0.0
        let glowRadius = size * (0.04 + 0.22 * intensity)

        ZStack {
            Circle()
                .fill(TravColors.border.opacity(0.2))

            Circle()
                .stroke(ringColor.opacity(0.12 + 0.2 * intensity), lineWidth: strokeWidth)

            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(glowOpacity), radius: glowRadius, x: 0, y: 0)
                .shadow(color: ringColor.opacity(glowOpacity * 0.55), radius: glowRadius * 0.45, x: 0, y: 0)

            Text(isUnrated ? "--" : String(format: "%.1f", score))
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(TravColors.primary)
        }
        .frame(width: size, height: size)
        .animation(TravAnimation.quick, value: rating)
        .accessibilityLabel(
            isUnrated
                ? "Not rated yet"
                : (isCommunityValidated
                    ? "Community rating \(TravFormatters.score(score)) out of 10"
                    : "Creator rating \(TravFormatters.score(score)) out of 10, no community ratings yet")
        )
    }

    /// Dull gray-purple at low intensity → rich, electric purple at full strength.
    private static func purple(intensity t: Double) -> Color {
        let low = (r: 0.30, g: 0.28, b: 0.36)
        let high = (r: 0.78, g: 0.36, b: 1.0)
        return Color(
            red: low.r + (high.r - low.r) * t,
            green: low.g + (high.g - low.g) * t,
            blue: low.b + (high.b - low.b) * t
        )
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
            badgeText: "Created by You",
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
