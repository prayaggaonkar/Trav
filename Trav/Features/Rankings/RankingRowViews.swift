import SwiftUI
import Foundation

// MARK: - Glistening Purple Rank Text (Moving Gradient within #1, 2, and 3)

struct GlisteningPurpleRankText: View {
    let text: String
    let font: Font
    var shadowRadius: CGFloat = 3
    var delayOffset: Double = 0.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate + delayOffset
            let cycleDuration: Double = 2.8
            let progress = (now.truncatingRemainder(dividingBy: cycleDuration)) / cycleDuration
            
            // Move startPoint & endPoint dynamically to create subtle internal glistening motion
            let startX = -1.8 + (CGFloat(progress) * 3.6)
            let endX = startX + 2.0
            
            let purpleGlisteningGradient = LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0.54, green: 0.18, blue: 0.86), location: 0.0),   // Deep Violet
                    .init(color: Color(red: 0.68, green: 0.28, blue: 0.94), location: 0.25),  // Electric Purple
                    .init(color: Color(red: 0.86, green: 0.70, blue: 0.98), location: 0.42),  // Soft Lavender
                    .init(color: Color(red: 0.98, green: 0.94, blue: 1.00).opacity(0.85), location: 0.50), // Subtle Glistening Shine Core
                    .init(color: Color(red: 0.86, green: 0.70, blue: 0.98), location: 0.58),  // Soft Lavender
                    .init(color: Color(red: 0.72, green: 0.32, blue: 0.95), location: 0.75),  // Soft Purple
                    .init(color: Color(red: 0.48, green: 0.12, blue: 0.80), location: 1.0)    // Rich Dark Violet
                ]),
                startPoint: UnitPoint(x: startX, y: 0.15),
                endPoint: UnitPoint(x: endX, y: 0.85)
            )

            Text(text)
                .font(font)
                .foregroundStyle(purpleGlisteningGradient)
                .shadow(color: Color(red: 0.58, green: 0.22, blue: 0.95).opacity(0.30), radius: shadowRadius, x: 0, y: 1.0)
        }
    }
}

// MARK: - 3D Rankings Podium View (Top 3 Showcase with Staggered Entrance Animation)


struct RankingsPodiumView<Item: Identifiable>: View {
    @Environment(\.colorScheme) private var colorScheme

    let topThree: [Item]
    let displayName: (Item) -> String
    let username: (Item) -> String
    let avatarURL: (Item) -> URL?
    let metricValue: (Item) -> String
    let metricIcon: String
    let onTap: (Item) -> Void

    @State private var showRank3 = false
    @State private var showRank2 = false
    @State private var showRank1 = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Layer 1 (BACK): 2nd and 3rd Place Stands (Static)
            HStack(alignment: .bottom, spacing: 0) {
                // Rank 2 (Left Stand - Perfectly Aligned)
                if topThree.count >= 2 {
                    podiumColumn(item: topThree[1], place: 2, pillarHeight: 75)
                        .frame(width: 102)
                } else {
                    Spacer().frame(width: 102)
                }

                // Center gap space making stands slightly separated
                Spacer().frame(width: 120)

                // Rank 3 (Right Stand - Perfectly Aligned)
                if topThree.count >= 3 {
                    podiumColumn(item: topThree[2], place: 3, pillarHeight: 55)
                        .frame(width: 102)
                } else {
                    Spacer().frame(width: 102)
                }
            }
            .offset(y: 0)

            // Layer 2 (FRONT): 1st Place Stand (Stepped forward with slight separation space)
            if topThree.count >= 1 {
                podiumColumn(item: topThree[0], place: 1, pillarHeight: 110)
                    .frame(width: 108)
                    .shadow(
                        color: colorScheme == .dark
                            ? Color.black.opacity(0.40)
                            : Color(red: 0.58, green: 0.22, blue: 0.95).opacity(0.15),
                        radius: 8,
                        x: 0,
                        y: 4
                    )
                    .offset(y: 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.top, TravSpacing.xs)
        .padding(.bottom, 4) // Moved spots below 1-3 up closer
        .task {
            triggerEntranceAnimation()
        }
        .onChange(of: topThree.map { $0.id }) { _, _ in
            triggerEntranceAnimation()
        }
    }

