import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search entries, tags, topics...", text: $viewModel.queryText)
                        .textFieldStyle(.plain)
                        .onSubmit { viewModel.performSearch() }
                }
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding()

                // Entity type filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ExtractedEntity.EntityType.allCases, id: \.rawValue) { type in
                            FilterChip(
                                label: type.displayLabel,
                                isSelected: viewModel.selectedEntityTypes.contains(type)
                            ) {
                                viewModel.toggleEntityType(type)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                Divider()
                    .padding(.top, 8)

                // Results
                if viewModel.results.isEmpty && !viewModel.queryText.isEmpty {
                    ContentUnavailableView(
                        "No results",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search term or filter")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.results) { entry in
                                EntryCardView(entry: entry)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.primary : Color.clear)
                .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color(.separator), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SearchView()
}
