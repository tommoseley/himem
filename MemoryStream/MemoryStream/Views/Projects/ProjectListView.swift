import SwiftUI

/// The Projects tab — replaces the memory feed when the toggle is set to Projects.
struct ProjectListView: View {
    @ObservedObject var projectVM: ProjectViewModel
    var selectedTopic: String?
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var newProjectPurpose = ""
    @State private var selectedProjectId: UUID? = nil

    private var filteredProjects: [ProjectDisplayModel] {
        guard let topic = selectedTopic else { return projectVM.projects }
        return projectVM.projects.filter { $0.topicNames.contains(topic) }
    }

    var body: some View {
        Group {
            if filteredProjects.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder")
                        .font(.system(size: 40))
                        .foregroundStyle(Crucible.Color.ink4)
                    Text("No projects yet")
                        .font(.subheadline)
                        .foregroundStyle(Crucible.Color.ink2)
                    Text("Projects are curated sets of memories with intent.\nGather related memories, then shape them into something.")
                        .font(.caption)
                        .foregroundStyle(Crucible.Color.ink3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button {
                        newProjectName = ""
                        newProjectPurpose = ""
                        showNewProject = true
                    } label: {
                        Text("Create your first Project")
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
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    projectVM.deleteProject(id: project.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }

                    // "New Project" row at the bottom
                    Button {
                        newProjectName = ""
                        newProjectPurpose = ""
                        showNewProject = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Crucible.Color.accent)
                            Text("New Project")
                                .foregroundStyle(Crucible.Color.accent)
                                .fontWeight(.semibold)
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
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet(
                name: $newProjectName,
                purpose: $newProjectPurpose,
                onCreate: { name, purpose in
                    projectVM.createProject(name: name, purpose: purpose.isEmpty ? nil : purpose)
                }
            )
        }
        .navigationDestination(item: $selectedProjectId) { projectId in
            if let project = projectVM.projects.first(where: { $0.id == projectId }) {
                ProjectDetailView(projectId: project.id, projectVM: projectVM)
            }
        }
    }
}

// MARK: - New Project Sheet

private struct NewProjectSheet: View {
    @Binding var name: String
    @Binding var purpose: String
    let onCreate: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("Project name", text: $name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Crucible.Color.ink)
                    .padding(12)
                    .background(Crucible.Color.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.accent, lineWidth: 1.5))

                VStack(alignment: .leading, spacing: 4) {
                    TextField("What are you building toward?", text: $purpose)
                        .font(.subheadline)
                        .foregroundStyle(Crucible.Color.ink)
                        .padding(12)
                        .background(Crucible.Color.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.hairline, lineWidth: 1))
                    Text("A video? A post? An idea?")
                        .font(.caption)
                        .foregroundStyle(Crucible.Color.ink4)
                        .padding(.leading, 4)
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onCreate(trimmed, purpose)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
