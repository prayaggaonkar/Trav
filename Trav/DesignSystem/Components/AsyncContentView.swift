import SwiftUI

struct AsyncContentView<Data, Content: View, Loading: View, Empty: View, ErrorView: View>: View {
    enum Phase {
        case loading
        case empty
        case loaded(Data)
        case failed(Error)
    }

    let phase: Phase
    let retry: () -> Void
    @ViewBuilder let content: (Data) -> Content
    @ViewBuilder let loading: () -> Loading
    @ViewBuilder let empty: () -> Empty
    @ViewBuilder let error: (Error, @escaping () -> Void) -> ErrorView

    init(
        phase: Phase,
        retry: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (Data) -> Content,
        @ViewBuilder loading: @escaping () -> Loading = { ProgressView() },
        @ViewBuilder empty: @escaping () -> Empty = { Text("Nothing here yet.") },
        @ViewBuilder error: @escaping (Error, @escaping () -> Void) -> ErrorView
    ) {
        self.phase = phase
        self.retry = retry
        self.content = content
        self.loading = loading
        self.empty = empty
        self.error = error
    }

    var body: some View {
        switch phase {
        case .loading:
            loading()
        case .empty:
            empty()
        case let .loaded(data):
            content(data)
        case let .failed(err):
            error(err, retry)
        }
    }
}

struct SkeletonView: View {
    var height: CGFloat = 16
    var cornerRadius: CGFloat = TravRadius.sm

    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(TravColors.surfaceElevated)
            .frame(height: height)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.5),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: shimmerOffset * geo.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.5
                }
            }
    }
}

private struct DefaultAsyncErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(message)
                .font(TravTypography.bodyMedium())
                .multilineTextAlignment(.center)
            Button("Try Again", action: retry)
        }
        .padding()
    }
}

extension AsyncContentView where ErrorView == DefaultAsyncErrorView {
    init(
        phase: Phase,
        retry: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (Data) -> Content,
        @ViewBuilder loading: @escaping () -> Loading = { ProgressView() },
        @ViewBuilder empty: @escaping () -> Empty = { Text("Nothing here yet.") }
    ) {
        self.init(
            phase: phase,
            retry: retry,
            content: content,
            loading: loading,
            empty: empty,
            error: { err, retry in
                DefaultAsyncErrorView(message: err.localizedDescription, retry: retry)
            }
        )
    }
}
