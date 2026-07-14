import SwiftUI

// MARK: - Search

struct CitySearchBar: View {
    @Binding var text: String
    let cityName: String

    var body: some View {
        HStack(spacing: TravSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(TravColors.muted)

            TextField("Search experiences in \(cityName)...", text: $text)
                .font(TravTypography.bodyMedium())
                .foregroundStyle(TravColors.primary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(TravColors.muted)
                        .frame(width: TravLayout.minTouchTarget, height: TravLayout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, TravSpacing.md)
        .frame(height: TravLayout.citySearchHeight)
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TravRadius.xl, style: .continuous)
                .stroke(TravColors.border.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
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
                    .clear,
                    .black.opacity(0.25),
                    .black.opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: TravSpacing.md) {
                Spacer(minLength: TravSpacing.xl)

                Text("Featured")
                    .font(TravTypography.labelMedium())
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.75))

                Text(experience.title)
                    .font(TravTypography.displayMedium())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)

                creatorChip

                Text("\(TravFormatters.duration(experience.durationMinutes)) · \(experience.costLabel)")
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(.white.opacity(0.8))

                HStack(spacing: TravSpacing.md) {
                    Label(
                        "\(TravFormatters.count(experience.saveCount + (isSaved ? 1 : 0))) Saved",
                        systemImage: isSaved ? "bookmark.fill" : "bookmark"
                    )
                    .foregroundStyle(.white.opacity(0.78))

                    Label(
                        "\(TravFormatters.count(experience.completionCount)) Completed",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(TravColors.success)
                    .fontWeight(.semibold)
                }
                .font(TravTypography.caption())

                RoutePreview(
                    stops: experience.stops,
                    compact: false,
                    style: .editorial
                )
                .padding(.top, TravSpacing.xxs)
            }
            .padding(TravSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: TravSpacing.xs) {
                glassIcon(isLiked ? "heart.fill" : "heart", accent: isLiked) { onLike?() }
                glassIcon(isSaved ? "bookmark.fill" : "bookmark", accent: isSaved) { onSave?() }
                glassIcon("square.and.arrow.up") { onShare?() }
            }
            .padding(TravSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(height: TravLayout.featuredCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.xl, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: TravRadius.xl, style: .continuous))
        .onTapGesture(perform: onTap)
        .shadow(color: Color.black.opacity(0.35), radius: 24, y: 12)
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
                AvatarView(url: experience.creator.avatarURL, size: 28)
                Text(experience.creator.displayName)
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(.white)
                if experience.creator.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(TravColors.accent)
                }
            }
            .padding(.trailing, TravSpacing.sm)
            .padding(.vertical, 4)
            .padding(.leading, 4)
            .background {
                Capsule().fill(.ultraThinMaterial)
            }
        }
        .buttonStyle(.plain)
        .disabled(onCreatorTap == nil)
    }

    private func glassIcon(
        _ systemName: String,
        accent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent ? TravColors.accent : .white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.18), lineWidth: 1)
                }
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.9))
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
                .padding(.vertical, TravSpacing.xxs)
            }
        }
    }
}

private struct TrendingCreatorCard: View {
    let creator: Profile

    var body: some View {
        VStack(spacing: TravSpacing.xs) {
            AvatarView(url: creator.avatarURL, size: 64)
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [TravColors.accent.opacity(0.9), .white.opacity(0.15)],
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

            Text("@\(creator.username)")
                .font(TravTypography.caption())
                .foregroundStyle(TravColors.muted)
                .lineLimit(1)

            Text("\(TravFormatters.count(creator.followerCount)) followers")
                .font(TravTypography.caption())
                .foregroundStyle(TravColors.muted.opacity(0.9))
                .lineLimit(1)
        }
        .frame(width: TravLayout.creatorCardWidth)
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(prominent ? .white : TravColors.primary)
                .frame(width: TravLayout.minTouchTarget, height: TravLayout.minTouchTarget)
                .background {
                    if prominent {
                        Circle().fill(.ultraThinMaterial)
                    } else {
                        Circle().fill(TravColors.surfaceElevated)
                    }
                }
                .overlay {
                    Circle().stroke(
                        prominent ? .white.opacity(0.2) : TravColors.border.opacity(0.5),
                        lineWidth: 1
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
