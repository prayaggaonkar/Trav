import SwiftUI

/// Identifiable container for full screen image viewing.
struct ImagePreviewItem: Identifiable, Sendable {
    let id = UUID()
    let urls: [URL]
    let initialIndex: Int
}

/// Full screen interactive image viewer with swipeable pagination, pinch-to-zoom,
/// double tap zoom, and swipe-down to dismiss.
struct FullScreenImageViewer: View {
    let urls: [URL]
    @State private var selectedIndex: Int
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero

    init(urls: [URL], initialIndex: Int = 0, onDismiss: @escaping () -> Void) {
        self.urls = urls
        self._selectedIndex = State(initialValue: initialIndex)
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            if urls.count > 1 {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        zoomableImage(url: url)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else if let firstURL = urls.first {
                zoomableImage(url: firstURL)
            } else {
                ContentUnavailableView(
                    "Image Unavailable",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("Could not load image file.")
                )
                .foregroundStyle(.white)
            }

            // Top control bar
            VStack {
                HStack {
                    if urls.count > 1 {
                        Text("\(selectedIndex + 1) of \(urls.count)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.18)))
                    }

                    Spacer()

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30, weight: .bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.black.opacity(0.5))
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close full screen image viewer")
                }
                .padding(.horizontal, TravSpacing.screenHorizontal)
                .padding(.top, TravSpacing.md)

                Spacer()
            }
        }
        .offset(y: dragOffset.height)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    if scale <= 1.0 {
                        dragOffset = gesture.translation
                    }
                }
                .onEnded { gesture in
                    if scale <= 1.0 && abs(gesture.translation.height) > 90 {
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
    }

    private var backgroundOpacity: Double {
        let maxDrag: CGFloat = 280
        let dragProgress = min(abs(dragOffset.height) / maxDrag, 1.0)
        return max(0.2, 1.0 - Double(dragProgress) * 0.8)
    }

    @ViewBuilder
    private func zoomableImage(url: URL) -> some View {
        GeometryReader { geo in
            ZStack {
                RemoteImage(
                    url: url,
                    height: geo.size.height,
                    cornerRadius: 0,
                    maxPixelSize: 2048
                )
                .scaledToFit()
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale = max(1.0, min(scale * delta, 4.0))
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            if scale < 1.0 {
                                withAnimation(.spring()) { scale = 1.0 }
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        scale = scale > 1.0 ? 1.0 : 2.5
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if scale == 1.0 {
                onDismiss()
            }
        }
    }
}
