import Foundation
import Combine
import CoreData

/// Calculates whether the user has crossed the post-trust gate that
/// surfaces the Supporter entry: **≥30 days of use AND ≥10 memories
/// saved AND not currently Plus/Studio/Founder**.
///
/// `installDate` is captured the first time `start()` runs and held in
/// UserDefaults. Memory count reads from Core Data on demand — this is
/// a lightweight count() query, fine to run on Settings appearance.
///
/// The Supporter row never surfaces in onboarding or upgrade flow.
/// Settings-only, per spec.
@MainActor
final class TenureTracker: ObservableObject {
    static let shared = TenureTracker()

    @Published private(set) var isTenured: Bool = false

    private enum Keys {
        static let installDate = "tenure.installDate"
    }

    /// Days required before the Supporter prompt may surface. Pulled
    /// out for testability.
    private static let requiredDays: Int = 30
    private static let requiredMemories: Int = 10

    /// Capture install date on first run and recompute eligibility.
    func start() {
        if UserDefaults.standard.object(forKey: Keys.installDate) == nil {
            UserDefaults.standard.set(Date(), forKey: Keys.installDate)
        }
        refresh()
    }

    /// Recomputes `isTenured`. Cheap — call from Settings.onAppear and
    /// from scene-active.
    func refresh() {
        let entitlement = EntitlementService.shared
        // Only Free users see Supporter — Plus/Founders shouldn't be
        // asked to support on top of their subscription.
        guard entitlement.tier == .free else {
            isTenured = false
            return
        }
        guard daysSinceInstall() >= TenureTracker.requiredDays else {
            isTenured = false
            return
        }
        guard memoryCount() >= TenureTracker.requiredMemories else {
            isTenured = false
            return
        }
        isTenured = true
    }

    #if DEBUG
    /// Rewrites the install date to N days ago. Use with a high N
    /// (e.g., 31) to immediately satisfy the tenure-time half of the
    /// Supporter gate without waiting a month.
    func debugSetInstallDaysAgo(_ days: Int) {
        let cal = Calendar.current
        if let date = cal.date(byAdding: .day, value: -days, to: Date()) {
            UserDefaults.standard.set(date, forKey: Keys.installDate)
        }
        refresh()
    }
    #endif

    private func daysSinceInstall() -> Int {
        guard let install = UserDefaults.standard.object(forKey: Keys.installDate) as? Date else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: install, to: Date()).day ?? 0
        return days
    }

    private func memoryCount() -> Int {
        let ctx = StorageService.shared.viewContext
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "isRecycled == NO OR isRecycled == nil")
        return (try? ctx.count(for: request)) ?? 0
    }
}
