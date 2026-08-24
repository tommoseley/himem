import SwiftUI
import WatchConnectivity

/// Learn hub — the replay surface for the locked five-tutorial
/// set per `docs/design/Tutorials · triggers spec.md` (June 10 2026)
/// and `docs/design/Himem · Tutorials.html`. Opened from the `?`
/// toolbar glyph in the main browsing header and from the `Learn`
/// row in Settings → Display.
///
/// Copy: "Learn, not Help" (locked in `Kingfisher · North Star.md`).
/// Help says something's wrong; Learn says *want to understand this?*
/// The hub title is "Learn"; internal identifiers still say
/// `Tutorial…` to avoid a mass rename with no functional payoff.
///
/// **Five tutorials, locked:**
/// 1. Capture · Next · Watch — phone capture + on-a-roll behavior + Watch hint
/// 2. Organizing with AI — draft / review / keep, editing never un-organizes
/// 3. Find the thread (Plus) — project synthesis + suggested memories
/// 4. Captured Clips · the Watch story — what to do with arrived clips
/// 5. Watch discovery — paired-but-not-installed nudge
///
/// **What's intentionally NOT here.** Topics, browsing, search,
/// settings, and all editing teach themselves and earn no tutorial.
/// Adding one would signal a failed flow.
///
/// Replay only — auto-trigger logic per the spec ("once each ever,
/// one per session, max one per day, defer overlaps, never mid-task")
/// is a separate orchestrator slice.
struct TutorialsHubView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Layout matches `docs/design/screens-settings.jsx` §ScrTutorialsHub:
        //   - subheading paragraph
        //   - Tour card (single row) SET APART at the top
        //   - "BY FEATURE" section header (uppercase, tracked)
        //   - concept-tutorials card (six rows with dividers)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Short walkthroughs you can replay any time. Opened from the **?** in the toolbar.")
                    .font(.system(size: 13))
                    .foregroundStyle(Crucible.Color.ink3)
                    .lineSpacing(3)
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 14)

                // "Start from the beginning" sits ABOVE the walkthrough card
                // (ruled 2026-08-23): the tour precedes the walkthrough in the
                // product, and it is the answer to "I wasn't sure what was
                // going on" — so it must be reachable from the `?` on any
                // screen, never a one-time-only explanation.
                introTourCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                tourCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                Text("By feature")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 8)

                conceptsCard
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 40)
        }
        .background(Crucible.Color.sunk)
        .navigationTitle("Learn")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The intro tour — the seven-page "what is this" sequence, replayed from
    /// page 1. An ACTION, not a navigation: the root presents it, so this row
    /// asks via `IntroTourReplayBus` and dismisses the hub.
    @ViewBuilder
    private var introTourCard: some View {
        Button {
            IntroTourReplayBus.shared.requestReplay()
            dismiss()
        } label: {
            TutorialsHubRow(entry: TutorialCatalog.introTour)
        }
        .buttonStyle(.plain)
        .background(Crucible.Color.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// The tour row on its own — anchored coachmark walkthrough, set
    /// apart per `Tutorials · triggers spec.md`.
    @ViewBuilder
    private var tourCard: some View {
        // F2b (2026-07-26): "Show me around" is an ACTION, not a navigation —
        // it resets every coachmark's seen flag and re-fires the current tab's
        // coachmark once this hub pops (`HiMemTabView` observes `restorePending`
        // and calls `consumeRestore`). Stateless: always present, never gated
        // on whether coachmarks have been seen, no "seen" checkmark.
        Button {
            // "Show me around" launches the guided walkthrough (F8). The per-tab
            // coachmark cards + their restore were retired 2026-07-27 now that
            // F8 (teach-by-doing) + F7c (section-?) cover the ground. D4: also
            // re-arm the section-? coachmark so it re-teaches alongside the
            // walkthrough — one recoverability entry, not two.
            WalkthroughOrchestrator.shared.start()
            OneShotCoachmark.sectionHelp.rearm()
            OneShotCoachmark.projectsConcept.rearm()
            dismiss()
        } label: {
            TutorialsHubRow(entry: TutorialCatalog.tour)
        }
        .buttonStyle(.plain)
        .background(Crucible.Color.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// The concept tutorials — one card with dividers between rows.
    @ViewBuilder
    private var conceptsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(TutorialCatalog.byFeature.enumerated()), id: \.element.id) { idx, entry in
                NavigationLink {
                    entry.destination
                } label: {
                    TutorialsHubRow(entry: entry)
                }
                .buttonStyle(.plain)
                if idx < TutorialCatalog.byFeature.count - 1 {
                    Divider().background(Crucible.Color.hairline)
                        .padding(.leading, 68)
                }
            }
        }
        .background(Crucible.Color.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// One row in the Tutorials hub. 36×36 rounded-10 tinted square + glyph,
/// title + subtitle, trailing chevron.
private struct TutorialsHubRow: View {
    let entry: TutorialCatalogEntry

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(entry.tint.background)
                    .frame(width: 36, height: 36)
                Image(systemName: entry.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(entry.tint.foreground)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.system(size: 16))
                        .tracking(-0.2)
                        .foregroundStyle(Crucible.Color.ink)
                    if entry.isPlusOnly {
                        Text("Plus")
                            .font(.system(size: 9.5, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(Crucible.Color.aiBlue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Crucible.Color.aiBlue, lineWidth: 1)
                            )
                    }
                }
                Text(entry.subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Crucible.Color.ink3)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink4)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }
}

// MARK: - Catalog

/// The hub catalog — **six rows, ordered per the locked spec**
/// (`docs/design/Tutorials · triggers spec.md` §"The '?' toolbar
/// entry + Tutorials hub"). This is the *complete library* of
/// replayable explainers; it is **not the same set as the auto-fire
/// triggers**. Five tutorials auto-fire (#1 Capture / #2 Organizing /
/// #3 Find the thread / #4 Watch story / #5 Watch discovery). The
/// hub lists six — Topics and Where-your-memories-live are minor
/// enough not to warrant interrupting the user, but useful enough to
/// be lookup-able. The Watch discovery card (#5) auto-fires only and
/// is intentionally not in the hub (by the time a user could replay
/// it, they've already accepted or declined the install).
enum TutorialCatalog {
    /// The tour row — **"Show me around"** (F2b · 2026-07-26). The
    /// recoverability entry for the guided walkthrough: tapping it relaunches
    /// F8 (`WalkthroughOrchestrator.start`) once the hub closes. The per-tab
    /// coachmark cards this originally restored were retired 2026-07-27 (F8 +
    /// F7c cover the ground). The row is an action, not a navigation, so
    /// `destination` is unused.
    /// The seven-page intro tour. Distinct from `tour` below, which relaunches
    /// the do-it-with-me walkthrough — this one explains, that one does.
    static let introTour = TutorialCatalogEntry(
        id: "intro-tour",
        title: "Start from the beginning",
        subtitle: "What HiMem is, in seven pages",
        systemImage: "book.pages",
        tint: .accent,
        isPlusOnly: false,
        destination: AnyView(EmptyView())
    )

    static let tour = TutorialCatalogEntry(
        id: "screen-tour",
        title: "Show me around",
        subtitle: "What each button and area does",
        systemImage: "hand.point.up.left.fill",
        tint: .accent,
        isPlusOnly: false,
        destination: AnyView(EmptyView())
    )

    static let byFeature: [TutorialCatalogEntry] = [
        TutorialCatalogEntry(
            id: "capture",
            title: "Capturing a memory",
            subtitle: "Recording, Next, and your Watch",
            systemImage: "mic",
            tint: .accent,
            isPlusOnly: false,
            destination: AnyView(CaptureTutorialView())
        ),
        TutorialCatalogEntry(
            id: "organize",
            title: "Organizing with AI",
            subtitle: "Draft, review, and keep",
            systemImage: "sparkles",
            tint: .aiBlue,
            isPlusOnly: false,
            destination: AnyView(OrganizingTutorialView())
        ),
        TutorialCatalogEntry(
            id: "projects",
            title: "Projects",
            subtitle: "Group memories and find the thread",
            systemImage: "folder",
            tint: .aiBlue,
            isPlusOnly: true,
            destination: AnyView(FindTheThreadTutorialView())
        ),
        TutorialCatalogEntry(
            id: "topics",
            title: "Topics",
            subtitle: "Your top-level categories",
            systemImage: "circle.fill",
            tint: .accent,
            isPlusOnly: false,
            destination: AnyView(TopicsTutorialView())
        ),
        TutorialCatalogEntry(
            id: "captured-clips",
            title: "Captured Clips",
            subtitle: "From your Watch to a memory",
            systemImage: "applewatch",
            tint: .accent,
            isPlusOnly: false,
            destination: AnyView(WatchStoryTutorialView())
        ),
        TutorialCatalogEntry(
            id: "siri",
            title: "Capturing with Siri",
            subtitle: "Hands-free, before it fades",
            systemImage: "mic.badge.plus",
            tint: .accent,
            isPlusOnly: false,
            destination: AnyView(SiriTutorialView())
        ),
        TutorialCatalogEntry(
            id: "storage",
            title: "Where your memories live",
            subtitle: "Private by default, in your iCloud",
            systemImage: "shield",
            tint: .aiBlue,
            isPlusOnly: false,
            destination: AnyView(StorageTutorialView())
        )
    ]
}

struct TutorialCatalogEntry: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: TutorialTint
    let isPlusOnly: Bool
    let destination: AnyView
}

