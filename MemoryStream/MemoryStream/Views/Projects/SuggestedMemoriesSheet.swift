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
    /// Default selected — bias toward accepting the AI's surfaced
    /// memories. Tap a row to deselect; tap again to reselect.
    @State private var selected: Set<UUID>

    struct Suggestion: Identifiable {
        let id: UUID
        let title: String
        let createdAt: Date
        let rationale: String
        let confidence: Confidence

        enum Confidence {
            case likely
            case maybe

            var label: String {
                switch self {
                case .likely: return "LIKELY MATCH"
                case .maybe:  return "MAYBE"
                }
            }

            var dotColor: Color {
                switch self {
                case .likely: return Color(red: 0x3F/255, green: 0xA8/255, blue: 0x77/255)
                case .maybe:  return Crucible.Color.warning
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
        // Default-select everything — see Suggestion docs above.
        self._selected = State(initialValue: Set(suggestions.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow

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
                    Button("Add \(selected.count)") {
                        onCommit(selected)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(selected.isEmpty ? Crucible.Color.ink3 : Crucible.Color.aiBlue)
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
        "Suggestions are proposals. Nothing gets added until you tap Add \(selected.count)."
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
                    Text(s.rationale)
                        .font(.system(size: 12.5, design: .serif).italic())
                        .foregroundStyle(Crucible.Color.ink2)
                        .lineSpacing(2)
                        .padding(.top, 7)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(s.confidence.dotColor)
                            .frame(width: 6, height: 6)
                        Text(s.confidence.label)
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(Crucible.Color.ink3)
                    }
                    .padding(.top, 9)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
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
