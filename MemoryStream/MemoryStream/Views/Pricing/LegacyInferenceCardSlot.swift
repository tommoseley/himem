import SwiftUI
import CoreData

/// Wrapper that fetches a live `JournalEntry` by ID and decides
/// whether to render the supplied legacy `InferenceCard` content.
///
/// Suppression rule: if the entry has any modern `OrganizePass`
/// records, the new `OrganizeDoneSections` is already rendering the
/// Summary inline above. Surfacing the legacy `InferenceCard` on top
/// of that would duplicate the AI's output. This wrapper hides the
/// slot in that case.
///
/// Old entries (created before the v2 pricing-design rebuild) have
/// only `InferenceSummary` and no `OrganizePass`; the slot renders
/// for them as before.
struct LegacyInferenceCardSlot<Content: View>: View {
    let entryID: UUID
    @ViewBuilder var content: Content

    @FetchRequest private var entries: FetchedResults<JournalEntry>

    init(entryID: UUID, @ViewBuilder content: () -> Content) {
        self.entryID = entryID
        self.content = content()
        let request: NSFetchRequest<JournalEntry> = NSFetchRequest(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "id == %@", entryID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdAt, ascending: false)]
        request.fetchLimit = 1
        _entries = FetchRequest(fetchRequest: request)
    }

    var body: some View {
        if entries.first?.latestOrganizePass == nil {
            content
        }
    }
}
