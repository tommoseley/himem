import WidgetKit
import SwiftUI

/// One snapshot of complication state. Read from the App Group's shared
/// UserDefaults; refreshed on writes via the watch app's
/// WidgetTimelineRefresher and on a 5-minute periodic poll otherwise.
struct ComplicationEntry: TimelineEntry {
    let date: Date
    let pendingCount: Int
    let isRecording: Bool
}

/// Provides the complication's timeline. Reads the watch app's shared
/// state (pending count + recording flag) and emits a single entry —
/// WidgetKit re-invokes this when the watch app calls
/// `WidgetCenter.shared.reloadAllTimelines()` after a write, so we don't
/// need to bake future entries.
struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), pendingCount: 0, isRecording: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let entry = currentEntry()
        // When pending > 0 we keep a 5-minute periodic refresh so the
        // count stays fresh even if a write notification was missed.
        // When idle we let WidgetKit hold the entry indefinitely; the
        // watch app calls reloadAllTimelines() the moment something
        // changes.
        let policy: TimelineReloadPolicy = entry.pendingCount > 0
            ? .after(Date().addingTimeInterval(5 * 60))
            : .never
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func currentEntry() -> ComplicationEntry {
        ComplicationEntry(
            date: Date(),
            pendingCount: WatchSharedState.pendingCount,
            isRecording: WatchSharedState.isRecording
        )
    }
}

/// The HiMem complication. Single Widget definition supporting all four
/// modern WidgetKit families on watchOS 10+; the system picks the
/// rendering per face slot.
///
/// Tap behaviour: `widgetURL` fires `himem://record`; the watch app's
/// root view consumes the URL via `.onOpenURL` and routes to the
/// recording surface (or starts recording immediately, per the user's
/// setting).
struct HimemComplication: Widget {
    let kind: String = "com.himem.app.watchkitapp.complication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
                .widgetURL(URL(string: "himem://record"))
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("HiMem Recorder")
        .description("Tap to record a voice clip. Shows pending sync count.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

/// Renders the complication. Switches on `widgetFamily` to produce the
/// right shape for whatever face slot the user has placed it in. All
/// shapes share the same source-of-truth state (pending count + recording
/// flag) and the same ochre/glyph styling.
struct ComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: ComplicationEntry

    private static let ochre = Color(red: 0xC6/255, green: 0x4A/255, blue: 0x1C/255)
    private static let recordingRed = Color(red: 0xFF/255, green: 0x5A/255, blue: 0x3C/255)

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularBody
        case .accessoryCorner:
            cornerBody
        case .accessoryRectangular:
            rectangularBody
        case .accessoryInline:
            inlineBody
        default:
            circularBody
        }
    }

    // MARK: - Circular (primary)
    /// Mic glyph centered. Ochre count badge pinned top-trailing when
    /// pending > 0. Recording state replaces the glyph with a pulsing red
    /// dot.
    private var circularBody: some View {
        ZStack {
            if entry.isRecording {
                Circle()
                    .fill(Self.recordingRed.opacity(0.8))
                    .frame(width: 22, height: 22)
            } else {
                micGlyph(size: 22, color: Self.ochre)
            }
            if entry.pendingCount > 0 {
                Text(countLabel)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Self.ochre))
                    .offset(x: 12, y: -12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Corner
    /// Mic glyph alone. Corner complications don't have room for the
    /// count badge; the design says glyph-only here.
    private var cornerBody: some View {
        micGlyph(size: 22, color: Self.ochre)
            .widgetLabel {
                if entry.pendingCount > 0 {
                    Text("\(entry.pendingCount) pending")
                }
            }
    }

    // MARK: - Rectangular
    /// Two-line: title + status. "Tap to record" / "N pending" (or
    /// "All synced").
    private var rectangularBody: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Self.ochre).frame(width: 24, height: 24)
                micGlyph(size: 12, color: .white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.isRecording ? "Recording…" : "Tap to record")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Inline
    /// Single short line of text. Used for system-chosen contextual
    /// surfaces. Glyph-as-image isn't supported here; inline is text-only.
    private var inlineBody: some View {
        if entry.isRecording {
            Text("Recording")
        } else if entry.pendingCount > 0 {
            Text("HiMem · \(countLabel) pending")
        } else {
            Text("HiMem · Tap to record")
        }
    }

    // MARK: - Helpers

    /// Mic glyph drawn as SF Symbol. Modern watchOS prefers SF Symbols
    /// for complications — they handle tinting and accessibility for us.
    private func micGlyph(size: CGFloat, color: Color) -> some View {
        Image(systemName: "mic.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
    }

    /// "9+" beyond 9, per the spec.
    private var countLabel: String {
        entry.pendingCount > 9 ? "9+" : "\(entry.pendingCount)"
    }

    private var statusLine: String {
        if entry.isRecording { return "HiMem is recording" }
        if entry.pendingCount > 0 { return "\(countLabel) pending" }
        return "All synced"
    }
}

// MARK: - Previews

#Preview(as: .accessoryCircular) {
    HimemComplication()
} timeline: {
    ComplicationEntry(date: .now, pendingCount: 0, isRecording: false)
    ComplicationEntry(date: .now, pendingCount: 2, isRecording: false)
    ComplicationEntry(date: .now, pendingCount: 12, isRecording: false)
    ComplicationEntry(date: .now, pendingCount: 0, isRecording: true)
}

#Preview(as: .accessoryRectangular) {
    HimemComplication()
} timeline: {
    ComplicationEntry(date: .now, pendingCount: 0, isRecording: false)
    ComplicationEntry(date: .now, pendingCount: 2, isRecording: false)
    ComplicationEntry(date: .now, pendingCount: 0, isRecording: true)
}
