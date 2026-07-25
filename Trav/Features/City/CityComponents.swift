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
        HStack(alignment: .top, spacing: 14) {
            // 1. Left: Clickable Small Square Photo
            if let imageURL = experience.coverImageURL {
                Button(action: onTap) {
                    RemoteImage(
                        url: imageURL,
                        height: 72,
                        cornerRadius: 12
                    )
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            // 2. Center/Right Details
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 6) {
                    if !badgeText.isEmpty {
                        Text(badgeText.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1.0)
                            .foregroundStyle(TravColors.accent)
                    }
                    
                    Spacer(minLength: 0)
                    
                    // Small compact action buttons
                    Button {
                        onSave?()
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 13))
                            .foregroundStyle(isSaved ? Color.yellow : .white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        onShare?()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 6)
                }
                
                Text(experience.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                
                // Author row
                Button {
                    onCreatorTap?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(TravColors.accent)
                        Text("by \(experience.creator.displayName)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
                .disabled(onCreatorTap == nil)
                .padding(.top, 2)
                
                HStack(alignment: .center, spacing: 8) {
                    Text(cityLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    
                    Spacer()
                    
                    // Rating indicator badge instead of giant progress circle
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(TravColors.accent)
                        Text(String(format: "%.1f", displayRating))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.12),
                    Color(red: 0.12, green: 0.12, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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
