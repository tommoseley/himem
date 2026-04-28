import SwiftUI
import AppIntents

@main
struct MemoryStreamApp: App {
    let storageService = StorageService.shared

    init() {
        TopicPaletteStore.shared.loadFromCoreData()
        HiMemShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            JournalView()
                .environment(\.managedObjectContext, storageService.viewContext)
                .preferredColorScheme(.light)
        }
    }
}
