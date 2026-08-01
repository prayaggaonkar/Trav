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
                            Color.white.opacity(0.15),
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

struct SkeletonExperienceCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkeletonView(height: TravLayout.feedCardImageHeight, cornerRadius: 0)
            
            VStack(alignment: .leading, spacing: 10) {
                SkeletonView(height: 18, cornerRadius: 4)
                    .frame(maxWidth: .infinity)
                SkeletonView(height: 14, cornerRadius: 4)
                    .frame(width: 180)
                SkeletonView(height: 12, cornerRadius: 4)
                    .frame(width: 120)
                
                HStack {
                    SkeletonView(height: 18, cornerRadius: 4).frame(width: 80)
                    Spacer()
                    SkeletonView(height: 28, cornerRadius: 14).frame(width: 90)
                }
                .padding(.top, 6)
            }
            .padding(TravSpacing.md)
        }
        .background(TravColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous))
    }
}

struct SkeletonPopupCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonView(height: 110, cornerRadius: TravRadius.md)
            SkeletonView(height: 14, cornerRadius: 4).frame(width: 140)
            SkeletonView(height: 12, cornerRadius: 4).frame(width: 100)
        }
        .padding(10)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                .fill(TravColors.surfaceElevated)
        )
    }
}

struct SkeletonUpcomingTripCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SkeletonView(height: 38, cornerRadius: 19).frame(width: 38)
                VStack(alignment: .leading, spacing: 4) {
                    SkeletonView(height: 14, cornerRadius: 4).frame(width: 120)
                    SkeletonView(height: 12, cornerRadius: 4).frame(width: 80)
                }
            }
            SkeletonView(height: 16, cornerRadius: 4).frame(width: 180)
            SkeletonView(height: 34, cornerRadius: TravRadius.sm)
        }
        .padding(14)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: TravRadius.lg, style: .continuous)
                .fill(TravColors.surfaceElevated)
        )
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
