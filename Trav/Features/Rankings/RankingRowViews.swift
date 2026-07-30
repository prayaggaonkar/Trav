import SwiftUI

// MARK: - Leaderboard User Row View

struct LeaderboardUserRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TravSpacing.md) {
                // Rank number
                Text("\(rank)")
                    .font(TravTypography.bodyLarge())
                    .fontWeight(.bold)
                    .foregroundStyle(rank <= 3 ? TravColors.primary : TravColors.muted.opacity(0.8))
                    .frame(width: 24, alignment: .leading)

                // Avatar / Initials badge fallback
                LeaderboardAvatarView(
                    url: entry.avatarURL,
                    name: entry.displayName,
                    size: 42
                )

                // Username handle
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(entry.username)")
                        .font(TravTypography.bodyLarge())
                        .fontWeight(.semibold)
                        .foregroundStyle(TravColors.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: TravSpacing.xs)

                // Count of experiences created
                Text("\(entry.experienceCount)")
                    .font(TravTypography.titleMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(TravColors.primary)
                    .monospacedDigit()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .contentShape(Rectangle())
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.98))
    }
}

// MARK: - Leaderboard Avatar View with Initials Fallback

struct LeaderboardAvatarView: View {
    let url: URL?
    let name: String
    let size: CGFloat

    private var initials: String {
        let parts = name.split(separator: " ").compactMap { $0.first }
        if parts.count >= 2 {
            return String([parts[0], parts[1]]).uppercased()
        } else if let first = name.first {
            return String(first).uppercased()
        }
        return "U"
    }

