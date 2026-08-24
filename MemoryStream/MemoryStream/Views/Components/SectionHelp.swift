import SwiftUI

/// F7c · per-section help. The densest surfaces (Memory Detail, Edit Clip) meet
/// a first-timer with Topics · Projects · Mentions · the clip card · Organize
/// and nothing that explains them. Each section gets a small `?` that opens a
/// short panel in one locked shape:
///
///   **what it is → what you can do → where it's maintained**
///
/// The third clause is load-bearing — it's the part nothing else in the app
/// says, and the one that most directly answers "I'm stuck, more than once"
/// (Tom, 2026-07-27). The walkthrough (F8) teaches the spine by doing; these
/// `?` marks teach the rest on demand (Option B — no screen-level nav `?`).
///
/// Copy is design-authority, **drafted cold for Judi per F7e — not declared
/// clear.** Ontology terms stay accurate: a clip is the atom (stored once,
/// shared across memories); a project connects memories, it doesn't contain
/// them; Organize never rewrites on its own.
enum HelpTopic: String, CaseIterable, Identifiable {
    case memoryTopics
    case memoryProjects
    case memoryMentions
    case memoryClip
    case memoryOrganize
    case editClip
    /// Projects LIST — "what is a project for", asked from the screen where
    /// the question actually occurs. Added 2026-08-23 when the intro tour
    /// retired the `projectsConcept` coachmark: the net moves here rather than
    /// disappearing, and Projects stops being the one browsing tab with no `?`.
    case projectsConcept
    // Project Detail (F7c, both surfaces · 2026-07-27)
    case projectGoal
    case projectMemories
    case projectFindThread

    var id: String { rawValue }

    /// The panel heading — the thing being explained, in the app's own words.
    var title: String {
        switch self {
        case .memoryTopics:   return "Topics"
        case .memoryProjects: return "Projects"
        case .memoryMentions: return "Mentions"
        case .memoryClip:     return "Clips"
        case .memoryOrganize: return "Organize"
        case .editClip:       return "Editing a clip"
        case .projectsConcept:    return "Projects"
        case .projectGoal:        return "Goal"
        case .projectMemories:    return "Memories"
        case .projectFindThread:  return "Find the thread"
        }
    }

    /// Clause 1 — what it is.
    var whatItIs: String {
        switch self {
        case .memoryTopics:
            return "The themes this memory touches. The app reads your words and suggests them."
        case .memoryProjects:
            return "Projects are things you're working on over time. A memory can belong to several — or none."
        case .memoryMentions:
            return "People, places, and ideas the app noticed in this memory."
        case .memoryClip:
            return "A clip is one thing you captured — a voice note, photo, video, or written note. A memory is built from one or more of them."
        case .memoryOrganize:
            // Honest Label (Tom 2026-07-27): the AI writes those sentences —
            // they are NOT the user's words. What's true is it draws only on
            // what's in the clips and adds nothing.
            return "Organize reads this memory's parts and writes a title and summary. It only uses what's in your clips — it never adds anything that isn't there."
        case .editClip:
            return "This is a single clip — the smallest thing you capture. What you change here changes the clip everywhere it's used."
        case .projectsConcept:
            return "A project is something you're working on over time. It connects related memories — the same one can be in several projects, or none."
        case .projectGoal:
            return "The goal names what this project is building toward — a line you write for yourself."
        case .projectMemories:
            return "The memories connected to this project."
        case .projectFindThread:
            return "Find the thread is the project's one AI action. It reads across the project's memories and writes a short summary of what connects them — and suggests a few other memories that might belong."
        }
    }

    /// Clause 2 — what you can do.
    var whatYouCanDo: String {
        switch self {
        case .memoryTopics:
            return "Tap a topic to find other memories that share it."
        case .memoryProjects:
            return "Open a project to see every memory connected to it."
        case .memoryMentions:
            return "Tap a mention to see everywhere it comes up across your memories."
        case .memoryClip:
            return "Play it, read its transcript, or open it to edit the words."
        case .memoryOrganize:
            return "Run it from the Organize card. Add more clips later, then Reorganize to fold them in."
        case .editClip:
            return "Re-transcribe it, add a note, add it to a memory, or delete it."
        case .projectsConcept:
            return "Tap + to start one. Give it a name and a line about what you're building toward, then add memories to it whenever they turn up."
        case .projectGoal:
            return "Tap it to write or change it — one line about what you're working toward."
        case .projectMemories:
            return "Open any of them, or add more from your library."
        case .projectFindThread:
            return "Run it when you want a fresh read. Nothing auto-adds — the suggestions are yours to accept or ignore."
        }
    }

