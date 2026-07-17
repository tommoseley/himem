import SwiftUI

/// Sheet-based editor for a project's name + goal. Replaces the
/// previous pen-driven inline edit mode on `ProjectDetailView` per
/// `docs/design/Memory Detail · unified editing model.md` §"Applies
/// to every surface":
///
/// > **Projects · Edit sheet** — Name, Goal (real fields, ochre focus);
/// > topics are derived, read-only (not edited here); Cancel / Save nav.
///
/// Reached from Project Detail via the boxed **✎ Edit** button beside the
/// header (F4, 2026-07-17 — the one edit affordance; title/goal text are NOT
/// tap-to-edit), or the dashed "+ Add a goal" affordance when the goal is
/// empty. Also carries the Find-the-thread trigger (AI action reachable from
/// edit; the summary renders on the detail).
///
/// **Topics on this sheet are intentionally read-only.** A project's
/// topic chips are *derived* from its member memories — managing them
/// here would mislead the user about where chips come from (they come
/// from the memories). So this sheet only edits the two project-owned
/// fields.
struct EditProjectSheet: View {
    let projectId: UUID
    let initialName: String
    let initialGoal: String
    /// Derived topic-name list, computed once from the project's
    /// member entries. Renders as a row of read-only chips at the
    /// bottom of the sheet so the user sees where the project's
    /// topics live, but they can't be edited from here.
    let derivedTopics: [String]
    let onSave: (_ name: String, _ goal: String) -> Void
    /// F4 (2026-07-17): the AI action reachable from edit. A trigger only —
    /// the thread's summary/suggestions render in their existing home on the
    /// project detail, not here (one surface per concept). Saves + dismisses,
    /// then runs on the detail. nil hides the button.
    let onFindTheThread: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var goal: String
    @FocusState private var focused: Field?

    private enum Field { case name, goal }

    init(
        projectId: UUID,
        initialName: String,
        initialGoal: String,
        derivedTopics: [String],
        focus: FocusTarget = .name,
        onSave: @escaping (_ name: String, _ goal: String) -> Void,
        onFindTheThread: (() -> Void)? = nil
    ) {
        self.projectId = projectId
        self.initialName = initialName
        self.initialGoal = initialGoal
        self.derivedTopics = derivedTopics
        self.onSave = onSave
        self.onFindTheThread = onFindTheThread
        _name = State(initialValue: initialName)
        _goal = State(initialValue: initialGoal)
        _initialFocus = State(initialValue: focus)
    }

    /// Which field receives the caret when the sheet opens. Tapping
    /// the goal text on the detail screen routes here with `.goal`
    /// pre-focused; tapping the title routes with `.name`. Identifiable
    /// so the host can present via `.sheet(item:)` — the focus target
    /// doubles as the presentation trigger.
    enum FocusTarget: Identifiable { case name, goal; var id: Self { self } }
    @State private var initialFocus: FocusTarget

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                nameField
                goalField
                if !derivedTopics.isEmpty {
                    derivedTopicsRow
                }
                if onFindTheThread != nil {
                    findTheThreadButton
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .background(Crucible.Color.paper)
            .navigationTitle("Edit project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Crucible.Color.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty else { return }
                        onSave(trimmedName, goal.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                     ? Crucible.Color.ink3
                                     : Crucible.Color.accent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                focused = (initialFocus == .goal) ? .goal : .name
            }
        }
    }

    @ViewBuilder
    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NAME")
                .font(.caption2)
                .fontWeight(.bold)
                .tracking(0.5)
                .foregroundStyle(Crucible.Color.ink3)
            TextField("Project name", text: $name)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink)
                .tint(Crucible.Color.accent)
                .focused($focused, equals: .name)
                .submitLabel(.next)
                .onSubmit { focused = .goal }
                .padding(12)
                .background(Crucible.Color.paper)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            focused == .name ? Crucible.Color.accent : Crucible.Color.hairline,
                            lineWidth: focused == .name ? 1.5 : 1
                        )
                )
        }
    }

    @ViewBuilder
    private var goalField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GOAL")
                .font(.caption2)
                .fontWeight(.bold)
                .tracking(0.5)
                .foregroundStyle(Crucible.Color.ink3)
            TextField("What are you building toward?", text: $goal, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(Crucible.Color.ink)
                .tint(Crucible.Color.accent)
                .focused($focused, equals: .goal)
                .lineLimit(2...6)
                .padding(12)
                .background(Crucible.Color.paper)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            focused == .goal ? Crucible.Color.accent : Crucible.Color.hairline,
                            lineWidth: focused == .goal ? 1.5 : 1
                        )
                )
            Text("A video, a post, an idea. Something concrete.")
                .font(.caption)
                .foregroundStyle(Crucible.Color.ink4)
                .padding(.leading, 4)
        }
    }

    /// Find the thread — a blue AI *trigger* (named verb + trailing sparkle).
    /// Saves any pending name/goal edit, dismisses, then runs the assist so
    /// its summary lands on the project detail (the thread's home).
    @ViewBuilder
    private var findTheThreadButton: some View {
        Button {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty {
                onSave(trimmedName, goal.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            dismiss()
            onFindTheThread?()
        } label: {
            HStack(spacing: 8) {
                Text("Find the thread")
                    .font(.system(size: 14.5, weight: .semibold))
                    .tracking(-0.1)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Crucible.Color.aiBlue)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 46)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Crucible.Color.aiBlue, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Find the thread with AI")
    }

    @ViewBuilder
    private var derivedTopicsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("TOPICS")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .tracking(0.5)
                    .foregroundStyle(Crucible.Color.ink3)
                Text("from this project's memories")
                    .font(.caption2)
                    .foregroundStyle(Crucible.Color.ink4)
            }
            FlowLayout(spacing: 6) {
                ForEach(derivedTopics, id: \.self) { topic in
                    let hue = Crucible.Color.topicHue(for: topic)
                    HStack(spacing: 3) {
                        Circle().fill(hue.fg).frame(width: 5, height: 5)
                        Text(topic)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(hue.fg)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(hue.bg)
                    .clipShape(Capsule())
                }
            }
        }
    }
}
