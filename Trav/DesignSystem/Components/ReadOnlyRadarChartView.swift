import SwiftUI

/// A read-only SwiftUI view that renders a filled radar (spider) chart polygon from a deserialized `RadarRating` / Dictionary.
/// Used on the Experience Details / View page.
struct ReadOnlyRadarChartView: View {
    let rating: RadarRating
    let axes: [RadarAxis]
    let maxScore: Double
    let minScore: Double
    let fillColor: Color
    let strokeColor: Color
    var showsHeader: Bool
    var showsScoreSummary: Bool
    /// Stronger concentric grid — used on individual review radar expansions.
    var emphasizesGrid: Bool

    @State private var isVisible: Bool = false

    init(
        rating: RadarRating,
        axes: [RadarAxis] = RadarAxis.defaultAxes,
        minScore: Double = 1.0,
        maxScore: Double = 10.0,
        fillColor: Color = TravColors.accent,
        strokeColor: Color = TravColors.accent,
        showsHeader: Bool = true,
        showsScoreSummary: Bool = true,
        emphasizesGrid: Bool = false
    ) {
        self.rating = rating
        self.axes = axes
        self.minScore = minScore
        self.maxScore = maxScore
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.showsHeader = showsHeader
        self.showsScoreSummary = showsScoreSummary
        self.emphasizesGrid = emphasizesGrid
    }

    var body: some View {
        VStack(spacing: TravSpacing.sm) {
            if showsHeader {
                headerView
            }

            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let center = CGPoint(x: geometry.size.width / 2.0, y: geometry.size.height / 2.0)
                // Leave room for boxed labels placed by closest-edge gap, not center distance.
                let radius = (size / 2.0) - 58.0

                radarPlotView(size: size, center: center, radius: radius)
            }
            .frame(height: 268)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    isVisible = true
                }
            }

            if showsScoreSummary {
                scoreSummaryGrid
            }
        }
    }

    @ViewBuilder
    private func backgroundGridRings(radius: CGFloat) -> some View {
        ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { level in
            let w = radius * 2 * CGFloat(level)
            let h = radius * 2 * CGFloat(level)
            let isOuter = level == 1.0
            let innerOpacity = emphasizesGrid ? 0.72 : 0.35
            let innerWidth: CGFloat = emphasizesGrid ? 1.35 : 1.0
            RadarChartPolygonShape(values: Array(repeating: level, count: axes.count))
                .stroke(
                    isOuter ? TravColors.border.opacity(0.85) : TravColors.border.opacity(innerOpacity),
                    style: StrokeStyle(
                        lineWidth: isOuter ? 2.5 : innerWidth,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: isOuter ? [7, 5] : []
                    )
                )
                .frame(width: w, height: h)
        }
    }

    @ViewBuilder
    private func axisSpokes(center: CGPoint, radius: CGFloat) -> some View {
        ForEach(0..<axes.count, id: \.self) { i in
            ReadOnlyAxisSpokeView(
                index: i,
                axis: axes[i],
                center: center,
                radius: radius,
                rating: rating,
                axesCount: axes.count
            )
        }
    }

    @ViewBuilder
    private func activePolygon(radius: CGFloat, normalizedValues: [Double]) -> some View {
        ZStack {
            RadarChartPolygonShape(values: normalizedValues)
                .fill(
                    LinearGradient(
                        colors: [fillColor.opacity(0.45), fillColor.opacity(0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: radius * 2, height: radius * 2)

            RadarChartPolygonShape(values: normalizedValues)
                .stroke(strokeColor, lineWidth: 2.5)
                .frame(width: radius * 2, height: radius * 2)
        }
    }

    @ViewBuilder
    private func vertexDots(center: CGPoint, radius: CGFloat) -> some View {
        ForEach(0..<axes.count, id: \.self) { i in
            ReadOnlyVertexDotView(
                index: i,
                axis: axes[i],
                center: center,
                radius: radius,
                rating: rating,
                minScore: minScore,
                maxScore: maxScore,
                activeColor: strokeColor,
                axesCount: axes.count
            )
        }
    }

    @ViewBuilder
    private func perimeterLabels(center: CGPoint, radius: CGFloat) -> some View {
        ForEach(0..<axes.count, id: \.self) { i in
            ReadOnlyPerimeterLabelView(
                index: i,
                axis: axes[i],
                center: center,
                radius: radius,
                rating: rating,
                minScore: minScore,
                axesCount: axes.count
            )
        }
    }

    @ViewBuilder
    private func radarPlotView(size: CGFloat, center: CGPoint, radius: CGFloat) -> some View {
        // Always draw at final scores so vertices never travel past / below rest positions.
        let normalizedValues = axes.map { axis in
            rating.normalizedScore(for: axis.id, min: minScore, max: maxScore)
        }

        ZStack {
            backgroundGridRings(radius: radius)
            axisSpokes(center: center, radius: radius)
            activePolygon(radius: radius, normalizedValues: normalizedValues)
            vertexDots(center: center, radius: radius)
            perimeterLabels(center: center, radius: radius)
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.96, anchor: .center)
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.0))

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.1f", rating.overallScore))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(TravColors.primary)

                    Text("/ 10.0")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(TravColors.muted)
                }
            }
        }
    }

    private var scoreSummaryGrid: some View {
        HStack(spacing: 8) {
            ForEach(axes) { axis in
                scorePill(for: axis)
            }
        }
    }

    private func scorePill(for axis: RadarAxis) -> some View {
        let isEnabled = rating.isEnabled(axis.id)
        let score = rating.score(for: axis.id, default: minScore)

        return VStack(spacing: 2) {
            Text(axis.name.prefix(4).uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isEnabled ? TravColors.muted : Color.gray.opacity(0.6))

            Text(isEnabled ? String(format: "%.1f", score) : "OFF")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isEnabled ? TravColors.primary : Color.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(isEnabled ? TravColors.surfaceElevated : Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.sm))
    }
}

