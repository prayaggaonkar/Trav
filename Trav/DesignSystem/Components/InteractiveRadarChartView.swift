import SwiftUI
import UIKit

/// An interactive SwiftUI Radar Chart that matches the experience-page read-only
/// pentagon look, while letting users drag vertices to set scores (1.0–10.0) and
/// tap axis labels to toggle categories on/off.
struct InteractiveRadarChartView: View {
    @Binding var rating: RadarRating
    let axes: [RadarAxis]
    let minScore: Double
    let maxScore: Double

    @State private var activeAxisIndex: Int? = nil
    @State private var activeScoreValue: Double? = nil
    @State private var hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    init(
        rating: Binding<RadarRating>,
        axes: [RadarAxis] = RadarAxis.defaultAxes,
        minScore: Double = 1.0,
        maxScore: Double = 10.0
    ) {
        self._rating = rating
        self.axes = axes
        self.minScore = minScore
        self.maxScore = maxScore
    }

    var body: some View {
        VStack(spacing: TravSpacing.sm) {
            headerView

            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let center = CGPoint(x: geometry.size.width / 2.0, y: geometry.size.height / 2.0)
                // Match experience chart inset so boxed labels clear the outer ring.
                let radius = (size / 2.0) - 58.0

                radarPlotView(size: size, center: center, radius: radius)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                handleDrag(location: value.location, center: center, radius: radius)
                            }
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    activeAxisIndex = nil
                                    activeScoreValue = nil
                                }
                            }
                    )
            }
            .frame(height: 280)
            .padding(.vertical, TravSpacing.xs)
        }
    }

    @ViewBuilder
    private func backgroundGridRings(radius: CGFloat) -> some View {
        ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { level in
            let w = radius * 2 * CGFloat(level)
            let h = radius * 2 * CGFloat(level)
            let isOuter = level == 1.0
            RadarChartPolygonShape(values: Array(repeating: level, count: axes.count))
                .stroke(
                    isOuter ? TravColors.border.opacity(0.85) : TravColors.border.opacity(0.72),
                    style: StrokeStyle(
                        lineWidth: isOuter ? 2.5 : 1.35,
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
            InteractiveAxisSpokeView(
                index: i,
                axis: axes[i],
                center: center,
                radius: radius,
                rating: rating,
                axesCount: axes.count,
                isActive: activeAxisIndex == i
            )
        }
    }

    @ViewBuilder
    private func ratingPolygon(radius: CGFloat, normalizedValues: [Double]) -> some View {
        ZStack {
            RadarChartPolygonShape(values: normalizedValues)
                .fill(
                    LinearGradient(
                        colors: [TravColors.accent.opacity(0.45), TravColors.accent.opacity(0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: radius * 2, height: radius * 2)

            RadarChartPolygonShape(values: normalizedValues)
                .stroke(TravColors.accent, lineWidth: 2.5)
                .frame(width: radius * 2, height: radius * 2)
        }
    }

    @ViewBuilder
    private func draggableKnobsAndLabels(center: CGPoint, radius: CGFloat) -> some View {
        ForEach(0..<axes.count, id: \.self) { i in
            InteractiveKnobAndLabelView(
                index: i,
                axis: axes[i],
                center: center,
                radius: radius,
                rating: $rating,
                minScore: minScore,
                maxScore: maxScore,
                activeAxisIndex: activeAxisIndex,
                axesCount: axes.count,
                hapticFeedback: hapticFeedback
            )
        }
    }

    @ViewBuilder
    private func radarPlotView(size: CGFloat, center: CGPoint, radius: CGFloat) -> some View {
        let normalizedValues = axes.map { axis in
            rating.normalizedScore(for: axis.id, min: minScore, max: maxScore)
        }

        ZStack {
            backgroundGridRings(radius: radius)
            axisSpokes(center: center, radius: radius)
            ratingPolygon(radius: radius, normalizedValues: normalizedValues)
            draggableKnobsAndLabels(center: center, radius: radius)
        }
    }

    // MARK: - Radial Touch Projection & Live Score Update Logic

    /// Projects drag position onto nearest axis vector and updates continuous decimal score (e.g. 7.5, 8.2).
    private func handleDrag(location: CGPoint, center: CGPoint, radius: CGFloat) {
        guard radius > 0 else { return }

        let dx = location.x - center.x
        let dy = location.y - center.y
        let count = axes.count
        let stepAngle = (2.0 * .pi) / Double(count)

        var touchAngle = atan2(dy, dx)
        if touchAngle < -.pi / 2.0 - .pi / Double(count) {
            touchAngle += 2.0 * .pi
        }

        var closestIndex = 0
        var minAngleDiff = Double.greatestFiniteMagnitude

        for i in 0..<count {
            let axisAngle = -.pi / 2.0 + Double(i) * stepAngle
            var diff = abs(touchAngle - axisAngle)
            if diff > .pi { diff = 2.0 * .pi - diff }
            if diff < minAngleDiff {
                minAngleDiff = diff
                closestIndex = i
            }
        }

        let targetIndex = activeAxisIndex ?? closestIndex

        if activeAxisIndex != targetIndex {
            activeAxisIndex = targetIndex
            hapticFeedback.impactOccurred()
        }

        let targetAxis = axes[targetIndex]

        let targetAngle = -.pi / 2.0 + Double(targetIndex) * stepAngle
        let unitX = cos(targetAngle)
        let unitY = sin(targetAngle)

        let projectionDistance = (dx * CGFloat(unitX)) + (dy * CGFloat(unitY))
        let rawRatio = Double(projectionDistance / radius)
        let clampedRatio = Swift.max(0.0, Swift.min(1.0, rawRatio))

        if clampedRatio > 0.05 && !rating.isEnabled(targetAxis.id) {
            rating.setEnabled(true, for: targetAxis.id)
        }

        let rawScore = minScore + clampedRatio * (maxScore - minScore)
        let continuousDecimalScore = (rawScore * 10.0).rounded() / 10.0

        if rating.score(for: targetAxis.id) != continuousDecimalScore {
            rating.setScore(continuousDecimalScore, for: targetAxis.id, min: minScore, max: maxScore)
            activeScoreValue = continuousDecimalScore
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
                        .contentTransition(.numericText())

                    Text("/ 10.0")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(TravColors.muted)
                }
            }
        }
    }
}

// MARK: - Helper Subviews

private struct InteractiveAxisSpokeView: View {
    let index: Int
    let axis: RadarAxis
    let center: CGPoint
    let radius: CGFloat
    let rating: RadarRating
    let axesCount: Int
    let isActive: Bool

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
        .stroke(
            isActive && isEnabled
                ? TravColors.accent.opacity(0.55)
                : (isEnabled ? TravColors.border.opacity(0.3) : Color.gray.opacity(0.2)),
            style: StrokeStyle(lineWidth: isActive ? 1.5 : 1, dash: [4, 4])
        )
    }
}

private struct InteractiveKnobAndLabelView: View {
    let index: Int
    let axis: RadarAxis
    let center: CGPoint
    let radius: CGFloat
    @Binding var rating: RadarRating
    let minScore: Double
    let maxScore: Double
    let activeAxisIndex: Int?
    let axesCount: Int
    let hapticFeedback: UIImpactFeedbackGenerator

    /// Same tip-to-box gap as the experience-page read-only labels.
    private let tipToBoxGap: CGFloat = 12

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

    private var isActive: Bool {
        activeAxisIndex == index
    }

    private var score: Double {
        rating.score(for: axis.id, default: minScore)
    }

    private var estimatedLabelSize: CGSize {
        let nameChars = CGFloat(axis.name.count)
        let nameWidth = nameChars * 6.2 + 4
        let scoreWidth: CGFloat = 34
        let width = max(nameWidth, scoreWidth) + 16
        let height: CGFloat = 38
        return CGSize(width: width, height: height)
    }

    private var radialHalfExtent: CGFloat {
        let halfW = estimatedLabelSize.width / 2
        let halfH = estimatedLabelSize.height / 2
        return halfW * abs(CGFloat(cos(angle))) + halfH * abs(CGFloat(sin(angle)))
    }

    private var labelPoint: CGPoint {
        let distance = radius + tipToBoxGap + radialHalfExtent
        return CGPoint(
            x: center.x + CGFloat(distance * cos(angle)),
            y: center.y + CGFloat(distance * sin(angle))
        )
    }

    var body: some View {
        ZStack {
            // Vertex handle — matches experience dots at rest; enlarges while dragging.
            ZStack {
                if isActive && isEnabled {
                    Circle()
                        .fill(TravColors.accent.opacity(0.25))
                        .frame(width: 34, height: 34)

                    Text(String(format: "%.1f", score))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TravColors.accent)
                        .clipShape(Capsule())
                        .shadow(color: TravColors.accent.opacity(0.4), radius: 4, y: 2)
                        .offset(y: -30)
                }

                Circle()
                    .fill(isEnabled ? TravColors.accent : Color.gray)
                    .frame(
                        width: isActive ? 14 : (isEnabled ? 8 : 6),
                        height: isActive ? 14 : (isEnabled ? 8 : 6)
                    )
                    .shadow(
                        color: isEnabled ? TravColors.accent.opacity(isActive ? 0.55 : 0.5) : Color.clear,
                        radius: isActive ? 4 : 3
                    )
            }
            .position(point)

            // Axis label box — same boxed name + score treatment as experience page.
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    rating.toggleCategory(axis.id)
                }
                hapticFeedback.impactOccurred()
            } label: {
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
                            isEnabled
                                ? TravColors.accent.opacity(isActive ? 1.0 : 0.75)
                                : Color.gray.opacity(0.35),
                            lineWidth: isActive ? 1.75 : 1.25
                        )
                )
                .fixedSize()
                .scaleEffect(isActive ? 1.04 : 1.0)
                .animation(.spring(response: 0.2), value: isActive)
            }
            .buttonStyle(.plain)
            .position(labelPoint)
        }
    }
}

#Preview {
    @Previewable @State var sampleRating = RadarRating.defaultRating
    InteractiveRadarChartView(rating: $sampleRating)
        .padding()
        .background(TravColors.surface)
}
