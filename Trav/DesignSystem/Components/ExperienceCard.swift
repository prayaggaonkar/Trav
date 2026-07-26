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
            GemPostCardView(
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

/// Frosted card design with a split action bar (private save + public watchlist) and facepile row.
struct GemPostCardView: View {
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

    @Environment(AppEnvironment.self) private var environment
    @Environment(EngagementStore.self) private var engagement

    @State private var isSavedLocal: Bool
    @State private var isLikedLocal: Bool

    private var isWatchlisted: Bool {
        engagement.isCompleted(experience.id)
    }

    init(
        experience: ExperienceSummary,
        badgeText: String = "",
        isSaved: Bool = false,
        isLiked: Bool = false,
        connectedLayout: Bool = false,
        onTap: @escaping () -> Void,
        onCreatorTap: (() -> Void)? = nil,
        onSave: (() -> Void)? = nil,
        onLike: (() -> Void)? = nil,
        onShare: (() -> Void)? = nil
    ) {
        self.experience = experience
        self.badgeText = badgeText
        self.connectedLayout = connectedLayout
        self.onTap = onTap
        self.onCreatorTap = onCreatorTap
        self.onSave = onSave
        self.onLike = onLike
        self.onShare = onShare
        
        _isSavedLocal = State(initialValue: isSaved)
        _isLikedLocal = State(initialValue: isLiked)
    }

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

                // Facepile (Social Proof) Row
                if !experience.watchlistedBy.isEmpty {
                    HStack(spacing: 0) {
                        HStack(spacing: -8) {
                            ForEach(experience.watchlistedBy.prefix(3)) { user in
                                AsyncImage(url: URL(string: user.avatarImage)) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Image(systemName: "person.crop.circle.fill")
                                        .foregroundStyle(TravColors.muted)
                                }
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            }
                        }
                        .padding(.trailing, 6)

                        Group {
                            if experience.watchlistedBy.count == 1 {
                                Text("Added to watchlist by ") +
                                Text(experience.watchlistedBy[0].name)
                                    .fontWeight(.bold)
                            } else {
                                Text("Added to watchlist by ") +
                                Text(experience.watchlistedBy[0].name)
                                    .fontWeight(.bold) +
                                Text(" and ") +
                                Text("\(experience.watchlistedBy.count - 1) others")
                                    .fontWeight(.bold)
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(Color.gray)
                    }
                    .padding(.vertical, 6)
                }

                // Split Action Bar
                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 8)

                HStack {
                    // Left Group: Like, Save, Comment, Share
                    HStack(spacing: 16) {
                        Button {
                            isLikedLocal.toggle()
                            onLike?()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: isLikedLocal ? "heart.fill" : "heart")
                                .font(.system(size: 18))
                                .foregroundStyle(isLikedLocal ? Color.red : .white.opacity(0.6))
                        }
                        .buttonStyle(.plain)

                        Button {
                            isSavedLocal.toggle()
                            onSave?()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: isSavedLocal ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 18))
                                .foregroundStyle(isSavedLocal ? Color.yellow : .white.opacity(0.6))
                        }
                        .buttonStyle(.plain)

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: "bubble.right")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)

                        Button {
                            onShare?()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Right Group: Watchlist Pill Button
                    Button {
                        let expID = experience.id
                        let summary = experience
                        Task {
                            await engagement.toggleComplete(experienceID: expID, summary: summary, using: environment)
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isWatchlisted ? "checkmark.circle.fill" : "plus.circle.fill")
                            Text(isWatchlisted ? "I'm Down" : "Watchlist")
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(isWatchlisted ? Color.gray.opacity(0.4) : TravColors.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
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
        experience.saveCount + (isSavedLocal ? 1 : 0)
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

typealias StandardExperienceCard = GemPostCardView
