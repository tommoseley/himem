import SwiftUI

/// The Projects tab — replaces the memory feed when the toggle is set to Projects.
struct ProjectListView: View {
    @ObservedObject var projectVM: ProjectViewModel
    var selectedTopic: String?
    /// Threaded to ProjectDetailView so a member card can open the canonical
    /// Memory Detail (F2/F3, 2026-07-17).
    @ObservedObject var viewModel: JournalViewModel
    let cameraService: CameraService
    @ObservedObject var speechService: SpeechService
    @State private var showNewProject = false
    @State private var showPricing = false
    @State private var newProjectName = ""
    @State private var newProjectPurpose = ""
    @State private var selectedProjectId: UUID? = nil
    @ObservedObject private var entitlement = Entitlement.shared
    /// Consumes the tab-shell FAB's "open new-project sheet" signal.
    /// The FAB lives at `HiMemTabView`; the sheet lives here. Wired
    /// via `NewProjectRequestBus` per the July 10 FAB lock.
    @ObservedObject private var newProjectBus = NewProjectRequestBus.shared
    /// Consumes a project read-chip tap routed from a memory's Projects
    /// read section (unified associations, 2026-07-17).
    @ObservedObject private var projectOpenBus = ProjectOpenBus.shared
    /// F22 · the one fact this view reads before it claims to be empty.
    @ObservedObject private var firstImport = FirstImportState.shared

    private var filteredProjects: [ProjectDisplayModel] {
        guard let topic = selectedTopic else { return projectVM.projects }
        return projectVM.projects.filter { $0.topicNames.contains(topic) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Projects was the only browsing tab with no `?` (2026-08-23) —
            // an omission rather than a decision, and it became load-bearing
            // when the intro tour retired the `projectsConcept` coachmark.
            // The net moved here rather than disappearing: the panel's first
            // clause is that coachmark's sentence, answerable one tap from the
            // screen where "what is a project for" is actually asked. Section-
            // anchored per F7c, so it sits in every branch below including the
            // empty states — which is where a first-time user reads it.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                SectionHelpButton(topic: .projectsConcept)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            Group {
            // F22 · one of the three surfaces that speak while the first
            // import is running. Projects sync from the private DB like
            // everything else, so "No projects yet" mid-import is the same
            // false certainty the Memories list showed on the iPad reinstall.
            if filteredProjects.isEmpty, !firstImport.mayAssertEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 40)) // design-token size
                        .foregroundStyle(Crucible.Color.ink4)
                        .accessibilityHidden(true)
                    Text(FirstImportState.Copy.projectsTitle)
                        .font(.subheadline)
                        .foregroundStyle(Crucible.Color.ink2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40)
            } else if filteredProjects.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder")
                        .font(.system(size: 40)) // design-token size
                        .foregroundStyle(Crucible.Color.ink4)
                        .accessibilityHidden(true)
                    Text("No projects yet")
                        .font(.subheadline)
                        .foregroundStyle(Crucible.Color.ink2)
                    Text("Projects are curated sets of memories with intent.\nGather related memories, then shape them into something.")
                        .font(.caption)
                        .foregroundStyle(Crucible.Color.ink3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button {
                        attemptCreateProject()
                    } label: {
                        Text("Create your first project")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Crucible.Color.accent)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40)
            } else {
                List {
                    ForEach(filteredProjects) { project in
                        ProjectCardView(project: project)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedProjectId = project.id }
                            // Swipe-to-delete retired per
                            // `HiMem · Buttons & Actions.html` §3
                            // (June 12 2026). Destruction lives at
                            // the bottom of the opened project.
                    }

                    // Inline "+ New project" row. Per the JSX
                    // (`ScrProjectsList`) this is the single creation
                    // affordance — no FAB. Lowercase "project" matches
                    // the spec's vocabulary ("New project" everywhere).
                    Button {
                        attemptCreateProject()
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Crucible.Color.accent)
                                    .frame(width: 22, height: 22)
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .accessibilityHidden(true)
                            Text("New project")
                                .font(.system(size: 15, weight: .medium))
                                .tracking(-0.2)
                                .foregroundStyle(Crucible.Color.accent)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        // Item 2 · teach what a project IS on first arrival — the walkthrough
        // covers clips→memories, not projects. One card, non-blocking, once
        // per device; re-armed with the walkthrough from Settings → Learn.
            .onAppear { OneShotCoachmark.projectsConcept.armIfEligible() }
            .overlay(alignment: .top) { CoachmarkBanner(coachmark: .projectsConcept) }
        }
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet(
                name: $newProjectName,
                purpose: $newProjectPurpose,
                onCreate: { name, purpose in
                    projectVM.createProject(name: name, purpose: purpose.isEmpty ? nil : purpose)
                }
            )
        }
        .onChange(of: newProjectBus.pendingToken) { _, token in
            if token != nil {
                attemptCreateProject()
                newProjectBus.consume()
            }
        }
        // A project read-chip was tapped on an opened memory (from any
        // tab). HiMemTabView switched to Projects; push the detail here.
        .onChange(of: projectOpenBus.pendingProjectId) { _, pid in
            if let pid {
                selectedProjectId = pid
                projectOpenBus.pendingProjectId = nil
            }
        }
        .sheet(isPresented: $showPricing) {
            PricingView()
        }
        .navigationDestination(item: $selectedProjectId) { projectId in
            if let project = projectVM.projects.first(where: { $0.id == projectId }) {
                ProjectDetailView(
                    projectId: project.id,
                    projectVM: projectVM,
                    viewModel: viewModel,
                    cameraService: cameraService,
                    speechService: speechService
                )
            }
        }
    }

    /// Free users get three projects. At-cap taps route to the
    /// `PricingView` upgrade flow (Plus is uncapped). The cap
    /// decision is pure — see `ProjectCapPolicy.canCreate`.
    private func attemptCreateProject() {
        let allowed = ProjectCapPolicy.canCreate(
            isPlus: entitlement.isPlus,
            currentCount: projectVM.projects.count
        )
        guard allowed else {
            showPricing = true
            return
        }
        newProjectName = ""
        newProjectPurpose = ""
        showNewProject = true
    }
}

// MARK: - New Project Sheet

private struct NewProjectSheet: View {
    @Binding var name: String
    @Binding var purpose: String
    let onCreate: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Field?

    private enum Field { case name, goal }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("Project name", text: $name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Crucible.Color.ink)
                    .tint(Crucible.Color.accent)
                    .focused($focused, equals: .name)
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

                VStack(alignment: .leading, spacing: 4) {
                    // UI label "goal" — Core Data attribute remains
                    // `Project.purpose` for backward-compat (renaming
                    // would force a CloudKit schema deploy).
                    TextField("Goal", text: $purpose, axis: .vertical)
                        .font(.subheadline)
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
                    Text("What are you building toward? A video, a post, an idea.")
                        .font(.caption)
                        .foregroundStyle(Crucible.Color.ink4)
                        .padding(.leading, 4)
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Crucible.Color.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Create = user-commit → ochre.
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onCreate(trimmed, purpose)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(name.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? Crucible.Color.ink3
                                     : Crucible.Color.accent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
