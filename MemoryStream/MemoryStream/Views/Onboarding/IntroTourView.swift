import SwiftUI

/// The seven-page intro tour — a fixed sequence, straight 1→7, no branching
/// and no bouncing.
///
/// **Why it exists.** A second dogfooder stopped using the app and said why:
/// *"I wasn't sure what was going on, so I used it less."* Everything here
/// answers that sentence. It is shown once after onboarding and is replayable
/// forever from the `?` on any screen and from Settings → Learn, so it is
/// never a one-time-only explanation.
///
/// **Its relationship to the other two teaching surfaces**, which is the part
/// that took the most deciding (all ruled 2026-08-23):
/// - **The F8 walkthrough** teaches the *task*, by doing it. The tour precedes
///   it and hands off: page 7's primary action starts the walkthrough at
///   **beat 1**, bypassing `.offer` entirely, because page 7 already asked the
///   question `.offer` asks. Seeing the tour — accepted **or** skipped —
///   suppresses `offerIfFirstRun()`. **The tour is the invitation now.**
/// - **The coachmarks** hold at their line. The tour is not a third. It does
///   retire `projectsConcept`, whose card page 5 duplicates near-verbatim, via
///   the same mechanism the walkthrough uses for the one-pagers it replaced.
///   It deliberately retires **nothing else**: `findTheThread` is Plus-only
///   and fires at a moment the tour cannot anticipate, and `watchStory` /
///   `siri` get one clause in a list here, which has not taught the arrival
///   workflow.
///
/// **F13 still binds.** The tour teaches the *task*, never the ontology — "a
/// memory is one thing you'll want back," never "a memory references N clips."
/// If a page drifts toward the model rather than the task, that page is wrong,
/// not F13.
///
/// Spec: `docs/design/HiMem · Intro tour.html`, `screens-intro-tour.jsx`.
/// Vocabulary per F7g: **parts**, never "evidence".
struct IntroTourView: View {
    /// Called when the tour ends — finished at page 7, or skipped. The caller
    /// marks it seen and decides where the user lands.
    let onFinish: () -> Void
    /// Page 7's primary. Starts the F8 walkthrough at beat 1.
    let onStartWalkthrough: () -> Void

    @State private var page: Int = 1
    @State private var callout: CaptureModality?

    static let pageCount = 7

    var body: some View {
        ZStack {
            Crucible.Color.paper.ignoresSafeArea()
            content
        }
        .sheet(item: $callout) { modality in
            TourModalityCallout(modality: modality)
                .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case 1:  pageWhy
        case 2:  pagePlusButton
        case 3:  pageMemories
        case 4:  pageClips
        case 5:  pageProjects
        case 6:  pageSearch
        default: pageWhatNext
        }
    }

    // MARK: - 1 · Why it exists
    //
    // No eyebrow — the first page shouldn't open with a label. No Skip,
    // deliberately: this is the one answer she can't recover by poking around,
    // and one page of reading is a fair price for it.

