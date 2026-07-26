import SwiftUI

/// Custom SwiftUI Shape for rendering radar chart polygons (used for both background concentric grid rings and rating shapes).
struct RadarChartPolygonShape: Shape {
    /// Normalized values array (each element between 0.0 and 1.0)
    var values: [Double]

    /// Vector animation support for smooth polygon transitions when updating continuous decimal ratings.
    var animatableData: AnimatableVector {
        get { AnimatableVector(values: values) }
        set { values = newValue.values }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count >= 3 else { return path }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = min(rect.width, rect.height) / 2.0
        let count = values.count
        let stepAngle = (2.0 * .pi) / Double(count)

        for i in 0..<count {
            let angle = -.pi / 2.0 + Double(i) * stepAngle
            let r = maxRadius * Swift.max(0.0, Swift.min(1.0, values[i]))
            let point = CGPoint(
                x: center.x + CGFloat(r * cos(angle)),
                y: center.y + CGFloat(r * sin(angle))
            )

            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.closeSubpath()
        return path
    }
}

/// Helper animatable vector for custom vector shape animations in SwiftUI.
struct AnimatableVector: VectorArithmetic {
    var values: [Double]

    mutating func scale(by factor: Double) {
        values = values.map { $0 * factor }
    }

    var magnitudeSquared: Double {
        values.reduce(0.0) { $0 + $1 * $1 }
    }

    static func + (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        let count = max(lhs.values.count, rhs.values.count)
        var result = [Double]()
        for i in 0..<count {
            let l = i < lhs.values.count ? lhs.values[i] : 0
            let r = i < rhs.values.count ? rhs.values[i] : 0
            result.append(l + r)
        }
        return AnimatableVector(values: result)
    }

    static func - (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        let count = max(lhs.values.count, rhs.values.count)
        var result = [Double]()
        for i in 0..<count {
            let l = i < lhs.values.count ? lhs.values[i] : 0
            let r = i < rhs.values.count ? rhs.values[i] : 0
            result.append(l - r)
        }
        return AnimatableVector(values: result)
    }

    static var zero: AnimatableVector {
        AnimatableVector(values: [])
    }
}
