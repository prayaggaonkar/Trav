import SwiftUI

struct ProfileView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    let username: String
    var showDismissButton: Bool = true

    @State private var isSigningOut = false

    private var isOwnProfile: Bool {
        session.currentUser?.username == username
    }

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
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.center)

                        Text("Profile coming in Phase 6")
                            .font(TravTypography.bodyMedium())
                            .foregroundStyle(TravColors.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .travAppear(delay: 0.06)

                    statsPlaceholder
                        .travAppear(delay: 0.12)

                    if isOwnProfile {
                        SecondaryButton("Sign Out", icon: "arrow.right.square") {
                            Task { await signOut() }
                        }
                        .travAppear(delay: 0.18)
                    }
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
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TravSpacing.xxs)
        .padding(.vertical, TravSpacing.md)
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
    }

    private func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }

        try? await environment.auth.signOut()
        session.currentUser = nil
        session.phase = .unauthenticated
    }
}
