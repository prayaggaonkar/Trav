import SwiftUI

// MARK: - Segmented tabs

struct ProfileTabBar: View {
    let tabs: [ProfileContentTab]
    @Binding var selection: ProfileContentTab
    var counts: [ProfileContentTab: Int] = [:]
    var onSelect: (ProfileContentTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    let count = counts[tab]
                    Button {
                        withAnimation(TravAnimation.tab) {
                            selection = tab
                        }
                        onSelect(tab)
                    } label: {
                        HStack(spacing: 5) {
                            Text(tab.title)
                                .font(.system(size: 14, weight: selection == tab ? .semibold : .regular, design: .rounded))

                            if let count, count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(selection == tab ? TravColors.accent : TravColors.muted)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(selection == tab ? TravColors.accent.opacity(0.15) : Color.gray.opacity(0.12))
                                    )
                            }
                        }
                        .foregroundStyle(selection == tab ? TravColors.primary : TravColors.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, TravSpacing.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(TravColors.border.opacity(0.55))
                    .frame(height: 0.5)

                GeometryReader { geo in
                    let width = geo.size.width / CGFloat(tabs.count)
                    let index = tabs.firstIndex(of: selection) ?? 0
                    Rectangle()
                        .fill(TravColors.primary)
                        .frame(width: width * 0.45, height: 1.5)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .offset(x: width * CGFloat(index) + width * 0.275)
                        .animation(TravAnimation.tab, value: selection)
                }
                .frame(height: 1.5)
            }
            .frame(height: 1.5)
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
    }
}

// MARK: - Stats row

struct ProfileStatsRow: View {
    let profile: Profile
    var onFollowers: () -> Void
    var onFollowing: () -> Void
    var onCreated: () -> Void
    var onCompleted: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            statButton(value: profile.followerCount, label: "Followers", action: onFollowers)
            statButton(value: profile.followingCount, label: "Following", action: onFollowing)
            statButton(value: profile.experienceCount, label: "Created", action: onCreated)
        }
    }

    private func statButton(value: Int, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(TravFormatters.count(value))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(TravColors.primary)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(TravColors.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.97))
    }
}

// MARK: - Follow button

struct ProfileFollowButton: View {
    let isFollowing: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(isFollowing ? TravColors.primary : .white)
                } else {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(isFollowing ? TravColors.primary : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(isFollowing ? TravColors.surfaceElevated : TravColors.accent)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.98))
        .disabled(isLoading)
        .animation(TravAnimation.quick, value: isFollowing)
    }
}

struct ProfileEditButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(TravColors.primary)
                .padding(.horizontal, 18)
                .frame(height: 32)
                .background(TravColors.surfaceElevated)
                .clipShape(Capsule())
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.97))
    }
}

// MARK: - Profile experience row (no card chrome)

struct ProfileExperienceCard: View {
    let experience: ExperienceSummary
    var completedAt: Date? = nil
    /// When `nil`, the row is display-only (parent owns tap / swipe handling).
    var onTap: (() -> Void)? = nil

    var body: some View {
        let cardContent = ZStack {
            // Glass background fill
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.07, blue: 0.28).opacity(0.85),
                        Color(red: 0.08, green: 0.11, blue: 0.32).opacity(0.88),
                        Color(red: 0.05, green: 0.07, blue: 0.22).opacity(0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.65, green: 0.32, blue: 1.0).opacity(0.25),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 180
                )

                Rectangle()
                    .fill(.thinMaterial)
                    .opacity(0.15)
            }

            HStack(alignment: .center, spacing: TravSpacing.md) {
                ZStack {
                    RemoteImage(
                        url: experience.coverImageURL,
                        height: 68,
                        cornerRadius: 12
                    )
                    .frame(width: 68, height: 68)

                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.5), Color(red: 0.65, green: 0.35, blue: 1.0).opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(experience.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            if let url = experience.creator.avatarURL {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white)
                                }
                                .frame(width: 14, height: 14)
                                .clipShape(Circle())
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                            }
                            Text(experience.creator.displayName)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                        }

                        Text("·")
                            .foregroundStyle(.white.opacity(0.4))

                        Text(metaLine)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(TravSpacing.sm + 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.35),
                            .white.opacity(0.1),
                            Color(red: 0.65, green: 0.35, blue: 1.0).opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color(red: 0.12, green: 0.06, blue: 0.30).opacity(0.35), radius: 12, x: 0, y: 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())

        if let onTap {
            Button(action: onTap) { cardContent }
                .buttonStyle(TravPressButtonStyle(scale: 0.98))
        } else {
            cardContent
        }
    }

    private var metaLine: String {
        var parts: [String] = [cityLabel]
        parts.append("\(TravFormatters.count(experience.saveCount)) saves")
        if let completedAt {
            parts = [cityLabel, "Completed \(completedAt.formatted(date: .abbreviated, time: .omitted))"]
        }
        return parts.joined(separator: "  ·  ")
    }

    private var cityLabel: String {
        if let name = experience.cityName, !name.isEmpty { return name }
        return MockData.cities.first(where: { $0.id == experience.cityID })?.name ?? experience.displayCityName
    }
}

