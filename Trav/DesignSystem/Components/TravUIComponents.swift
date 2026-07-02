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
                .background(TravColors.surfaceElevated)
                .clipShape(Circle())
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

                Text(description)
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, TravSpacing.xl)

            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, action: action)
                    .padding(.horizontal, TravSpacing.xl)
                    .padding(.top, TravSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, TravSpacing.screenHorizontal)
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

            PrimaryButton(title: "Try Again", action: retry)
        }
        .padding(TravSpacing.screenHorizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Images

struct RemoteImage: View {
    let url: URL?
    var height: CGFloat = TravLayout.cardImageHeight
    var cornerRadius: CGFloat = TravRadius.md

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        placeholder.overlay { ProgressView().tint(TravColors.muted) }
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        Rectangle().fill(TravColors.surfaceElevated)
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
                .padding(TravSpacing.screenHorizontal)
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
            VStack(alignment: .leading, spacing: TravSpacing.lg) {
                SkeletonView(height: TravLayout.heroCityHeight, cornerRadius: 0)
                VStack(alignment: .leading, spacing: TravSpacing.sm) {
                    SkeletonView(height: 22, cornerRadius: TravRadius.sm)
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                    SkeletonView(height: TravLayout.featuredCardHeight, cornerRadius: TravRadius.lg)
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TravSpacing.md) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(spacing: TravSpacing.sm) {
                            SkeletonView(height: TravLayout.cardImageHeight, cornerRadius: TravRadius.md)
                            SkeletonView(height: 14)
                            SkeletonView(height: 12)
                        }
                        .padding(TravSpacing.sm)
                        .background(TravColors.surfaceElevated.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
                    }
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
            }
        }
    }
}

struct ExperienceDetailSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TravSpacing.lg) {
                SkeletonView(height: TravLayout.heroExperienceHeight, cornerRadius: 0)
                HStack(spacing: TravSpacing.sm) {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonView(height: 52, cornerRadius: TravRadius.md)
                    }
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonView(height: 80, cornerRadius: TravRadius.md)
                        .padding(.horizontal, TravSpacing.screenHorizontal)
                }
            }
        }
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
        return shadow(color: spec.color, radius: spec.radius, y: spec.y)
    }
}
