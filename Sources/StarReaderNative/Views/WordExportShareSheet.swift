import SwiftUI
import UIKit

struct WordExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Standard iOS share sheet offers Save to Files, AirDrop and other apps.
struct WordExportShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
