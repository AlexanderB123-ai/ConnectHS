import SwiftUI
import UIKit

/// Thin SwiftUI wrapper around UIActivityViewController. Use via `.sheet`:
///
///     .sheet(item: $payload) { ShareSheet(items: [$0.image]) }
///
/// The `Equatable` conformance lets `.sheet(item:)` diff cleanly when the
/// sharing payload reference changes.
struct ShareSheet: UIViewControllerRepresentable {

    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
