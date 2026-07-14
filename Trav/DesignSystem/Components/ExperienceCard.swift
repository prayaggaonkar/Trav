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
                    colors: [.black.opacity(0.35), .clear, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )

                actionCluster
                    .padding(TravSpacing.sm)
            }
            .frame(height: TravLayout.feedCardImageHeight)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: TravRadius.lg,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: TravRadius.lg,
                    style: .continuous
                )
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            VStack(alignment: .leading, spacing: TravSpacing.sm) {
                Text(experience.title)
                    .font(TravTypography.titleLarge())
                    .foregroundStyle(TravColors.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)

                creatorRow

                Text(durationCostLine)
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(TravColors.muted)

                socialProofRow

                RoutePreview(stops: experience.stops, compact: false)
                    .padding(.top, TravSpacing.xxs)
            }
            .padding(TravSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
        }
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
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
                    Text("@\(experience.creator.username)")
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onCreatorTap == nil)
        .accessibilityLabel("Creator \(experience.creator.displayName)")
    }

    private var socialProofRow: some View {
        HStack(spacing: TravSpacing.md) {
            Label {
                Text("\(TravFormatters.count(displaySaveCount)) Saved")
                    .font(TravTypography.caption())
            } icon: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(TravColors.muted)

            Label {
                Text("\(TravFormatters.count(displayCompletionCount)) Completed")
                    .font(TravTypography.labelMedium())
                    .fontWeight(.semibold)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(TravColors.success)
        }
    }

    private var actionCluster: some View {
        HStack(spacing: TravSpacing.xs) {
            circularAction(
                systemName: isLiked ? "heart.fill" : "heart",
                tint: isLiked ? TravColors.accent : .white
            ) {
                onLike?()
            }
            circularAction(
                systemName: isSaved ? "bookmark.fill" : "bookmark",
                tint: isSaved ? TravColors.accent : .white
            ) {
                onSave?()
            }
            circularAction(systemName: "square.and.arrow.up", tint: .white) {
                onShare?()
            }
        }
    }

    private func circularAction(
        systemName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.18), lineWidth: 1)
                }
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.9))
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