/// Two-tint scheme: ochre for product features, AI-blue for
/// AI-flavored concepts. Each carries its tinted-square background
/// + glyph foreground.
enum TutorialTint: Hashable {
    case accent
    case aiBlue

    var foreground: Color {
        switch self {
        case .accent: return Crucible.Color.accent
        case .aiBlue: return Crucible.Color.aiBlue
        }
    }

    var background: Color {
        switch self {
        case .accent: return Crucible.Color.accent.opacity(0.15)
        case .aiBlue: return Crucible.Color.aiBlue.opacity(0.15)
        }
    }
}

// MARK: - Shared one-pager scaffold

/// The canonical tutorial layout: × dismiss top-right, eyebrow + optional
/// Plus chip, serif title, intro, 3 points, ochre CTA + optional ghost
/// secondary + footnote. Used by both the replayable hub views (where
/// dismiss = pop) and the in-context first-encounter triggers (where
/// dismiss = mark seen + dismiss sheet).
///
/// Mirrors the `TutorialPage` JSX scaffold from
/// `docs/design/screens-tutorials.jsx`.
struct TutorialPage<CtaGlyph: View>: View {
    let eyebrow: String
    let isPlusOnly: Bool
    let title: String
    let intro: String
    let points: [TutorialPoint]
    let ctaTitle: String
    let ctaGlyph: CtaGlyph
    let onCtaTap: () -> Void
    let secondaryTitle: String?
    let onSecondaryTap: (() -> Void)?
    let footnote: String?
    /// Dismiss handler for the corner × glyph. Pop the navigation stack
    /// in the replayable case; mark-seen + dismiss-sheet in the
    /// trigger case.
    let onDismiss: () -> Void

