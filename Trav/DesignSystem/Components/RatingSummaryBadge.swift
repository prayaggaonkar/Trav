import SwiftUI

/// Shows an experience's rating with the styling that tells users whether it has
/// genuine public validation.
///
/// Purple means the community has spoken. Grey means the only score on record is
/// the creator's own, which is not social proof — so it is deliberately muted and
/// labelled as such.
struct RatingSummaryBadge: View {
    let summary: RatingSummary
    var showsCaption: Bool = true
    var compact: Bool = false

    private var tint: Color {
        summary.hasCommunityValidation ? TravColors.accent : TravColors.muted
    }

    var body: some View {
        if let score = summary.displayScore {
            HStack(spacing: compact ? TravSpacing.xxs : TravSpacing.xs) {
                scorePill(score)

                if showsCaption {
                    Text(summary.caption)
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func scorePill(_ score: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: summary.hasCommunityValidation ? "hexagon.fill" : "hexagon")
                .font(.system(size: compact ? 9 : 11, weight: .semibold))
            Text(TravFormatters.score(score))
                .font(compact ? TravTypography.caption() : TravTypography.labelMedium())
                .monospacedDigit()
        }
        .foregroundStyle(summary.hasCommunityValidation ? .white : tint)
        .padding(.horizontal, compact ? TravSpacing.xs : TravSpacing.sm)
        .padding(.vertical, compact ? 3 : TravSpacing.xxs)
        .background(
            summary.hasCommunityValidation
                ? AnyShapeStyle(TravColors.accent)
                : AnyShapeStyle(TravColors.muted.opacity(0.16))
        )
        .clipShape(Capsule())
        .overlay {
            if !summary.hasCommunityValidation {
                Capsule().stroke(TravColors.muted.opacity(0.35), lineWidth: 1)
            }
        }
        .accessibilityLabel(
            summary.hasCommunityValidation
                ? "Community rating \(TravFormatters.score(score)) out of 10"
                : "Creator rating \(TravFormatters.score(score)) out of 10, no community ratings yet"
        )
    }
}

extension TravFormatters {
    /// One decimal place, matching the hexagon control's granularity.
    static func score(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
