import SwiftUI
import UIKit

/// Comments for an experience: paginated list, Instagram-style threaded replies, posting, deleting,
/// and reporting.
struct CommentsSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    let experienceID: UUID
    /// Called after a comment is added/removed so the parent can update counts.
    var onCountChange: ((Int) -> Void)? = nil
    /// Optional close handler when presented outside a system sheet (custom drawer).
    var onClose: (() -> Void)? = nil

    @State private var comments: [Comment] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var hasMore = false
    @State private var page = 0
    @State private var isLoadingMore = false

    @State private var draft = ""
    @State private var isPosting = false
    @State private var replyingTo: Comment? = nil
    @State private var expandedParentIDs: Set<UUID> = []
    @State private var reportingComment: Comment?
    @FocusState private var composerFocused: Bool

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                composer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.black)
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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

    private var topLevelComments: [Comment] {
        comments.filter { $0.parentID == nil }
    }

    private func replies(for parentID: UUID) -> [Comment] {
        comments
            .filter { $0.parentID == parentID }
            .sorted { $0.createdAt < $1.createdAt }
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
                    ForEach(topLevelComments) { comment in
                        topLevelCommentThread(comment)
                            .onAppear {
                                if comment.id == topLevelComments.last?.id, hasMore {
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

    @ViewBuilder
    private func topLevelCommentThread(_ comment: Comment) -> some View {
        let childReplies = replies(for: comment.id)
        let isExpanded = expandedParentIDs.contains(comment.id)

        VStack(alignment: .leading, spacing: 8) {
            CommentRow(
                comment: comment,
                isOwn: comment.author.id == session.currentUser?.id,
                onProfileTap: {
                    close()
                    router.openProfile(comment.author.username)
                },
                onReply: {
                    startReply(to: comment)
                },
                onDelete: {
                    Task { await delete(comment) }
                },
                onReport: {
                    reportingComment = comment
                }
            )

            if !childReplies.isEmpty {
                Button {
                    withAnimation(TravAnimation.quick) {
                        if isExpanded {
                            expandedParentIDs.remove(comment.id)
                        } else {
                            expandedParentIDs.insert(comment.id)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(TravColors.muted.opacity(0.35))
                            .frame(width: 24, height: 1)
                        Text(isExpanded ? "Hide replies" : "View \(childReplies.count) \(childReplies.count == 1 ? "reply" : "replies")")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(TravColors.muted)
                    }
                    .padding(.leading, 42)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(childReplies) { reply in
                            CommentRow(
                                comment: reply,
                                isReply: true,
                                isOwn: reply.author.id == session.currentUser?.id,
                                onProfileTap: {
                                    close()
                                    router.openProfile(reply.author.username)
                                },
                                onReply: {
                                    startReply(to: reply)
                                },
                                onDelete: {
                                    Task { await delete(reply) }
                                },
                                onReport: {
                                    reportingComment = reply
                                }
                            )
                        }
                    }
                    .padding(.leading, 42)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .overlay(TravColors.border.opacity(0.5))
                .padding(.top, TravSpacing.xs)

            if let target = replyingTo {
                HStack {
                    Text("Replying to ")
                        .font(TravTypography.caption())
                        .foregroundStyle(TravColors.muted)
                    + Text("@\(target.author.username)")
                        .font(TravTypography.caption())
                        .fontWeight(.semibold)
                        .foregroundStyle(TravColors.primary)

                    Spacer()

                    Button {
                        replyingTo = nil
                        let handle = "@\(target.author.username) "
                        if draft.hasPrefix(handle) {
                            draft = String(draft.dropFirst(handle.count))
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(TravColors.muted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, TravSpacing.md)
                .padding(.top, TravSpacing.sm)
                .padding(.bottom, 4)
            }

            HStack(spacing: TravSpacing.sm) {
                TextField(
                    replyingTo != nil ? "Reply to @\(replyingTo!.author.username)..." : "Add a comment...",
                    text: $draft,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .focused($composerFocused)
                .foregroundStyle(TravColors.primary)
                .padding(.horizontal, TravSpacing.md)
                .padding(.vertical, 10)
                .background(Color(white: 0.12))
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
            .padding(.top, TravSpacing.sm)
            .padding(.bottom, TravSpacing.sm)
        }
        .background(Color.black)
    }

    private var canPost: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= CommentLimits.maxLength
    }

    // MARK: - Actions

    private func startReply(to comment: Comment) {
        replyingTo = comment
        let handle = "@\(comment.author.username) "
        if !draft.contains(handle) {
            draft = handle + draft
        }
        composerFocused = true
    }

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
            close()
            router.presentAuth()
            return
        }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        isPosting = true
        defer { isPosting = false }

        let parentID = replyingTo?.parentID ?? replyingTo?.id
        do {
            let comment = try await environment.engagementRepo.addComment(
                experienceID: experienceID,
                authorID: user.id,
                body: body,
                parentID: parentID
            )
            comments.append(comment)
            if let parentID {
                expandedParentIDs.insert(parentID)
            }
            draft = ""
            replyingTo = nil
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
        comments.removeAll { $0.id == comment.id || $0.parentID == comment.id }
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
    var isReply: Bool = false
    let isOwn: Bool
    let onProfileTap: () -> Void
    let onReply: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void

    @State private var showOptions = false

    var body: some View {
        HStack(alignment: .top, spacing: TravSpacing.sm) {
            Button(action: onProfileTap) {
                AvatarView(url: comment.author.avatarURL, size: isReply ? 28 : 34)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(comment.author.displayName)
                    .font(.system(size: isReply ? 12 : 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(TravColors.primary)

                Text(comment.body)
                    .font(isReply ? TravTypography.caption() : TravTypography.bodyMedium())
                    .foregroundStyle(TravColors.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Text(Self.relativeTime(comment.createdAt))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(TravColors.muted)

                    Button("Reply", action: onReply)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(TravColors.muted)
                        .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)

            ZStack(alignment: .topTrailing) {
                Button {
                    withAnimation(TravAnimation.quick) {
                        showOptions.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TravColors.muted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Comment options")

                if showOptions {
                    VStack(alignment: .leading, spacing: 0) {
                        if isOwn {
                            Button {
                                showOptions = false
                                onDelete()
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(TravColors.error)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                showOptions = false
                                onReport()
                            } label: {
                                Label("Report", systemImage: "flag")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(TravColors.error)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 140)
                    .background(TravColors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous)
                            .stroke(TravColors.border.opacity(0.7), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                    .offset(y: 30)
                    .zIndex(10)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                }
            }
        }
    }

    static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}


/// Custom bottom drawer for comments — flush to the screen bottom (no system-sheet corner gap).
struct CommentsDrawer: View {
    let experienceID: UUID
    var onCountChange: ((Int) -> Void)? = nil
    var onDismiss: () -> Void

    private enum Detent {
        case medium
        case large

        func height(in screenHeight: CGFloat) -> CGFloat {
            switch self {
            case .medium: return screenHeight * 0.55
            case .large: return screenHeight * 0.92
            }
        }
    }

    @State private var detent: Detent = .medium
    @State private var dragTranslation: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let screenHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            let baseHeight = detent.height(in: screenHeight)
            let currentHeight = min(
                max(baseHeight - dragTranslation, screenHeight * 0.35),
                screenHeight * 0.95
            )

            ZStack(alignment: .bottom) {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissDrawer()
                    }

                VStack(spacing: 0) {
                    // Grabber — only this area resizes the drawer.
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 36, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .gesture(drawerDragGesture(screenHeight: screenHeight))

                    CommentsSheet(
                        experienceID: experienceID,
                        onCountChange: onCountChange,
                        onClose: onDismiss
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: currentHeight, alignment: .top)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: TravRadius.xl,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: TravRadius.xl,
                        style: .continuous
                    )
                )
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .ignoresSafeArea()
    }

    private func drawerDragGesture(screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                dragTranslation = value.translation.height
            }
            .onEnded { value in
                let predicted = value.predictedEndTranslation.height
                let total = value.translation.height + predicted * 0.15
                defer { dragTranslation = 0 }

                // Swipe down far enough dismisses.
                if total > 140 || (detent == .medium && total > 100) {
                    dismissDrawer()
                    return
                }

                // Snap to medium / large from drag direction.
                if total < -60 {
                    withAnimation(TravAnimation.quick) { detent = .large }
                } else if total > 60 {
                    withAnimation(TravAnimation.quick) { detent = .medium }
                } else {
                    withAnimation(TravAnimation.quick) { dragTranslation = 0 }
                }
            }
    }

    private func dismissDrawer() {
        withAnimation(TravAnimation.quick) {
            onDismiss()
        }
    }
}