    init(
        eyebrow: String,
        isPlusOnly: Bool = false,
        title: String,
        intro: String,
        points: [TutorialPoint],
        ctaTitle: String,
        @ViewBuilder ctaGlyph: () -> CtaGlyph = { EmptyView() },
        onCtaTap: @escaping () -> Void,
        secondaryTitle: String? = nil,
        onSecondaryTap: (() -> Void)? = nil,
        footnote: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.eyebrow = eyebrow
        self.isPlusOnly = isPlusOnly
        self.title = title
        self.intro = intro
        self.points = points
        self.ctaTitle = ctaTitle
        self.ctaGlyph = ctaGlyph()
        self.onCtaTap = onCtaTap
        self.secondaryTitle = secondaryTitle
        self.onSecondaryTap = onSecondaryTap
        self.footnote = footnote
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dismissRow
                .padding(.top, 16)
            Spacer().frame(height: 14)
            eyebrowRow
            Text(title)
                .font(.system(size: 28, design: .serif))
                .tracking(-0.5)
                .lineSpacing(2)
                .foregroundStyle(Crucible.Color.ink)
                .padding(.top, 8)
            Text(intro)
                .font(.system(size: 14))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(3)
                .padding(.top, 10)
                .padding(.bottom, 26)
            VStack(alignment: .leading, spacing: 20) {
                ForEach(points) { TutorialPointRow(point: $0) }
            }
            Spacer(minLength: 20)
            ctaStack
                .padding(.bottom, 30)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Crucible.Color.paper)
    }

    @ViewBuilder
    private var dismissRow: some View {
        HStack {
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(width: 30, height: 30)
                    .background(Crucible.Color.sunk)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss tutorial")
        }
    }

    @ViewBuilder
    private var eyebrowRow: some View {
        HStack(spacing: 9) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Crucible.Color.ink3)
            if isPlusOnly {
                Text("Plus")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Crucible.Color.aiBlue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Crucible.Color.aiBlue.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Crucible.Color.aiBlue, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private var ctaStack: some View {
        VStack(spacing: 8) {
            Button(action: onCtaTap) {
                HStack(spacing: 9) {
                    ctaGlyph
                    Text(ctaTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.2)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Crucible.Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ctaTitle)

            if let secondaryTitle, let onSecondaryTap {
                Button(action: onSecondaryTap) {
                    Text(secondaryTitle)
                        .font(.system(size: 15.5, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Crucible.Color.ink2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .multilineTextAlignment(.center)
                    .lineSpacing(1)
                    .padding(.top, 2)
            }
        }
    }
}

/// One teaching point. 40×40 rounded-11 tinted square + glyph, title
/// + body. The glyph is either an SF Symbol (used by every tutorial)
/// or an ochre numeral (used by the Watch-discovery manual fallback's
/// numbered steps per `docs/design/screens-tutorials.jsx` §5b).
/// Tint splits by tone — ochre for product features, AI-blue for
/// AI-flavored or cross-surface concepts.
struct TutorialPoint: Identifiable {
    let id = UUID()
    let glyph: Glyph
    let tint: TutorialTint
    let title: String
    let body: String

    enum Glyph: Equatable {
        case symbol(String)
        case number(Int)
    }

    init(systemImage: String, tint: TutorialTint, title: String, body: String) {
        self.glyph = .symbol(systemImage)
        self.tint = tint
        self.title = title
        self.body = body
    }

    init(number: Int, tint: TutorialTint, title: String, body: String) {
        self.glyph = .number(number)
        self.tint = tint
        self.title = title
        self.body = body
    }
}

private struct TutorialPointRow: View {
    let point: TutorialPoint
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(point.tint.background)
                    .frame(width: 40, height: 40)
                switch point.glyph {
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(point.tint.foreground)
                case .number(let n):
                    Text("\(n)")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(point.tint.foreground)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(point.title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Crucible.Color.ink)
                Text(point.body)
                    .font(.system(size: 13))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(3)
            }
        }
    }
}

// MARK: - The five concrete tutorials

/// Tutorial #1 — Capture · Next · Watch. The third point is
/// conditional per spec §"Coverage / edge cases": when no watch is
/// paired, soften the Watch advice to "If you have an Apple Watch…"
/// rather than advertising a surface the user can't use.
struct CaptureTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        TutorialPage(
            eyebrow: "Capturing a memory",
            title: "Just start talking.",
            intro: "HiMem listens, transcribes, and keeps it — no buttons to fumble while a thought is fresh.",
            points: [
                TutorialPoint(systemImage: "mic", tint: .accent,
                              title: "Speak, and it's saved",
                              body: "Tap record and talk. The audio stays on your device; the words become a searchable memory."),
                TutorialPoint(systemImage: "arrow.forward.to.line", tint: .accent,
                              title: "On a roll? Tap Next",
                              body: "Next saves the current clip and starts a fresh one without stopping — they group into one memory. Great for a list of thoughts."),
                Self.watchPoint()
            ],
            ctaTitle: "Got it",
            onCtaTap: { dismiss() },
            footnote: "Replay any time from the ? in the toolbar.",
            onDismiss: { dismiss() }
        )
        .navigationBarHidden(true)
    }

    /// Returns the third (Watch) teaching point with content varied
    /// by WCSession pairing state. Read at body evaluation — the
    /// pairing state rarely changes mid-session so a one-shot read
    /// is fine.
    private static func watchPoint() -> TutorialPoint {
        let paired = WCSession.isSupported() && WCSession.default.isPaired
        if paired {
            return TutorialPoint(
                systemImage: "applewatch", tint: .aiBlue,
                title: "Your Watch records too",
                body: "Catch a thought on your Apple Watch and it syncs here automatically. No phone needed in the moment."
            )
        } else {
            return TutorialPoint(
                systemImage: "applewatch", tint: .aiBlue,
                title: "If you have an Apple Watch",
                body: "HiMem records on the Watch too. Pair one and quick thoughts sync to your phone on their own — no phone needed in the moment."
            )
        }
    }
}

