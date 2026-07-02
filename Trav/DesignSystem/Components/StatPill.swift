import SwiftUI

struct StatPill: View {
    let symbol: String
    let value: String

    var body: some View {
        HStack(spacing: TravSpacing.xxs) {
            Image(systemName: symbol)
                .font(.system(size: TravIcon.sm - 3, weight: .medium))
            Text(value)
                .font(TravTypography.caption())
        }
        .foregroundStyle(TravColors.muted)
        .padding(.horizontal, TravSpacing.xs)
        .padding(.vertical, TravSpacing.xxs)
        .background(TravColors.surface)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(TravColors.border.opacity(0.4), lineWidth: 1)
        }
    }
}
