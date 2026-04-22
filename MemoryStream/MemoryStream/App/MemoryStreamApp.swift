import SwiftUI

@main
struct MemoryStreamApp: App {
    let storageService = StorageService.shared

    init() {
        TopicPaletteStore.shared.loadFromCoreData()
    }

    var body: some Scene {
        WindowGroup {
            JournalView()
                .environment(\.managedObjectContext, storageService.viewContext)
        }
    }
}
