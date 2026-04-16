import SwiftUI

@main
struct MemoryStreamApp: App {
    let storageService = StorageService.shared

    var body: some Scene {
        WindowGroup {
            JournalView()
                .environment(\.managedObjectContext, storageService.viewContext)
        }
    }
}
