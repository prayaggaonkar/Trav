import SwiftUI
import UIKit

/// An item presented through the system share sheet.
struct ShareItem: Identifiable {
    let id = UUID()
    let message: String
    let url: URL

    var activityItems: [Any] { [message, url] }
}

/// UIKit share sheet wrapper (SwiftUI `ShareLink` can't be triggered from
/// closure-based card actions).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension View {
    /// Presents the system share sheet whenever `item` becomes non-nil.
    func travShareSheet(item: Binding<ShareItem?>) -> some View {
        sheet(item: item) { share in
            ShareSheet(items: share.activityItems)
                .presentationDetents([.medium, .large])
        }
    }
}
