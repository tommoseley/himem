import Foundation

/// Shared "h:mm a" time formatter for a part's meta line.
///
/// **Extracted from `ClipsTabView` in the deletion slice** (2026-09-21), for
/// the same reason `SelectCircle` and `HiMemSegmentedControl` were: it was
/// declared alongside the bench but is not bench machinery.
/// `AddExistingClipsSheet` — the paperclip, which survives as *bring something
/// existing here* — renders it on every row.
///
/// It was missed by the mechanical block that moved the other two, because
/// that pass scanned top-level **type** declarations and this is a free
/// function. The compiler caught it; the scan could not have.
private let clipTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    return f
}()

func clipTimeString(_ ref: MediaReference) -> String {
    guard let date = ref.createdAt else { return "" }
    return clipTimeFormatter.string(from: date)
}
