import SwiftUI

/// Full-width editorial experience card used in the City page feed.
struct ExperienceCard: View {
    let experience: ExperienceSummary
    var isSaved: Bool = false
    var isLiked: Bool = false
    var onTap: () -> Void
    var onCreatorTap: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    var onLike: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                RemoteImage(
                    url: experience.coverImageURL,
                    height: TravLayout.feedCardImageHeight,
                    cornerRadius: 0
                )

                LinearGradient(
                    colors: [.black.opacity(0.4), .clear],
                    startPoint: .top,
                    endPoint: .center
                )

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
            }
            .frame(height: TravLayout.feedCardImageHeight)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: TravLayout.cardContentSpacing) {
                Text(experience.title)
                    .font(TravTypography.titleMedium())
                    .foregroundStyle(TravColors.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                creatorRow

                Text(durationCostLine)
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(TravColors.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                TravSocialProofRow(
                    saveCount: displaySaveCount,
                    completionCount: displayCompletionCount,
                    isSaved: isSaved
                )

                RoutePreview(stops: experience.stops, maxVisibleStops: 3, compact: true)
            }
            .padding(TravSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                .strokeBorder(TravColors.border.opacity(0.45), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
        .onTapGesture(perform: onTap)
        .travCardShadow()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(experience.title)
    }

    private var creatorRow: some View {
        Button {
            onCreatorTap?()
        } label: {
            HStack(spacing: TravSpacing.xs) {
                AvatarView(url: experience.creator.avatarURL, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(experience.creator.displayName)
                        .font(TravTypography.bodyMedium())
                        .foregroundStyle(TravColors.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                    Text("@\(experience.creator.username)")
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onCreatorTap == nil)
        .accessibilityLabel("Creator \(experience.creator.displayName)")
    }

    private var durationCostLine: String {
        "\(TravFormatters.duration(experience.durationMinutes)) · \(experience.costLabel)"
    }

    private var displaySaveCount: Int {
        experience.saveCount + (isSaved ? 1 : 0)
    }

    private var displayCompletionCount: Int {
        experience.completionCount
    }
}
