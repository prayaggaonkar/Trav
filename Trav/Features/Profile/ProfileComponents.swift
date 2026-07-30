import SwiftUI

// MARK: - Segmented Pill Tab Bar (Icon Only)

struct ProfileTabBar: View {
    let tabs: [ProfileContentTab]
    @Binding var selection: ProfileContentTab
    var counts: [ProfileContentTab: Int] = [:]
    var onSelect: (ProfileContentTab) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tabs) { tab in
                let isSelected = selection == tab
                let count = counts[tab]
                Button {
                    withAnimation(TravAnimation.quick) {
                        selection = tab
                    }
                    onSelect(tab)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tabIcon(for: tab))
                            .font(.system(size: 16, weight: isSelected ? .bold : .semibold))

                        if let count, count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(isSelected ? TravColors.accent.opacity(0.2) : Color.gray.opacity(0.15)))
                        }
                    }
                    .foregroundStyle(isSelected ? TravColors.accent : TravColors.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(isSelected ? TravColors.accentSoft : TravColors.surfaceElevated.opacity(0.5))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(isSelected ? TravColors.accent.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.97))
                .accessibilityLabel(tabAccessibilityLabel(for: tab))
            }
        }
        .padding(4)
        .background(TravColors.surfaceElevated.opacity(0.4))
        .clipShape(Capsule())
    }

    private func tabIcon(for tab: ProfileContentTab) -> String {
        switch tab {
        case .created: "square.grid.3x3.fill"
        case .saved: "bookmark.fill"
        case .completed: "checkmark.circle.fill"
        }
    }

    private func tabAccessibilityLabel(for tab: ProfileContentTab) -> String {
        switch tab {
        case .created: "Created experiences"
        case .saved: "Saved experiences"
        case .completed: "Watchlist experiences"
        }
    }
}

// MARK: - Stats Row (Clean, No Icons)

struct ProfileStatsRow: View {
    let profile: Profile
    var rankLabel: String = "—"
    var isRankLoading: Bool = false
    var isFollowersLoading: Bool = false
    var isFollowingLoading: Bool = false
    var onFollowers: () -> Void
    var onFollowing: () -> Void
    var onRankTap: () -> Void

    var body: some View {
        HStack(spacing: TravSpacing.md) {
            statButton(
                valueString: TravFormatters.count(profile.followerCount),
                label: "Followers",
                isLoading: isFollowersLoading && profile.followerCount > 0,
                action: onFollowers
            )
            statButton(
                valueString: TravFormatters.count(profile.followingCount),
                label: "Following",
                isLoading: isFollowingLoading && profile.followingCount > 0,
                action: onFollowing
            )
            statButton(
                valueString: rankLabel,
                label: "Rank",
                isLoading: isRankLoading,
                action: onRankTap
            )
        }
    }

    private func statButton(
        valueString: String,
        label: String,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if isLoading {
                    SkeletonView(height: 18, cornerRadius: 4)
                        .frame(width: 38, height: 22)
                } else {
                    Text(valueString)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(TravColors.primary)
                        .contentTransition(.numericText())
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(TravColors.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.96))
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
                    HStack(spacing: 5) {
                        Image(systemName: isFollowing ? "checkmark" : "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text(isFollowing ? "Following" : "Follow")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    }
                }
            }
            .foregroundStyle(isFollowing ? TravColors.primary : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(isFollowing ? TravColors.surfaceElevated : TravColors.accent)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isFollowing ? TravColors.border.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.97))
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
                .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.vertical, TravSpacing.xs)
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

/// Swipe right→left to reveal Delete. Partial swipe parks on the button; full swipe deletes.
struct SwipeToDeleteRow<Content: View>: View {
    var onDelete: () -> Void
    var onOpen: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var dragOriginOffset: CGFloat = 0
    @State private var isHorizontalDrag = false
    @State private var suppressOpen = false

