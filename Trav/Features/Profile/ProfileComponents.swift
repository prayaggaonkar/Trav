import SwiftUI

// MARK: - Segmented tabs

struct ProfileTabBar: View {
    let tabs: [ProfileContentTab]
    @Binding var selection: ProfileContentTab
    var onSelect: (ProfileContentTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    Button {
                        withAnimation(TravAnimation.tab) {
                            selection = tab
                        }
                        onSelect(tab)
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 14, weight: selection == tab ? .semibold : .regular, design: .rounded))
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
    var onCompleted: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            statButton(value: profile.followerCount, label: "Followers", action: onFollowers)
            statButton(value: profile.followingCount, label: "Following", action: onFollowing)
            statButton(value: profile.experienceCount, label: "Created", action: onCreated)
            statButton(value: profile.completionCount, label: "Completed", action: onCompleted)
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
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: TravSpacing.md) {
                RemoteImage(
                    url: experience.coverImageURL,
                    height: 72,
                    cornerRadius: 10
                )
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text(experience.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(TravColors.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(metaLine)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(TravColors.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, TravSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.99))
    }

    private var metaLine: String {
        var parts: [String] = [cityLabel]
        parts.append("\(TravFormatters.count(experience.saveCount)) saves")
        parts.append("\(TravFormatters.count(experience.completionCount)) completed")
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
