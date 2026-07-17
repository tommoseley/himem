import SwiftUI
import CoreData
import Photos
import AVFoundation
import UIKit

/// Project View — header + purpose + curated memory stack.
/// Entry cards are used here (inside a project), not on the project list.
struct ProjectDetailView: View {
    let projectId: UUID
    @ObservedObject var projectVM: ProjectViewModel
    /// F2/F3 (2026-07-17): a member card opens the canonical Memory Detail
    /// (EntryExpandedView), so the project stack needs the same services the
    /// Memories list feeds it. Threaded from JournalView via ProjectListView.
    @ObservedObject var viewModel: JournalViewModel
    let cameraService: CameraService
    @ObservedObject var speechService: SpeechService
    @Environment(\.dismiss) private var dismiss
    @State private var project: Project?
    /// Drives the push to the member memory's Memory Detail.
    @State private var selectedEntryId: UUID? = nil
    /// "Removed from [project] · Undo" toast (F2/F3) — the safety net that
    /// lets the remove skip a confirm dialog. 5-second timeout; Undo re-adds.
    @State private var removalToast: RemovalToast? = nil
    /// Projects-only delete confirm (ruled 2026-07-17 — a scoped carve-out
    /// to the deletion lock). A project dissolves a container spanning many
    /// memories, and unlike a memory/clip the loss is abstract (no clips
    /// visibly survive in front of you), so it earns one light confirm on
    /// top of the soft-delete net. Memory/clip deletion stays no-confirm.
    @State private var showDeleteConfirm = false

    private struct RemovalToast: Identifiable {
        let id = UUID()
        let entryId: UUID
        let projectName: String
    }
    @State private var entries: [EntryDisplayModel] = []
    @State private var topicFilter: String? = nil
    @State private var showShareSheet = false
    @State private var showAddMemorySheet = false
    /// Consumes the in-project FAB's "Add existing memory" signal (F7).
    /// The FAB lives at `HiMemTabView`; the search-to-add sheet lives
    /// here — this bus is the seam, mirroring `NewProjectRequestBus`.
    @ObservedObject private var addExistingBus = AddExistingMemoryRequestBus.shared
    @State private var shareItems: [Any] = []
    @State private var isPreparingShare = false
    @State private var showSuggestionsSheet = false
    @State private var showPricing = false
    /// Drives presentation of the Edit Project sheet — tap title or
    /// goal text on the detail page to open. `.name` pre-focuses the
    /// name field; `.goal` pre-focuses the goal field. Per the unified
    /// editing model the pen button on Project Detail is retired.
    @State private var editSheetFocus: EditProjectSheet.FocusTarget? = nil
    @StateObject private var suggestionsVM = ProjectSuggestionsViewModel()
    @StateObject private var assistVM = ProjectAssistViewModel()
    @ObservedObject private var entitlement = Entitlement.shared

