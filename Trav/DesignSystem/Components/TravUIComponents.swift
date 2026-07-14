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
    }

    @ViewBuilder
    private var imageContent: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    EmptyView()
                case .empty:
                    ProgressView().tint(TravColors.muted)
                @unknown default:
                    EmptyView()
                }
            }
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

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TravTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(TravAnimation.tab) {
                        activeTab = tab
                    }
                } label: {
                    VStack(spacing: TravSpacing.xxs) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: TravLayout.tabBarIconSize, weight: activeTab == tab ? .semibold : .medium))
                            .symbolEffect(.bounce, value: activeTab == tab)

                        Text(tab.rawValue)
                            .font(TravTypography.tabLabel())
                    }
                    .foregroundStyle(activeTab == tab ? TravColors.accent : TravColors.muted)
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
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.28), .white.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: TravShadow.elevated().color, radius: TravShadow.elevated().radius, y: TravShadow.elevated().y)
        }
        .padding(.horizontal, TravSpacing.screenHorizontal)
        .padding(.bottom, TravSpacing.tabBarBottom)
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
