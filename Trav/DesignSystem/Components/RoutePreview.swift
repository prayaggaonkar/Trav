import SwiftUI

struct RoutePreview: View {
    let stops: [StopPreview]
    var maxVisibleStops: Int = 4
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            ForEach(Array(visibleStops.enumerated()), id: \.element.id) { index, stop in
                HStack(spacing: TravSpacing.xs) {
                    Text(stop.emoji ?? "📍")
                        .font(.system(size: compact ? 12 : 14))

                    Text(stop.name)
                        .font(compact ? TravTypography.caption() : TravTypography.labelMedium())
                        .foregroundStyle(TravColors.primary)
                        .lineLimit(1)
                }

                if index < visibleStops.count - 1 {
                    HStack(spacing: 0) {
                        Text("↓")
                            .font(.system(size: compact ? 10 : 12, weight: .medium))
                            .foregroundStyle(TravColors.muted.opacity(0.6))
                            .padding(.leading, compact ? 4 : 6)
                        Spacer()
                    }
                }
            }

            if stops.count > maxVisibleStops {
                Text("+\(stops.count - maxVisibleStops) more")
                    .font(TravTypography.caption())
                    .foregroundStyle(TravColors.muted)
                    .padding(.leading, TravSpacing.xs)
            }
        }
    }

    private var visibleStops: [StopPreview] {
        Array(stops.prefix(maxVisibleStops))
    }
}

#Preview {
    RoutePreview(stops: MockData.experiences[0].stops)
        .padding()
}