    private let storage = StorageService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title — serif 30pt. F4 (2026-07-17): the boxed ✎ Edit is
                // the ONE edit affordance (matching ✎ on every clip surface);
                // the title text is NOT tap-to-edit. Editing routes to the
                // EditProjectSheet.
                HStack(alignment: .top, spacing: 10) {
                    Text(project?.name ?? "")
                        .font(.system(size: 30, design: .serif))
                        .tracking(-0.5)
                        .lineSpacing(2)
                        .foregroundStyle(Crucible.Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ClipEditButton(action: { editSheetFocus = .name })
                }

                // Goal — italic serif when present (read-only; edited via the
                // ✎ Edit button, not tap-the-text, F4). Dashed "+ Add a goal"
                // add-affordance when empty (dashed = add/provisional, an
                // allowed invite — distinct from tap-the-content).
                if let purpose = project?.purpose, !purpose.isEmpty {
                    Text(purpose)
                        .font(.system(size: 13, design: .serif).italic())
                        .foregroundStyle(Crucible.Color.ink2)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Button {
                        editSheetFocus = .goal
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Add a goal")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(Crucible.Color.ink3)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(
                            Capsule().strokeBorder(
                                Crucible.Color.ink4,
                                style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                            )
                        )
                        .frame(minHeight: 38)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a goal")
                }

                // Topic pills from project entries (tap to filter)
                if let proj = project, !proj.topicNames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(proj.topicNames, id: \.self) { topic in
                                let hue = Crucible.Color.topicHue(for: topic)
                                Button {
                                    if topicFilter == topic {
                                        topicFilter = nil
                                    } else {
                                        topicFilter = topic
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Circle().fill(hue.fg).frame(width: 6, height: 6)
                                            .accessibilityHidden(true)
                                        Text(topic)
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(hue.fg)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(topicFilter == topic ? hue.bg : hue.bg.opacity(0.5))
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(topicFilter == topic ? hue.fg.opacity(0.3) : .clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Project Assist summary — spec § States state 4
                // "Summarized". Rendered above the memory list
                // when a prior Find-the-thread run has persisted
                // a summary. Re-running replaces in place.
                projectThreadSummaryCard

                // Find the thread — Project Assist affordance.
                // Visible below 3 memories but disabled with helper
                // copy so the user discovers the affordance early.
                // Activates at ≥3 per the Projects MVP spec.
                findTheThreadButton

                // Suggested memberships — local topic-match.
                // Hidden when there are zero candidates so the
                // section's presence is its own affordance.
                suggestionsAffordance

                // Memory count
                let displayCount = topicFilter == nil ? entries.count : entries.filter { $0.topicNames.contains(topicFilter!) }.count
                Text("\(displayCount) memor\(displayCount == 1 ? "y" : "ies")")
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.ink3)

                // Memory stack — entry cards
                if entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.title)
                            .foregroundStyle(Crucible.Color.ink4)
                            .accessibilityHidden(true)
                        Text("No memories in this project yet")
                            .font(.subheadline)
                            .foregroundStyle(Crucible.Color.ink3)
                        Text("Open a memory and use \"Add to Project\" to curate this collection.")
                            .font(.caption)
                            .foregroundStyle(Crucible.Color.ink4)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                } else {
                    let filtered = topicFilter == nil ? entries : entries.filter { $0.topicNames.contains(topicFilter!) }
                    // F2/F3 (2026-07-17): tapping a member card opens the
                    // canonical Memory Detail (below), with the project-context
                    // fate buttons ("Remove from [project]" → "Let Go").
                    ForEach(filtered) { entry in
                        EntryCardView(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedEntryId = entry.id }
                    }
                }

                // Bottom Delete project — the sole project-delete path
                // per `HiMem · Buttons & Actions.html` §3 and `Memory
                // Detail · unified editing model.md` (June 12 2026).
                // Swipe-to-recycle on member rows is retired alongside
                // the toolbar Trash; opening a member memory carries
                // its own bottom button.
                BottomDeleteButton(kind: .delete(noun: "project")) {
                    showDeleteConfirm = true
                }
                .padding(.top, 24)
            }
            .padding(16)
        }
        .background(Crucible.Color.paper)
        .overlay(alignment: .bottom) {
            if let toast = removalToast {
                removalToastView(toast)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: removalToast?.id)
        .alert("Delete Project?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                projectVM.deleteProject(id: projectId)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The memories stay in your library.")
        }
        .navigationDestination(item: $selectedEntryId) { entryId in
            memberDetailDestination(for: entryId)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .accessibilityHidden(true)
                        Text("Projects")
                    }
                    .foregroundStyle(Crucible.Color.accent)
                }
            }
            // Trailing toolbar: share only. The add-memory `+` is retired
            // (F7, 2026-07-17) — adding memories now lives on the context-
            // aware FAB's two paths (new-in-project + "Add existing
            // memory"), per Projects · MVP spec §Surfaces ("no toolbar
            // trash, no +"). No pen, no Trash (title/goal edit via
            // EditProjectSheet; destruction is the bottom Delete Project
            // button).
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        Task { await prepareAndShowShareSheet() }
                    } label: {
                        if isPreparingShare {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15))
                                .foregroundStyle(Crucible.Color.ink2)
                        }
                    }
                    .disabled(isPreparingShare)
                    .accessibilityLabel("Share project")
                }
            }
        }
        .sheet(item: $editSheetFocus) { focus in
            EditProjectSheet(
                projectId: projectId,
                initialName: project?.name ?? "",
                initialGoal: project?.purpose ?? "",
                derivedTopics: project?.topicNames ?? [],
                focus: focus,
                onSave: { newName, newGoal in
                    projectVM.updateProject(
                        id: projectId,
                        name: newName,
                        purpose: newGoal.isEmpty ? nil : newGoal
                    )
                    loadProject()
                },
                onFindTheThread: {
                    // Run the assist so the summary lands on the detail
                    // (its home) after the sheet dismisses. Plus-gated;
                    // Free routes to Pricing — same as the detail button.
                    handleFindTheThreadTap()
                }
            )
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .sheet(isPresented: $showAddMemorySheet, onDismiss: {
            loadProjectEntries()
            // Membership changed: a memory the user just added is
            // no longer a "may belong" candidate. Recompute so the
            // affordance row's count stays honest.
            suggestionsVM.reload(projectId: projectId)
        }) {
            AddMemoryToProjectSheet(projectId: projectId, projectVM: projectVM)
        }
        .sheet(isPresented: $showPricing) {
            PricingView()
        }
        .sheet(isPresented: $showSuggestionsSheet) {
            // Reload after dismissal so the affordance row's count
            // reflects whatever the user just committed/skipped.
            suggestionsVM.reload(projectId: projectId)
            loadProjectEntries()
        } content: {
            SuggestedMemoriesSheet(
                projectName: project?.name ?? "this project",
                suggestions: suggestionsVM.suggestions,
                onCommit: { accepted in
                    suggestionsVM.commit(acceptedIDs: accepted, projectId: projectId)
                }
            )
        }
        .onAppear {
            loadProject()
            loadProjectEntries()
            suggestionsVM.reload(projectId: projectId)
            attemptFindTheThreadTutorial()
            // Publish the current project id so `HiMemTabView`'s FAB
            // knows we're inside a project detail — routes the +
            // to "new memory in this project" per the July 10 lock
            // (`CLAUDE.md:142`). Cleared in `.onDisappear`.
            ProjectsNavigationContext.shared.enter(projectId: projectId)
        }
        .onDisappear {
            ProjectsNavigationContext.shared.exit(projectId: projectId)
        }
        .onChange(of: addExistingBus.pendingToken) { _, token in
            // The in-project FAB's "Add existing memory" path fired —
            // present the same search-to-add sheet the retired toolbar +
            // used to open, then clear the one-shot token.
            if token != nil {
                showAddMemorySheet = true
                addExistingBus.consume()
            }
        }
    }

    /// Tutorial #3 (Find the thread) trigger. Spec gates: Plus user,
    /// project detail open with **≥3 memories**, Find-the-thread
    /// **unrun** (no persisted `lastThreadSummary`). The ≥3 gate is
    /// the *tutorial* threshold — the feature itself activates at ≥1
    /// per `Projects · MVP spec.md`; the tutorial waits for 3 because
    /// a 1-2-memory "thread" makes a thin first impression. The
    /// orchestrator handles the once-each + session/day caps.
    private func attemptFindTheThreadTutorial() {
        guard entitlement.isPlus else { return }
        guard entries.count >= 3 else { return }
        guard project?.lastThreadSummary == nil
              || project?.lastThreadSummary?.isEmpty == true else { return }
        TutorialOrchestrator.shared.tryFire(.findTheThread)
    }

    /// Routes the "Find the thread" tap. Plus-only after the
    /// assist-quota retirement; Free taps route to PricingView.
    private func handleFindTheThreadTap() {
        guard entitlement.isPlus else {
            showPricing = true
            return
        }
        Task {
            await assistVM.run(projectId: projectId)
            // Reload project state so the new summary renders +
            // the suggester refreshes (Find the thread doesn't
            // change membership today, but re-reading is cheap
            // and future-proofs).
            loadProject()
            suggestionsVM.reload(projectId: projectId)
        }
    }

    /// "Find the thread" card — Project Assist entry point.
    /// Card with a 36-square AI-tint icon on the left, title +
    /// sub-line stacked in the middle, "Run" pill on the right.
    /// Disabled below `ProjectAssistGate.minimumMemories`; sub-line
    /// adapts to whichever threshold is currently active. Spec
    /// (Projects MVP § States) wants `Add a memory first.` for the
    /// ≥1 path and `Add a few more memories first.` for the gated-
    /// off conservative path.

    /// "N memories may belong here" affordance row. Hidden when
    /// the local suggester returns zero candidates — the section's
    /// presence is its own affordance, same pattern the spec uses
    /// for the post-AI "N memories may belong here · Review" card.
    /// This row ships local-match only (Plan B); the AI re-rank
    /// version is a v1.1 upgrade that pipes these candidates
    /// through `/himem/project-assist`.
    @ViewBuilder
    private var suggestionsAffordance: some View {
        let n = suggestionsVM.suggestions.count
        if n > 0 {
            Button {
                showSuggestionsSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Crucible.Color.aiBlue)
                    Text("\(n) memor\(n == 1 ? "y" : "ies") may belong here")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Crucible.Color.ink)
                    Spacer(minLength: 0)
                    HStack(spacing: 2) {
                        Text("Review")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Crucible.Color.aiBlue)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Crucible.Color.aiBlue)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Crucible.Color.aiBlueTint.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Review \(n) memory suggestions")
        }
    }

    @ViewBuilder
    private var findTheThreadButton: some View {
        // Hidden once a summary exists — the post-run state lives in
        // `projectThreadSummaryCard` (which carries its own re-run
        // button "Find the thread again"). One named verb per surface
        // per `docs/design/CLAUDE.md` § button colour code.
        if project?.lastThreadSummary == nil || project?.lastThreadSummary?.isEmpty == true {
            let enabled = ProjectAssistGate.isEnabled(memoryCount: entries.count)
            let subline = enabled
                ? "A short summary across these \(entries.count) memor\(entries.count == 1 ? "y" : "ies"), and others that may belong."
                : (ProjectAssistGate.allowSingleMemoryThreshold
                   ? "Add a memory first."
                   : "Add a few more memories first.")
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Crucible.Color.aiBlueTint)
                            .frame(width: 36, height: 36)
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Crucible.Color.aiBlue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Find the thread")
                            .font(.system(size: 14, weight: .semibold))
                            .tracking(-0.1)
                            .foregroundStyle(Crucible.Color.ink)
                        Text(subline)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Crucible.Color.ink3)
                            .lineSpacing(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Full-width primary AI button — blue fill, named
                // feature ("Find the thread") + trailing sparkle, ≥44pt.
                // Matches the spec mock (`ScrProjectDetail` June 10).
                Button {
                    guard enabled, !assistVM.isRunning else { return }
                    handleFindTheThreadTap()
                } label: {
                    HStack(spacing: 8) {
                        if assistVM.isRunning {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Text("Find the thread")
                                .font(.system(size: 14.5, weight: .semibold))
                                .tracking(-0.1)
                                .foregroundStyle(.white)
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 46)
                    .background(enabled
                                ? Crucible.Color.aiBlue
                                : Crucible.Color.aiBlue.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!enabled || assistVM.isRunning)
                .accessibilityLabel("Find the thread with AI")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Crucible.Color.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Crucible.Color.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    /// Project Assist synthesis card — spec § States state 4
    /// "Summarized". Renders when `project.lastThreadSummary` is
    /// non-nil. Body is serif (reflective register), framed with
    /// the AI-blue tint and an AI-blue 1px border. The Dismiss
    /// action clears local state only; the assist is not refunded
    /// (the work happened).
    @ViewBuilder
    private var projectThreadSummaryCard: some View {
        if let summary = project?.lastThreadSummary, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("PROJECT SUMMARY")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(Crucible.Color.ink3)
                    Spacer(minLength: 8)
                    // Review-state label per the unified spec: AI-blue,
                    // quiet (never a button). Mirrors the "Draft
                    // organized" pattern on Memory Detail.
                    Text("Draft · give this a glance")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Crucible.Color.aiBlue)
                }

                Text(summary)
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(Crucible.Color.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                // Re-run as a real AI button (blue, bordered, ≥44pt,
                // named feature + trailing sparkle). Per the colour
                // code lock: never "Regenerate" — the named verb is
                // `Find the thread again`.
                HStack(spacing: 12) {
                    Button {
                        guard !assistVM.isRunning else { return }
                        handleFindTheThreadTap()
                    } label: {
                        HStack(spacing: 6) {
                            if assistVM.isRunning {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(Crucible.Color.aiBlue)
                                    .scaleEffect(0.8)
                            } else {
                                Text("Find the thread again")
                                    .font(.system(size: 13, weight: .semibold))
                                    .tracking(-0.1)
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .foregroundStyle(Crucible.Color.aiBlue)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Crucible.Color.aiBlue, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(assistVM.isRunning)
                    .accessibilityLabel("Find the thread again with AI")
                    Spacer(minLength: 0)
                    Text("\(entries.count) of \(entries.count) memor\(entries.count == 1 ? "y" : "ies")")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Crucible.Color.ink3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Crucible.Color.aiBlueTint.opacity(0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Crucible.Color.aiBlue.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contextMenu {
                Button {
                    UIPasteboard.general.string = summary
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    assistVM.dismissSummary(projectId: projectId)
                    loadProject()
                } label: {
                    Label("Dismiss summary", systemImage: "xmark")
                }
            }
        }
    }

    private static let _summaryTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f
    }()

    private static func summaryTimestamp(_ date: Date) -> String {
        _summaryTimestampFormatter.string(from: date)
    }

    private func composeProjectText() -> String {
        Self.composeProjectText(
            name: project?.name,
            purpose: project?.purpose,
            entries: entries
        )
    }

    /// Pure formatter for the share-sheet output. Header (uppercased name +
    /// optional purpose) followed by `---`-separated entry blocks containing
    /// the entry title and clean content. Static so tests can call it
    /// directly with any (name, purpose, entries) inputs.
    static func composeProjectText(name: String?, purpose: String?, entries: [EntryDisplayModel]) -> String {
        var lines: [String] = []

        if let name {
            lines.append(name.uppercased())
            if let purpose, !purpose.isEmpty {
                lines.append(purpose)
            }
            lines.append("")
        }

        for entry in entries {
            lines.append("---")
            lines.append("")
            lines.append(entry.displayTitle)
            lines.append(entry.content)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// The canonical Memory Detail for a member memory, opened from its card
    /// (F2/F3). Same EntryExpandedView + callbacks the Memories list uses — no
    /// fork — plus the project-context `onRemoveFromProject` (de-associate
    /// only; the memory survives) which renders the "Remove from [project]"
    /// button above the memory's red "Let Go of this Memory".
    @ViewBuilder
    private func memberDetailDestination(for entryId: UUID) -> some View {
        if let entry = viewModel.currentEntry(id: entryId) {
            EntryExpandedView(
                entry: entry,
                backLabel: project?.name ?? "Project",
                allTopics: viewModel.topics,
                cameraService: cameraService,
                speechService: speechService,
                onSave: { entryId, newContent, newTitle in
                    viewModel.editEntry(
                        entryId: entryId,
                        newContent: newContent,
                        newTitle: newTitle,
                        removedTagIds: [],
                        removedMediaIds: [],
                        addedTopicNames: [],
                        removedTopicNames: []
                    )
                },
                onFeedback: { entryId, state in
                    viewModel.submitFeedback(entryId: entryId, state: state)
                },
                onAdjust: { entryId, correction in
                    viewModel.submitFeedback(entryId: entryId, state: .edited, correction: correction)
                },
                onCommit: { entryId, additionalContent, mediaCaptures in
                    viewModel.appendToEntry(
                        entryId: entryId,
                        additionalContent: additionalContent,
                        mediaCaptures: mediaCaptures
                    )
                },
                onRecycle: { entryId in
                    viewModel.recycleEntry(entryId: entryId)
                },
                onAddToProject: { entryId, projId in
                    projectVM.addMemory(entryId: entryId, toProjectId: projId)
                },
                onRemoveFromProject: { entryId in
                    projectVM.removeMemory(entryId: entryId, fromProjectId: projectId)
                    loadProjectEntries()
                    showRemovalToast(entryId: entryId)
                },
                projectContextName: project?.name,
                availableProjects: projectVM.projects
            )
            .onAppear { viewModel.markEntryViewed(entryId) }
        } else {
            Color(Crucible.Color.paper).ignoresSafeArea()
        }
    }

    private func loadProject() {
        let request = NSFetchRequest<Project>(entityName: "Project")
        request.predicate = NSPredicate(format: "id == %@", projectId as CVarArg)
        request.fetchLimit = 1
        project = try? storage.viewContext.fetch(request).first
    }

    private func loadProjectEntries() {
        guard let project else { return }
        let journalEntries = project.entriesArray.filter { !$0.isRecycled }
        entries = journalEntries.map(EntryMapper.mapToDisplayModel)
    }

    // MARK: - Remove-from-project toast (F2/F3)

    /// The "Removed from [project]" confirmation + Undo. This is the safety
    /// net that lets the remove skip a confirm dialog (per the deletion-lock
    /// model): a de-association is cheap to reverse, so we surface an
    /// immediate Undo instead of a modal.
    private func showRemovalToast(entryId: UUID) {
        let toast = RemovalToast(entryId: entryId, projectName: project?.name ?? "this project")
        removalToast = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if removalToast?.id == toast.id { removalToast = nil }
        }
    }

    private func undoRemoval(_ toast: RemovalToast) {
        projectVM.addMemory(entryId: toast.entryId, toProjectId: projectId)
        loadProjectEntries()
        removalToast = nil
    }

    @ViewBuilder
    private func removalToastView(_ toast: RemovalToast) -> some View {
        HStack(spacing: 12) {
            Text("Removed from \(toast.projectName)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                undoRemoval(toast)
            } label: {
                Text("Undo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Crucible.Color.accentBright)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(Crucible.Color.ink, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    // MARK: - Share preparation

    /// Builds the share-sheet payload: composed text plus full-resolution
    /// image data, video file URLs, and voice-clip file URLs pulled from each
    /// entry. PhotoKit lookups are async so we set a `isPreparingShare` flag
    /// to swap the share button to a spinner while we collect items.
    private func prepareAndShowShareSheet() async {
        isPreparingShare = true
        defer { isPreparingShare = false }

        var items: [Any] = [composeProjectText()]

        // Photos + videos: route through MediaResolver. Ubiquity-backed
        // media shares as a URL (UIActivityViewController prefers
        // file URLs for downstream apps). PhotoKit-backed legacy
        // media still uses the PHImageManager fetch.
        let mediaItems: [(localIdentifier: String, mediaType: MediaReference.MediaType)] =
            entries.flatMap { entry in
                entry.mediaItems
                    .filter { $0.mediaType == .image || $0.mediaType == .video }
                    .map { ($0.localIdentifier, $0.mediaType) }
            }
        var photoKitImageIds: [String] = []
        var photoKitVideoIds: [String] = []
        for media in mediaItems {
            switch MediaResolver.resolve(osIdentifier: media.localIdentifier, mediaType: media.mediaType) {
            case .ubiquity(let fileURL):
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    items.append(fileURL)
                }
            case .photoKit(let identifier):
                if media.mediaType == .image {
                    photoKitImageIds.append(identifier)
                } else {
                    photoKitVideoIds.append(identifier)
                }
            }
        }
        let legacyIds = photoKitImageIds + photoKitVideoIds
        if !legacyIds.isEmpty {
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: legacyIds, options: nil)
            var assets: [PHAsset] = []
            fetch.enumerateObjects { asset, _, _ in assets.append(asset) }
            for asset in assets {
                if asset.mediaType == .image, let image = await loadFullImage(from: asset) {
                    items.append(image)
                } else if asset.mediaType == .video, let url = await loadVideoURL(from: asset) {
                    items.append(url)
                }
            }
        }

        // Voice clips on disk — every voice fragment lives on a `.voice`
        // MediaReference post-FragmentMigration.
        var voiceFilenames: [String] = []
        for entry in entries {
            voiceFilenames.append(contentsOf: entry.mediaItems
                .filter { $0.mediaType == .voice }
                .map { $0.localIdentifier })
        }
        for filename in voiceFilenames {
            let url = SpeechService.audioURL(for: filename)
            if FileManager.default.fileExists(atPath: url.path) {
                items.append(url)
            }
        }

        shareItems = items
        showShareSheet = true
    }

    private func loadFullImage(from asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    private func loadVideoURL(from asset: PHAsset) async -> URL? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            var resumed = false
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard !resumed else { return }
                resumed = true
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