/// Tutorial #2 — Organizing with AI. The mental model: AI drafts,
/// you're the editor, editing never un-organizes.
struct OrganizingTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        TutorialPage(
            eyebrow: "Organizing with AI",
            title: "A first draft, from your clips.",
            intro: "When you ask, HiMem drafts the details so a memory is easy to find later — but you stay the editor.",
            points: [
                TutorialPoint(systemImage: "sparkles", tint: .aiBlue,
                              title: "AI drafts the details",
                              body: "A title, a short summary, and a topic or two — drafted right on your device. Free organizes when you tap; Plus does it for you."),
                TutorialPoint(systemImage: "eye", tint: .aiBlue,
                              title: "Give it a glance",
                              body: "It opens as a draft — keep it as is, or fix anything that doesn't sound like you. Nothing is final until you say so."),
                TutorialPoint(systemImage: "pencil", tint: .accent,
                              title: "It stays yours",
                              body: "Edit a title or summary any time. Fixing a detail is an improvement — it never un-organizes the memory.")
            ],
            ctaTitle: "Got it",
            onCtaTap: { dismiss() },
            footnote: "Replay from the ? in the toolbar.",
            onDismiss: { dismiss() }
        )
        .navigationBarHidden(true)
    }
}

/// Tutorial #3 — Find the thread (Plus). Project synthesis + suggested
/// memories, you decide nothing auto-adds.
struct FindTheThreadTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        TutorialPage(
            eyebrow: "Projects",
            isPlusOnly: true,
            title: "Find the thread.",
            intro: "A project is a place for related memories. Find the thread reads across them and pulls out what connects.",
            points: [
                TutorialPoint(systemImage: "text.alignleft", tint: .aiBlue,
                              title: "One thread across the project",
                              body: "A short, honest summary of what these memories are really about — in second person, in your voice."),
                TutorialPoint(systemImage: "list.bullet", tint: .aiBlue,
                              title: "Memories that may belong",
                              body: "It also surfaces memories from elsewhere in your library that look like they fit — \"8 may belong here.\""),
                TutorialPoint(systemImage: "hand.tap", tint: .accent,
                              title: "You decide",
                              body: "Suggestions are proposals. Nothing is added until you pick it. Run it again whenever the project grows.")
            ],
            ctaTitle: "Got it",
            onCtaTap: { dismiss() },
            footnote: "A Plus feature. Replay from the ? in the toolbar.",
            onDismiss: { dismiss() }
        )
        .navigationBarHidden(true)
    }
}

