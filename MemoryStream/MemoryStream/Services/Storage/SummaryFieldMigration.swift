import Foundation
import CoreData

/// Backfills `JournalEntry.summary` from the latest accepted
/// `OrganizePass.summaryText` so the unified-editing model
/// (`docs/design/Memory Detail · unified editing model.md`, Tom 2026-06-09)
/// has a canonical working value to display + edit on every entry
/// that had previously accepted an AI summary.
///
/// Pre-migration: the displayed summary was computed at render time
/// from `OrganizePass.summaryText` (the accepted draft). Post-migration:
/// the working summary lives on `JournalEntry.summary` (a stored attribute);
/// the OrganizePass keeps holding the AI's draft, and a user tap-to-edit
/// writes directly to `JournalEntry.summary` + sets
/// `JournalEntry.summaryUserEdited`.
///
/// **Idempotent every call.** Per-entry check (`entry.summary == nil`)
/// makes re-running a no-op for migrated rows; this matches the
/// `FragmentMigration` pattern so the same CloudKit-import-gate
/// strategy applies here too.
///
/// **Does NOT set `summaryUserEdited`.** The backfill is the AI's
/// accepted text, not a user edit — preserving the marker's meaning
/// (true == the user touched it) so the auto-pass-no-clobber rule
/// still works correctly post-migration.
enum SummaryFieldMigration {
    /// Bump if the migration's semantics ever change. The completion
    /// flag is per-version, so old devices that ran v1 will re-run
    /// against v2 once and lock in.
    internal static let completionFlagKey = "summaryFieldMigration.v1.completed"

    /// Runs the migration on `context`. Idempotent + cheap when there's
    /// nothing to do. `LaunchScreenView` should invoke this on every
    /// CloudKit `.import .succeeded` event the same way it does for
    /// `FragmentMigration`, so entries that arrive in a later import
    /// batch still get backfilled.
    ///
    /// **Caller is responsible for the CloudKit-import gate** — running
    /// during an import races the importer's model and raises a
    /// Core Data NSException Swift cannot catch. Same constraint
    /// `FragmentMigration.runIfNeeded` documents.
    ///
    /// **Skipped under XCTest** for the same reason: the test host
    /// binary shares the live store with the app, so an in-test launch
    /// would otherwise mutate the user's real data.
    static func runIfNeeded(in context: NSManagedObjectContext, force: Bool = false) {
        if isRunningTests && !force { return }
        let defaults = UserDefaults.standard
        if !force && defaults.bool(forKey: completionFlagKey) { return }

        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        // Only fetch entries that haven't been backfilled yet. A nil
        // `summary` is the post-migration "not yet touched" sentinel;
        // any non-nil value (AI accept or user edit) means we're done
        // for that row.
        request.predicate = NSPredicate(format: "summary == nil")
        guard let entries = try? context.fetch(request) else { return }

        var walked = 0
        var backfilled = 0
        for entry in entries {
            walked += 1
            if let pass = entry.latestOrganizePass,
               pass.acceptedRows.contains(.summary),
               let text = pass.summaryText, !text.isEmpty {
                entry.summary = text
                // Do NOT set summaryUserEdited — this is the AI's
                // accepted text, not a user edit. The marker's job is
                // to gate the silent-auto-overwrite path; leaving it
                // false preserves that semantic correctly.
                backfilled += 1
            }
            // Entries that don't have an accepted pass leave `summary`
            // nil; the renderedSummary computed property still falls
            // back to the old computed path until/unless the user
            // organizes them later. Nothing to migrate.
        }

        if backfilled > 0 {
            do {
                try context.save()
            } catch {
                NSLog("[HiMem][SummaryMigration] save failed after backfilling \(backfilled) entries: \(error.localizedDescription)")
                return
            }
        }

        // Only set the completion flag after a successful walk. A
        // "walked zero" outcome (CloudKit hasn't imported yet) doesn't
        // set the flag, matching `FragmentMigration`'s behavior so the
        // next launch tries again.
        if walked > 0 {
            defaults.set(true, forKey: completionFlagKey)
        }
        NSLog("[HiMem][SummaryMigration] walked=\(walked) backfilled=\(backfilled)")
    }

    /// Same XCTest sentinel `FragmentMigration` uses — check whether the
    /// test runner is the active process so the live-store migration
    /// doesn't fire while tests are spinning up in-memory stores.
    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }
}
