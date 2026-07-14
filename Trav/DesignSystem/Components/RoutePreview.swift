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

        var connectorColor: Color {
            switch self {
            case .standard: TravColors.muted.opacity(0.55)
            case .onDark: .white.opacity(0.45)
            case .editorial: .white.opacity(0.55)
            }
        }

        var moreColor: Color {
            switch self {
            case .standard: TravColors.muted
            case .onDark, .editorial: .white.opacity(0.65)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? TravSpacing.xxs / 2 : TravSpacing.xxs) {
            ForEach(Array(visibleStops.enumerated()), id: \.element.id) { index, stop in
                HStack(spacing: TravSpacing.xs) {
                    Text(stop.emoji ?? "📍")
                        .font(.system(size: emojiSize))

                    Text(stop.name)
                        .font(nameFont)
                        .foregroundStyle(style.titleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if index < visibleStops.count - 1 {
                    Text("↓")
                        .font(.system(size: connectorSize, weight: .medium))
                        .foregroundStyle(style.connectorColor)
                        .padding(.leading, compact ? TravSpacing.xxs : TravSpacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if stops.count > maxVisibleStops {
                Text("+\(stops.count - maxVisibleStops) more")
                    .font(TravTypography.caption())
                    .foregroundStyle(style.moreColor)
                    .padding(.leading, TravSpacing.xs)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var visibleStops: [StopPreview] {
        Array(stops.prefix(maxVisibleStops))
    }

    private var emojiSize: CGFloat {
        switch style {
        case .editorial: 16
        case .standard, .onDark: compact ? 12 : 14
        }
    }

    private var connectorSize: CGFloat {
        switch style {
        case .editorial: 13
        case .standard, .onDark: compact ? 10 : 12
        }
    }

    private var nameFont: Font {
        switch style {
        case .editorial: TravTypography.labelMedium()
        case .standard, .onDark: compact ? TravTypography.caption() : TravTypography.labelMedium()
        }
    }
}

#Preview {
    RoutePreview(stops: MockData.experiences[0].stops)
        .padding()
}