/// Tutorial #4 — Captured Clips · the Watch story. Usage-oriented:
/// what to do with clips that have arrived.
struct WatchStoryTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        TutorialPage(
            eyebrow: "From your Watch",
            title: "Catch it on your wrist.",
            intro: "Your Apple Watch is a capture queue — record a thought anywhere, sort it out on your phone later.",
            points: [
                TutorialPoint(systemImage: "applewatch", tint: .accent,
                              title: "Record, hands-free",
                              body: "Raise your wrist and talk. The Watch captures audio only — no screen to manage, nothing to organize in the moment."),
                TutorialPoint(systemImage: "arrow.triangle.2.circlepath", tint: .aiBlue,
                              title: "It syncs to your phone",
                              body: "Clips land in Captured Clips on your iPhone and are transcribed there. Your Watch never holds your library — just the latest clips."),
                TutorialPoint(systemImage: "square.stack.3d.up", tint: .accent,
                              title: "Bundle into a memory",
                              body: "Review the session and turn it into a new memory, or add it to one you're already building. A roll of clips becomes one memory.")
            ],
            ctaTitle: "Got it",
            onCtaTap: { dismiss() },
            footnote: "Replay from the ? in the toolbar.",
            onDismiss: { dismiss() }
        )
        .navigationBarHidden(true)
    }
}

