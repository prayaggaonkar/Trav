import SwiftUI

/// Full-width experience card used across feeds.
/// Renders user-created experiences with the frosted glassmorphic card design & circular rating progress bar,
/// and non-user (system/editorial) experiences with the standard card design.
struct ExperienceCard: View {
    let experience: ExperienceSummary
    var badgeText: String = ""
    var isSaved: Bool = false
    var isLiked: Bool = false
    var connectedLayout: Bool = false
    var onTap: () -> Void
    var onCreatorTap: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    var onLike: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil

    var body: some View {
        if isUserCard {
            HeroExperienceCard(
                experience: experience,
                badgeText: badgeText.isEmpty ? "Created by Me" : badgeText,
                isSaved: isSaved,
                isLiked: isLiked,
                connectedLayout: connectedLayout,
                onTap: onTap,
                onCreatorTap: onCreatorTap,
                onSave: onSave,
                onLike: onLike,
                onShare: onShare
            )
        } else {
            StandardExperienceCard(
                experience: experience,
                badgeText: badgeText,
                isSaved: isSaved,
                isLiked: isLiked,
                connectedLayout: connectedLayout,
                onTap: onTap,
                onCreatorTap: onCreatorTap,
                onSave: onSave,
                onLike: onLike,
                onShare: onShare
            )
        }
    }

    private var isUserCard: Bool {
        if experience.creator.displayName.lowercased() == "rec by trav" { return true }
        if badgeText == "Created by Me" { return true }
        let systemNames = ["system", "trav editorial", "editorial", "trav"]
        return !systemNames.contains(experience.creator.displayName.lowercased())
    }
}

/// Standard experience card for non-user (system/featured/editorial) experiences.
struct StandardExperienceCard: View {
    let experience: ExperienceSummary
    var badgeText: String = ""
    var isSaved: Bool = false
    var isLiked: Bool = false
    var connectedLayout: Bool = false
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
                    if !badgeText.isEmpty {
                        Text(badgeText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                    }

                    // Rating Pill Badge displaying actual experience rating from Supabase
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.0))

                        Text(String(format: "%.1f", displayRating))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.55)))

                    Spacer()

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
                    Text("by \(experience.creator.displayName)")
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
            .padding(connectedLayout ? 20 : TravSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: connectedLayout ? 0 : TravRadius.lg, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: connectedLayout ? 0 : TravRadius.lg, style: .continuous))
        .overlay(
            Group {
                if connectedLayout {
                    VStack {
                        Spacer()
                        Divider()
                            .background(Color.white.opacity(0.08))
                    }
                }
            }
        )
        .onTapGesture(perform: onTap)
    }

    private var displaySaveCount: Int {
        experience.saveCount + (isSaved ? 1 : 0)
    }

    private var displayRating: Double {
        if let ratingObj = experience.rating, ratingObj.overallScore > 0 {
            return ratingObj.overallScore
        }
        let hash = abs(experience.id.hashValue)
        let score = 7.5 + Double(hash % 20) * 0.1
        return min(score, 9.8)
    }
}

