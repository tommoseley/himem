import Testing
import Foundation
@testable import HiMem

/// **F32 · the creation toast, generalized.**
///
/// It answers *"where did it go?"* at the moment the question arises,
/// with no magic navigation: the surface does not move, and the way
/// there is one tap.
///
/// **Why it supersedes the walkthrough ring for this job.** The ring
/// failed structurally twice — a window that closed before she looked
/// (F20a), an `onAppear` that had already fired (F20b). A toast is
/// present at creation *by construction*: it is rendered by the code
/// path that did the creating, so it cannot miss its moment. The ring
/// has to predict when she will look; the toast does not.
@Suite struct CreationToastTests {

    /// **The copy names the OBJECT, not the action.** A toast reading
    /// "Created" or "Saved" alone would make her infer which thing —
    /// exactly the translation work F13's test forbids.
    @Test func everyKindNamesItsObject() {
        #expect(CreationToast.Kind.memory.label  == "Memory created")
        #expect(CreationToast.Kind.clip.label    == "Clip saved")
        #expect(CreationToast.Kind.project.label == "Project created")
    }

    /// Each kind is distinguishable — three creation moments must never
    /// share a string, for the same reason "not yet transcribed" and
    /// "transcribed to silence" must not (F24 Defect 4).
    @Test func kindsDoNotShareAString() {
        let labels = [CreationToast.Kind.memory, .clip, .project].map(\.label)
        #expect(Set(labels).count == labels.count)
    }

    /// The noun she'd use, not ours. "Clip" is a sanctioned handle (J1 —
    /// a label is a handle to grab, not a taxonomy to learn); "part" and
    /// "evidence" are ours and never appear in UI copy (F7g).
    @Test func labelsCarryNoArchitectureVocabulary() {
        for kind in [CreationToast.Kind.memory, .clip, .project] {
            let l = kind.label.lowercased()
            #expect(l.contains("evidence") == false)
            #expect(l.contains("part") == false)
        }
    }

    /// VoiceOver hears the outcome AND the affordance, because the whole
    /// row is now tappable rather than just a trailing link.
    @Test func everyKindDescribesWhatTappingDoes() {
        for kind in [CreationToast.Kind.memory, .clip, .project] {
            #expect(kind.accessibilityHint.lowercased().hasPrefix("opens"),
                    "\(kind) does not tell VoiceOver what a tap does.")
        }
    }

    // MARK: - Caller guards

    /// **The whole toast must be the tap target.** Previously only the
    /// trailing "View" link was tappable, which is the F29 shape one
    /// layer up: a control that looks pressable across its width and
    /// isn't.
    @Test func theWholeToastIsTheTapTarget() throws {
        let src = try Self.source("MemoryStream/Views/ClipsTabView.swift")
        let body = try Self.declBody(of: "struct CreationToast: View {", in: src)
        #expect(body.contains("Button(action: onOpen)"),
                "The toast is no longer a single button — the tap target has shrunk back.")
        #expect(body.contains("contentShape(Rectangle())"),
                "The toast declares no hit region.")
        // The trailing "View" must NOT be its own button any more, or the
        // outer tap target is competing with an inner one.
        #expect(body.contains("Button(action: onView)") == false,
                "A nested button inside the toast steals taps from the row.")
    }

    /// **Never auto-navigates.** The toast is a handle, not a teleport —
    /// the surface stays put unless she taps. A creation path that moved
    /// her would be the "no magic navigation" rule broken.
    @Test func theToastDoesNotNavigateOnItsOwn() throws {
        let src = try Self.source("MemoryStream/Views/ClipsTabView.swift")
        let body = try Self.declBody(of: "struct CreationToast: View {", in: src)
        for driver in ["pendingOpenMemoryId", "NavigationLink", "onAppear"] {
            #expect(body.contains(driver) == false,
                    "The toast performs navigation of its own (\(driver)) — it must only call onOpen.")
        }
    }

    // MARK: - Source access

    static func declBody(of needle: String, in source: String) throws -> String {
        guard let start = source.range(of: needle)?.lowerBound else {
            throw Failure.notFound(needle)
        }
        var depth = 0, started = false
        var out = ""
        for ch in source[start...] {
            if ch == "{" { depth += 1; started = true }
            if ch == "}" { depth -= 1 }
            if started { out.append(ch) }
            if started && depth == 0 { return out }
        }
        throw Failure.notFound(needle)
    }

    static func source(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String), notFound(String) }
}
