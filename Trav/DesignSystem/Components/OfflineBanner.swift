import SwiftUI

/// Thin banner pinned to the top of the root window when offline.
struct OfflineBanner: View {
    private var monitor = NetworkMonitor.shared

    var body: some View {
        if !monitor.isOnline {
            HStack(spacing: TravSpacing.sm) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 13, weight: .semibold))
                Text("You're offline — showing cached content when available")
                    .font(TravTypography.labelMedium())
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, TravSpacing.md)
            .padding(.vertical, TravSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.92))
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityLabel("Offline. Showing cached content when available.")
            .animation(TravAnimation.enter, value: monitor.isOnline)
        }
    }
}