    private var pageWhy: some View {
        TourScaffold(
            page: page, showsBack: false, showsSkip: false,
            title: "Most things fade\na little at a time.",
            lede: "A story someone told you. Why a place mattered. The thinking behind something you're building. HiMem is for catching those while they're still there — and finding them again later.",
            onSkip: finish, onBack: back, onNext: next
        ) {
            VStack(alignment: .leading, spacing: 7) {
                Text("\u{201C}Catch it now. Sort it out later.\u{201D}")
                    .font(.system(size: 17, design: .serif))
                    .foregroundStyle(Crucible.Color.ink)
                Text("That's the whole idea. Nothing you catch has to be filed, named, or decided about in the moment.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Crucible.Color.ink3)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Crucible.Color.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Crucible.Color.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.top, 24)

            TourPointRow(symbol: "mic", title: "One tap to catch something",
                         detail: "Speak, snap a photo, or type a note. No naming, no choosing where it goes.")
            TourPointRow(symbol: "clock", title: "Decide later, when you have time",
                         detail: "Sorting happens when you sit down with it — never while you're trying to remember.")
        }
    }

    // MARK: - 2 · The + button
    //
    // Placed before the three objects deliberately: the button is the first
    // thing she'll touch, and knowing what it catches is what makes Memories,
    // Clips and Projects legible.
    //
    // A TREE, not a sequence — each row opens one sheet and returns here, so
    // the 1→7 spine never lengthens and the detail exists only for whoever
    // wants it.
    //
    // **Driven off `CaptureModality`, never hand-drawn.** The glyph and tint
    // come from `sfSymbol` and `color`, so the tour cannot drift from the FAB
    // even when the FAB changes. The design canvas draws SVG approximations of
    // this binding; they are not the source. (Ruled 2026-08-23, after the tour
    // shipped four hand-drawn glyphs while the canonical set sat in the repo.)
    //
    // `.reversed()` because `stackOrder` is the FAB's bottom-up column — voice
    // sits nearest the thumb, so it is LAST there — while a read-top-down list
    // leads with Voice.

    private var pagePlusButton: some View {
        TourScaffold(
            page: page, eyebrow: "The + button",
            title: "One button, five ways to catch something.",
            lede: "It sits in the corner of every screen, and it follows where you are — loose on Clips, a new part when you're inside a memory. Tap any of these to see how it works.",
            onSkip: finish, onBack: back, onNext: next
        ) {
            VStack(spacing: 8) {
                ForEach(Array(CaptureModality.stackOrder.reversed()), id: \.id) { modality in
                    Button { callout = modality } label: {
                        TourModalityRow(modality: modality)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 22)
        }
    }

    // MARK: - 3 · Memories

    private var pageMemories: some View {
        TourScaffold(
            page: page, eyebrow: "Memories",
            title: "A memory is one thing you'll want back.",
            lede: "An afternoon, a conversation, an idea you had in the car. It's made of one or more parts — a voice note, a photo, a video, something you typed.",
            onSkip: finish, onBack: back, onNext: next
        ) {
            TourPointRow(symbol: "square.3.layers.3d", title: "Made of parts",
                         detail: "Add as many as you like, whenever you like. A memory can grow for days.")
            TourPointRow(symbol: "sparkles", title: "A title and summary, if you want one",
                         detail: "Tap Organize and HiMem writes a draft from what's actually in it. You can change it, or ignore it.",
                         tone: .ai)
            TourPointRow(symbol: "magnifyingglass", title: "Findable years from now",
                         detail: "Search a word, a person, a place. Everything you've kept is on one list, by the day it happened.")
        }
    }

    // MARK: - 4 · Clips

    private var pageClips: some View {
        TourScaffold(
            page: page, eyebrow: "Clips",
            title: "Everything you catch lands here first.",
            lede: "Clips is the workbench. Anything you record — on your phone, your Watch, or with Siri — shows up here until you decide what it belongs to.",
            onSkip: finish, onBack: back, onNext: next
        ) {
            TourPointRow(symbol: "hand.raised", title: "Nothing is waiting on you",
                         detail: "A clip can sit here as long as it likes. There's no inbox to empty and no count to clear.")
            TourPointRow(symbol: "square.3.layers.3d", title: "Turn a few into a memory",
                         detail: "Pick the ones that belong together and start a memory from them. The rest stay where they are.")
            TourPointRow(symbol: "sparkles", title: "HiMem may notice a group",
                         detail: "If a few clips look like they go together, it says so — as a suggestion. You decide.",
                         tone: .ai)
        }
    }

    // MARK: - 5 · Projects
    //
    // This page is why `projectsConcept` retires: it carries that coachmark's
    // sentence, and both would otherwise fire on the same first run.

    private var pageProjects: some View {
        TourScaffold(
            page: page, eyebrow: "Projects",
            title: "For the things you come back to.",
            lede: "A trip. A book you're writing. Your father's stories. A project connects memories that belong to the same effort — however far apart they happened.",
            onSkip: finish, onBack: back, onNext: next
        ) {
            TourPointRow(symbol: "target", title: "Name it and say what it's for",
                         detail: "A name and one line about what you're building toward. That's the whole setup.")
            TourPointRow(symbol: "point.topleft.down.curvedto.point.bottomright.up", title: "A memory can be in several",
                         detail: "The same afternoon can belong to your road trip and to your photography log. Nothing is filed away twice.")
            TourPointRow(symbol: "sparkles", title: "Find the thread",
                         detail: "When there's enough to work with, HiMem can read across a project and tell you what it sees.",
                         tone: .ai)
        }
    }

    // MARK: - 6 · Finding things
    //
    // After the three objects, because search is only legible once she knows
    // what it's searching.

    private var pageSearch: some View {
        TourScaffold(
            page: page, eyebrow: "Finding things",
            title: "If you can remember one word, you can find it.",
            lede: "Everything you've spoken or typed is searchable — not just titles. A phrase from a conversation two years ago is enough.",
            onSkip: finish, onBack: back, onNext: next
        ) {
            TourPointRow(symbol: "magnifyingglass", title: "Searches what was said",
                         detail: "Voice notes are written down, so the words inside them count. So do photo and video descriptions.")
            TourPointRow(symbol: "hand.raised", title: "People and places too",
                         detail: "A name that came up, or where you were. Tap a result and you land on the thing itself.")
            TourPointRow(symbol: "clock", title: "Or narrow it down",
                         detail: "By topic, by project, or by when it happened — for when you know roughly and not exactly.")
        }
    }

    // MARK: - 7 · What next
    //
    // The only page that offers choices. Primary is the do-it-with-me
    // walkthrough; the two points say where help LIVES rather than adding a
    // third destination — a closing page with four options is a fork, not an
    // ending.

    private var pageWhatNext: some View {
        TourScaffold(
            page: page, eyebrow: "That's the whole idea",
            title: "Want to try it together?",
            lede: "We'll catch one thing and turn it into a memory — about a minute. Or start on your own; this is all here whenever you want it.",
            nextLabel: "Walk me through it",
            onSkip: finish, onBack: back, onNext: onStartWalkthrough
        ) {
            TourPointRow(symbol: "questionmark.circle", title: "The ? on every screen",
                         detail: "Tap it and you'll get help for what you're looking at — not a manual.")
            TourPointRow(symbol: "book", title: "Short guides in Settings \u{2192} Learn",
                         detail: "One page each, on recording, organizing, the Watch, and Siri. This tour lives there too.")

            Text("Nothing here is a test, and nothing is lost if you put it down. Everything you catch stays until you delete it.")
                .font(.system(size: 13))
                .foregroundStyle(Crucible.Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .background(Crucible.Color.accentTint2)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.top, 22)
        }
    }

    // MARK: - Navigation

    private func next() {
        if page < Self.pageCount {
            withAnimation(.easeInOut(duration: 0.25)) { page += 1 }
        } else {
            finish()
        }
    }

    private func back() {
        guard page > 1 else { return }
        withAnimation(.easeInOut(duration: 0.25)) { page -= 1 }
    }

    private func finish() { onFinish() }
}

// MARK: - Shared chrome

/// One page of the tour: dots + count · optional eyebrow · serif headline ·
/// one true sentence · content · Back / Next.
///
/// **Truncation is pinned HERE, not at the call sites, and that is the whole
/// point of the component.** Text clipping inside a container that had room
/// has now cost this codebase three times — F7a (coachmark titles), the tour's
/// step label, and the tour's row spans — and **F7a's per-site fix is exactly
/// what did not hold.** So every text span the scaffold owns carries
/// `fixedSize(horizontal: false, vertical: true)`, and the step count carries
/// `lineLimit(1)` with `layoutPriority` so it cannot be squeezed by the dots.
/// A new page added later inherits this by construction rather than by anyone
/// remembering. (Ruled 2026-08-23 — replace the rule with a mechanism.)
private struct TourScaffold<Content: View>: View {
    let page: Int
    var eyebrow: String? = nil
    var showsBack: Bool = true
    var showsSkip: Bool = true
    let title: String
    let lede: String
    var nextLabel: String = "Next"
    let onSkip: () -> Void
    let onBack: () -> Void
    let onNext: () -> Void
    @ViewBuilder let content: () -> Content

    init(page: Int,
         eyebrow: String? = nil,
         showsBack: Bool = true,
         showsSkip: Bool = true,
         title: String,
         lede: String,
         nextLabel: String = "Next",
         onSkip: @escaping () -> Void,
         onBack: @escaping () -> Void,
         onNext: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.page = page
        self.eyebrow = eyebrow
        self.showsBack = showsBack
        self.showsSkip = showsSkip
        self.title = title
        self.lede = lede
        self.nextLabel = nextLabel
        self.onSkip = onSkip
        self.onBack = onBack
        self.onNext = onNext
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let eyebrow {
                Text(eyebrow)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(Crucible.Color.ink3)
                    .lineLimit(1)
                    .padding(.top, 24)
            }
            Text(title)
                .font(.system(size: 29, design: .serif))
                .foregroundStyle(Crucible.Color.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, eyebrow == nil ? 24 : 9)

            Text(lede)
                .font(.system(size: 14.5))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)

            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .padding(.horizontal, 26)
    }

    private var header: some View {
        HStack(spacing: 7) {
            ForEach(1...IntroTourView.pageCount, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Crucible.Color.accent : Crucible.Color.hairline)
                    .frame(width: i == page ? 18 : 6, height: 6)
            }
            Text("\(page) of \(IntroTourView.pageCount)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink3)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
                .padding(.leading, 6)

            Spacer(minLength: 8)

            if showsSkip {
                // 45px tap box (spec) — clears the 44px Crucible floor. ink2,
                // not ink3, for contrast.
                Button(action: onSkip) {
                    Text("Skip")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Crucible.Color.ink2)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .frame(height: 45)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 46)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if showsBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Crucible.Color.ink2)
                        .frame(width: 52, height: 52)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Crucible.Color.hairline, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button(action: onNext) {
                Text(nextLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Crucible.Color.accentInk)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Crucible.Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    // The button Tom could only tap on its words (device,
                    // 2026-08-23). The fill IS inside the label, which is why
                    // F17 cleared this shape — so the mechanism here is NOT
                    // the same as F29's outside-decoration one, and the
                    // suspected difference (`.buttonStyle(.plain)` removing
                    // the implicit hit region) is UNVERIFIED. `contentShape`
                    // is correct regardless and changes nothing on screen.
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 18)
        .padding(.bottom, 30)
    }
}

/// A glyph + title + body row. Both text spans carry `fixedSize` for the same
/// reason the scaffold's do.
private struct TourPointRow: View {
    enum Tone { case accent, ai }
    let symbol: String
    let title: String
    /// Named `detail`, not `body` — a stored property called `body` collides
    /// with `View.body`.
    let detail: String
    var tone: Tone = .accent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(tone == .ai ? Crucible.Color.aiBlue : Crucible.Color.accent)
                .frame(width: 38, height: 38)
                .background(tone == .ai ? Crucible.Color.aiBlueTint : Crucible.Color.accentTint2)
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Page 2's tree

/// One row of page 2. Glyph and tint come from `CaptureModality`, so this
/// cannot drift from the FAB.
private struct TourModalityRow: View {
    let modality: CaptureModality

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: modality.sfSymbol)
                .font(.system(size: 14))
                // **Ochre, not `modality.color`** (ruled 2026-08-23). Binding
                // to `CaptureModality` was right for `sfSymbol` — the tour must
                // show the iconography she'll see on her own clips — and wrong
                // for the tint: it imported five decorative hues onto one page,
                // including a green that Crucible reserves as semantic-only for
                // *confirmed* and which here would mean "photo".
                // Differentiation is the label and the symbol, never hue.
                .foregroundStyle(Crucible.Color.accent)
                .frame(width: 26, height: 26)
                .background(Crucible.Color.accentTint2)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(modality.label)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink)
                .lineLimit(1)
                .fixedSize()

            Text(TourModalityCopy.note(for: modality))
                .font(.system(size: 12))
                .foregroundStyle(Crucible.Color.ink2)
                .lineLimit(1)
                .fixedSize()

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink3)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
        .background(Crucible.Color.card)
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Crucible.Color.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .contentShape(Rectangle())
    }
}

