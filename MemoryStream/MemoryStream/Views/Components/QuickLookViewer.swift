import SwiftUI
import QuickLook

/// SwiftUI wrapper around `QLPreviewController` — Apple's native
/// document/photo/video preview surface. Used everywhere across iOS
/// (Files, Mail, Messages, Notes attachments) and gives us native
/// pinch-zoom, pan, swipe-to-share, and swipe-down dismissal for
/// free.
///
/// Photo Card "tap to consume" routes through here when the photo's
/// bytes live in the ubiquity container (`MediaResolver.Resolution
/// .ubiquity(URL)`). Legacy `.photoKit` identifiers fall back to the
/// description editor in the parent — QuickLook can't preview a
/// PHAsset identifier directly.
///
/// Per `CLAUDE.md` § UIKit Pickers in SwiftUI: `QLPreviewController`
/// is configured once in `makeUIViewController`; we never touch its
/// state on update. SwiftUI re-renders the parent view freely; the
/// QL controller stays untouched, which is what we want.
struct QuickLookViewer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        // Intentionally empty — see the type-level doc above.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

/// Identifiable URL wrapper so we can present QuickLook via
/// `.sheet(item:)`. The hash of the URL string is stable enough to
/// serve as the Identifiable id — two distinct URLs presented in
/// sequence won't dedup, which is what we want.
struct QuickLookItem: Identifiable, Equatable {
    let url: URL
    var id: String { url.absoluteString }
}
