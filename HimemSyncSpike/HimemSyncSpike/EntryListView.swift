import SwiftUI

/// Bare-bones list view. Single column of entry snapshots, with a
/// status header showing the fetch state. No styling beyond what's
/// needed to confirm "we got the records." This is a measurement
/// app, not a product.
struct EntryListView: View {
    @ObservedObject var reader: SyncedReader
    @State private var hasEmittedPaintSignpost = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(reader.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(reader.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title.isEmpty ? "(untitled)" : entry.title)
                            .font(.headline)
                        if let date = entry.createdAt {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !entry.contentPreview.isEmpty {
                            Text(entry.contentPreview)
                                .font(.subheadline)
                                .lineLimit(2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Sync Spike")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: reader.entries.count) { _, count in
            if count > 0 && !hasEmittedPaintSignpost {
                SpikeSignposter.event("spike.uiPainted")
                hasEmittedPaintSignpost = true
            }
        }
    }
}
