import Foundation

/// Pure decision: is the user allowed to create another project?
/// Extracted so the cap logic can be unit-tested without driving the
/// list view. Plus / Founders are uncapped; Free is hard-capped at
/// 1 active project (per `docs/design/pricing-model.md`).
///
/// Used at the "+ New project" tap in `ProjectListView`. When `false`,
/// route to the upsell sheet (`ProjectCapSheet`) instead of opening
/// the create form.
enum ProjectCapPolicy {
    static let freeProjectCap: Int = 1

    static func canCreate(isPlus: Bool, currentCount: Int) -> Bool {
        if isPlus { return true }
        return currentCount < freeProjectCap
    }
}
