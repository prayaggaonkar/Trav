import SwiftUI

// MARK: - Search

struct CitySearchBar: View {
    @Binding var text: String
    let cityName: String

    private var placeholder: String {
        "Search experiences in \(cityName)..."
    }

    var body: some View {
        HStack(spacing: TravSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(TravColors.muted)
                .accessibilityHidden(true)

            TextField(placeholder, text: $text)
                .font(TravTypography.bodyMedium())
                .foregroundStyle(TravColors.primary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(TravColors.muted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, TravSpacing.md)
        .frame(height: TravLayout.citySearchHeight)
        .frame(maxWidth: .infinity)
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.xl, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(placeholder)
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
        let hasImage = experience.coverImageURL != nil

        ZStack(alignment: .bottomLeading) {
            // Background Image / Gradient Fill
            if let imageURL = experience.coverImageURL {
                RemoteImage(
                    url: imageURL,
                    height: 200,
                    cornerRadius: TravRadius.lg
                )
                
                LinearGradient(
                    colors: [
                        .black.opacity(0.1),
                        .black.opacity(0.4),
                        .black.opacity(0.88)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                ZStack(alignment: .topTrailing) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.14, green: 0.16, blue: 0.24),
                            Color(red: 0.08, green: 0.09, blue: 0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    RadialGradient(
                        colors: [
                            TravColors.accent.opacity(0.25),
                            .clear
                        ],
                        center: .topTrailing,
                        startRadius: 10,
                        endRadius: 180
                    )

                    Image(systemName: "map.fill")
                        .font(.system(size: 80, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.05))
                        .padding(.trailing, 20)
                        .padding(.top, 20)
                }
                .frame(height: 200)
            }

            // Card Overlay Content
            VStack(alignment: .leading, spacing: TravSpacing.xs) {
                if !badgeText.isEmpty {
                    Text(badgeText)
                        .font(TravTypography.caption())
                        .fontWeight(.bold)
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, TravSpacing.xs + 2)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(TravColors.accent.opacity(0.85))
                        )
                }

                Text(experience.title)
                    .font(TravTypography.titleLarge())
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    onCreatorTap?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.circle.fill")
                            .font(.caption)
                        Text("by \(experience.creator.displayName)")
                            .font(TravTypography.caption())
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(onCreatorTap == nil)

                Spacer(minLength: TravSpacing.xs)

                RoutePreview(
                    stops: experience.stops,
                    maxVisibleStops: 4,
                    compact: true,
                    style: .editorial
                )
            }
            .padding(TravSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Top-Right Action Controls — above the card tap target so Save never
            // competes with the parent onTapGesture.
            HStack(spacing: TravSpacing.xs) {
                CityCardActionButton(
                    systemName: isSaved ? "bookmark.fill" : "bookmark",
                    isActive: isSaved
                ) { onSave?() }
                if onShare != nil {
                    CityCardActionButton(
                        systemName: "square.and.arrow.up",
                        isActive: false
                    ) { onShare?() }
                }
            }
            .padding(TravSpacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .zIndex(2)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(badgeText) experience \(experience.title)")
        .accessibilityAction(named: "Open") { onTap() }
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
        HeroExperienceCard(
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
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? TravColors.accent : .white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.black.opacity(0.45)))
        }
        .buttonStyle(.borderless)
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
