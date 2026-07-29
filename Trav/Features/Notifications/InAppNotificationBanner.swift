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
        if notification.primaryDestinationIsProfile {
            router.openProfile(notification.actor.username)
            return
        }
        if let experienceID = notification.referenceID {
            router.openExperience(experienceID)
        } else {
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
        // Single drag gesture owns both swipe-up dismiss and clean tap-to-open so
        // vertical swipes never get claimed by a Button and open the notification.
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
        .contentShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
        .offset(y: min(0, dragOffset))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragOffset = min(0, value.translation.height)
                }
                .onEnded { value in
                    let vertical = value.translation.height
                    let horizontal = abs(value.translation.width)
                    let predictedUp = value.predictedEndTranslation.height
                    let shouldDismiss = vertical < -28 || predictedUp < -60

                    if shouldDismiss {
                        onDismiss()
                    } else if abs(vertical) < 12 && horizontal < 12 {
                        onTap()
                    }

                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        dragOffset = 0
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
        .accessibilityHint("Opens the notification. Swipe up to dismiss.")
    }
}