// MARK: - Swipe to unsave

/// Swipe right→left to reveal Unsave. Opening the experience requires a clean tap
/// with no swipe. Partial swipe parks on the Unsave button; full swipe deletes.
struct SwipeToUnsaveRow<Content: View>: View {
    var onUnsave: () -> Void
    var onOpen: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var dragOriginOffset: CGFloat = 0
    @State private var isHorizontalDrag = false
    @State private var suppressOpen = false

    private let actionWidth: CGFloat = 88
    private let fullSwipeDistance: CGFloat = 150

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: commitUnsave) {
                VStack(spacing: 6) {
                    Image(systemName: "bookmark.slash.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Unsave")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .background(TravColors.error)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(offset < -4 ? 1 : 0)
            .accessibilityLabel("Unsave experience")

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TravColors.surface)
                .offset(x: offset)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Only a clean tap opens — never after a swipe gesture.
                    guard !suppressOpen, !isHorizontalDrag else { return }
                    if offset < -8 {
                        withAnimation(TravAnimation.quick) { offset = 0 }
                    } else {
                        onOpen()
                    }
                }
                .gesture(rowGesture)
        }
        .clipped()
    }

    private var rowGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height

                if !isHorizontalDrag {
                    let isHorizontal = abs(dx) > abs(dy) * 1.15
                    let openingLeft = dx < 0
                    let closingRight = dx > 0 && offset < -4

                    if isHorizontal && (openingLeft || closingRight) {
                        isHorizontalDrag = true
                        suppressOpen = true
                        dragOriginOffset = offset
                    } else {
                        return
                    }
                }

                guard isHorizontalDrag else { return }
                offset = min(0, max(dragOriginOffset + dx, -fullSwipeDistance))
            }
            .onEnded { value in
                let wasSwipe = isHorizontalDrag
                let predicted = value.predictedEndTranslation.width

                defer {
                    isHorizontalDrag = false
                    if wasSwipe {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            suppressOpen = false
                        }
                    }
                }

                guard wasSwipe else { return }

                // Full-swipe delete only past a clear threshold — peeking must not delete.
                let shouldDelete =
                    offset <= -(actionWidth + 36)
                    || (predicted < -fullSwipeDistance && offset < -actionWidth * 0.9)

                if shouldDelete {
                    commitUnsave()
                } else if offset < -actionWidth * 0.35 {
                    withAnimation(TravAnimation.quick) { offset = -actionWidth }
                } else {
                    withAnimation(TravAnimation.quick) { offset = 0 }
                }
            }
    }

    private func commitUnsave() {
        withAnimation(TravAnimation.quick) {
            offset = -420
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onUnsave()
    }
}

// MARK: - Quiet empty state

struct ProfileEmptyState: View {
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: TravSpacing.sm) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(TravColors.primary)
                .multilineTextAlignment(.center)
            Text(description)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(TravColors.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TravSpacing.xl)
        .padding(.vertical, TravSpacing.xxl)
    }
}

// MARK: - Skeleton

struct ProfileSkeleton: View {
    var body: some View {
        VStack(spacing: TravSpacing.lg) {
            SkeletonView(height: 88, cornerRadius: 44)
                .frame(width: 88, height: 88)
            SkeletonView(height: 22, cornerRadius: 4)
                .frame(width: 140)
            SkeletonView(height: 14, cornerRadius: 4)
                .frame(width: 90)
            HStack {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(spacing: 6) {
                        SkeletonView(height: 16, cornerRadius: 4)
                        SkeletonView(height: 10, cornerRadius: 4)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, TravSpacing.sm)
            SkeletonView(height: 36, cornerRadius: 10)
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: TravSpacing.md) {
                    SkeletonView(height: 72, cornerRadius: 10)
                        .frame(width: 72)
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonView(height: 14, cornerRadius: 4)
                        SkeletonView(height: 12, cornerRadius: 4)
                            .frame(width: 160)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.top, TravSpacing.xl)
    }
}

// MARK: - User row (followers list)

struct ProfileUserRow: View {
    let user: ProfileSummary
    var isFollowing: Bool?
    var onTap: () -> Void
    var onFollowToggle: (() -> Void)?

    var body: some View {
        HStack(spacing: TravSpacing.md) {
            Button(action: onTap) {
                HStack(spacing: TravSpacing.md) {
                    AvatarView(url: user.avatarURL, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(user.displayName)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(TravColors.primary)
                                .lineLimit(1)
                            if user.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(TravColors.muted)
                            }
                        }
                        Text("@\(user.username)")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(TravColors.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            if let isFollowing, let onFollowToggle {
                Button(action: onFollowToggle) {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isFollowing ? TravColors.primary : .white)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(isFollowing ? TravColors.surfaceElevated : TravColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.96))
            }
        }
        .padding(.vertical, 6)
    }
}
