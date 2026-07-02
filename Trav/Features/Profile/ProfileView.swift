import SwiftUI

struct ProfileView: View {
    @Environment(AppRouter.self) private var router

    let username: String
    var showDismissButton: Bool = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TravSpacing.lg) {
                    AvatarView(url: nil, size: 88)
                        .travAppear()

                    VStack(spacing: TravSpacing.xs) {
                        Text("@\(username)")
                            .font(TravTypography.titleLarge())
                            .foregroundStyle(TravColors.primary)

                        Text("Profile coming in Phase 6")
                            .font(TravTypography.bodyMedium())
                            .foregroundStyle(TravColors.muted)
                    }
                    .travAppear(delay: 0.06)

                    statsPlaceholder
                        .travAppear(delay: 0.12)
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.top, TravSpacing.xl)
                .padding(.bottom, TravSpacing.xxl)
            }
            .travScreenBackground()
            .toolbar {
                if showDismissButton {
                    ToolbarItem(placement: .topBarLeading) {
                        DismissButton { router.dismiss() }
                    }
                }
            }
        }
    }

    private var statsPlaceholder: some View {
        HStack(spacing: TravSpacing.sm) {
            profileStat(value: "—", label: "Experiences")
            profileStat(value: "—", label: "Completed")
            profileStat(value: "—", label: "Saved")
        }
    }

    private func profileStat(value: String, label: String) -> some View {
        VStack(spacing: TravSpacing.xxs) {
            Text(value)
                .font(TravTypography.titleMedium())
                .foregroundStyle(TravColors.primary)
            Text(label)
                .font(TravTypography.caption())
                .foregroundStyle(TravColors.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TravSpacing.md)
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
    }
}