/// Tutorial #5 — Watch discovery. Two-step flow per
/// `docs/design/screens-tutorials.jsx` §5 + §5b.
///
/// **Step .discovery** is the entry card explaining what HiMem on
/// the Watch does for the user. CTA "Show me how" transitions to
/// `.manual`.
///
/// **Step .manual** is the written-instructions page — three
/// numbered steps the user follows by hand. CTA "Got it" dismisses.
///
/// **Why no deep-link.** Earlier builds attempted the undocumented
/// `x-apple-watch://` scheme on the CTA. Apple has progressively
/// locked down internal URL schemes; on shipping iOS the open call
/// no longer launches the Watch companion app — TestFlight
/// 2026-06-12 confirmed this. There is no public API to deep-link
/// the Watch app, so we stopped pretending and made the CTAs say
/// what they actually do.
///
/// Triggered app-side from `JournalView.attemptWatchDiscoveryTutorial`
/// when `WCSession.isPaired && !isWatchAppInstalled` and the
/// orchestrator's gates pass.
struct WatchDiscoveryTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .discovery

    private enum Step { case discovery, manual }

    var body: some View {
        Group {
            switch step {
            case .discovery: discoveryPage
            case .manual:    manualPage
            }
        }
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private var discoveryPage: some View {
        TutorialPage(
            eyebrow: "Your Apple Watch",
            title: "Capture on your wrist.",
            intro: "You have an Apple Watch — HiMem can record there too, so a thought never has to wait for your phone.",
            points: [
                TutorialPoint(systemImage: "applewatch", tint: .accent,
                              title: "Raise and talk",
                              body: "Record a thought hands-free, even when your phone isn't nearby. Audio only — nothing to manage in the moment."),
                TutorialPoint(systemImage: "arrow.triangle.2.circlepath", tint: .aiBlue,
                              title: "It shows up here",
                              body: "Clips sync to your iPhone on their own and land in Captured Clips, ready to become memories.")
            ],
            ctaTitle: "Show me how",
            ctaGlyph: {
                Image(systemName: "applewatch")
                    .font(.system(size: 14, weight: .semibold))
            },
            onCtaTap: { step = .manual },
            secondaryTitle: "Later",
            onSecondaryTap: { dismiss() },
            footnote: "Shown because your Apple Watch is paired, but HiMem isn't on it yet.",
            onDismiss: { dismiss() }
        )
    }

    @ViewBuilder
    private var manualPage: some View {
        TutorialPage(
            eyebrow: "Add HiMem to your Watch",
            title: "A couple of taps in the Watch app.",
            intro: "About thirty seconds. The Watch app is on your iPhone — same one you used to pair your watch.",
            points: [
                TutorialPoint(number: 1, tint: .accent,
                              title: "Open the Watch app",
                              body: "On your iPhone home screen, find the app named Watch — it comes with every iPhone."),
                TutorialPoint(number: 2, tint: .accent,
                              title: "Find \"Available Apps\"",
                              body: "In the My Watch tab, scroll to the bottom to the Available Apps section."),
                TutorialPoint(number: 3, tint: .accent,
                              title: "Tap Install next to HiMem",
                              body: "It lands on your wrist in a few moments. Then just raise and talk.")
            ],
            ctaTitle: "Got it",
            ctaGlyph: { EmptyView() },
            onCtaTap: { dismiss() },
            secondaryTitle: nil,
            onSecondaryTap: nil,
            footnote: "Don't see Available Apps? Your Watch may still be syncing — try again in a minute.",
            onDismiss: { dismiss() }
        )
    }
}