    private let actionWidth: CGFloat = 88
    private let fullSwipeDistance: CGFloat = 150

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: commitDelete) {
                VStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Delete")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .background(TravColors.error)
                .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.vertical, TravSpacing.xs)
            .opacity(offset < -4 ? 1 : 0)
            .accessibilityLabel("Delete")

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TravColors.surface)
                .offset(x: offset)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !suppressOpen, !isHorizontalDrag else { return }
                    if offset < -8 {
                        withAnimation(TravAnimation.quick) { offset = 0 }
                    } else {
                        onOpen?()
                    }
                }
                // Prefer over ScrollView’s pan so horizontal swipes actually start
                // (nested Buttons in row content also steal `.gesture` otherwise).
                .highPriorityGesture(rowGesture)
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

                let shouldDelete =
                    offset <= -(actionWidth + 36)
                    || (predicted < -fullSwipeDistance && offset < -actionWidth * 0.9)

                if shouldDelete {
                    commitDelete()
                } else if offset < -actionWidth * 0.35 {
                    withAnimation(TravAnimation.quick) { offset = -actionWidth }
                } else {
                    withAnimation(TravAnimation.quick) { offset = 0 }
                }
            }
    }

    private func commitDelete() {
        withAnimation(TravAnimation.quick) {
            offset = -420
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onDelete()
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

// MARK: - Suggested users

struct SuggestedUsersSection: View {
    let users: [SuggestedUser]
    var isLoading: Bool
    var contactsAuthorization: ContactAuthorizationStatus
    var onSelect: (SuggestedUser) -> Void
    var onFollow: (SuggestedUser) -> Void
    var onDismiss: (SuggestedUser) -> Void
    var onSyncContacts: () -> Void

    var body: some View {
        // Parent (ProfileView) already applies screenHorizontal padding to match
        // the Edit profile / Share / Add people action row — do not inset again.
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            HStack(alignment: .center) {
                Text("Suggested for you")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(TravColors.primary)

                Spacer(minLength: 0)

                if contactsAuthorization != .authorized {
                    Button(action: onSyncContacts) {
                        Text(contactsAuthorization == .notDetermined ? "Allow Contacts" : "Sync Contacts")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(TravColors.accent)
                    }
                    .buttonStyle(TravPressButtonStyle(scale: 0.97))
                }
            }

            if isLoading && users.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TravSpacing.md) {
                        ForEach(0..<4, id: \.self) { _ in
                            SuggestedUserCardSkeleton()
                        }
                    }
                }
            } else if users.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(TravColors.muted)
                    .padding(.vertical, TravSpacing.xs)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TravSpacing.md) {
                        ForEach(users) { user in
                            SuggestedUserCard(
                                suggestion: user,
                                onSelect: { onSelect(user) },
                                onFollow: { onFollow(user) },
                                onDismiss: { onDismiss(user) }
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, TravSpacing.md)
        .padding(.bottom, TravSpacing.xs)
    }

    private var emptyMessage: String {
        switch contactsAuthorization {
        case .authorized:
            return "No suggestions right now. Check back later."
        case .notDetermined:
            return "Allow contacts to find people you know."
        case .denied, .restricted:
            return "Enable contacts in Settings, or follow mutuals below when available."
        }
    }
}

private struct SuggestedUserCard: View {
    let suggestion: SuggestedUser
    var onSelect: () -> Void
    var onFollow: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: TravSpacing.xs) {
            ZStack(alignment: .topTrailing) {
                Button(action: onSelect) {
                    VStack(spacing: TravSpacing.xs) {
                        AvatarView(url: suggestion.profile.avatarURL, size: 56)

                        Text(suggestion.profile.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(TravColors.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)

                        Text(suggestion.reasonText)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(TravColors.muted)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.center)
                            .frame(height: 28, alignment: .top)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(TravColors.muted)
                        .frame(width: 22, height: 22)
                        .background(TravColors.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.9))
                .offset(x: 4, y: -4)
            }

            Button(action: onFollow) {
                Text("Follow")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(TravColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(TravPressButtonStyle(scale: 0.96))
        }
        .padding(TravSpacing.sm)
        .frame(width: 132)
        .background(TravColors.surfaceElevated.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(suggestion.profile.displayName), \(suggestion.reasonText)")
    }
}

private struct SuggestedUserCardSkeleton: View {
    var body: some View {
        VStack(spacing: TravSpacing.xs) {
            Circle()
                .fill(TravColors.surfaceElevated)
                .frame(width: 56, height: 56)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(TravColors.surfaceElevated)
                .frame(width: 72, height: 12)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(TravColors.surfaceElevated)
                .frame(width: 88, height: 10)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(TravColors.surfaceElevated)
                .frame(height: 30)
        }
        .padding(TravSpacing.sm)
        .frame(width: 132)
        .redacted(reason: .placeholder)
    }
}
