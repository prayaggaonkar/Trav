import SwiftUI

struct ExperienceCard: View {
    let experience: ExperienceSummary
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: TravSpacing.sm) {
                coverImage
                titleSection
                metadataRow
                RoutePreview(stops: experience.stops, compact: true)
            }
            .padding(TravSpacing.sm)
            .background(TravColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var coverImage: some View {
        Group {
            if let url = experience.coverImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Rectangle().fill(TravColors.surfaceElevated)
                    }
                }
            } else {
                Rectangle().fill(TravColors.surfaceElevated)
            }
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(experience.title)
                .font(TravTypography.titleMedium())
                .foregroundStyle(TravColors.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                AvatarView(url: experience.creator.avatarURL, size: 20)
                Text(experience.creator.displayName)
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
            }
        }
    }

    private var metadataRow: some View {
        HStack(spacing: TravSpacing.xs) {
            StatPill(symbol: "clock", value: formatDuration(experience.durationMinutes))
            StatPill(symbol: "dollarsign.circle", value: experience.costLevel.displayName)
            StatPill(symbol: "bookmark", value: formatCount(experience.saveCount))
            StatPill(symbol: "checkmark.circle", value: formatCount(experience.completionCount))
        }
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes >= 60 {
            return "\(minutes / 60)h"
        }
        return "\(minutes)m"
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000)
        }
        return "\(count)"
    }
}
