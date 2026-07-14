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
                .font(.system(size: 16, weight: .medium))
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
        .overlay {
            RoundedRectangle(cornerRadius: TravRadius.xl, style: .continuous)
                .strokeBorder(TravColors.border.opacity(0.55), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(placeholder)
    }
}

// MARK: - Featured

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
        ZStack(alignment: .bottomLeading) {
            RemoteImage(
                url: experience.coverImageURL,
                height: TravLayout.featuredCardHeight,
                cornerRadius: 0
            )

            LinearGradient(
                colors: [
                    .black.opacity(0.15),
                    .black.opacity(0.45),
                    .black.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: TravSpacing.sm) {
                Text("Featured")
                    .font(TravTypography.labelMedium())
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)

                Text(experience.title)
                    .font(TravTypography.titleLarge())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)
                    .fixedSize(horizontal: false, vertical: true)

                creatorChip

                Text("\(TravFormatters.duration(experience.durationMinutes)) · \(experience.costLabel)")
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                TravSocialProofRow(
                    saveCount: experience.saveCount + (isSaved ? 1 : 0),
                    completionCount: experience.completionCount,
                    isSaved: isSaved,
                    style: .onDark
                )

                RoutePreview(
                    stops: experience.stops,
                    maxVisibleStops: 3,
                    compact: true,
                    style: .editorial
                )
            }
            .padding(TravSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: TravSpacing.xs) {
                TravGlassIconButton(
                    systemName: isLiked ? "heart.fill" : "heart",
                    tint: isLiked ? TravColors.accent : .white
                ) { onLike?() }
                TravGlassIconButton(
                    systemName: isSaved ? "bookmark.fill" : "bookmark",
                    tint: isSaved ? TravColors.accent : .white
                ) { onSave?() }
                TravGlassIconButton(systemName: "square.and.arrow.up") { onShare?() }
            }
            .padding(TravSpacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(height: TravLayout.featuredCardHeight)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
        .onTapGesture(perform: onTap)
        .travCardShadow()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Featured experience \(experience.title)")
        .accessibilityAction(named: "Open") { onTap() }
    }

    private var creatorChip: some View {
        Button {
            onCreatorTap?()
        } label: {
            HStack(spacing: TravSpacing.xs) {
                AvatarView(url: experience.creator.avatarURL, size: 24)
                Text(experience.creator.displayName)
                    .font(TravTypography.caption())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                if experience.creator.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(TravColors.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.trailing, TravSpacing.sm)
            .padding(.vertical, TravSpacing.xxs)
            .padding(.leading, TravSpacing.xxs)
            .background {
                Capsule().fill(.black.opacity(0.35))
            }
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(onCreatorTap == nil)
    }
}

// MARK: - Creators

struct TrendingCreatorsSection: View {
    let creators: [Profile]
    var onSelect: (Profile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            Text("Trending Creators")
                .font(TravTypography.titleLarge())
                .foregroundStyle(TravColors.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TravSpacing.screenHorizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TravSpacing.sm) {
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
                .padding(.vertical, TravSpacing.xxs)
            }
        }
    }
}

private struct TrendingCreatorCard: View {
    let creator: Profile

    var body: some View {
        VStack(spacing: TravSpacing.xs) {
            AvatarView(url: creator.avatarURL, size: 56)
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [TravColors.accent.opacity(0.9), .white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }

            Text(creator.displayName)
                .font(TravTypography.labelMedium())
                .foregroundStyle(TravColors.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)

            Text("@\(creator.username)")
                .font(TravTypography.caption())
                .foregroundStyle(TravColors.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)

            Text("\(TravFormatters.count(creator.followerCount)) followers")
                .font(TravTypography.caption())
                .foregroundStyle(TravColors.muted.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, TravSpacing.xxs)
        .frame(width: TravLayout.creatorCardWidth)
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(creator.displayName), \(creator.followerCount) followers")
    }
}

// MARK: - Navigation chrome

struct CityBackButton: View {
    let action: () -> Void
    var prominent = true

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(prominent ? .white : TravColors.primary)
                .frame(width: TravLayout.minTouchTarget, height: TravLayout.minTouchTarget)
                .background {
                    Circle()
                        .fill(prominent ? Color.black.opacity(0.55) : TravColors.surfaceElevated)
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            prominent ? Color.white.opacity(0.75) : TravColors.border,
                            lineWidth: 1.5
                        )
                }
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.94))
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
