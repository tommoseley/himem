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
            return "Organize reads this memory's clips and writes a title and summary in your own words."
        case .editClip:
            return "This is a single clip — the smallest thing you capture. What you change here changes the clip everywhere it's used."
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
            return "A clip is stored once and can belong to several memories. Open it to see where else it's used — or to let it go."
        case .memoryOrganize:
            return "You decide when it runs; nothing is rewritten on its own. Re-run it anytime from here."
        case .editClip:
            return "A clip is stored once and shared across memories. The In N memories line shows where it lives; deleting it removes it from all of them."
        }
    }

    /// The label for clause 3, per-panel. Default "WHERE IT LIVES" fits the
    /// where-it-persists sections; Organize is about when/how it runs, not where
    /// it lives, so it gets its own label (Tom, 2026-07-27 — a label that's
    /// untrue for the panel is a sign it doesn't fit).
    var clause3Label: String {
        switch self {
        case .memoryOrganize: return "HOW IT RUNS"
        default:              return "WHERE IT LIVES"
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