/// One sheet, not a page: serif headline · what it's for · what happens after
/// · Done. No step count, no Back/Next — opening a callout must never advance
/// the 1→7 spine (ruled 2026-08-23).
private struct TourModalityCallout: View {
    let modality: CaptureModality
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Crucible.Color.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    Image(systemName: modality.sfSymbol)
                        .font(.system(size: 17))
                        .foregroundStyle(Crucible.Color.accent)   // see TourModalityRow
                        .frame(width: 38, height: 38)
                        .background(Crucible.Color.accentTint2)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                    Text(modality.label)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(Crucible.Color.ink3)
                        .lineLimit(1)
                }
                .padding(.top, 28)

                Text(TourModalityCopy.headline(for: modality))
                    .font(.system(size: 24, design: .serif))
                    .foregroundStyle(Crucible.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)

                Text(TourModalityCopy.detail(for: modality))
                    .font(.system(size: 14.5))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                Spacer(minLength: 18)

                Button { dismiss() } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Crucible.Color.accentInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Crucible.Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 26)
            }
            .padding(.horizontal, 26)
        }
    }
}

/// Page 2's copy, kept beside the rows it feeds. Design authority — do not
/// reword without a ruling (`docs/design/HiMem · Intro tour.html`).
///
/// Voice's "Next while recording" line is the ONLY place the tour mentions
/// on-a-roll, and it is a mention rather than a lesson: the F8 walkthrough
/// teaches it, as beat 1b.
private enum TourModalityCopy {
    static func note(for m: CaptureModality) -> String {
        switch m {
        case .voice:  return "one tap, no typing"
        case .photo:  return "with a description"
        case .video:  return "with a description"
        case .note:   return "type it out"
        case .attach: return "a file you have"
        }
    }

