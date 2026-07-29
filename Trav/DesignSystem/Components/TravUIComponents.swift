import SwiftUI

// MARK: - Button Styles

struct TravPressButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(TravAnimation.press, value: configuration.isPressed)
    }
}

// MARK: - Buttons

struct SecondaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: TravSpacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: TravIcon.sm, weight: .semibold))
                }
                Text(title)
                    .font(TravTypography.titleMedium())
            }
            .foregroundStyle(TravColors.primary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: TravLayout.buttonHeight)
            .background(TravColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                    .stroke(TravColors.border.opacity(0.6), lineWidth: 1)
            }
        }
        .buttonStyle(TravPressButtonStyle())
    }
}

struct DismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: TravIcon.sm, weight: .semibold))
                .foregroundStyle(TravColors.primary)
                .frame(width: TravLayout.minTouchTarget, height: TravLayout.minTouchTarget)
                .background(
                    Circle()
                        .fill(TravColors.surfaceElevated)
                )
                .overlay {
                    Circle()
                        .strokeBorder(TravColors.border, lineWidth: 1.5)
                }
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.94))
        .accessibilityLabel("Close")
    }
}

// MARK: - Form Fields

struct TravTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var contentType: UITextContentType?
    var keyboardType: UIKeyboardType = .default
    var isSecure = false

    var body: some View {
        VStack(alignment: .leading, spacing: TravSpacing.xxs) {
            Text(title)
                .font(TravTypography.labelMedium())
                .foregroundStyle(TravColors.muted)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text, axis: axis)
                }
            }
            .font(TravTypography.bodyLarge())
            .textContentType(contentType)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(isSecure ? .never : .sentences)
            .autocorrectionDisabled(isSecure)
            .padding(TravSpacing.md)
            .frame(minHeight: TravLayout.minTouchTarget)
            .background(TravColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                    .stroke(TravColors.border.opacity(0.5), lineWidth: 1)
            }
        }
    }
}

struct TravFormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TravSpacing.sm) {
            Text(title)
                .font(TravTypography.titleMedium())
                .foregroundStyle(TravColors.primary)
            content
        }
    }
}

// MARK: - Chips

struct SelectionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(TravTypography.labelMedium())
                .foregroundStyle(isSelected ? .white : TravColors.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, TravSpacing.md)
                .frame(minHeight: TravLayout.minTouchTarget)
                .background(isSelected ? TravColors.accent : TravColors.surfaceElevated)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.clear : TravColors.border.opacity(0.5), lineWidth: 1)
                }
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.96))
        .animation(TravAnimation.quick, value: isSelected)
    }
}

// MARK: - Glass Icon Button

struct TravGlassIconButton: View {
    let systemName: String
    var tint: Color = .white
    var material = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: TravLayout.glassIconSize, height: TravLayout.glassIconSize)
                .background {
                    ZStack {
                        if material {
                            Circle().fill(.black.opacity(0.5))
                            Circle().fill(.ultraThinMaterial)
                        } else {
                            Circle().fill(TravColors.surfaceElevated)
                        }
                    }
                }
                .overlay {
                    Circle().strokeBorder(
                        material ? .white.opacity(0.55) : TravColors.border,
                        lineWidth: 1.25
                    )
                }
        }
        .buttonStyle(TravPressButtonStyle(scale: 0.9))
        .frame(width: TravLayout.glassIconSize, height: TravLayout.glassIconSize)
    }
}

// MARK: - Social Proof

struct TravSocialProofRow: View {
    let saveCount: Int
    let completionCount: Int
    var isSaved: Bool = false
    var style: Style = .standard

    enum Style {
        case standard
        case onDark

        var saveColor: Color {
            switch self {
            case .standard: TravColors.muted
            case .onDark: .white.opacity(0.78)
            }
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TravSpacing.md) {
                saveLabel
                completionLabel
            }
            VStack(alignment: .leading, spacing: TravSpacing.xxs) {
                saveLabel
                completionLabel
            }
        }
    }

    private var saveLabel: some View {
        Label {
            Text("\(TravFormatters.count(saveCount)) Saved")
                .font(TravTypography.caption())
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        } icon: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(style.saveColor)
        .labelStyle(.titleAndIcon)
    }

    private var completionLabel: some View {
        Label {
            Text("\(TravFormatters.count(completionCount)) Completed")
                .font(TravTypography.labelMedium())
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(TravColors.success)
        .labelStyle(.titleAndIcon)
    }
}

