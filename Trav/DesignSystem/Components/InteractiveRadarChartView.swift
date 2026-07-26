import SwiftUI
import UIKit

/// An interactive SwiftUI Radar Chart (spider chart) view that allows users to drag vertices or handles
/// directly on the polygon to adjust ratings continuously (1.0 to 10.0), toggle categories ON/OFF (disabled categories render as 0.0 in gray and are excluded from overall average), with a live updating experience score at the top.
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
        VStack(spacing: TravSpacing.md) {
            // Live Score Header Display
            headerView

            // Quick Category Toggle Chips
            categoryToggleBar

            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let center = CGPoint(x: geometry.size.width / 2.0, y: geometry.size.height / 2.0)
                let radius = (size / 2.0) - 40.0 // Padding for interactive vertex knobs and labels

                radarPlotView(size: size, center: center, radius: radius)
                // Gesture Overlay handling radial touch projection directly on the polygon
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
            .frame(height: 270)
            .padding(.vertical, TravSpacing.xs)
        }
        .padding(TravSpacing.md)
        .background(TravColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: TravRadius.lg)
                .stroke(TravColors.border.opacity(0.5), lineWidth: 1)
        )
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
    private func axisSpokesAndGuides(center: CGPoint, radius: CGFloat) -> some View {
        ForEach(0..<axes.count, id: \.self) { i in
            AxisSpokeView(
                index: i,
                axis: axes[i],
                center: center,
                radius: radius,
                rating: rating,
                minScore: minScore,
                maxScore: maxScore,
                activeAxisIndex: activeAxisIndex,
                axesCount: axes.count
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
            DraggableKnobView(
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
            axisSpokesAndGuides(center: center, radius: radius)
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

        // Find closest axis by angle if starting drag session
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

        // Vector projection of touch point onto selected axis ray
        let projectionDistance = (dx * CGFloat(unitX)) + (dy * CGFloat(unitY))

        // Normalized ratio along axis spoke (0.0 to 1.0)
        let rawRatio = Double(projectionDistance / radius)
        let clampedRatio = Swift.max(0.0, Swift.min(1.0, rawRatio))

        // If dragging outwards on a disabled category, automatically enable it
        if clampedRatio > 0.05 && !rating.isEnabled(targetAxis.id) {
            rating.setEnabled(true, for: targetAxis.id)
        }

        // Continuous decimal score calculation (1.0 to 10.0 scale)
        let rawScore = minScore + clampedRatio * (maxScore - minScore)
        let continuousDecimalScore = (rawScore * 10.0).rounded() / 10.0

        if rating.score(for: targetAxis.id) != continuousDecimalScore {
            rating.setScore(continuousDecimalScore, for: targetAxis.id, min: minScore, max: maxScore)
            activeScoreValue = continuousDecimalScore
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RATING RADAR")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(TravColors.accent)
                Text("Experience Rating")
                    .font(TravTypography.titleMedium())
                    .foregroundStyle(TravColors.primary)
            }

            Spacer()

            // Prominent Live Score Display at Top (Averages active categories ONLY)
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.0))

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.1f", rating.overallScore))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(TravColors.primary)
                        .contentTransition(.numericText())

                    Text("/ 10.0")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(TravColors.muted)
                }
            }
            .padding(.horizontal, TravSpacing.md)
            .padding(.vertical, TravSpacing.xs)
            .background(TravColors.surfaceElevated)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(TravColors.accent.opacity(0.3), lineWidth: 1.5)
            )
            .shadow(color: TravColors.accent.opacity(0.12), radius: 6, x: 0, y: 3)
        }
    }

    private var categoryToggleBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TravSpacing.xs) {
                ForEach(axes) { axis in
                    let isEnabled = rating.isEnabled(axis.id)
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            rating.toggleCategory(axis.id)
                        }
                        hapticFeedback.impactOccurred()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isEnabled ? (axis.iconName ?? "checkmark.circle.fill") : "xmark.circle.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(isEnabled ? TravColors.accent : Color.gray)

                            Text(axis.name)
                                .font(.system(size: 11, weight: isEnabled ? .bold : .medium, design: .rounded))
                                .foregroundStyle(isEnabled ? TravColors.primary : Color.gray)

                            Text(isEnabled ? String(format: "%.1f", rating.score(for: axis.id)) : "OFF")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(isEnabled ? TravColors.accent : Color.gray.opacity(0.7))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isEnabled ? TravColors.accent.opacity(0.12) : Color.gray.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(isEnabled ? TravColors.accent.opacity(0.35) : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

}

// MARK: - Helper Subviews for Compiler Optimization

struct AxisSpokeView: View {
    let index: Int
    let axis: RadarAxis
    let center: CGPoint
    let radius: CGFloat
    let rating: RadarRating
    let minScore: Double
    let maxScore: Double
    let activeAxisIndex: Int?
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

    private var vertexPoint: CGPoint {
        CGPoint(
            x: center.x + CGFloat(radius * val * cos(angle)),
            y: center.y + CGFloat(radius * val * sin(angle))
        )
    }

    private var maxPoint: CGPoint {
        CGPoint(
            x: center.x + CGFloat(radius * cos(angle)),
            y: center.y + CGFloat(radius * sin(angle))
        )
    }

    private var isActive: Bool {
        activeAxisIndex == index
    }

    var body: some View {
        ZStack {
            // Solid line from center to current rated vertex
            Path { p in
                p.move(to: center)
                p.addLine(to: vertexPoint)
            }
            .stroke(
                isEnabled ? (isActive ? TravColors.accent : TravColors.accent.opacity(0.35)) : Color.gray.opacity(0.2),
                lineWidth: isActive ? 2.5 : 1.5
            )

            // Soft dashed headroom line indicating remaining capacity up to max 10.0
            Path { p in
                p.move(to: vertexPoint)
                p.addLine(to: maxPoint)
            }
            .stroke(
                isEnabled ? (isActive ? TravColors.accent.opacity(0.85) : TravColors.border.opacity(0.6)) : Color.gray.opacity(0.25),
                style: StrokeStyle(
                    lineWidth: isActive ? 2.0 : 1.2,
                    dash: [5, 4]
                )
            )
        }
    }
}

struct DraggableKnobView: View {
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

    private var labelPoint: CGPoint {
        let labelRadius = radius + 28.0
        return CGPoint(
            x: center.x + CGFloat(labelRadius * cos(angle)),
            y: center.y + CGFloat(labelRadius * sin(angle))
        )
    }

    var body: some View {
        ZStack {
            // Draggable Knob Handle on the Polygon (Gray when disabled at center)
            ZStack {
                if isActive && isEnabled {
                    Circle()
                        .fill(TravColors.accent.opacity(0.25))
                        .frame(width: 38, height: 38)

                    // Floating Tooltip badge showing live continuous decimal value
                    Text(String(format: "%.1f", score))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TravColors.accent)
                        .clipShape(Capsule())
                        .shadow(color: TravColors.accent.opacity(0.4), radius: 4, y: 2)
                        .offset(y: -32)
                }

                Circle()
                    .fill(isEnabled ? TravColors.surface : Color.gray.opacity(0.2))
                    .frame(width: isActive ? 24 : (isEnabled ? 18 : 14), height: isActive ? 24 : (isEnabled ? 18 : 14))
                    .shadow(color: Color.black.opacity(isEnabled ? 0.15 : 0.05), radius: 3)

                Circle()
                    .fill(isEnabled ? (isActive ? TravColors.accent : TravColors.primary) : Color.gray)
                    .frame(width: isActive ? 14 : (isEnabled ? 10 : 8), height: isActive ? 14 : (isEnabled ? 10 : 8))
            }
            .position(point)

            // Outer Axis Title & Icon Badge (Tapping toggles Category ON/OFF)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    rating.toggleCategory(axis.id)
                }
                hapticFeedback.impactOccurred()
            } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 3) {
                        if let iconName = axis.iconName {
                            Image(systemName: isEnabled ? iconName : "eye.slash.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(isEnabled ? (isActive ? TravColors.accent : TravColors.muted) : Color.gray)
                        }
                        Text(axis.name)
                            .font(.system(size: 11, weight: isEnabled ? (isActive ? .bold : .semibold) : .medium, design: .rounded))
                            .foregroundStyle(isEnabled ? (isActive ? TravColors.accent : TravColors.primary) : Color.gray)
                    }
                    Text(isEnabled ? String(format: "%.1f", score) : "OFF")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(isEnabled ? (isActive ? TravColors.accent : TravColors.muted) : Color.gray.opacity(0.8))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isEnabled ? TravColors.surface.opacity(0.95) : Color.gray.opacity(0.15))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isEnabled ? (isActive ? TravColors.accent : TravColors.border.opacity(0.5)) : Color.gray.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(isActive ? 0.15 : 0.04), radius: isActive ? 3 : 1)
                .scaleEffect(isActive ? 1.08 : 1.0)
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
