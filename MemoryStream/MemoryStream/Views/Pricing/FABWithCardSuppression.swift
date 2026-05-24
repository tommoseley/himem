import SwiftUI
import CoreData

/// Wrapper that hides its child (typically the `AppendFAB`) while the
/// AI Suggestions card is open on a memory detail. Card-open means
/// either:
///
///   • **Review state** — `latestOrganizePass?.dismissedAt == nil`.
///     The card always renders; the user hasn't yet dismissed.
///   • **Organized + chip unfolded** — the user tapped the chip and
///     the accordion-unfolded card is currently visible.
///
/// The Review state is observed via `@FetchRequest` on the entry's
/// `latestOrganizePass` so the wrapper reacts immediately when the
/// user dismisses the card (or a new pass lands and sets
/// `dismissedAt = nil`). The unfolded state is passed in from
/// `EntryExpandedView` via `OrganizeMemorySection`'s `unfolded`
/// binding.
///
/// Hiding the FAB prevents the bottom-right ochre FAB from
/// overlapping "Accept all" / `×` in the card footer.
struct FABWithCardSuppression<Content: View>: View {
    let entryID: UUID
    let cardUnfolded: Bool
    @ViewBuilder var content: Content

    @FetchRequest private var entries: FetchedResults<JournalEntry>

    init(entryID: UUID, cardUnfolded: Bool, @ViewBuilder content: () -> Content) {
        self.entryID = entryID
        self.cardUnfolded = cardUnfolded
        self.content = content()
        let request: NSFetchRequest<JournalEntry> = NSFetchRequest(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", entryID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdAt, ascending: false)]
        request.fetchLimit = 1
        _entries = FetchRequest(fetchRequest: request)
    }

    private var isReviewState: Bool {
        guard let pass = entries.first?.latestOrganizePass else { return false }
        return pass.dismissedAt == nil
    }

    private var cardOpen: Bool { isReviewState || cardUnfolded }

    var body: some View {
        if !cardOpen {
            content
        }
    }
}
