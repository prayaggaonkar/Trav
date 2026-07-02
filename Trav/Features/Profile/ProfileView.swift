import SwiftUI

struct ProfileView: View {
    @Environment(AppRouter.self) private var router

    let username: String
    var showDismissButton: Bool = true

    var body: some View {
        NavigationStack {
            VStack(spacing: TravSpacing.lg) {
                AvatarView(url: nil, size: 80)
                Text("@\(username)")
                    .font(TravTypography.titleLarge())
                Text("Profile coming in Phase 6")
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TravColors.surface)
            .toolbar {
                if showDismissButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { router.dismiss() } label: {
                            Image(systemName: "xmark")
                                .padding(10)
                                .background(TravColors.surfaceElevated)
                                .clipShape(Circle())
                        }
                    }
                }
            }
        }
    }
}
