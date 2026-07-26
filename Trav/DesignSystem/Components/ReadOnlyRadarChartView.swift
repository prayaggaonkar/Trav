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

    @State private var isAnimated: Bool = false

    init(
        rating: RadarRating,
        axes: [RadarAxis] = RadarAxis.defaultAxes,
        minScore: Double = 1.0,
        maxScore: Double = 10.0,
        fillColor: Color = TravColors.accent,
        strokeColor: Color = TravColors.accent
    ) {
        self.rating = rating
        self.axes = axes
        self.minScore = minScore
        self.maxScore = maxScore
        self.fillColor = fillColor
        self.strokeColor = strokeColor
    }

    var body: some View {
        VStack(spacing: TravSpacing.sm) {
            // Header showing aggregate rating across active categories
            headerView

            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let center = CGPoint(x: geometry.size.width / 2.0, y: geometry.size.height / 2.0)
                let radius = (size / 2.0) - 36.0 // Leave padding for text labels

                ZStack {
                    // 1. Concentric background grid rings (25%, 50%, 75%, 100%)
                    ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                        RadarChartPolygonShape(values: Array(repeating: level, count: axes.count))
                            .stroke(TravColors.border.opacity(0.4), lineWidth: level == 1.0 ? 1.5 : 1.0)
                            .frame(width: radius * 2 * CGFloat(level), height: radius * 2 * CGFloat(level))
                    }

                    // 2. Axis spokes from center
                    ForEach(0..<axes.count, id: \.self) { i in
                        let axis = axes[i]
                        let isEnabled = rating.isEnabled(axis.id)
                        let angle = -.pi / 2.0 + Double(i) * (2.0 * .pi / Double(axes.count))
                        let endPoint = CGPoint(
                            x: center.x + CGFloat(radius * cos(angle)),
                            y: center.y + CGFloat(radius * sin(angle))
                        )
                        Path { p in
                            p.move(to: center)
                            p.addLine(to: endPoint)
                        }
                        .stroke(isEnabled ? TravColors.border.opacity(0.3) : Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }

                    // 3. Filled polygon shape representing active scores (disabled categories collapse to 0.0)
                    let normalizedValues = axes.map { axis in
                        isAnimated ? rating.normalizedScore(for: axis.id, min: minScore, max: maxScore) : 0.0
                    }

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

                    // 4. Vertex dots at active points
                    ForEach(0..<axes.count, id: \.self) { i in
                        let axis = axes[i]
                        let isEnabled = rating.isEnabled(axis.id)
                        let val = isAnimated ? rating.normalizedScore(for: axis.id, min: minScore, max: maxScore) : 0.0
                        let angle = -.pi / 2.0 + Double(i) * (2.0 * .pi / Double(axes.count))
                        let point = CGPoint(
                            x: center.x + CGFloat(radius * val * cos(angle)),
                            y: center.y + CGFloat(radius * val * sin(angle))
                        )

                        Circle()
                            .fill(isEnabled ? strokeColor : Color.gray)
                            .frame(width: isEnabled ? 8 : 6, height: isEnabled ? 8 : 6)
                            .shadow(color: isEnabled ? strokeColor.opacity(0.5) : Color.clear, radius: 3)
                            .position(point)
                    }

                    // 5. Axis labels & numerical values around the perimeter
                    ForEach(0..<axes.count, id: \.self) { i in
                        let axis = axes[i]
                        let score = rating.score(for: axis.id, default: minScore)
                        let angle = -.pi / 2.0 + Double(i) * (2.0 * .pi / Double(axes.count))
                        let labelRadius = radius + 24.0

                        let labelPoint = CGPoint(
                            x: center.x + CGFloat(labelRadius * cos(angle)),
                            y: center.y + CGFloat(labelRadius * sin(angle))
                        )

                        axisLabelView(axis: axis, score: score)
                            .position(labelPoint)
                    }
                }
            }
            .frame(height: 250)
            .padding(.vertical, TravSpacing.xs)
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) {
                    isAnimated = true
                }
            }

            // Summary breakdown bar below chart
            scoreSummaryGrid
        }
        .padding(TravSpacing.md)
        .background(TravColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: TravRadius.lg)
                .stroke(TravColors.border.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("RATING OVERVIEW")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(TravColors.accent)
                Text("Overall Rating")
                    .font(TravTypography.titleMedium())
                    .foregroundStyle(TravColors.primary)
            }

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
            .padding(.horizontal, TravSpacing.sm)
            .padding(.vertical, 4)
            .background(TravColors.surfaceElevated)
            .clipShape(Capsule())
        }
    }

    private func axisLabelView(axis: RadarAxis, score: Double) -> some View {
        let isEnabled = rating.isEnabled(axis.id)

        return VStack(spacing: 2) {
            HStack(spacing: 3) {
                if let iconName = axis.iconName {
                    Image(systemName: isEnabled ? iconName : "eye.slash.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isEnabled ? TravColors.accent : Color.gray)
                }
                Text(axis.name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isEnabled ? TravColors.primary : Color.gray)
            }
            Text(isEnabled ? String(format: "%.1f", score) : "OFF")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(isEnabled ? TravColors.accent : Color.gray.opacity(0.8))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isEnabled ? TravColors.surface.opacity(0.95) : Color.gray.opacity(0.12))
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
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
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(isEnabled ? TravColors.primary : Color.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(isEnabled ? TravColors.surfaceElevated : Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: TravRadius.sm))
    }
}

#Preview {
    ReadOnlyRadarChartView(rating: .defaultRating)
        .padding()
        .background(TravColors.surface)
}
