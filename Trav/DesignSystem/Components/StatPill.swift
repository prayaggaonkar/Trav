import SwiftUI

struct StatPill: View {
    let symbol: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
            Text(value)
                .font(TravTypography.caption())
        }
        .foregroundStyle(TravColors.muted)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(TravColors.surfaceElevated)
        .clipShape(Capsule())
    }
}
