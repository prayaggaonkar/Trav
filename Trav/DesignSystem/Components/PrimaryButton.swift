import SwiftUI

struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(TravTypography.titleMedium())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TravSpacing.sm)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: TravLayout.buttonHeight)
            .background(isEnabled ? TravColors.accent : TravColors.muted.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: TravRadius.md, style: .continuous))
        }
        .buttonStyle(TravPressButtonStyle())
        .disabled(isLoading || !isEnabled)
        .animation(TravAnimation.quick, value: isEnabled)
    }
}