    static func headline(for m: CaptureModality) -> String {
        switch m {
        case .voice:  return "Talk and it writes itself down."
        case .photo:  return "A picture, and why it mattered."
        case .video:  return "For when a picture isn't enough."
        case .note:   return "When you'd rather type."
        case .attach: return "Something you already have."
        }
    }

    static func detail(for m: CaptureModality) -> String {
        switch m {
        case .voice:
            return "Speak for as long as you like; HiMem transcribes it so the words are searchable later. Tap Next while recording to start a fresh clip without stopping."
        case .photo:
            return "Take one or pick one you already have. Add a description in your own words — that's what makes it findable."
        case .video:
            return "Same as a photo, moving. Add a description; the sound isn't transcribed yet."
        case .note:
            return "A few words or a few paragraphs. Sometimes quieter than talking."
        case .attach:
            return "A file from your phone or iCloud — a document, a scan, a screenshot."
        }
    }
}

// MARK: - Persistence

/// Whether the intro tour has been seen, and what seeing it retires.
///
/// **"Seen" means accepted OR skipped**, deliberately (ruled 2026-08-23).
/// Skipping is an answer — *"I've got the why, I'll find the rest myself"* —
/// and re-offering the walkthrough seconds later would be the nagging posture
/// this product doesn't have. Both exits mark it, and both suppress
/// `WalkthroughOrchestrator.offerIfFirstRun()`.
///
/// Nothing is gated behind finishing it: the tour is reachable forever from
/// the `?` on any screen and from Settings → Learn.
enum IntroTourStore {
    private static let seenKey = "himem.introTour.hasSeen"