    /// Clause 3 — where it's maintained. The load-bearing clause: where this
    /// lives, who owns it, how to change it later.
    var whereItsMaintained: String {
        switch self {
        case .memoryTopics:
            return "Tap Edit on the Topics row to add or remove them. The app only suggests — the set is yours."
        case .memoryProjects:
            return "Tap Edit on the Projects row to add this memory to a project or take it out. The memory stays either way."
        case .memoryMentions:
            return "Mentions are shared across your memories — you can rename or remove one everywhere from Settings."
        case .memoryClip:
            return "A clip is stored once and can belong to several memories. Open it to see where else it's used — or to delete it."
        case .memoryOrganize:
            return "You decide when it runs; nothing is rewritten on its own. Re-run it anytime from here."
        case .editClip:
            return "A clip is stored once and shared across memories. The In N memories line shows where it lives; deleting it removes it from all of them."
        case .projectsConcept:
            return "Nothing is filed away twice — a memory stays everywhere it already was. Adding it here doesn't move it."
        case .projectGoal:
            return "It's yours — the app never changes it."
        case .projectMemories:
            return "Add or remove them here anytime. Removing a memory from a project never deletes it — it stays in your library, and can be in other projects too."
        case .projectFindThread:
            return "It reads only your memories' titles, topics, dates, and summaries — never the raw transcripts. Re-run it anytime; you decide when."
        }
    }

    /// The label for clause 3, per-panel. Default "WHERE IT LIVES" fits the
    /// where-it-persists sections; Organize is about when/how it runs, not where
    /// it lives, so it gets its own label (Tom, 2026-07-27 — a label that's
    /// untrue for the panel is a sign it doesn't fit).
    var clause3Label: String {
        switch self {
        case .memoryOrganize, .projectFindThread: return "HOW IT RUNS"
        default:                                   return "WHERE IT LIVES"
        }
    }
}

/// The small `?` glyph placed beside a section eyebrow (or in a modal's top
/// bar). Muted so it reads as a quiet affordance, not a call to action; opens
/// the help panel for its topic.
struct SectionHelpButton: View {
    let topic: HelpTopic
    /// Point size — smaller inline with a section eyebrow, standard in a bar.
    var size: CGFloat = 15
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(Crucible.Color.ink3)
                .frame(minWidth: 30, minHeight: 30) // ≥30pt hit target inline
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What is \(topic.title)?")
        .sheet(isPresented: $showing) {
            SectionHelpSheet(topic: topic)
        }
    }
}