// MARK: - Helper Subviews for Compiler Optimization

struct ReadOnlyAxisSpokeView: View {
    let index: Int
    let axis: RadarAxis
    let center: CGPoint
    let radius: CGFloat
    let rating: RadarRating
    let axesCount: Int

    private var isEnabled: Bool {
        rating.isEnabled(axis.id)
    }

    private var angle: Double {
        -.pi / 2.0 + Double(index) * (2.0 * .pi / Double(axesCount))
    }

    private var endPoint: CGPoint {
        CGPoint(
            x: center.x + CGFloat(radius * cos(angle)),
            y: center.y + CGFloat(radius * sin(angle))
        )
    }

    var body: some View {
        Path { p in
            p.move(to: center)
            p.addLine(to: endPoint)
        }
        .stroke(isEnabled ? TravColors.border.opacity(0.3) : Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }
}

struct ReadOnlyVertexDotView: View {
    let index: Int
    let axis: RadarAxis
    let center: CGPoint
    let radius: CGFloat
    let rating: RadarRating
    let minScore: Double
    let maxScore: Double
    let activeColor: Color
    let axesCount: Int

    private var isEnabled: Bool {
        rating.isEnabled(axis.id)
    }

    private var val: Double {
        rating.normalizedScore(for: axis.id, min: minScore, max: maxScore)
    }

    private var angle: Double {
        -.pi / 2.0 + Double(index) * (2.0 * .pi / Double(axesCount))
    }

    private var point: CGPoint {
        CGPoint(
            x: center.x + CGFloat(radius * val * cos(angle)),
            y: center.y + CGFloat(radius * val * sin(angle))
        )
    }

    var body: some View {
        Circle()
            .fill(isEnabled ? activeColor : Color.gray)
            .frame(width: isEnabled ? 8 : 6, height: isEnabled ? 8 : 6)
            .shadow(color: isEnabled ? activeColor.opacity(0.5) : Color.clear, radius: 3)
            .position(point)
    }
}

struct ReadOnlyPerimeterLabelView: View {
    let index: Int
    let axis: RadarAxis
    let center: CGPoint
    let radius: CGFloat
    let rating: RadarRating
    let minScore: Double
    let axesCount: Int

    /// Visual gap between the pentagon tip and the nearest point on the label box.
    private let tipToBoxGap: CGFloat = 12

    private var isEnabled: Bool {
        rating.isEnabled(axis.id)
    }

    private var score: Double {
        rating.score(for: axis.id, default: minScore)
    }

    private var angle: Double {
        -.pi / 2.0 + Double(index) * (2.0 * .pi / Double(axesCount))
    }

    /// Approximate label box size so we can place by closest-edge distance, not center.
    private var estimatedLabelSize: CGSize {
        let nameChars = CGFloat(axis.name.count)
        let nameWidth = nameChars * 6.2 + 4
        let scoreWidth: CGFloat = 34
        let width = max(nameWidth, scoreWidth) + 16
        let height: CGFloat = 38
        return CGSize(width: width, height: height)
    }

    /// Distance from box center to its nearest edge along the inward radial direction.
    private var radialHalfExtent: CGFloat {
        let halfW = estimatedLabelSize.width / 2
        let halfH = estimatedLabelSize.height / 2
        return halfW * abs(CGFloat(cos(angle))) + halfH * abs(CGFloat(sin(angle)))
    }

    private var labelPoint: CGPoint {
        // tip + gap + distance to nearest box edge (along the radial axis)
        let distance = radius + tipToBoxGap + radialHalfExtent
        return CGPoint(
            x: center.x + CGFloat(distance * cos(angle)),
            y: center.y + CGFloat(distance * sin(angle))
        )
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(axis.name)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(isEnabled ? TravColors.primary : Color.gray)

            Text(isEnabled ? String(format: "%.1f", score) : "OFF")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isEnabled ? TravColors.accent : Color.gray.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isEnabled ? TravColors.surfaceElevated.opacity(0.95) : Color.gray.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isEnabled ? TravColors.accent.opacity(0.75) : Color.gray.opacity(0.35),
                    lineWidth: 1.25
                )
        )
        .fixedSize()
        .position(labelPoint)
    }
}

#Preview {
    ReadOnlyRadarChartView(rating: .defaultRating)
        .padding()
        .background(TravColors.surface)
}
