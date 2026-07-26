import SwiftUI

struct NotificationsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(NotificationStore.self) private var notificationStore

    @State private var items: [AppNotification] = []
    @State private var page = 0
    @State private var hasMore = true
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView()
                        .tint(TravColors.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, items.isEmpty {
                    ErrorStateView(message: error.localizedDescription) {
                        Task { await reload(reset: true) }
                    }
                } else if items.isEmpty {
                    EmptyStateView(
                        icon: "bell",
                        title: "No notifications yet",
                        description: "When someone follows you, saves your experience, or posts something new, it’ll show up here."
                    )
                } else {
                    List {
                        ForEach(items) { notification in
                            Button {
                                Task { await openNotification(notification) }
                            } label: {
                                NotificationRow(
                                    notification: notification,
                                    showsUnreadDot: notificationStore.showsUnreadDot(for: notification.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(
                                notificationStore.showsUnreadDot(for: notification.id)
                                    ? TravColors.accent.opacity(0.08)
                                    : TravColors.surface
                            )
                            .listRowSeparatorTint(TravColors.border.opacity(0.5))
                            .onAppear {
                                if notification.id == items.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                        }

                        if isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .listRowBackground(TravColors.surface)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .travScreenBackground()
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                notificationsBackToolbar
            }
            .navigationBarBackButtonHidden(true)
            .task {
                notificationStore.beginInboxSession()
                await reload(reset: true)
            }
        }
    }

    @ToolbarContentBuilder
    private var notificationsBackToolbar: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) {
                notificationsBackButton
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) {
                notificationsBackButton
            }
        }
    }

    private var notificationsBackButton: some View {
        Button {
            Task { await dismissInbox() }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TravColors.primary)
                .frame(width: TravLayout.minTouchTarget, height: TravLayout.minTouchTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private func reload(reset: Bool) async {
        guard let userID = session.currentUser?.id else {
            isLoading = false
            items = []
            return
        }

        if reset {
            isLoading = items.isEmpty
            page = 0
            hasMore = true
        }
        defer { isLoading = false }

        do {
            let result = try await environment.notifications.fetchNotifications(userID: userID, page: page)
            if reset {
                items = result.items
            } else {
                items += result.items
            }
            notificationStore.captureUnreadSnapshot(from: result.items)
            hasMore = result.hasMore
            error = nil
        } catch {
            self.error = error
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, session.currentUser != nil else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        page += 1
        await reload(reset: false)
    }

    private func dismissInbox() async {
        if let userID = session.currentUser?.id {
            await notificationStore.endInboxSessionIfNeeded(userID: userID, using: environment)
        }
        router.dismiss()
    }

    private func openNotification(_ notification: AppNotification) async {
        if let userID = session.currentUser?.id {
            await notificationStore.endInboxSessionIfNeeded(userID: userID, using: environment)
        }

        switch notification.type {
        case .follow:
            router.openProfile(notification.actor.username)
        case .save, .newExperience:
            if let experienceID = notification.referenceID {
                router.openExperience(experienceID)
            } else {
                router.openProfile(notification.actor.username)
            }
        }
    }
}

private struct NotificationRow: View {
    let notification: AppNotification
    let showsUnreadDot: Bool

    var body: some View {
        HStack(alignment: .top, spacing: TravSpacing.md) {
            AvatarView(url: notification.actor.avatarURL, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(notification.message)
                    .font(.system(size: 15, weight: showsUnreadDot ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(TravColors.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(Self.relativeTime(notification.createdAt))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(TravColors.muted)
            }

            Spacer(minLength: 0)

            if showsUnreadDot {
                Circle()
                    .fill(TravColors.accent)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                    .accessibilityLabel("Unread")
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static func relativeTime(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
