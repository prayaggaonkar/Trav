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
                    colors: [.black.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .center
                )

                HStack(spacing: TravSpacing.xs) {
                    CityCardActionButton(
                        systemName: isSaved ? "bookmark.fill" : "bookmark",
                        isActive: isSaved
                    ) { onSave?() }
                    CityCardActionButton(
                        systemName: "square.and.arrow.up"
                    ) { onShare?() }
                }
                .padding(TravSpacing.sm)
            }
            .frame(height: TravLayout.feedCardImageHeight)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: TravSpacing.xs) {
                Text(experience.title)
                    .font(TravTypography.titleMedium())
                    .foregroundStyle(TravColors.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    onCreatorTap?()
                } label: {
                    Text(experience.creator.displayName)
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(onCreatorTap == nil)

                Text("\(TravFormatters.duration(experience.durationMinutes)) · \(experience.costLabel)")
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
                    .lineLimit(1)

                Text("\(TravFormatters.count(experience.completionCount)) completed · \(TravFormatters.count(displaySaveCount)) saved")
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                RoutePreview(stops: experience.stops, maxVisibleStops: 3, compact: true)
                    .padding(.top, TravSpacing.xxs)
            }
            .padding(TravSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(experience.title)
    }

    private var displaySaveCount: Int {
        experience.saveCount + (isSaved ? 1 : 0)
    }
}
