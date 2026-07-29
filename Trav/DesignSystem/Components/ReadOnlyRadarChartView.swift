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

    @State private var isAnimated: Bool = false

    init(
        rating: RadarRating,
        axes: [RadarAxis] = RadarAxis.defaultAxes,
        minScore: Double = 1.0,
        maxScore: Double = 10.0,
        fillColor: Color = TravColors.accent,
        strokeColor: Color = TravColors.accent,
        showsHeader: Bool = true
    ) {
        self.rating = rating
        self.axes = axes
        self.minScore = minScore
        self.maxScore = maxScore
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.showsHeader = showsHeader
    }

    var body: some View {
        VStack(spacing: TravSpacing.sm) {
            if showsHeader {
                headerView
            }

            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let center = CGPoint(x: geometry.size.width / 2.0, y: geometry.size.height / 2.0)
                let radius = (size / 2.0) - 36.0 // Leave padding for text labels

                radarPlotView(size: size, center: center, radius: radius)
            }
            .frame(height: 250)
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) {
                    isAnimated = true
                }
            }

            // Summary breakdown bar below chart
            scoreSummaryGrid
        }
    }

    @ViewBuilder
    private func backgroundGridRings(radius: CGFloat) -> some View {
        ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { level in
            let w = radius * 2 * CGFloat(level)
            let h = radius * 2 * CGFloat(level)
            let lw: CGFloat = level == 1.0 ? 1.5 : 1.0
            RadarChartPolygonShape(values: Array(repeating: level, count: axes.count))
                .stroke(TravColors.border.opacity(0.4), lineWidth: lw)
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
                isAnimated: isAnimated,
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
        let normalizedValues = axes.map { axis in
            isAnimated ? rating.normalizedScore(for: axis.id, min: minScore, max: maxScore) : 0.0
        }

        ZStack {
            backgroundGridRings(radius: radius)
            axisSpokes(center: center, radius: radius)
            activePolygon(radius: radius, normalizedValues: normalizedValues)
            vertexDots(center: center, radius: radius)
            perimeterLabels(center: center, radius: radius)
        }
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
    let isAnimated: Bool
    let axesCount: Int

    private var isEnabled: Bool {
        rating.isEnabled(axis.id)
    }

    private var val: Double {
        isAnimated ? rating.normalizedScore(for: axis.id, min: minScore, max: maxScore) : 0.0
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

    private var isEnabled: Bool {
        rating.isEnabled(axis.id)
    }

    private var score: Double {
        rating.score(for: axis.id, default: minScore)
    }

    private var angle: Double {
        -.pi / 2.0 + Double(index) * (2.0 * .pi / Double(axesCount))
    }

    private var labelPoint: CGPoint {
        let labelRadius = radius + 24.0
        return CGPoint(
            x: center.x + CGFloat(labelRadius * cos(angle)),
            y: center.y + CGFloat(labelRadius * sin(angle))
        )
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(axis.name)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isEnabled ? TravColors.primary : Color.gray)

            Text(isEnabled ? String(format: "%.1f", score) : "OFF")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isEnabled ? TravColors.accent : Color.gray.opacity(0.8))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isEnabled ? TravColors.surface.opacity(0.95) : Color.gray.opacity(0.12))
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
        .position(labelPoint)
    }
}

#Preview {
    ReadOnlyRadarChartView(rating: .defaultRating)
        .padding()
        .background(TravColors.surface)
}