/// Catalog-only — Topics. Never auto-fires; explains what topics are
/// and how the user shapes them. Listed in the hub because the
/// concept is minor enough not to warrant interrupting the user but
/// useful enough to be lookup-able.
struct TopicsTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        TutorialPage(
            eyebrow: "Topics",
            title: "Your top-level categories.",
            intro: "Topics are the broad buckets at the top of your library — the things you keep coming back to.",
            points: [
                TutorialPoint(systemImage: "circle.fill", tint: .accent,
                              title: "One per memory",
                              body: "Each memory gets a single topic — the one that best fits. AI suggests one when it organizes; you can swap it any time."),
                TutorialPoint(systemImage: "sparkles", tint: .aiBlue,
                              title: "AI proposes, you approve",
                              body: "When the AI sees a new theme it asks before adding a topic to your palette. Nothing lands without you saying yes."),
                TutorialPoint(systemImage: "paintpalette", tint: .accent,
                              title: "Rename or recolor any time",
                              body: "Edit a topic in Settings — every memory in that topic updates with it. Topics are a living index, not a label gun.")
            ],
            ctaTitle: "Got it",
            onCtaTap: { dismiss() },
            footnote: "Replay from the ? in the toolbar.",
            onDismiss: { dismiss() }
        )
        .navigationBarHidden(true)
    }
}

/// Tutorial #6 — Capturing with Siri. Discovery-triggered per
/// `Tutorials · triggers spec.md` (July 5 2026): auto-fires once on
/// Today after `memoryCount >= 3` so the faster path only surfaces
/// after the capture habit is established. Both phrases are All-tier;
/// Plus adds background auto-organize (mentioned inline in the third
/// point). Also replayable from the Learn hub.
struct SiriTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        TutorialPage(
            eyebrow: "Capturing with Siri",
            title: "Hands-free, before it fades.",
            intro: "Two phrases keep HiMem within reach when your hands aren't — a thought that has to wait for the app is a thought that fades.",
            points: [
                TutorialPoint(systemImage: "mic.badge.plus", tint: .accent,
                              title: "\u{201C}Record in HiMem\u{201D}",
                              body: "Opens HiMem and starts recording right away. Best for a longer thought — talk as long as you need."),
                TutorialPoint(systemImage: "text.bubble", tint: .accent,
                              title: "\u{201C}Capture in HiMem\u{2026}\u{201D}",
                              body: "Dictate a short thought straight to Siri — never opens the app. Good for a one-liner while you're on the move."),
                TutorialPoint(systemImage: "sparkles", tint: .aiBlue,
                              title: "Plus organizes it in the background",
                              body: "On Plus, dictated notes get a title, summary, and topics drafted automatically. Free keeps them as raw notes until you tap Organize.")
            ],
            ctaTitle: "Got it",
            onCtaTap: { dismiss() },
            footnote: "Replay from the ? in the toolbar.",
            onDismiss: { dismiss() }
        )
        .navigationBarHidden(true)
    }
}

/// Catalog-only — Where your memories live. Never auto-fires; the
/// data-custody explainer for users who want to know where their
/// content actually lives. Mirrors the locked CLAUDE.md § Data
/// custody language.
struct StorageTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        TutorialPage(
            eyebrow: "Where your memories live",
            title: "Private by default.",
            intro: "Your memories are yours. They live in your iCloud — not on our servers.",
            points: [
                TutorialPoint(systemImage: "cloud", tint: .aiBlue,
                              title: "Your iCloud, not ours",
                              body: "Transcripts, titles, summaries, topics, and projects sync via your private iCloud. We never see your content."),
                TutorialPoint(systemImage: "folder", tint: .accent,
                              title: "Audio and photos in Files",
                              body: "Original recordings and media live in a HiMem folder in iCloud Drive — visible in the Files app, exportable anywhere."),
                TutorialPoint(systemImage: "arrow.down.circle", tint: .aiBlue,
                              title: "Survives reinstall",
                              body: "Delete the app and reinstall — your memories come back from iCloud, audio included. They live in your iCloud, not in HiMem.")
            ],
            ctaTitle: "Got it",
            onCtaTap: { dismiss() },
            footnote: "Replay from the ? in the toolbar.",
            onDismiss: { dismiss() }
        )
        .navigationBarHidden(true)
    }
}
