import SwiftUI

struct ExperienceCard: View {
    let experience: ExperienceSummary
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: TravSpacing.sm) {
                RemoteImage(url: experience.coverImageURL, height: TravLayout.cardImageHeight)
                titleSection
                metadataRow
                RoutePreview(stops: experience.stops, compact: true)
            }
            .padding(TravSpacing.sm)
            .background(TravColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
            .travCardShadow()
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.98))
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: TravSpacing.xxs) {
            Text(experience.title)
                .font(TravTypography.titleMedium())
                .foregroundStyle(TravColors.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: TravSpacing.xs) {
                AvatarView(url: experience.creator.avatarURL, size: 20)
                Text(experience.creator.displayName)
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
            }
        }
    }

    private var metadataRow: some View {
        HStack(spacing: TravSpacing.xxs) {
            StatPill(symbol: "clock", value: TravFormatters.duration(experience.durationMinutes))
            StatPill(symbol: "dollarsign.circle", value: experience.costLevel.displayName)
            StatPill(symbol: "bookmark", value: TravFormatters.count(experience.saveCount))
            StatPill(symbol: "checkmark.circle", value: TravFormatters.count(experience.completionCount))
        }
    }
}