/// The help panel — three clauses in the locked shape. A calm reading surface
/// (paper), medium detent, no actions: it explains, it doesn't do.
struct SectionHelpSheet: View {
    let topic: HelpTopic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(topic.title)
                        .font(.system(size: 24, design: .serif))
                        .tracking(-0.3)
                        .foregroundStyle(Crucible.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    clause("WHAT IT IS", topic.whatItIs)
                    clause("WHAT YOU CAN DO", topic.whatYouCanDo)
                    clause(topic.clause3Label, topic.whereItsMaintained)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(Crucible.Color.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Crucible.Color.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func clause(_ label: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Crucible.Color.ink3)
            Text(body)
                .font(.system(size: 15))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - One-shot coachmarks (the single-card pattern)

/// A SINGLE non-blocking coachmark, tracked per-device, fired once on first
/// arrival at its surface. One mechanism for the (deliberately few) cards we
/// allow after retiring the per-tab system:
///
/// - `sectionHelp` — introduces the section-`?` affordance the walkthrough
///   promises ("tap ? beside a section for help") but never shows (Memory
///   Detail, after the walkthrough).
/// - `projectsConcept` — teaches what a project IS on first Projects-list
///   arrival (the walkthrough covers clips→memories, not projects).
///
/// **Hold the line at these two.** We retired the per-tab coachmarks; each card
/// here must teach something the walkthrough genuinely doesn't. A third that
/// just explains a tab is the system we removed — stop and raise it (Tom,
/// 2026-07-27).
@MainActor
final class OneShotCoachmark: ObservableObject {
    private let seenKey: String
    let text: String
    /// When true, waits until the walkthrough is done (completed or skipped) —
    /// `sectionHelp` (the walkthrough promises the `?`). `projectsConcept` is
    /// independent of the walkthrough, so false.
    private let requiresWalkthroughDone: Bool

    @Published var visible = false

    init(seenKey: String, text: String, requiresWalkthroughDone: Bool) {
        self.seenKey = seenKey
        self.text = text
        self.requiresWalkthroughDone = requiresWalkthroughDone
    }

    var hasSeen: Bool { UserDefaults.standard.bool(forKey: seenKey) }

    /// Fire once, never while the walkthrough runs, never twice. Marks seen on
    /// fire so a dismiss (or a background) can't re-trigger.
    func armIfEligible() {
        guard !visible, !hasSeen, !WalkthroughOrchestrator.shared.isRunning,
              (!requiresWalkthroughDone || WalkthroughOrchestrator.shared.hasCompleted) else { return }
        visible = true
        UserDefaults.standard.set(true, forKey: seenKey)
    }

    func dismiss() { visible = false }

    /// Mark seen WITHOUT the user seeing it, because something else now
    /// teaches the same thing. Mirrors
    /// `TutorialOrchestrator.retireOnePagersReplacedByWalkthrough()`, which
    /// does exactly this for the one-pagers the F8 walkthrough replaced.
    /// Used by the intro tour for `projectsConcept`, whose card page 5
    /// carries near-verbatim (ruled 2026-08-23).
    ///
    /// This exists so the seen-key lives in ONE place. The caller having to
    /// know the literal `"himem.projectsCoachmark.seen"` is how a rename
    /// silently stops retiring anything.
    func retireBecauseSomethingElseTeachesIt() {
        UserDefaults.standard.set(true, forKey: seenKey)
        visible = false
    }

    /// Re-armed from "? → Show me around" so every card re-teaches alongside the
    /// relaunched walkthrough — one recoverability entry, not several.
    func rearm() {
        UserDefaults.standard.removeObject(forKey: seenKey)
        visible = false
    }

    static let sectionHelp = OneShotCoachmark(
        seenKey: "himem.sectionHelpCoachmark.seen",
        text: "Each section has a ? — tap it for a short explanation of what that section is and how it works.",
        requiresWalkthroughDone: true
    )

    static let projectsConcept = OneShotCoachmark(
        seenKey: "himem.projectsCoachmark.seen",
        text: "A project is something you're working on over time. It connects related memories — the same one can be in several projects, or none. Tap + to start one.",
        requiresWalkthroughDone: false
    )
}

/// The coachmark banner — non-blocking top-card register matching F8's
/// walkthrough banners (raised `card` surface, full-weight ochre border), one
/// "Got it" dismiss. Host it as a top overlay; the empty area passes touches
/// through so the controls underneath stay live.
struct CoachmarkBanner: View {
    @ObservedObject var coachmark: OneShotCoachmark

    var body: some View {
        if coachmark.visible {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(coachmark.text)
                        .font(.system(size: 14))
                        .foregroundStyle(Crucible.Color.ink)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Spacer(minLength: 0)
                        Button("Got it", action: coachmark.dismiss)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Crucible.Color.accentInk)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .background(Crucible.Color.accent, in: RoundedRectangle(cornerRadius: 10))
                            // F29 · String-label Button: the fill decorates the
                            // Button, not its label, so the pill drew at 40pt
                            // and tapped only on the text. Twin of the
                            // walkthrough's "Got it".
                            .contentShape(Rectangle())
                    }
                }
                .padding(16)
                .background(Crucible.Color.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Crucible.Color.accent, lineWidth: 2))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .shadow(color: Color.black.opacity(0.20), radius: 18, y: 6)

                Spacer(minLength: 0)
            }
            .transition(.opacity)
        }
    }
}
