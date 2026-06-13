import SwiftUI

/// Projects MVP screen 5 — the review sheet for AI-suggested memories
/// that may belong to a project. Pixel rules locked in the design's
/// row-spec section (decoded 2026-05-19). Selection is a ring; the
/// only feedback is the ring filling. Rows stack with a 1px ink
/// divider, **not** as cards.
///
/// One assist on the project ran the server-side re-rank that
/// produced these `Suggestion` rows; the sheet itself is read-only
/// review + selection + commit (Add N).
struct SuggestedMemoriesSheet: View {
    let projectName: String
    let suggestions: [Suggestion]
    let onCommit: (_ acceptedIDs: Set<UUID>) -> Void
    @Environment(\.dismiss) private var dismiss
    /// Empty by default — the user makes a deliberate choice. A
    /// "Select all" / "Select none" toggle in the selection toolbar
    /// (between the eyebrow and the rows) flips everything at once.
    /// Spec update June 10 2026: review is an active read, not a
    /// gentle nudge to accept-all.
    @State private var selected: Set<UUID>

    struct Suggestion: Identifiable {
        let id: UUID
        let title: String
        let createdAt: Date
        let rationale: String
        let confidence: Confidence

        enum Confidence: Equatable {
            case likely
            case maybe

            var label: String {
                switch self {
                case .likely: return "LIKELY MATCH"
                case .maybe:  return "MAYBE MATCH"
                }
            }
        }
    }

