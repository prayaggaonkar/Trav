import SwiftUI

/// Hosts the Instagram-style top notification banner above the whole app.
struct InAppNotificationBannerHost: View {
    @Environment(NotificationStore.self) private var notificationStore
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if let toast = notificationStore.currentToast {
                InAppNotificationBanner(
                    toast: toast,
                    onTap: {
                        open(toast.notification)
                    },
                    onDismiss: {
                        notificationStore.dismissCurrentToast()
                    }
                )
                .padding(.horizontal, TravSpacing.md)
                .padding(.top, 8)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: notificationStore.currentToast?.id)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func open(_ notification: AppNotification) {
        notificationStore.dismissCurrentToast()
        switch notification.type {
        case .follow:
            router.openProfile(notification.actor.username)
        case .save, .newExperience, .like, .comment:
            if let experienceID = notification.referenceID {
                router.openExperience(experienceID)
            } else {
                router.openProfile(notification.actor.username)
            }
        case .watchlist:
            router.openProfile(notification.actor.username)
        }
    }
}

private struct InAppNotificationBanner: View {
    let toast: InAppToast
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: TravSpacing.sm) {
                AvatarView(url: toast.notification.actor.avatarURL, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.notification.message)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(TravColors.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    Text("Just now")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(TravColors.muted)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, TravSpacing.md)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                    .fill(TravColors.surface)
                    .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                    .strokeBorder(TravColors.border.opacity(0.6), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .offset(y: min(0, dragOffset))
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    dragOffset = min(0, value.translation.height)
                }
                .onEnded { value in
                    let shouldDismiss = value.translation.height < -36
                        || value.predictedEndTranslation.height < -80
                    if shouldDismiss {
                        onDismiss()
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        dragOffset = 0
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the notification. Swipe up to dismiss.")
    }
}