// MARK: - Empty & Error States

struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    var actionTitle: String?
    var action: (() -> Void)?

    @State private var appeared = false

    var body: some View {
        VStack(spacing: TravSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: TravIcon.xl))
                .foregroundStyle(TravColors.accent)
                .padding(TravSpacing.lg)
                .background(TravColors.accentSoft)
                .clipShape(Circle())
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: TravSpacing.sm) {
                Text(title)
                    .font(TravTypography.displayMedium())
                    .foregroundStyle(TravColors.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(description)
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, action: action)
                    .padding(.top, TravSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.vertical, TravSpacing.lg)
        .onAppear {
            withAnimation(TravAnimation.enter) { appeared = true }
        }
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: TravSpacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: TravIcon.lg))
                .foregroundStyle(TravColors.error)

            Text(message)
                .font(TravTypography.bodyMedium())
                .foregroundStyle(TravColors.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(title: "Try Again", action: retry)
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.vertical, TravSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Images

struct RemoteImage: View {
    let url: URL?
    var height: CGFloat = TravLayout.cardImageHeight
    var cornerRadius: CGFloat = TravRadius.md
    /// Cap decoded pixel size for grid/list thumbnails.
    var maxPixelSize: CGFloat = 900

    @State private var image: UIImage?
    @State private var failed = false
    @State private var loadToken = 0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(TravColors.surfaceElevated)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                imageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .clipped()
            .task(id: url?.absoluteString) {
                await load()
            }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if failed {
            VStack(spacing: TravSpacing.xs) {
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(TravColors.muted)
                Button("Retry") {
                    loadToken &+= 1
                    Task { await load() }
                }
                .font(TravTypography.labelMedium())
                .foregroundStyle(TravColors.accent)
            }
            .accessibilityLabel("Image failed to load. Retry.")
        } else if url != nil {
            ProgressView().tint(TravColors.muted)
        }
    }

    private func load() async {
        guard let url else {
            image = nil
            failed = false
            return
        }
        failed = false
        image = nil
        let token = loadToken
        let result = await ImageCache.shared.image(for: url, maxPixelSize: maxPixelSize)
        guard token == loadToken else { return }
        if let result {
            image = result
        } else {
            failed = true
        }
    }
}

struct HeroImageHeader<Overlay: View>: View {
    let url: URL?
    let height: CGFloat
    @ViewBuilder let overlay: () -> Overlay

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: url, height: height, cornerRadius: 0)

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)

            overlay()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.bottom, TravSpacing.lg)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

// MARK: - Tab Bar

struct TravTabBar: View {
    @Binding var activeTab: TravTab
    /// Independent of app appearance — driven by content behind the bar.
    var backdrop: TabBarBackdrop = .dark
    @Environment(AppearanceStore.self) private var appearance
    @Environment(SessionStore.self) private var session

    /// In light mode always use light chrome + black labels, even over dark feed cards.
    private var isDarkChrome: Bool {
        if appearance.isLightMode { return false }
        return backdrop == .dark
    }