    init(
        projectName: String,
        suggestions: [Suggestion],
        onCommit: @escaping (Set<UUID>) -> Void
    ) {
        self.projectName = projectName
        self.suggestions = suggestions
        self.onCommit = onCommit
        // None selected by default — see `selected` docs above.
        self._selected = State(initialValue: [])
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow

                selectionToolbar

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { idx, suggestion in
                            row(suggestion)
                            if idx < suggestions.count - 1 {
                                Divider().background(Crucible.Color.hairline)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                bottomDisclaimer
            }
            .background(Crucible.Color.paper)
            .navigationTitle("Suggested")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Crucible.Color.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Add = user-commit action → ochre per the colour
                    // code lock. The AI ran already; committing the
                    // selection is *you* acting, not the AI. Label is
                    // plain "Add" (not "Add N") per the June 10 spec
                    // update — the selection-toolbar row carries the
                    // count, so the button doesn't need to repeat it.
                    Button("Add") {
                        onCommit(selected)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(selected.isEmpty ? Crucible.Color.ink3 : Crucible.Color.accent)
                    .disabled(selected.isEmpty)
                }
            }
        }
        // Tall sheet — the review surface is where the user reads
        // serif italic rationales, so it earns the room. Matches the
        // `Sheet height="88%"` in `ScrSuggestionsReview`.
        .presentationDetents([.fraction(0.88), .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var eyebrow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .semibold))
                Text("FROM YOUR MEMORIES")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
            }
            .foregroundStyle(Crucible.Color.aiBlue)

            // Serif headline with the project name italicized. Voice
            // softens into reflective register at the review sheet —
            // matches the `ScrSuggestionsReview` JSX exactly.
            (Text(headlinePrefix)
             + Text(projectName).italic()
             + Text("."))
                .font(.system(size: 17, design: .serif))
                .tracking(-0.2)
                .foregroundStyle(Crucible.Color.ink)
                .lineSpacing(2)

            Text("HiMem found these by looking at topics, mentions, and dates — not by reading every word. Add the ones that fit; skip the rest.")
                .font(.system(size: 12.5))
                .foregroundStyle(Crucible.Color.ink3)
                .lineSpacing(2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    /// Prefix that precedes the italicized project name. Three
    /// branches keep the demonstrative and verb grammatically
    /// consistent with the number of suggestions.
    private var headlinePrefix: String {
        let n = suggestions.count
        switch n {
        case 1: return "This one may belong in "
        case 2: return "These two may belong in "
        case 3: return "These three may belong in "
        default: return "These \(n) may belong in "
        }
    }

    /// Row between the eyebrow and the rows: live count on the left,
    /// a `Select all` / `Select none` toggle on the right. The toggle
    /// is ochre (user action — "you act"), not blue. Flips its label
    /// based on whether the user has already accepted everything.
    @ViewBuilder
    private var selectionToolbar: some View {
        let total = suggestions.count
        let count = selected.count
        let countLabel: String = {
            let suggestionsLabel = "\(total) suggestion\(total == 1 ? "" : "s")"
            if count == 0 {
                return "\(suggestionsLabel) · none selected"
            } else if count == total {
                return "\(suggestionsLabel) · all selected"
            } else {
                return "\(suggestionsLabel) · \(count) selected"
            }
        }()
        let allSelected = (count == total && total > 0)

        HStack(spacing: 8) {
            Text(countLabel)
                .font(.system(size: 12))
                .foregroundStyle(Crucible.Color.ink3)
            Spacer(minLength: 8)
            Button {
                if allSelected {
                    selected.removeAll()
                } else {
                    selected = Set(suggestions.map(\.id))
                }
            } label: {
                Text(allSelected ? "Select none" : "Select all")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(Crucible.Color.accent)
                    .frame(minHeight: 40)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(allSelected ? "Deselect all suggestions" : "Select all suggestions")
            .disabled(total == 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var bottomDisclaimer: some View {
        VStack(spacing: 0) {
            Divider().background(Crucible.Color.hairline)
            // "Nothing gets added until you tap Add N" — the no-auto-
            // add promise the user makes with themselves. Same voice
            // as the spec's `borderTop` block.
            Text(disclaimerString)
                .font(.system(size: 11))
                .foregroundStyle(Crucible.Color.ink3)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity)
        }
    }

    private var disclaimerString: String {
        "Suggestions are proposals. Nothing gets added until you tap Add."
    }

    /// One row. Pixel rules from row spec:
    ///   - Ring 22×22, 1.5px border, ink4 unselected → aiBlue fill +
    ///     white check selected.
    ///   - Title SF Pro 14.5 weight 600 tracking -0.1.
    ///   - Date SF Pro 11 ink3 tabular-nums.
    ///   - Why Source Serif 4 12.5/1.45 italic ink2.
    ///   - Confidence band: 6×6 dot + 11px uppercase tracking 1.4.
    @ViewBuilder
    private func row(_ s: Suggestion) -> some View {
        let isSelected = selected.contains(s.id)
        Button {
            if isSelected { selected.remove(s.id) } else { selected.insert(s.id) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ring(isSelected: isSelected)
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .tracking(-0.1)
                        .foregroundStyle(Crucible.Color.ink)
                        .multilineTextAlignment(.leading)
                    Text(Self.dateLabel(s.createdAt))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Crucible.Color.ink3)
                        .padding(.top, 3)
                    // "why" line — AI attribution → AI blue serif
                    // italic (Projects "AI blue, always" lock).
                    Text(s.rationale)
                        .font(.system(size: 12.5, design: .serif).italic())
                        .foregroundStyle(Crucible.Color.aiBlue)
                        .lineSpacing(2)
                        .padding(.top, 7)
                    // Confidence chip — AI blue per same lock; Likely
                    // = filled dot, Maybe = hollow dot. Form (fill vs
                    // outline) carries the distinction; colour is
                    // constant so it always reads as AI attribution.
                    HStack(spacing: 5) {
                        confidenceDot(for: s.confidence)
                        Text(s.confidence.label)
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(Crucible.Color.aiBlue)
                    }
                    .padding(.top, 9)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    /// Confidence dot shape: Likely = filled AI-blue, Maybe = hollow
    /// AI-blue outline. Same colour either way so the chip always
    /// reads as AI attribution; form carries the strength signal.
    @ViewBuilder
    private func confidenceDot(for confidence: Suggestion.Confidence) -> some View {
        let likely = (confidence == .likely)
        ZStack {
            Circle()
                .strokeBorder(Crucible.Color.aiBlue, lineWidth: 1.5)
                .frame(width: 7, height: 7)
            if likely {
                Circle()
                    .fill(Crucible.Color.aiBlue)
                    .frame(width: 7, height: 7)
            }
        }
    }

    @ViewBuilder
    private func ring(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? Crucible.Color.aiBlue : Crucible.Color.ink4, lineWidth: 1.5)
                .background(
                    Circle()
                        .fill(isSelected ? Crucible.Color.aiBlue : Color.clear)
                )
                .frame(width: 22, height: 22)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, 1)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f
    }()

    static func dateLabel(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
