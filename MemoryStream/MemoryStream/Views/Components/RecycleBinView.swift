import SwiftUI

struct RecycleBinView: View {
    @ObservedObject var viewModel: JournalViewModel
    @State private var recycledEntries: [EntryDisplayModel] = []
    @State private var showEmptyConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if recycledEntries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "trash")
                            .font(.system(size: 40))
                            .foregroundStyle(Crucible.Color.ink4)
                        Text("Recycle bin is empty")
                            .font(.subheadline)
                            .foregroundStyle(Crucible.Color.ink3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(recycledEntries) { entry in
                            GhostCard(entry: entry, onRestore: {
                                viewModel.restoreEntry(entryId: entry.id)
                                recycledEntries = viewModel.loadRecycledEntries()
                            }, onDelete: {
                                viewModel.deleteEntry(entryId: entry.id)
                                recycledEntries = viewModel.loadRecycledEntries()
                            })
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Crucible.Color.paper)
            .navigationTitle("Recycle Bin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !recycledEntries.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Empty") {
                            showEmptyConfirm = true
                        }
                        .foregroundStyle(Crucible.Color.danger)
                    }
                }
            }
            .confirmationDialog("Empty Recycle Bin?", isPresented: $showEmptyConfirm, titleVisibility: .visible) {
                Button("Delete All Forever", role: .destructive) {
                    viewModel.emptyRecycleBin()
                    recycledEntries = []
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(recycledEntries.count) memories will be permanently deleted.")
            }
        }
        .onAppear {
            recycledEntries = viewModel.loadRecycledEntries()
        }
    }
}

// MARK: - Ghost Card

/// Grayscale, italicized card for recycled entries.
private struct GhostCard: View {
    let entry: EntryDisplayModel
    let onRestore: () -> Void
    let onDelete: () -> Void

    private var daysRemaining: Int {
        guard let recycledAt = entry.recycledAt else { return 30 }
        let elapsed = Calendar.current.dateComponents([.day], from: recycledAt, to: Date()).day ?? 0
        return max(0, 30 - elapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title + countdown
            HStack {
                Text(entry.displayTitle)
                    .font(.headline)
                    .italic()
                    .foregroundStyle(Crucible.Color.ink3)
                Spacer()
                Text("\(daysRemaining)d left")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Crucible.Color.sunk)
                    .clipShape(Capsule())
            }

            // Timestamp
            HStack(spacing: 6) {
                Text(entry.timeString)
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.ink4)
                Circle()
                    .fill(Crucible.Color.ink4)
                    .frame(width: 3, height: 3)
                Text(entry.inputType.displayLabel)
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.ink4)
            }

            // Content preview (italicized ghost text)
            Text(entry.content)
                .font(.subheadline)
                .italic()
                .foregroundStyle(Crucible.Color.ink3)
                .lineLimit(2)

            // Media dots (grayscale)
            if let summary = entry.mediaSummary {
                HStack(spacing: 6) {
                    if entry.hasAudio {
                        Circle().fill(Crucible.Color.ink4).frame(width: 6, height: 6)
                    }
                    ForEach(entry.mediaItems.indices, id: \.self) { _ in
                        Circle().fill(Crucible.Color.ink4).frame(width: 6, height: 6)
                    }
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(Crucible.Color.ink4)
                }
            }

            // Actions
            HStack(spacing: 12) {
                Spacer()
                Button {
                    onRestore()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                        Text("Restore")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Crucible.Color.accent)
                }
                .buttonStyle(.plain)

                Button {
                    onDelete()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                        Text("Delete")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Crucible.Color.danger)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.xl))
        .modifier(WarmShadow(level: 1))
        .saturation(0) // Grayscale ghost effect
        .opacity(0.75)
    }
}
