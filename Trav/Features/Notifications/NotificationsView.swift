import SwiftUI

struct NotificationsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(NotificationStore.self) private var notificationStore
    @Environment(\.dismiss) private var dismiss

    @State private var items: [AppNotification] = []
    @State private var page = 0
    @State private var hasMore = true
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var error: Error?
    @State private var didMarkAllRead = false

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
                                handleTap(notification)
                            } label: {
                                NotificationRow(notification: notification)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(
                                notification.isRead
                                    ? TravColors.surface
                                    : TravColors.accent.opacity(0.08)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await reload(reset: true)
                await markAllReadIfNeeded()
            }
        }
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
            items = reset ? result.items : items + result.items
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

    private func markAllReadIfNeeded() async {
        guard !didMarkAllRead, let userID = session.currentUser?.id else { return }
        didMarkAllRead = true
        do {
            try await environment.notifications.markAllRead(userID: userID)
            notificationStore.markAllReadLocally()
            for index in items.indices {
                items[index].isRead = true
            }
        } catch {
            print("NotificationsView.markAllRead failed: \(error)")
        }
    }

    private func handleTap(_ notification: AppNotification) {
        Task {
            try? await environment.notifications.markRead(ids: [notification.id])
            if let index = items.firstIndex(where: { $0.id == notification.id }) {
                items[index].isRead = true
            }
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

    var body: some View {
        HStack(alignment: .top, spacing: TravSpacing.md) {
            AvatarView(url: notification.actor.avatarURL, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(notification.message)
                    .font(.system(size: 15, weight: notification.isRead ? .regular : .semibold, design: .rounded))
                    .foregroundStyle(TravColors.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(Self.relativeTime(notification.createdAt))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(TravColors.muted)
            }

            Spacer(minLength: 0)

            if !notification.isRead {
                Circle()
                    .fill(TravColors.accent)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
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