    static var hasSeen: Bool {
        get { UserDefaults.standard.bool(forKey: seenKey) }
        set { UserDefaults.standard.set(newValue, forKey: seenKey) }
    }

    /// Called on either exit. Marks the tour seen and retires the one
    /// coachmark it duplicates.
    ///
    /// **`projectsConcept` only** — enumerated and ruled 2026-08-23. Page 5
    /// carries that card's sentence near-verbatim and both would otherwise
    /// fire on the same first run. The other coachmark (`sectionHelp`) teaches
    /// the `?` affordance, which no page covers. Of the six auto-fire
    /// one-pagers, `capture` and `organizing` are already retired by the F8
    /// walkthrough; `findTheThread` is Plus-only and fires at a moment the
    /// tour cannot anticipate; `watchStory` and `siri` get one clause in a
    /// list on page 4, which has not taught the arrival workflow. **Retiring
    /// a taught feature for a mention is a bad trade** — so this retires
    /// exactly one thing, and the coachmark line holds.
    @MainActor
    static func markSeenAndRetireDuplicates() {
        hasSeen = true
        OneShotCoachmark.projectsConcept.retireBecauseSomethingElseTeachesIt()
    }

    /// Replay from `?` / Learn re-arms what the tour retired, so the answer is
    /// recoverable the same way the walkthrough's relaunch re-arms its own.
    @MainActor
    static func rearmForReplay() {
        OneShotCoachmark.projectsConcept.rearm()
    }
}

/// Requests a replay of the tour from anywhere — the `?` on any screen, or
/// Settings → Learn. The root owns presentation; this is how a leaf asks.
///
/// Replay is the **plain** entry (ruled 2026-08-23): it opens page 1 and walks
/// 1→7 as normal. No resumption, no jumping to the page matching the current
/// screen, no separate mode. The only difference from first launch is that
/// it's replayable and nothing is gated behind finishing it.
@MainActor
final class IntroTourReplayBus: ObservableObject {
    static let shared = IntroTourReplayBus()
    @Published var replayRequested = false
    private init() {}

    /// Ask the root to show the tour from page 1, re-arming what it retired so
    /// the coachmark teaches alongside it — the same shape as
    /// "? → Show me around" re-arming its own cards.
    func requestReplay() {
        IntroTourStore.rearmForReplay()
        replayRequested = true
    }
}