    private var profileAvatarURL: URL? {
        session.currentUser?.avatarURL
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TravTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(TravAnimation.tab) {
                        activeTab = tab
                    }
                } label: {
                    VStack(spacing: TravSpacing.xxs) {
                        tabIcon(for: tab)

                        Text(tab.rawValue)
                            .font(TravTypography.tabLabel())
                            .foregroundStyle(tabForeground(isSelected: activeTab == tab))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: TravLayout.minTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(activeTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, TravSpacing.sm)
        .padding(.vertical, TravSpacing.xs)
        .background {
            Capsule()
                .fill(.regularMaterial)
                .overlay {
                    Capsule()
                        .fill(
                            isDarkChrome
                                ? Color.black.opacity(0.28)
                                : Color.white.opacity(appearance.isLightMode ? 0.72 : 0.35)
                        )
                }
                .overlay {
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: isDarkChrome
                                    ? [.white.opacity(0.28), .white.opacity(0.08)]
                                    : [Color.black.opacity(0.18), Color.black.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: TravShadow.elevated().color.opacity(isDarkChrome ? 1 : 0.45),
                    radius: TravShadow.elevated().radius,
                    y: TravShadow.elevated().y
                )
                .environment(\.colorScheme, isDarkChrome ? .dark : .light)
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.bottom, TravSpacing.tabBarBottom)
        .animation(.easeInOut(duration: 0.22), value: backdrop)
        .animation(.easeInOut(duration: 0.22), value: appearance.isLightMode)
        .animation(.easeInOut(duration: 0.22), value: profileAvatarURL?.absoluteString)
    }

    @ViewBuilder
    private func tabIcon(for tab: TravTab) -> some View {
        let isSelected = activeTab == tab

        if tab == .profile, let avatarURL = profileAvatarURL {
            AvatarView(url: avatarURL, size: TravLayout.tabBarAvatarSize)
                .overlay {
                    Circle()
                        .strokeBorder(
                            isSelected ? TravColors.accent : tabAvatarOutline,
                            lineWidth: 1.5
                        )
                }
        } else {
            Image(systemName: tab.systemImage)
                .font(.system(size: TravLayout.tabBarIconSize, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(tabForeground(isSelected: isSelected))
                .symbolEffect(.bounce, value: isSelected)
        }
    }

    private func tabForeground(isSelected: Bool) -> Color {
        if isSelected { return TravColors.accent }
        if appearance.isLightMode { return TravColors.muted }
        return isDarkChrome ? Color.white.opacity(0.62) : TravColors.muted
    }

    /// Unselected avatar ring — solid opaque gray.
    private var tabAvatarOutline: Color {
        TravColors.muted
    }
}

/// Whether content under the floating tab bar is visually dark or light.
enum TabBarBackdrop: String, Equatable {
    case light
    case dark
}

struct TabBarBackdropPreferenceKey: PreferenceKey {
    static let defaultValue: TabBarBackdrop = .dark

    static func reduce(value: inout TabBarBackdrop, nextValue: () -> TabBarBackdrop) {
        value = nextValue()
    }
}

extension View {
    /// Reports the visual backdrop under the tab bar so chrome can adapt independently.
    func tabBarBackdrop(_ backdrop: TabBarBackdrop) -> some View {
        preference(key: TabBarBackdropPreferenceKey.self, value: backdrop)
    }
}

// MARK: - Action Bar

struct TravActionButton: View {
    let symbol: String
    let label: String
    var isAccent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: TravSpacing.xxs) {
                Image(systemName: symbol)
                    .font(.system(size: TravIcon.md, weight: .medium))
                Text(label)
                    .font(TravTypography.caption())
            }
            .foregroundStyle(isAccent ? TravColors.accent : TravColors.primary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: TravLayout.minTouchTarget)
            .background(isAccent ? TravColors.accentSoft : TravColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
        }
        .buttonStyle(TravPressButtonStyle())
    }
}

// MARK: - Loading Skeletons

struct CityPageSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TravLayout.sectionSpacing) {
                SkeletonView(height: TravLayout.heroCityHeightMin, cornerRadius: 0)

                VStack(alignment: .leading, spacing: TravLayout.sectionSpacing) {
                    SkeletonView(height: TravLayout.citySearchHeight, cornerRadius: TravRadius.xl)
                        .padding(.horizontal, TravSpacing.screenHorizontal)

                    SkeletonView(height: TravLayout.featuredCardHeight, cornerRadius: TravRadius.xl)
                        .padding(.horizontal, TravSpacing.screenHorizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: TravSpacing.md) {
                            ForEach(0..<4, id: \.self) { _ in
                                VStack(spacing: TravSpacing.xs) {
                                    SkeletonView(height: 64, cornerRadius: 32)
                                        .frame(width: 64)
                                    SkeletonView(height: 12, cornerRadius: TravRadius.sm)
                                    SkeletonView(height: 10, cornerRadius: TravRadius.sm)
                                }
                                .frame(width: TravLayout.creatorCardWidth)
                            }
                        }
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                    }

