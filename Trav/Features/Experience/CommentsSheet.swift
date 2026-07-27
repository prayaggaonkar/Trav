import SwiftUI

/// Comments for an experience: paginated list, posting, deleting your own,
/// and reporting others'.
struct CommentsSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    let experienceID: UUID
    /// Called after a comment is added/removed so the parent can update counts.
    var onCountChange: ((Int) -> Void)? = nil

    @State private var comments: [Comment] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var hasMore = false
    @State private var page = 0
    @State private var isLoadingMore = false

    @State private var draft = ""
    @State private var isPosting = false
    @State private var reportingComment: Comment?
    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content

                composer
            }
            .travScreenBackground()
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(TravColors.accent)
                }
            }
        }
        .task { await load() }
        .confirmationDialog(
            "Report Comment",
            isPresented: Binding(
                get: { reportingComment != nil },
                set: { if !$0 { reportingComment = nil } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(ReportReason.allCases) { reason in
                Button(reason.displayName, role: reason == .other ? nil : .destructive) {
                    if let comment = reportingComment {
                        Task { await report(comment, reason: reason) }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            Spacer()
            ProgressView()
                .tint(TravColors.accent)
            Spacer()
        } else if let loadError {
            Spacer()
            ErrorStateView(message: loadError) {
                Task { await load() }
            }
            Spacer()
        } else if comments.isEmpty {
            Spacer()
            EmptyStateView(
                icon: "bubble.left.and.bubble.right",
                title: "No Comments Yet",
                description: "Be the first to share your thoughts about this experience."
            )
            Spacer()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: TravSpacing.md) {
                    ForEach(comments) { comment in
                        CommentRow(
                            comment: comment,
                            isOwn: comment.author.id == session.currentUser?.id,
                            onProfileTap: {
                                dismiss()
                                router.openProfile(comment.author.username)
                            },
                            onDelete: {
                                Task { await delete(comment) }
                            },
                            onReport: {
                                reportingComment = comment
                            }
                        )
                        .onAppear {
                            if comment.id == comments.last?.id, hasMore {
                                Task { await loadMore() }
                            }
                        }
                    }

                    if isLoadingMore {
                        ProgressView()
                            .tint(TravColors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, TravSpacing.sm)
                    }
                }
                .padding(TravSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var composer: some View {
        HStack(spacing: TravSpacing.sm) {
            TextField("Add a comment...", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($composerFocused)
                .padding(.horizontal, TravSpacing.md)
                .padding(.vertical, 10)
                .background(TravColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
                .tint(TravColors.accent)

            Button {
                Task { await post() }
            } label: {
                if isPosting {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 36, height: 36)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canPost ? TravColors.accent : TravColors.muted)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canPost || isPosting)
            .accessibilityLabel("Post comment")
        }
        .padding(.horizontal, TravSpacing.md)
        .padding(.vertical, TravSpacing.sm)
        .background(.ultraThinMaterial)
    }

    private var canPost: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= CommentLimits.maxLength
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            let result = try await environment.engagementRepo.fetchComments(experienceID: experienceID, page: 0)
            comments = result.items
            page = 0
            hasMore = result.hasMore
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await environment.engagementRepo.fetchComments(experienceID: experienceID, page: page + 1)
            page += 1
            comments.append(contentsOf: result.items.filter { item in
                !comments.contains(where: { $0.id == item.id })
            })
            hasMore = result.hasMore
        } catch {
            hasMore = false
        }
    }

    private func post() async {
        guard let user = session.currentUser else {
            dismiss()
            router.presentAuth()
            return
        }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        isPosting = true
        defer { isPosting = false }
        do {
            let comment = try await environment.engagementRepo.addComment(
                experienceID: experienceID,
                authorID: user.id,
                body: body,
                parentID: nil
            )
            comments.insert(comment, at: 0)
            draft = ""
            composerFocused = false
            onCountChange?(comments.count)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            loadError = nil
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func delete(_ comment: Comment) async {
        let backup = comments
        comments.removeAll { $0.id == comment.id }
        onCountChange?(comments.count)
        do {
            try await environment.engagementRepo.deleteComment(id: comment.id)
        } catch {
            comments = backup
            onCountChange?(comments.count)
        }
    }

    private func report(_ comment: Comment, reason: ReportReason) async {
        guard let user = session.currentUser else {
            router.presentAuth()
            return
        }
        try? await environment.engagementRepo.report(
            target: .comment(comment.id),
            reporterID: user.id,
            reason: reason,
            details: nil
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

private struct CommentRow: View {
    let comment: Comment
    let isOwn: Bool
    let onProfileTap: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: TravSpacing.sm) {
            Button(action: onProfileTap) {
                AvatarView(url: comment.author.avatarURL, size: 34)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.author.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(TravColors.primary)

                    Text(Self.relativeTime(comment.createdAt))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(TravColors.muted)
                }

                Text(comment.body)
                    .font(TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Menu {
                if isOwn {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } else {
                    Button(role: .destructive, action: onReport) {
                        Label("Report", systemImage: "flag")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TravColors.muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Comment options")
        }
    }

    static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
