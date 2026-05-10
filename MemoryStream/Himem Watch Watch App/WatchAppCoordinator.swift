import Foundation
import SwiftUI
import Combine

/// Global state holder for the watch app. Owns the long-lived services
/// (recording, transfer, pending manifest) and the navigation route. The
/// pending list, recording surface, and confirmation UI all read from
/// here.
@MainActor
final class WatchAppCoordinator: ObservableObject {
    /// What screen the root is currently showing. The complication launch
    /// path (deep-link via WKExtension) jumps straight to .recording.
    enum Route: Equatable {
        case home
        case recording
        case confirmation(WatchConfirmation)
        case pendingList
    }

    @Published var route: Route = .home

    let recording = WatchRecordingService()
    let transfer = WatchTransferService()
    let pending = WatchPendingManifest.shared

    private var bag = Set<AnyCancellable>()

    init() {
        NSLog("[Himem][WC] watch — WatchAppCoordinator.init")
        // Forward acks from the iPhone into the pending manifest so rows
        // get removed from the watch list as the iPhone confirms each clip.
        transfer.$lastAckedClipId
            .compactMap { $0 }
            .sink { [weak self] clipId in
                NSLog("[Himem][WC] watch — coordinator removing clipId=\(clipId) from manifest")
                self?.pending.remove(clipId: clipId)
            }
            .store(in: &bag)

        // Re-attempt unsent clips on app launch — transferFile is durable
        // across launches but we ping the queue once at startup so the
        // user sees recent progress.
        transfer.start()
        Task { await retryPendingTransfers() }
    }

    /// Retries `transferFile` for every clip currently in the pending
    /// manifest that doesn't already have a transfer in flight. The
    /// system de-dupes, so retrying a clip that's already queued is a
    /// no-op.
    func retryPendingTransfers() async {
        NSLog("[Himem][WC] watch — retryPendingTransfers running, manifest has \(pending.count) clip(s)")
        for clip in pending.clips {
            transfer.send(clip: clip)
        }
    }
}
