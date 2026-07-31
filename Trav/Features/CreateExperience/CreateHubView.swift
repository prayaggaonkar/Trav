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
                .padding(.bottom, 12)

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
    @Environment(AppearanceStore.self) private var appearance
    @Binding var selection: CreateTab

    var body: some View {
        HStack(spacing: 3) {
            ForEach(CreateTab.allCases) { tab in
                Button {
                    guard selection != tab else { return }
                    withAnimation(TravAnimation.quick) { selection = tab }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(tab.title)
                        .font(.system(size: 13, weight: selection == tab ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(selection == tab ? TravColors.primary : TravColors.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if selection == tab {
                                    RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                                        .fill(TravColors.surfaceElevated)
                                        .shadow(color: Color.black.opacity(0.08), radius: 3, y: 1)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab == .rating ? "Create rating" : "Create experience")
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                .fill(appearance.isLightMode ? Color(red: 0.94, green: 0.94, blue: 0.96) : Color.white.opacity(0.08))
        )
    }
}