    var body: some View {
        if let url {
            RemoteImage(url: url, height: size, cornerRadius: size / 2)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(TravColors.surfaceElevated)
                    .overlay(
                        Circle().stroke(TravColors.border.opacity(0.5), lineWidth: 1)
                    )
                Text(initials)
                    .font(TravTypography.caption())
                    .fontWeight(.bold)
                    .foregroundStyle(TravColors.muted)
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Filter Pill Button View

struct FilterPillButton: View {
    let title: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(title)
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(TravColors.primary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TravColors.primary.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(TravColors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(TravColors.border.opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.96))
    }
}

// MARK: - Member Scope Modal Sheet

struct MemberFilterModalSheet: View {
    let selectedScope: MemberScopeFilter
    let onSelect: (MemberScopeFilter) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: TravSpacing.md) {
            HStack {
                Text("Filter Members")
                    .font(TravTypography.titleLarge())
                    .foregroundStyle(TravColors.primary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(TravColors.muted.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, TravSpacing.md)

            VStack(spacing: TravSpacing.sm) {
                ForEach(MemberScopeFilter.allCases) { scope in
                    Button {
                        onSelect(scope)
                        dismiss()
                    } label: {
                        HStack(spacing: TravSpacing.md) {
                            ZStack {
                                Circle()
                                    .fill(selectedScope == scope ? TravColors.accent.opacity(0.18) : TravColors.surfaceElevated)
                                    .frame(width: 40, height: 40)
                                Image(systemName: scope.iconName)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(selectedScope == scope ? TravColors.accent : TravColors.muted)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(scope.title)
                                    .font(TravTypography.bodyLarge())
                                    .fontWeight(.semibold)
                                    .foregroundStyle(TravColors.primary)
                                Text(scope.subtitle)
                                    .font(TravTypography.caption())
                                    .foregroundStyle(TravColors.muted)
                            }

                            Spacer()

                            if selectedScope == scope {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(TravColors.accent)
                            }
                        }
                        .padding(TravSpacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                .fill(selectedScope == scope ? TravColors.surfaceElevated : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                .stroke(selectedScope == scope ? TravColors.accent.opacity(0.4) : TravColors.border.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .travScreenBackground()
        .presentationDetents([.height(280), .medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(TravRadius.xl)
    }
}

// MARK: - Location Filter Modal Sheet (With MapKit City Search)

struct LocationFilterModalSheet: View {
    let availableLocations: [LocationOption]
    let selectedLocation: LocationOption
    let onSelect: (LocationOption) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var customCityName: String? = nil
    @State private var isSettled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: TravSpacing.md) {
            HStack {
                Text("Select Location")
                    .font(TravTypography.titleLarge())
                    .foregroundStyle(TravColors.primary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(TravColors.muted.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, TravSpacing.md)

            // Autocomplete city search (same MapKit search as profile page)
            CityAutocompleteField(
                title: "",
                placeholder: "Search for any city worldwide...",
                selectedCity: $customCityName,
                isSettled: $isSettled
            )
            .onChange(of: customCityName) { _, newCity in
                if let newCity, !newCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let option = LocationOption(id: "city_\(newCity.lowercased())", name: newCity, subtitle: nil)
                    onSelect(option)
                    dismiss()
                }
            }

            Text("POPULAR LOCATIONS")
                .font(TravTypography.overline())
                .tracking(2.0)
                .foregroundStyle(TravColors.muted)
                .padding(.top, TravSpacing.xs)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(availableLocations) { location in
                        Button {
                            onSelect(location)
                            dismiss()
                        } label: {
                            HStack(spacing: TravSpacing.md) {
                                ZStack {
                                    Circle()
                                        .fill(selectedLocation.id == location.id ? TravColors.accent.opacity(0.18) : TravColors.surfaceElevated)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: location.id == LocationOption.allLocations.id ? "globe" : "mappin.circle.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(selectedLocation.id == location.id ? TravColors.accent : TravColors.muted)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(location.name)
                                        .font(TravTypography.bodyLarge())
                                        .foregroundStyle(TravColors.primary)
                                    if let sub = location.subtitle {
                                        Text(sub)
                                            .font(TravTypography.caption())
                                            .foregroundStyle(TravColors.muted)
                                    }
                                }

                                Spacer()

                                if selectedLocation.id == location.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(TravColors.accent)
                                }
                            }
                            .padding(.horizontal, TravSpacing.md)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                    .fill(selectedLocation.id == location.id ? TravColors.surfaceElevated : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .travScreenBackground()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(TravRadius.xl)
    }
}

// MARK: - Heat Streak User Row View

// MARK: - Heat Streak User Row View

struct HeatStreakUserRow: View {
    let entry: HeatStreakEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TravSpacing.md) {
                // Rank number
                Text("\(entry.rank)")
                    .font(TravTypography.titleMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(entry.rank <= 3 ? TravColors.primary : TravColors.muted.opacity(0.7))
                    .frame(width: 26, alignment: .leading)

                // Avatar
                LeaderboardAvatarView(
                    url: entry.avatarURL,
                    name: entry.displayName,
                    size: 44
                )

                // User name and handle
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(TravTypography.bodyLarge())
                        .fontWeight(.semibold)
                        .foregroundStyle(TravColors.primary)
                        .lineLimit(1)

                    Text("@\(entry.username)")
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: TravSpacing.xs)

                // Stats
                VStack(alignment: .trailing, spacing: 4) {
                    // Active Days Streak (Highlight)
                    HStack(spacing: 4) {
                        Image(systemName: entry.flameIcon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(entry.flameColor)

                        Text(entry.daysLabel)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(entry.flameColor)
                    }

                    // Total Posts
                    Text(entry.postsLabel)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(TravColors.muted)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .contentShape(Rectangle())
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.98))
    }
}

// MARK: - Skeleton Leaderboard Row & List Loader

struct SkeletonLeaderboardRow: View {
    var body: some View {
        HStack(spacing: TravSpacing.md) {
            SkeletonView(height: 16, cornerRadius: 4)
                .frame(width: 22)

            SkeletonView(height: 44, cornerRadius: 22)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                SkeletonView(height: 14, cornerRadius: 4)
                    .frame(width: 140)
                SkeletonView(height: 11, cornerRadius: 3)
                    .frame(width: 90)
            }

            Spacer()

            SkeletonView(height: 16, cornerRadius: 4)
                .frame(width: 32)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, TravSpacing.screenHorizontal)
    }
}

struct SkeletonRankingsList: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in
                    SkeletonLeaderboardRow()
                    Divider()
                        .padding(.leading, 72)
                        .opacity(0.3)
                }
            }
            .padding(.vertical, TravSpacing.xs)
        }
    }
}

// MARK: - Trending / Heat Streak Leaderboard View

struct TrendingLeaderboardView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(EngagementStore.self) private var engagement

    let memberScope: MemberScopeFilter
    let selectedLocation: LocationOption

    @State private var entries: [HeatStreakEntry] = []
    @State private var isLoading = true

    var filteredEntries: [HeatStreakEntry] {
        var items = entries
        if memberScope == .friends {
            let following = engagement.followingUserIDs
            let currentUserID = environment.session.currentUser?.id
            items = items.filter { following.contains($0.id) || $0.id == currentUserID }
        }
        return items
    }

    var body: some View {
        Group {
            if isLoading && entries.isEmpty {
                SkeletonRankingsList()
            } else if filteredEntries.isEmpty {
                EmptyStateView(
                    icon: "flame",
                    title: "No active streaks",
                    description: "No members match the selected filters with an active streak. Create an experience to start a streak!"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            HeatStreakUserRow(entry: entry) {
                                router.openProfile(entry.username)
                            }
                            Divider()
                                .padding(.leading, 72)
                                .opacity(0.3)
                        }
                    }
                    .padding(.vertical, TravSpacing.xs)
                }
            }
        }
        .task {
            await loadRealEntries()

            // Real-time live update stream from Supabase
            for await _ in environment.experiences.observeExperiencesInsert() {
                await loadRealEntries()
            }
        }
        .onChange(of: selectedLocation) { _, _ in
            Task { await loadRealEntries() }
        }
        .onChange(of: memberScope) { _, _ in
            Task { await loadRealEntries() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ExperiencePublishedNotification"))) { _ in
            Task {
                await loadRealEntries()
            }
        }
        .refreshable {
            await loadRealEntries()
        }
    }

    private func loadRealEntries() async {
        isLoading = true
        let cityID: UUID? = (selectedLocation.id == LocationOption.allLocations.id) ? nil : UUID(uuidString: selectedLocation.id)
        let realUsers = (try? await environment.experiences.fetchHeatStreakEntries(
            cityID: cityID,
            cityName: selectedLocation.id == LocationOption.allLocations.id ? nil : selectedLocation.name
        )) ?? []

        entries = realUsers
        isLoading = false
    }
}

// MARK: - Impact User Row View

struct ImpactUserRow: View {
    let entry: ImpactEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TravSpacing.md) {
                // Rank number
                Text("\(entry.rank)")
                    .font(TravTypography.titleMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(entry.rank <= 3 ? TravColors.primary : TravColors.muted.opacity(0.7))
                    .frame(width: 26, alignment: .leading)

                // Avatar
                LeaderboardAvatarView(
                    url: entry.avatarURL,
                    name: entry.displayName,
                    size: 44
                )

                // User name and handle
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(TravTypography.bodyLarge())
                        .fontWeight(.semibold)
                        .foregroundStyle(TravColors.primary)
                        .lineLimit(1)

                    Text("@\(entry.username)")
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: TravSpacing.xs)

                // Impact Stats
                HStack(spacing: 4) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TravColors.accent)

                    Text("\(entry.totalImpactCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(TravColors.primary)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .contentShape(Rectangle())
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.98))
    }
}

// MARK: - Impact Leaderboard View

struct ImpactLeaderboardView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(EngagementStore.self) private var engagement

    let memberScope: MemberScopeFilter
    let selectedLocation: LocationOption

    @State private var entries: [ImpactEntry] = []
    @State private var isLoading = true

    var filteredEntries: [ImpactEntry] {
        var items = entries
        if memberScope == .friends {
            let following = engagement.followingUserIDs
            let currentUserID = environment.session.currentUser?.id
            items = items.filter { following.contains($0.id) || $0.id == currentUserID }
        }
        return items
    }

    var body: some View {
        Group {
            if isLoading && entries.isEmpty {
                SkeletonRankingsList()
            } else if filteredEntries.isEmpty {
                EmptyStateView(
                    icon: "star",
                    title: "No impact records",
                    description: "No creators match the selected filters. Create and share experiences to build your impact!"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            ImpactUserRow(entry: entry) {
                                router.openProfile(entry.username)
                            }
                            Divider()
                                .padding(.leading, 72)
                                .opacity(0.3)
                        }
                    }
                    .padding(.vertical, TravSpacing.xs)
                }
            }
        }
        .task {
            await loadRealEntries()

            for await _ in environment.experiences.observeExperiencesInsert() {
                await loadRealEntries()
            }
        }
        .task(id: engagement.revision) {
            await loadRealEntries()
        }
        .onChange(of: selectedLocation) { _, _ in
            Task { await loadRealEntries() }
        }
        .onChange(of: memberScope) { _, _ in
            Task { await loadRealEntries() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ExperiencePublishedNotification"))) { _ in
            Task {
                await loadRealEntries()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ExperienceSavedNotification"))) { _ in
            Task {
                await loadRealEntries()
            }
        }
        .refreshable {
            await loadRealEntries()
        }
    }

    private func loadRealEntries() async {
        isLoading = true
        let cityID: UUID? = (selectedLocation.id == LocationOption.allLocations.id) ? nil : UUID(uuidString: selectedLocation.id)
        let realUsers = (try? await environment.experiences.fetchImpactLeaderboard(
            cityID: cityID,
            cityName: selectedLocation.id == LocationOption.allLocations.id ? nil : selectedLocation.name
        )) ?? []

        entries = realUsers
        isLoading = false
    }
}

// MARK: - Main Leaderboard User Row View

struct MainLeaderboardUserRow: View {
    let entry: MainLeaderboardEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TravSpacing.md) {
                // Rank number
                Text("\(entry.rank)")
                    .font(TravTypography.titleMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(entry.rank <= 3 ? TravColors.primary : TravColors.muted.opacity(0.7))
                    .frame(width: 26, alignment: .leading)

                // Avatar
                LeaderboardAvatarView(
                    url: entry.avatarURL,
                    name: entry.displayName,
                    size: 44
                )

                // User name and handle
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(TravTypography.bodyLarge())
                        .fontWeight(.semibold)
                        .foregroundStyle(TravColors.primary)
                        .lineLimit(1)

                    Text("@\(entry.username)")
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: TravSpacing.xs)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .contentShape(Rectangle())
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.98))
    }
}

