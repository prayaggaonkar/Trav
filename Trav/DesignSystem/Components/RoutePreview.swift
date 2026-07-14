import SwiftUI

struct RoutePreview: View {
    let stops: [StopPreview]
    var maxVisibleStops: Int = 4
    var compact: Bool = false
    var style: Style = .standard

    enum Style {
        case standard
        case onDark
        case editorial

        var titleColor: Color {
            switch self {
            case .standard: TravColors.primary
            case .onDark, .editorial: .white
            }
        }

        var moreColor: Color {
            switch self {
            case .standard: TravColors.muted
            case .onDark, .editorial: .white.opacity(0.65)
            }
        }

        var separatorColor: Color {
            switch self {
            case .standard: TravColors.muted.opacity(0.45)
            case .onDark, .editorial: .white.opacity(0.4)
            }
        }
    }

    var body: some View {
        // Horizontal route chips — cleaner and less symbol-heavy than a vertical ↓ list.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TravSpacing.xs) {
                ForEach(Array(visibleStops.enumerated()), id: \.element.id) { index, stop in
                    HStack(spacing: TravSpacing.xxs) {
                        if let emoji = stop.emoji {
                            Text(emoji)
                                .font(.system(size: compact ? 11 : 13))
                        }
                        Text(stop.name)
                            .font(compact ? TravTypography.caption() : TravTypography.labelMedium())
                            .foregroundStyle(style.titleColor)
                            .lineLimit(1)
                    }

                    if index < visibleStops.count - 1 {
                        Text("·")
                            .font(TravTypography.caption())
                            .foregroundStyle(style.separatorColor)
                    }
                }

                if stops.count > maxVisibleStops {
                    Text("+\(stops.count - maxVisibleStops)")
                        .font(TravTypography.caption())
                        .foregroundStyle(style.moreColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var visibleStops: [StopPreview] {
        Array(stops.prefix(maxVisibleStops))
    }
}

#Preview {
    RoutePreview(stops: MockData.experiences[0].stops)
        .padding()
}