    private func triggerEntranceAnimation() {
        showRank3 = false
        showRank2 = false
        showRank1 = false

        // Staggered Entrance: #3 at 0.18s, #2 at 0.36s, #1 at 0.54s (List below 1-3 loads first at 0.05s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                showRank3 = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                showRank2 = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.54) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                showRank1 = true
            }
        }
    }

    private func podiumColumn(item: Item, place: Int, pillarHeight: CGFloat) -> some View {
        let isFirst = place == 1
        let isSecond = place == 2
        let isDark = colorScheme == .dark

        let showContent: Bool = {
            switch place {
            case 1: return showRank1
            case 2: return showRank2
            default: return showRank3
            }
        }()

        // Theme-aware cylinder body fill
        let cylinderStyle: AnyShapeStyle = isDark
            ? AnyShapeStyle(
                LinearGradient(
                    colors: [
                        TravColors.accent.opacity(0.45),
                        TravColors.accent.opacity(0.15)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            : AnyShapeStyle(
                Color(red: 0.88, green: 0.75, blue: 1.0).opacity(0.28)
            )

        let strokeColor: Color = isDark
            ? Color(red: 0.58, green: 0.22, blue: 0.95)
            : Color(red: 0.74, green: 0.48, blue: 0.96).opacity(0.65)

        let strokeWidth: CGFloat = 1.0
        let capHeight: CGFloat = 26

        return VStack(spacing: 0) {
            // Profile & User Details on Top of Cylinder Platform (Fades in & slides up in sequence)
            Button {
                onTap(item)
            } label: {
                VStack(spacing: 5) {
                    // BIG Rank Text at top ("#1", "#2", "#3") with Desynchronized Glistening Moving Purple Gradient
                    GlisteningPurpleRankText(
                        text: isFirst ? "#1" : (isSecond ? "#2" : "#3"),
                        font: .system(size: isFirst ? 26 : 22, weight: .black, design: .rounded),
                        shadowRadius: isFirst ? 4 : 2,
                        delayOffset: isFirst ? 0.0 : (isSecond ? 0.9 : 1.8)
                    )
                    .padding(.bottom, 2)

                    // Avatar with Purple border for each spot (#1, #2, #3)
                    LeaderboardAvatarView(
                        url: avatarURL(item),
                        name: username(item),
                        size: isFirst ? 56 : (isSecond ? 48 : 42)
                    )
                    .overlay(
                        Circle()
                            .stroke(TravColors.accent, lineWidth: isFirst ? 2.5 : 2.0)
                    )
                    .shadow(color: TravColors.accent.opacity(0.25), radius: isFirst ? 6 : 3, y: 2)

                    // Handle ONLY (@username)
                    Text("@\(username(item))")
                        .font(.system(size: isFirst ? 13 : 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(TravColors.primary)
                        .lineLimit(1)

                    // Score / Metric Pill (Hidden if empty)
                    if !metricValue(item).isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: metricIcon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(TravColors.accent)
                            Text(metricValue(item))
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundStyle(TravColors.accent)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(TravColors.accentSoft)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(TravColors.border.opacity(0.5), lineWidth: 1)
                        )
                    }
                }
                .padding(.bottom, 20)
            }
            .buttonStyle(TravPressButtonStyle(scale: 0.96))
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 18)

            // 3D Cylinder Pedestal with Uniform Body Fill
            ZStack(alignment: .top) {
                // Background Occlusion Layer
                ZStack(alignment: .top) {
                    Ellipse()
                        .fill(TravColors.surface)
                        .frame(height: capHeight)
                        .offset(y: -13)

                    Rectangle()
                        .fill(TravColors.surface)
                        .frame(height: pillarHeight)

                    Ellipse()
                        .fill(TravColors.surface)
                        .frame(height: capHeight)
                        .offset(y: pillarHeight - 13)
                }

                // Single Continuous Uniform Body Fill
                Rectangle()
                    .fill(cylinderStyle)
                    .frame(height: pillarHeight + capHeight)
                    .mask(
                        ZStack(alignment: .top) {
                            Ellipse()
                                .frame(height: capHeight)
                                .offset(y: -13)

                            Rectangle()
                                .frame(height: pillarHeight)

                            Ellipse()
                                .frame(height: capHeight)
                                .offset(y: pillarHeight - 13)
                        }
                    )
                    .offset(y: -13)

                // Left & Right Vertical Side Lines
                HStack {
                    Rectangle()
                        .fill(strokeColor)
                        .frame(width: strokeWidth, height: pillarHeight)
                    Spacer()
                    Rectangle()
                        .fill(strokeColor)
                        .frame(width: strokeWidth, height: pillarHeight)
                }

                // Top Oval Cap Stroke
                Ellipse()
                    .stroke(strokeColor, lineWidth: strokeWidth)
                    .frame(height: capHeight)
                    .offset(y: -13)

                // Bottom Oval Base Stroke
                Ellipse()
                    .stroke(strokeColor, lineWidth: strokeWidth)
                    .frame(height: capHeight)
                    .offset(y: pillarHeight - 13)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Rankings Full-Width List View (Rank 4+)

struct RankingsListView<Item: Identifiable>: View {
    let items: [Item]
    let startIndex: Int
    let displayName: (Item) -> String
    let username: (Item) -> String
    let avatarURL: (Item) -> URL?
    let metricValue: (Item) -> String
    let metricIcon: String
    let onTap: (Item) -> Void

    @State private var showList = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let rank = startIndex + index

                Button {
                    onTap(item)
                } label: {
                    HStack(spacing: 14) {
                        // Rank Number
                        if rank <= 3 {
                            let delay = Double(rank - 1) * 0.9
                            GlisteningPurpleRankText(
                                text: "\(rank)",
                                font: .system(size: 16, weight: .black, design: .rounded),
                                shadowRadius: 2,
                                delayOffset: delay
                            )
                            .frame(width: 24, alignment: .leading)
                        } else {
                            Text("\(rank)")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(TravColors.muted)
                                .frame(width: 24, alignment: .leading)
                        }

                        // Avatar
                        LeaderboardAvatarView(
                            url: avatarURL(item),
                            name: username(item),
                            size: 42
                        )

                        // Handle ONLY (Names removed as requested)
                        Text("@\(username(item))")
                            .font(TravTypography.bodyLarge())
                            .fontWeight(.semibold)
                            .foregroundStyle(TravColors.primary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        // Metric value (Hidden if empty)
                        if !metricValue(item).isEmpty {
                            let valueStr = metricValue(item)
                            let components = valueStr.components(separatedBy: " • ")

                            if components.count == 2 {
                                VStack(alignment: .trailing, spacing: 1) {
                                    HStack(spacing: 3) {
                                        Image(systemName: metricIcon)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(TravColors.accent)

                                        Text(components[0])
                                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                            .foregroundStyle(TravColors.primary)
                                            .monospacedDigit()
                                    }

                                    Text(components[1])
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(TravColors.muted)
                                        .monospacedDigit()
                                }
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: metricIcon)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(TravColors.accent)

                                    Text(valueStr)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(TravColors.primary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, TravSpacing.screenHorizontal)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(TravPressButtonStyle(scale: 0.98))

                Divider()
                    .padding(.leading, 68)
                    .opacity(0.35)
            }
        }
        .padding(.top, 0)
        .opacity(showList ? 1 : 0)
        .offset(y: showList ? 0 : 16)
        .task {
            triggerListAnimation()
        }
        .onChange(of: items.map { $0.id }) { _, _ in
            triggerListAnimation()
        }
    }

    private func triggerListAnimation() {
        showList = false
        // Fades in FIRST when page loads (0.05s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.38)) {
                showList = true
            }
        }
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
    var icon: String? = nil
    let title: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TravColors.accent)
                }

                Text(title)
                    .font(TravTypography.labelMedium())
                    .foregroundStyle(TravColors.primary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TravColors.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(TravColors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(TravColors.border.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.96))
    }
}

// MARK: - Combined Filter Modal Sheet (Member Scope & Location)

struct CombinedFilterModalSheet: View {
    let availableLocations: [LocationOption]
    let selectedScope: MemberScopeFilter
    let selectedLocation: LocationOption
    let onApply: (MemberScopeFilter, LocationOption) -> Void

    @Environment(\.dismiss) private var dismiss: DismissAction

    @State private var tempScope: MemberScopeFilter
    @State private var tempLocation: LocationOption
    @State private var customCityName: String? = nil
    @State private var isSettled: Bool = true

    init(
        availableLocations: [LocationOption],
        selectedScope: MemberScopeFilter,
        selectedLocation: LocationOption,
        onApply: @escaping (MemberScopeFilter, LocationOption) -> Void
    ) {
        self.availableLocations = availableLocations
        self.selectedScope = selectedScope
        self.selectedLocation = selectedLocation
        self.onApply = onApply
        self._tempScope = State(initialValue: selectedScope)
        self._tempLocation = State(initialValue: selectedLocation)
        if selectedLocation.id != LocationOption.allLocations.id {
            self._customCityName = State(initialValue: selectedLocation.name)
        }
    }

    var displayLocations: [LocationOption] {
        var locs = availableLocations
        if tempLocation.id != LocationOption.allLocations.id,
           !locs.contains(where: { $0.id == tempLocation.id || $0.name.lowercased() == tempLocation.name.lowercased() }) {
            locs.insert(tempLocation, at: 1)
        }
        return locs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Filter Rankings")
                    .font(TravTypography.titleLarge())
                    .fontWeight(.bold)
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
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .padding(.top, TravSpacing.md)
            .padding(.bottom, TravSpacing.sm)

            ScrollView {
                VStack(alignment: .leading, spacing: TravSpacing.lg) {
                    // SECTION 1: COMMUNITY MEMBER SCOPE
                    VStack(alignment: .leading, spacing: TravSpacing.xs) {
                        Text("COMMUNITY SCOPE")
                            .font(TravTypography.overline())
                            .tracking(2.0)
                            .foregroundStyle(TravColors.muted)

                        VStack(spacing: 8) {
                            ForEach(MemberScopeFilter.allCases) { scope in
                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        tempScope = scope
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    HStack(spacing: TravSpacing.md) {
                                        ZStack {
                                            Circle()
                                                .fill(tempScope == scope ? TravColors.accent.opacity(0.18) : TravColors.surfaceElevated)
                                                .frame(width: 36, height: 36)
                                            Image(systemName: scope.iconName)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(tempScope == scope ? TravColors.accent : TravColors.muted)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(scope.title)
                                                .font(TravTypography.bodyMedium())
                                                .fontWeight(.semibold)
                                                .foregroundStyle(TravColors.primary)
                                            Text(scope.subtitle)
                                                .font(TravTypography.caption())
                                                .foregroundStyle(TravColors.muted)
                                        }

                                        Spacer()

                                        if tempScope == scope {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundStyle(TravColors.accent)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                            .fill(tempScope == scope ? TravColors.surfaceElevated : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                            .stroke(tempScope == scope ? TravColors.accent.opacity(0.4) : TravColors.border.opacity(0.25), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // SECTION 2: LOCATION SCOPE
                    VStack(alignment: .leading, spacing: TravSpacing.xs) {
                        Text("LOCATION SCOPE")
                            .font(TravTypography.overline())
                            .tracking(2.0)
                            .foregroundStyle(TravColors.muted)

                        // Autocomplete city search
                        CityAutocompleteField(
                            title: "",
                            placeholder: "Search for any city worldwide...",
                            selectedCity: $customCityName,
                            isSettled: $isSettled
                        )
                        .onChange(of: customCityName) { _, newCity in
                            if let newCity, !newCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                let option = LocationOption(id: "city_\(newCity.lowercased())", name: newCity, subtitle: nil)
                                tempLocation = option
                            }
                        }

                        VStack(spacing: 6) {
                            ForEach(displayLocations) { location in
                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        tempLocation = location
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    HStack(spacing: TravSpacing.md) {
                                        ZStack {
                                            Circle()
                                                .fill(tempLocation.id == location.id ? TravColors.accent.opacity(0.18) : TravColors.surfaceElevated)
                                                .frame(width: 34, height: 34)
                                            Image(systemName: location.id == LocationOption.allLocations.id ? "globe" : "mappin.circle.fill")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(tempLocation.id == location.id ? TravColors.accent : TravColors.muted)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(location.name)
                                                .font(TravTypography.bodyMedium())
                                                .fontWeight(.semibold)
                                                .foregroundStyle(TravColors.primary)
                                            if let sub = location.subtitle {
                                                Text(sub)
                                                    .font(TravTypography.caption())
                                                    .foregroundStyle(TravColors.muted)
                                            }
                                        }

                                        Spacer()

                                        if tempLocation.id == location.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundStyle(TravColors.accent)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                            .fill(tempLocation.id == location.id ? TravColors.surfaceElevated : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                            .stroke(tempLocation.id == location.id ? TravColors.accent.opacity(0.4) : TravColors.border.opacity(0.25), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.bottom, 20)
            }

            // Apply Button
            Button {
                onApply(tempScope, tempLocation)
                dismiss()
            } label: {
                Text("Apply Filters")
                    .font(TravTypography.bodyLarge())
                    .fontWeight(.bold)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [TravColors.accent, Color(red: 0.52, green: 0.20, blue: 0.90)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
                    .shadow(color: TravColors.accent.opacity(0.35), radius: 6, y: 3)
            }
            .buttonStyle(TravPressButtonStyle(scale: 0.98))
            .padding(.horizontal, TravSpacing.screenHorizontal)
            .padding(.bottom, TravSpacing.md)
        }
        .travScreenBackground()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(TravRadius.xl)
    }
}

// MARK: - Member Scope Modal Sheet

struct MemberFilterModalSheet: View {
    let selectedScope: MemberScopeFilter
    let onSelect: (MemberScopeFilter) -> Void
    @Environment(\.dismiss) private var dismiss: DismissAction

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
    @Environment(\.dismiss) private var dismiss: DismissAction

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
                if entry.rank <= 3 {
                    let delay = Double(entry.rank - 1) * 0.9
                    GlisteningPurpleRankText(
                        text: "\(entry.rank)",
                        font: .system(size: 17, weight: .black, design: .rounded),
                        shadowRadius: 2,
                        delayOffset: delay
                    )
                    .frame(width: 26, alignment: .leading)
                } else {
                    Text("\(entry.rank)")
                        .font(TravTypography.titleMedium())
                        .fontWeight(.bold)
                        .foregroundStyle(entry.rank <= 3 ? TravColors.primary : TravColors.muted.opacity(0.7))
                        .frame(width: 26, alignment: .leading)
                }

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
    @Environment(AppEnvironment.self) private var environment: AppEnvironment
    @Environment(AppRouter.self) private var router: AppRouter
    @Environment(EngagementStore.self) private var engagement: EngagementStore

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
            if isLoading {
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
                    VStack(spacing: 0) {
                        if filteredEntries.count >= 3 {
                            RankingsPodiumView<HeatStreakEntry>(
                                topThree: Array(filteredEntries.prefix(3)),
                                displayName: { $0.displayName },
                                username: { $0.username },
                                avatarURL: { $0.avatarURL },
                                metricValue: { "\($0.consecutiveDays)d • \($0.count30Days) posts" },
                                metricIcon: "flame.fill",
                                onTap: { router.openProfile($0.username) }
                            )
                        }

                        let listEntries = filteredEntries.count >= 3 ? Array(filteredEntries.dropFirst(3)) : filteredEntries
                        let startIndex = filteredEntries.count >= 3 ? 4 : 1

                        if !listEntries.isEmpty {
                            RankingsListView<HeatStreakEntry>(
                                items: listEntries,
                                startIndex: startIndex,
                                displayName: { $0.displayName },
                                username: { $0.username },
                                avatarURL: { $0.avatarURL },
                                metricValue: { "\($0.consecutiveDays)d • \($0.count30Days) posts" },
                                metricIcon: "flame.fill",
                                onTap: { router.openProfile($0.username) }
                            )
                        }
                    }
                    .padding(.bottom, TravSpacing.tabBarBottom + 40)
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
        .task(id: engagement.revision) {
            await loadRealEntries()
        }
        .task(id: router.experienceCatalogRevision) {
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
        .refreshable {
            await loadRealEntries()
        }
    }

    @MainActor
    private func loadRealEntries() async {
        isLoading = true
        let cityID: UUID? = (selectedLocation.id == LocationOption.allLocations.id) ? nil : UUID(uuidString: selectedLocation.id)
        let fetchedUsers = (try? await environment.experiences.fetchHeatStreakEntries(
            cityID: cityID,
            cityName: selectedLocation.id == LocationOption.allLocations.id ? nil : selectedLocation.name
        )) ?? []

        entries = fetchedUsers
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
                if entry.rank <= 3 {
                    let delay = Double(entry.rank - 1) * 0.9
                    GlisteningPurpleRankText(
                        text: "\(entry.rank)",
                        font: .system(size: 17, weight: .black, design: .rounded),
                        shadowRadius: 2,
                        delayOffset: delay
                    )
                    .frame(width: 26, alignment: .leading)
                } else {
                    Text("\(entry.rank)")
                        .font(TravTypography.titleMedium())
                        .fontWeight(.bold)
                        .foregroundStyle(entry.rank <= 3 ? TravColors.primary : TravColors.muted.opacity(0.7))
                        .frame(width: 26, alignment: .leading)
                }

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
    @Environment(AppEnvironment.self) private var environment: AppEnvironment
    @Environment(AppRouter.self) private var router: AppRouter
    @Environment(EngagementStore.self) private var engagement: EngagementStore

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
            if isLoading {
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
                    VStack(spacing: 0) {
                        if filteredEntries.count >= 3 {
                            RankingsPodiumView<ImpactEntry>(
                                topThree: Array(filteredEntries.prefix(3)),
                                displayName: { $0.displayName },
                                username: { $0.username },
                                avatarURL: { $0.avatarURL },
                                metricValue: { "\($0.totalImpactCount)" },
                                metricIcon: "bookmark.fill",
                                onTap: { router.openProfile($0.username) }
                            )
                        }

                        let listEntries = filteredEntries.count >= 3 ? Array(filteredEntries.dropFirst(3)) : filteredEntries
                        let startIndex = filteredEntries.count >= 3 ? 4 : 1

                        if !listEntries.isEmpty {
                            RankingsListView<ImpactEntry>(
                                items: listEntries,
                                startIndex: startIndex,
                                displayName: { $0.displayName },
                                username: { $0.username },
                                avatarURL: { $0.avatarURL },
                                metricValue: { "\($0.totalImpactCount)" },
                                metricIcon: "bookmark.fill",
                                onTap: { router.openProfile($0.username) }
                            )
                        }
                    }
                    .padding(.bottom, TravSpacing.tabBarBottom + 40)
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
        .task(id: router.experienceCatalogRevision) {
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

    @MainActor
    private func loadRealEntries() async {
        isLoading = true
        let cityID: UUID? = (selectedLocation.id == LocationOption.allLocations.id) ? nil : UUID(uuidString: selectedLocation.id)
        let fetchedUsers = (try? await environment.experiences.fetchImpactLeaderboard(
            cityID: cityID,
            cityName: selectedLocation.id == LocationOption.allLocations.id ? nil : selectedLocation.name
        )) ?? []

        entries = fetchedUsers
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
                if entry.rank <= 3 {
                    let delay = Double(entry.rank - 1) * 0.9
                    GlisteningPurpleRankText(
                        text: "\(entry.rank)",
                        font: .system(size: 17, weight: .black, design: .rounded),
                        shadowRadius: 2,
                        delayOffset: delay
                    )
                    .frame(width: 26, alignment: .leading)
                } else {
                    Text("\(entry.rank)")
                        .font(TravTypography.titleMedium())
                        .fontWeight(.bold)
                        .foregroundStyle(entry.rank <= 3 ? TravColors.primary : TravColors.muted.opacity(0.7))
                        .frame(width: 26, alignment: .leading)
                }

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
    @Environment(AppEnvironment.self) private var environment: AppEnvironment
    @Environment(AppRouter.self) private var router: AppRouter
    @Environment(EngagementStore.self) private var engagement: EngagementStore

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
            if isLoading {
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
                    VStack(spacing: 0) {
                        if filteredEntries.count >= 3 {
                            RankingsPodiumView<MainLeaderboardEntry>(
                                topThree: Array(filteredEntries.prefix(3)),
                                displayName: { $0.displayName },
                                username: { $0.username },
                                avatarURL: { $0.avatarURL },
                                metricValue: { _ in "" },
                                metricIcon: "",
                                onTap: { router.openProfile($0.username) }
                            )
                        }

                        let listEntries = filteredEntries.count >= 3 ? Array(filteredEntries.dropFirst(3)) : filteredEntries
                        let startIndex = filteredEntries.count >= 3 ? 4 : 1

                        if !listEntries.isEmpty {
                            RankingsListView<MainLeaderboardEntry>(
                                items: listEntries,
                                startIndex: startIndex,
                                displayName: { $0.displayName },
                                username: { $0.username },
                                avatarURL: { $0.avatarURL },
                                metricValue: { _ in "" },
                                metricIcon: "",
                                onTap: { router.openProfile($0.username) }
                            )
                        }
                    }
                    .padding(.bottom, TravSpacing.tabBarBottom + 40)
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
        .task(id: router.experienceCatalogRevision) {
            await loadLeaderboard()
        }
        .onChange(of: selectedLocation) { _, _ in
            Task { await loadLeaderboard() }
        }
        .onChange(of: memberScope) { _, _ in
            Task { await loadLeaderboard() }
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

    @MainActor
    private func loadLeaderboard() async {
        isLoading = true
        let cityID: UUID? = (selectedLocation.id == LocationOption.allLocations.id) ? nil : UUID(uuidString: selectedLocation.id)
        let fetchedEntries = (try? await environment.experiences.fetchMainLeaderboard(
            cityID: cityID,
            cityName: selectedLocation.id == LocationOption.allLocations.id ? nil : selectedLocation.name
        )) ?? []

        entries = fetchedEntries
        isLoading = false
    }
}

