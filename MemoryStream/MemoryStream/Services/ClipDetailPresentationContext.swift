import Foundation

/// Shared, tab-level state: which clip (if any) the user is currently
/// viewing on `ClipDetailView`. Wired by both detail variants
/// (`MediaReferenceClipDetail`, `InboxClipDetail`) on
/// `.onAppear`/`.onDisappear` and read by `HiMemTabView` so the tab-
/// shell FAB steps aside on an opened clip.
///
/// `Clip model · spec.md` §Clip triage (July 12 2026):
/// > "No FAB on an opened clip — it's an opened item, not a capture
/// > surface. (CC's build still shows it; it must be hidden.)"
///
/// Same id-matched enter/exit rationale as
/// `MemoryDetailPresentationContext` — prevents a departing view's
/// disappear from clobbering the incoming view's appear during rapid
/// drill-to-drill navigation (e.g. dismissing a clip and pushing a
/// sibling in quick succession).
@MainActor
final class ClipDetailPresentationContext: ObservableObject {

    static let shared = ClipDetailPresentationContext()

    /// Non-nil while a `ClipDetailView` is on screen. Nil at every
    /// list-level surface. The id is the underlying source id — a
    /// `MediaReference.id` for the managed variant, an `InboxClip.
    /// clipId` for the bench variant — used only for the enter/exit
    /// match, not surfaced to callers.
    @Published private(set) var currentClipId: UUID? = nil

    private init() {}

    func enter(clipId: UUID) {
        currentClipId = clipId
    }

    /// Only clears when `clipId` matches the current — see
    /// `MemoryDetailPresentationContext.exit` for the rapid-drill
    /// rationale.
    func exit(clipId: UUID) {
        if currentClipId == clipId {
            currentClipId = nil
        }
    }

    #if DEBUG
    func debugReset() {
        currentClipId = nil
    }
    #endif
}
