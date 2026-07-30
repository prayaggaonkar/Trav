import SwiftUI

/// The Create screen, split in two.
///
/// **Rate** is where completions land: pick (or arrive with) an experience and
/// give it the rating that marks it complete. **Create** is the itinerary
/// builder. Both tabs stay mounted so switching never loses in-progress work.
struct CreateHubView: View {
    @Environment(AppRouter.self) private var router

    var isActive: Bool = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CreateTabPicker(selection: Binding(
                    get: { router.createTab },
                    set: { router.createTab = $0 }
                ))
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.top, TravSpacing.sm)
                .padding(.bottom, TravSpacing.xs)

                ZStack {
                    CreateRatingView(isActive: isActive && router.createTab == .rating)
                        .opacity(router.createTab == .rating ? 1 : 0)
                        .allowsHitTesting(router.createTab == .rating)

                    CreateExperienceView(isActive: isActive && router.createTab == .experience)
                        .opacity(router.createTab == .experience ? 1 : 0)
                        .allowsHitTesting(router.createTab == .experience)
                }
            }
            .travScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .animation(TravAnimation.enter, value: router.createTab)
        }
    }
}

private struct CreateTabPicker: View {
    @Binding var selection: CreateTab
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CreateTab.allCases) { tab in
                Button {
                    guard selection != tab else { return }
                    withAnimation(TravAnimation.enter) { selection = tab }
                } label: {
                    HStack(spacing: TravSpacing.xxs) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.title)
                            .font(TravTypography.labelMedium())
                    }
                    .foregroundStyle(selection == tab ? .white : TravColors.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TravSpacing.sm)
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(TravColors.accent)
                                .matchedGeometryEffect(id: "createTabIndicator", in: indicator)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab == .rating ? "Create rating" : "Create experience")
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(TravColors.surfaceElevated)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(TravColors.border.opacity(0.5), lineWidth: 1)
        }
    }
}
