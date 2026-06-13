import SwiftUI

/// One topic, four states. The visual contract from
/// `docs/design/screens-topics.jsx`'s `TopicChip` JSX component,
/// rendered in Swift.
///
/// Used by three surfaces — the spec's three topic moments:
/// - **DraftReviewSheet** — assigned topics (`.set`) and AI-suggested
///   new ones (`.new`) in the first-organize review.
/// - **EntryExpandedView's topic row** — `.set` chips under the
///   summary on every memory.
/// - **ManageTopicsSheet** — `.pick` for the user's current selection
///   and `.off` for the rest of the palette.
///
/// Tap behavior is owned by the host (`onTap` closure). When `onTap`
/// is `nil`, the chip is a plain `View`; when present, it's a `Button`
/// for accessibility — the host gets a single source of truth for
/// what tap means in its context (drop a NEW, pick from palette, etc.).
///
/// Color rule lock: ochre is user-owned organization (the dot for
/// `.set` / `.pick`); AI-blue is reserved for the NEW flag only
/// (the sparkle + NEW label + dashed border). The `.off` chip uses
/// hairline + ink3/ink4 — selectable but not selected.
struct TopicChip: View {
    enum State: Equatable {
        /// Assigned to the memory. Ochre dot, wash background. Read-only
        /// in the chip itself; an enclosing Edit affordance manages.
        case set
        /// AI-suggested at draft-review time, not yet in the palette.
        /// Sparkle glyph + NEW label, AI-blue dashed border. The host
        /// taps it to drop before commit.
        case new
        /// Currently selected in the Manage sheet's "On this memory"
        /// row. Same dot/wash as `.set` plus a **selection ring**
        /// (solid ochre border at 1.5pt). Per `docs/design/CLAUDE.md`
        /// June 8 lock: selection = ring; completion = check. Don't
        /// conflate.
        case pick
        /// Selectable but unselected in the Manage sheet's "From your
        /// library" row. Hairline outline, no fill, muted ink4 dot.
        case off
    }

    /// Two-tier sizing per H1 of the June 8 punch-list answer:
    /// **manage/act surfaces** use `.standard` (the chip is the
    /// thing you're aiming at), **dense/scan surfaces** use
    /// `.compact` (memory cards, filter bars — chips are skimmed
    /// past, the visible 28pt + row gap clears the 38pt-with-gap
    /// allowance).
    enum Size: Equatable {
        /// Manage/act surfaces — Memory Detail topic row, Manage
        /// Topics sheet, Draft review topics row. 44pt body, the
        /// strict hit-target floor for the chip itself.
        case standard
        /// Dense/scan surfaces — Memory cards on Memories list,
        /// filter bars. 28pt body; caller must guarantee a ≥10pt
        /// row gap so the tap zone clears 38pt.
        case compact

        var verticalPadding: CGFloat {
            switch self {
            case .standard: return 11
            case .compact:  return 6
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .standard: return 12
            case .compact:  return 10
            }
        }

        var minHeight: CGFloat {
            switch self {
            case .standard: return 44
            case .compact:  return 28
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .standard: return 18
            case .compact:  return 12
            }
        }

        var labelFontSize: CGFloat {
            switch self {
            case .standard: return 13.5
            case .compact:  return 12
            }
        }

        var dotSize: CGFloat {
            switch self {
            case .standard: return 7
            case .compact:  return 6
            }
        }
    }

    let label: String
    let state: State
    var size: Size = .standard
    /// Set false on filter pills that represent "no filter" / a
    /// scope toggle (`All`) — per H2 the leading dot encodes
    /// "palette topic"; a scope selector isn't a topic and has no
    /// dot. Defaults to true (chips with a dot, the normal case).
    var showsLeadingDot: Bool = true
    /// Optional override for the leading-dot color. When nil, the
    /// chip uses the standard ochre-for-set rule. Surfaces that
    /// show multiple chips side-by-side (memory cards, filter
    /// bars) override this with each topic's per-palette hue so
    /// the user can tell them apart at a glance. The Memory
    /// Detail topic row and Manage Topics sheet leave this nil
    /// and read ochre — single-color suits a focused surface.
    var dotColor: Color? = nil
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let onTap {
            Button(action: onTap) { chip }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
        } else {
            chip.accessibilityLabel(accessibilityLabel)
        }
    }

    // MARK: - Chip rendering

    private var chip: some View {
        HStack(spacing: 6) {
            if showsLeadingDot {
                leadingGlyph
            }
            Text(label)
                .font(.system(size: size.labelFontSize, weight: .medium))
                .foregroundStyle(textColor)
            if state == .new {
                Text("NEW")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Crucible.Color.aiBlue)
                    .padding(.leading, 1)
            }
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .frame(minHeight: size.minHeight)
        .background(backgroundFill)
        .overlay(border)
        .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius))
    }

    // MARK: - Per-state visual

    @ViewBuilder
    private var leadingGlyph: some View {
        switch state {
        case .new:
            // ✦ Sparkle — the AI moment. SF Symbol is `sparkle` (the
            // single-star one, not `sparkles` which is the multi-star
            // variant Crucible uses elsewhere for celebration moments).
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Crucible.Color.aiBlue)
        case .set, .pick:
            Circle()
                .fill(dotColor ?? Crucible.Color.accent)
                .frame(width: size.dotSize, height: size.dotSize)
        case .off:
            Circle()
                .fill(dotColor ?? Crucible.Color.ink4)
                .frame(width: size.dotSize, height: size.dotSize)
        }
    }

    private var textColor: Color {
        switch state {
        case .new:        return Crucible.Color.aiBlue
        case .set, .pick: return Crucible.Color.ink
        case .off:        return Crucible.Color.ink3
        }
    }

    private var backgroundFill: Color {
        switch state {
        case .new:        return Crucible.Color.aiBlueTint
        case .set, .pick: return Crucible.Color.wash1
        case .off:        return .clear
        }
    }

    @ViewBuilder
    private var border: some View {
        switch state {
        case .new:
            // Dashed AI-blue border — "add / incomplete / provisional"
            // per the June 8 affordance lock.
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .strokeBorder(Crucible.Color.aiBlue, style: StrokeStyle(lineWidth: 1, dash: [3.5, 2.5]))
        case .off:
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .strokeBorder(Crucible.Color.hairline, lineWidth: 1)
        case .pick:
            // **Selection ring** — solid ochre border at 1.5pt, the
            // Crucible-locked signal for "this is currently
            // selected." Replaces the trailing checkmark this state
            // used pre-June-8.
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .strokeBorder(Crucible.Color.accent, lineWidth: 1.5)
        case .set:
            EmptyView()
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        switch state {
        case .set:  return "Topic: \(label)"
        case .new:  return "New topic suggestion: \(label). Tap to remove."
        case .pick: return "\(label), selected. Tap to remove."
        case .off:  return "\(label). Tap to add."
        }
    }
}