// MARK: - Main Leaderboard View

struct MainLeaderboardView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(EngagementStore.self) private var engagement

    let memberScope: MemberScopeFilter
    let selectedLocation: LocationOption

    @State private var entries: [MainLeaderboardEntry] = []
    @State private var isLoading = true

    var filteredEntries: [MainLeaderboardEntry] {
        var items = entries
        if memberScope == .friends {
            let following = engagement.followingUserIDs
            let currentUserID = environment.session.currentUser?.id
            items = items.filter { following.contains($0.id) || $0.id == currentUserID }
        }
        return items
    }

    var body: some View {
        Group {
            if isLoading && entries.isEmpty {
                SkeletonRankingsList()
            } else if filteredEntries.isEmpty {
                EmptyStateView(
                    icon: "trophy",
                    title: "No leaderboard entries",
                    description: "No members on the main leaderboard yet. Create experiences and earn points!"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            MainLeaderboardUserRow(entry: entry) {
                                router.openProfile(entry.username)
                            }
                            Divider()
                                .padding(.leading, 72)
                                .opacity(0.3)
                        }
                    }
                    .padding(.vertical, TravSpacing.xs)
                }
            }
        }
        .task {
            await loadLeaderboard()

            for await _ in environment.experiences.observeExperiencesInsert() {
                await loadLeaderboard()
            }
        }
        .task(id: engagement.revision) {
            await loadLeaderboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ExperiencePublishedNotification"))) { _ in
            Task {
                await loadLeaderboard()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ExperienceSavedNotification"))) { _ in
            Task {
                await loadLeaderboard()
            }
        }
        .refreshable {
            await loadLeaderboard()
        }
    }

    private func loadLeaderboard() async {
        isLoading = true
        let realEntries = (try? await environment.experiences.fetchMainLeaderboard()) ?? []
        if !realEntries.isEmpty {
            entries = realEntries
        } else {
            entries = MockMainLeaderboardData.entries
        }
        isLoading = false
    }
}