                    ForEach(0..<2, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: TravSpacing.sm) {
                            SkeletonView(height: TravLayout.feedCardImageHeight, cornerRadius: TravRadius.lg)
                            SkeletonView(height: 22, cornerRadius: TravRadius.sm)
                            SkeletonView(height: 14, cornerRadius: TravRadius.sm)
                            SkeletonView(height: 48, cornerRadius: TravRadius.md)
                        }
                        .padding(TravSpacing.md)
                        .background(TravColors.surfaceElevated.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                    }
                }
                .padding(.top, TravSpacing.lg)
            }
            .padding(.bottom, TravSpacing.xxl)
        }
        .ignoresSafeArea(edges: .top)
    }
}

struct ExperienceDetailSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TravSpacing.lg) {
                SkeletonView(height: TravLayout.heroExperienceHeight, cornerRadius: 0)
                HStack(spacing: TravSpacing.sm) {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonView(height: TravLayout.buttonHeight, cornerRadius: TravRadius.md)
                    }
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonView(height: 80, cornerRadius: TravRadius.md)
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                }
            }
            .padding(.bottom, TravSpacing.xxl)
        }
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - View Modifiers

struct TravAppearModifier: ViewModifier {
    @State private var appeared = false
    var delay: Double = 0

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .onAppear {
                withAnimation(TravAnimation.enter.delay(delay)) {
                    appeared = true
                }
            }
    }
}

struct TravScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(TravColors.surface)
            .scrollIndicators(.hidden)
    }
}

extension View {
    func travAppear(delay: Double = 0) -> some View {
        modifier(TravAppearModifier(delay: delay))
    }

    func travScreenBackground() -> some View {
        modifier(TravScreenBackground())
    }

    func travCardShadow() -> some View {
        let spec = TravShadow.card()
        return shadow(color: spec.color.opacity(0.7), radius: min(spec.radius, 8), y: min(spec.y, 3))
    }
}

struct DottedGridView: View {
    @Environment(AppearanceStore.self) private var appearance
    var dotSpacing: CGFloat = 28
    var dotSize: CGFloat = 2.0

    var body: some View {
        Canvas { context, size in
            let cols = Int(size.width / dotSpacing) + 1
            let rows = Int(size.height / dotSpacing) + 1
            let fill = appearance.isLightMode
                ? Color.black.opacity(0.08)
                : Color.white.opacity(0.12)

            for col in 0..<cols {
                for row in 0..<rows {
                    let x = CGFloat(col) * dotSpacing
                    let y = CGFloat(row) * dotSpacing

                    let rect = CGRect(
                        x: x - dotSize / 2,
                        y: y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(fill))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Full Screen Image Viewer

/// Identifiable container for full screen image viewing.
struct ImagePreviewItem: Identifiable, Sendable {
    let id = UUID()
    let urls: [URL]
    let initialIndex: Int
}

/// Full screen interactive image viewer with swipeable pagination, pinch-to-zoom,
/// double tap zoom, and swipe-down to dismiss.
struct FullScreenImageViewer: View {
    let urls: [URL]
    @State private var selectedIndex: Int
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero

    init(urls: [URL], initialIndex: Int = 0, onDismiss: @escaping () -> Void) {
        self.urls = urls
        self._selectedIndex = State(initialValue: initialIndex)
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            if urls.count > 1 {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        fullSizeZoomableImage(url: url)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            } else if let firstURL = urls.first {
                fullSizeZoomableImage(url: firstURL)
            } else {
                ContentUnavailableView(
                    "Image Unavailable",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("Could not load image file.")
                )
                .foregroundStyle(.white)
            }

            // Top control bar
            VStack {
                HStack {
                    if urls.count > 1 {
                        Text("\(selectedIndex + 1) of \(urls.count)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.2)))
                    }

                    Spacer()

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32, weight: .bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.black.opacity(0.6))
                            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close full screen image viewer")
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.top, TravSpacing.md)

                Spacer()
            }
        }
        .offset(y: dragOffset.height)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    if scale <= 1.0 {
                        dragOffset = gesture.translation
                    }
                }
                .onEnded { gesture in
                    if scale <= 1.0 && abs(gesture.translation.height) > 90 {
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .onChange(of: selectedIndex) { _, _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                scale = 1.0
            }
        }
    }

    private var backgroundOpacity: Double {
        let maxDrag: CGFloat = 280
        let dragProgress = min(abs(dragOffset.height) / maxDrag, 1.0)
        return max(0.2, 1.0 - Double(dragProgress) * 0.8)
    }

    @ViewBuilder
    private func fullSizeZoomableImage(url: URL) -> some View {
        ZStack {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failure:
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 36))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("Could not load image")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                case .empty:
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                @unknown default:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .scaleEffect(scale)
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let delta = value / lastScale
                    lastScale = value
                    scale = max(1.0, min(scale * delta, 4.0))
                }
                .onEnded { _ in
                    lastScale = 1.0
                    if scale < 1.0 {
                        withAnimation(.spring()) { scale = 1.0 }
                    }
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                scale = scale > 1.0 ? 1.0 : 2.5
            }
        }
    }
}

// MARK: - Navigation Bar Scroll Zoom Components

private struct NavBarScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

private struct IsNavBarZoomedOutKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// The current scale of the navigation bar (1.0 normal, ~0.92 when zoomed out while scrolling).
    var navBarScale: CGFloat {
        get { self[NavBarScaleKey.self] }
        set { self[NavBarScaleKey.self] = newValue }
    }

