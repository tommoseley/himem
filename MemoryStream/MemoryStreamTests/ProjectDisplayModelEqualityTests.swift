import Testing
import Foundation
@testable import HiMem

/// Money tests for the stale-project-card bug (Tom, 2026-07-18): editing a
/// project's goal didn't show on the Projects list card until a cold
/// relaunch. Root cause — `ProjectDisplayModel`'s custom `Equatable`
/// compared **id only**, so SwiftUI treated a card with a changed goal
/// (same id) as unchanged and skipped re-rendering it. A model whose
/// render-affecting fields differ MUST be `!=` so the view refreshes.
@Suite
struct ProjectDisplayModelEqualityTests {

    private func model(
        id: UUID,
        name: String = "P",
        purpose: String? = nil,
        shortSummary: String? = nil,
        memoryCount: Int = 1,
        topicNames: [String] = ["Travel"]
    ) -> ProjectDisplayModel {
        ProjectDisplayModel(
            id: id,
            name: name,
            purpose: purpose,
            shortSummary: shortSummary,
            memoryCount: memoryCount,
            topicNames: topicNames,
            updatedAt: Date(timeIntervalSince1970: 0),
            previewText: nil
        )
    }

    @Test func sameId_differentGoal_areNotEqual() {
        let id = UUID()
        let before = model(id: id, purpose: nil)
        let after = model(id: id, purpose: "I am working on a script")
        #expect(before != after, "a goal change must make the card model unequal so SwiftUI re-renders")
    }

    @Test func sameId_differentName_areNotEqual() {
        let id = UUID()
        #expect(model(id: id, name: "Old") != model(id: id, name: "New"))
    }

    @Test func sameId_differentCount_areNotEqual() {
        let id = UUID()
        #expect(model(id: id, memoryCount: 1) != model(id: id, memoryCount: 2))
    }

    @Test func sameId_differentTopics_areNotEqual() {
        let id = UUID()
        #expect(model(id: id, topicNames: ["Travel"]) != model(id: id, topicNames: ["Travel", "Food"]))
    }

    @Test func identicalModels_areEqual() {
        let id = UUID()
        #expect(model(id: id, purpose: "same") == model(id: id, purpose: "same"))
    }

    @Test func differentId_areNotEqual() {
        #expect(model(id: UUID()) != model(id: UUID()))
    }
}
