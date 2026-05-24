import Foundation

/// Pure decision: is the "Find the thread" button (Project Assist)
/// enabled for a project? Activates at ≥3 memories per the Projects
/// MVP spec — below the threshold the button is still visible but
/// disabled with helper copy ("Add a few more memories first") so
/// the user discovers the affordance early.
///
/// Threshold is intentionally low — three memories is the minimum
/// scale where a synthesis paragraph + suggested-memories pass
/// produces signal worth the assist cost.
enum ProjectAssistGate {
    static let minimumMemories: Int = 3

    static func isEnabled(memoryCount: Int) -> Bool {
        memoryCount >= minimumMemories
    }
}