    /// Whether the navigation bar is currently zoomed out due to active downward scrolling.
    var isNavBarZoomedOut: Bool {
        get { self[IsNavBarZoomedOutKey.self] }
        set { self[IsNavBarZoomedOutKey.self] = newValue }
    }
}

// MARK: - Scroll Zoom Navigation Bar Modifier

private struct ScrollZoomNavBarOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next != 0 {
            value = next
        }
    }
}

/// A ViewModifier applied to a ScrollView or content container to detect scroll activity,
/// zooming out the navigation bar while actively scrolling down and restoring it when scrolling stops.
struct ScrollZoomNavBarModifier: ViewModifier {
    @State private var isScrollingDown: Bool = false
    @State private var lastOffset: CGFloat = 0
    @State private var stopTask: Task<Void, Never>? = nil

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollZoomNavBarOffsetKey.self,
                        value: geo.frame(in: .global).minY
                    )
                }
            }
            .onPreferenceChange(ScrollZoomNavBarOffsetKey.self) { newOffset in
                let delta = lastOffset - newOffset
                lastOffset = newOffset

                // Active scroll down (moving down past top boundary)
                if delta > 1.2 && newOffset < -5 {
                    if !isScrollingDown {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            isScrollingDown = true
                        }
                    }
                    // Reset stop timer on every scroll update
                    stopTask?.cancel()
                    stopTask = Task {
                        try? await Task.sleep(nanoseconds: 160_000_000) // 160ms pause threshold
                        if !Task.isCancelled {
                            await MainActor.run {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    isScrollingDown = false
                                }
                            }
                        }
                    }
                } else if delta < -1.2 {
                    // Scrolling back up - restore original size smoothly
                    stopTask?.cancel()
                    if isScrollingDown {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            isScrollingDown = false
                        }
                    }
                }
            }
            .environment(\.navBarScale, isScrollingDown ? 0.92 : 1.0)
            .environment(\.isNavBarZoomedOut, isScrollingDown)
    }
}

// MARK: - Navigation Bar Component Modifier

/// ViewModifier applied to custom navigation bar containers or toolbar items
/// to automatically scale down when scrolling down and restore when stopped.
struct NavBarZoomableModifier: ViewModifier {
    @Environment(\.navBarScale) private var navBarScale
    var anchor: UnitPoint = .center

    func body(content: Content) -> some View {
        content
            .scaleEffect(navBarScale, anchor: anchor)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: navBarScale)
    }
}

// MARK: - View Extensions for Navigation Bar Zooming

extension View {
    /// Enables navigation bar zoom-out animation during active downward scrolling.
    func trackScrollForNavBarZoom() -> some View {
        self.modifier(ScrollZoomNavBarModifier())
    }

    /// Applies the scroll-driven zoom animation to a navigation bar or header view.
    func navBarZoomable(anchor: UnitPoint = .center) -> some View {
        self.modifier(NavBarZoomableModifier(anchor: anchor))
    }
}

