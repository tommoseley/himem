import Foundation

/// Pure decision: is the user allowed to create another project?
/// Extracted so the cap logic can be unit-tested without driving the
/// list view. Plus is uncapped; Free is hard-capped at 3 active
/// projects (per `docs/design/Projects · MVP spec.md` § Tier and
/// `docs/design/Pricing model · Capture-Connect-Create.md` §4).
///
/// Used at the "+ New project" tap in `ProjectListView`. When `false`,
/// route to the upsell flow instead of opening the create form.
enum ProjectCapPolicy {
    static let freeProjectCap: Int = 3

    static func canCreate(isPlus: Bool, currentCount: Int) -> Bool {
        if isPlus { return true }
        return currentCount < freeProjectCap
    }
}
