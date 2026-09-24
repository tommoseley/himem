import SwiftUI
import CoreData

/// **"Add to a memory" — the first of the two doors** in
/// `HiMem · Transient capture.html` §4b.
///
/// > A picker of gists asks her to **recognise** the right memory from three
/// > lines, which is guessing. Instead: from the capture, "Add to a memory"
/// > opens search already scoped to the hours around it … she **asserts** the
/// > memory she means.
///
/// So this is a search field, not a list of recent memories, and the scoping
/// does the work: she almost always knows which memory it belongs to, and the
/// time window puts it near the top before she types anything.
///
/// **There is no AI guess slot, and no space is reserved for one** (Tom,
/// 2026-09-24). The spec describes under-suggested proposals above the field;
/// the Apple-Intelligence spike measured that door at **23% confidently
/// wrong**, which fails the under-suggest bar — *a confident wrong proposal is
/// worse than none, and silence is the correct answer here.* If proposals
/// arrive later through a better model that is a separate ruling with its own
/// precision bar, not a disabled row waiting to be switched on.
struct PlaceCaptureSheet: View {
    let capture: TransientCapture
    let onPlace: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FetchRequest private var memories: FetchedResults<JournalEntry>

    /// **The hours around the capture**, which is what "scoped" means here.
    /// Wide enough that a sitting is one window, narrow enough that it is not
    /// simply "recent".
    private static let window: TimeInterval = 6 * 3600

    init(capture: TransientCapture, onPlace: @escaping (UUID) -> Void) {
        self.capture = capture
        self.onPlace = onPlace
        _memories = FetchRequest(
            entity: JournalEntry.entity(),
            sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)],
            predicate: NSPredicate(format: "isRecycled == NO"),
            animation: .default
        )
    }

    /// In-window memories first, then everything else — both newest-first.
    /// Typing filters across the whole library, because the scope is a head
    /// start rather than a wall.
    private var ordered: [JournalEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matching = memories.filter { entry in
            guard !q.isEmpty else { return true }
            return entry.displayTitle.lowercased().contains(q)
                || entry.content.lowercased().contains(q)
        }
        let lo = capture.capturedAt.addingTimeInterval(-Self.window)
        let hi = capture.capturedAt.addingTimeInterval(Self.window)
        let near = matching.filter { $0.createdAt >= lo && $0.createdAt <= hi }
        let rest = matching.filter { $0.createdAt < lo || $0.createdAt > hi }
        return near + rest
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(ordered, id: \.id) { entry in
                    Button {
                        onPlace(entry.id)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.displayTitle)
                                .font(.system(size: 16, design: .serif))
                                .foregroundStyle(Crucible.Color.ink)
                            Text(entry.createdAt, format: .dateTime.weekday().hour().minute())
                                .font(.system(size: 12))
                                .foregroundStyle(Crucible.Color.ink3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Crucible.Color.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Crucible.Color.paper.ignoresSafeArea())
            .searchable(text: $query, prompt: "Search your memories")
            .navigationTitle("Add to a memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Crucible.Color.ink2)
                }
            }
        }
    }
}
