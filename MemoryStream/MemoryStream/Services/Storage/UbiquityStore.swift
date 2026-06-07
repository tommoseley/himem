import Foundation

/// Single source of truth for "where does HiMem put media files?"
///
/// Resolves to the iCloud Drive ubiquity container's `Documents`
/// directory when iCloud is available; falls back to the app's
/// sandbox `Documents` directory when it isn't. Either way, the
/// public path helpers (`audioURL(for:)`, `photoURL(for:)`,
/// `videoURL(for:)`) hide the difference from callers — they get a
/// stable filesystem URL they can read and write.
///
/// **The locked decision** (see `docs/design/Storage architecture · CLAUDE.md`):
/// originals (audio, photos, videos) live in iCloud Drive, not in
/// CloudKit. Per-record metadata (transcript, title, summary, topics,
/// projects, location) syncs via CloudKit. The user's iCloud quota
/// pays for the bytes; our CloudKit COGS only carry the structured
/// data. Files are visible in Files.app under "HiMem" because the
/// container is declared `NSUbiquitousContainerIsDocumentScopePublic`
/// in Info.plist.
///
/// **Threading.** `FileManager.url(forUbiquityContainerIdentifier:)`
/// must not be called on the main thread — Apple's docs say it
/// "doesn't return until iCloud configures the container directory"
/// and "can take an arbitrarily long time on the first call." So
/// `warmUp()` resolves the container off-main during app launch; until
/// it returns, the synchronous accessors fall back to sandbox. Once
/// resolved, every subsequent read uses ubiquity. The fallback path
/// is also what runs on devices without iCloud signed in.
final class UbiquityStore: @unchecked Sendable {
    static let shared = UbiquityStore()

    /// Container ID from `Info.plist` `NSUbiquitousContainers` and from
    /// the entitlement's `com.apple.developer.ubiquity-container-identifiers`.
    /// Same container as CloudKit — Apple lets one container host both.
    static let containerIdentifier = "iCloud.com.himem.app"

    /// Sandbox `Documents` directory. Used as the fallback when ubiquity
    /// isn't available. Resolved once at init — same on every launch.
    private let sandboxDocuments: URL

    /// Lock-protected snapshot of the resolved container URL. Reads are
    /// safe from any thread; writes only happen in `warmUp()`.
    private let lock = NSLock()
    private var _containerURL: URL?
    private var _isReady = false

    /// Resolved ubiquity container URL. `nil` until `warmUp()` finishes
    /// (during which time accessors fall back to sandbox) or if the
    /// user has iCloud signed out / iCloud Drive disabled.
    var containerURL: URL? {
        lock.lock(); defer { lock.unlock() }
        return _containerURL
    }

    /// True once `warmUp()` has finished, regardless of whether ubiquity
    /// was actually available. Callers that need to differentiate
    /// "haven't checked yet" from "checked and unavailable" can read
    /// this alongside `containerURL`.
    var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isReady
    }

    private init() {
        sandboxDocuments = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Test-only initializer that lets a suite point the store at a
    /// scratch directory. Production callers must use `.shared`.
    init(sandboxOverride: URL) {
        sandboxDocuments = sandboxOverride
    }

    /// Resolves the ubiquity container URL off the main thread and
    /// publishes it. Idempotent; subsequent calls are no-ops once the
    /// URL is set. Call from app launch.
    func warmUp() async {
        if isReady { return }
        let resolved = await Task.detached { () -> URL? in
            FileManager.default.url(forUbiquityContainerIdentifier: Self.containerIdentifier)
        }.value
        lock.lock()
        _containerURL = resolved
        _isReady = true
        lock.unlock()
        if let resolved {
            NSLog("[HiMem][Ubiquity] container resolved at \(resolved.path)")
        } else {
            NSLog("[HiMem][Ubiquity] container unavailable — falling back to sandbox Documents at \(sandboxDocuments.path)")
        }
    }

    // MARK: - Directory roots

    /// The directory that holds **user-visible** files. Ubiquity's
    /// `Documents/` subdirectory is what shows up in Files.app when
    /// the container is declared `IsDocumentScopePublic`. The sandbox
    /// fallback is the same `Documents` the app has always used.
    var documentsRoot: URL {
        if let containerURL {
            return containerURL.appendingPathComponent("Documents", isDirectory: true)
        }
        return sandboxDocuments
    }

    // MARK: - Subdirectory paths

    /// `Documents/Audio/` — voice recordings (master and split clips).
    var audioDirectory: URL { subdirectory("Audio") }

    /// `Documents/Photos/` — photos captured in-app and imported via PHPicker.
    var photosDirectory: URL { subdirectory("Photos") }

    /// `Documents/Videos/` — videos captured in-app and imported via PHPicker.
    var videosDirectory: URL { subdirectory("Videos") }

    /// `Documents/Inbox/` — watch-arrived audio clips, pre-bundle.
    /// Distinct from `Audio/` so the user-visible "Audio" folder is
    /// just memories' final files; transient inbox audio lives here
    /// until the user bundles it into a memory (moves to `Audio/`).
    var inboxDirectory: URL { subdirectory("Inbox") }

    private func subdirectory(_ name: String) -> URL {
        let url = documentsRoot.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - File URLs

    func audioURL(for filename: String) -> URL { audioDirectory.appendingPathComponent(filename) }
    func photoURL(for filename: String) -> URL { photosDirectory.appendingPathComponent(filename) }
    func videoURL(for filename: String) -> URL { videosDirectory.appendingPathComponent(filename) }
    func inboxURL(for filename: String) -> URL { inboxDirectory.appendingPathComponent(filename) }

    // MARK: - Download state

    /// Whether the file at `url` is on this device's local storage.
    enum DownloadStatus: Equatable {
        /// File is downloaded and locally available. Reads succeed.
        case downloaded
        /// File is present in iCloud Drive but not yet on this device.
        /// Caller should call `startDownload(at:)` and present a
        /// "downloading from iCloud" placeholder until the status
        /// flips to `downloaded`.
        case notDownloaded
        /// Download is currently in flight. Same UX state as
        /// `notDownloaded` from the user's perspective.
        case downloading
        /// File is missing from both local cache and iCloud Drive
        /// (deleted, never existed, or container unavailable).
        case missing
    }

    /// Reads the ubiquity download status. For sandbox-backed paths
    /// (no iCloud), returns `.downloaded` if the file exists and
    /// `.missing` otherwise — there's no concept of "in iCloud but
    /// not local" when ubiquity isn't in use.
    func downloadStatus(at url: URL) -> DownloadStatus {
        let fm = FileManager.default
        // Sandbox path: present or absent.
        if !isUnderContainer(url) {
            return fm.fileExists(atPath: url.path) ? .downloaded : .missing
        }
        // Ubiquity path: ask the file coordinator.
        do {
            let values = try url.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey
            ])
            if values.ubiquitousItemIsDownloading == true {
                return .downloading
            }
            switch values.ubiquitousItemDownloadingStatus {
            case .current, .downloaded:
                return .downloaded
            case .notDownloaded:
                return .notDownloaded
            default:
                return .notDownloaded
            }
        } catch {
            // No ubiquity metadata for this URL. If the file is
            // present we treat it as `.downloaded`; otherwise
            // `.missing` — the metadata error usually means the URL
            // doesn't correspond to any iCloud item.
            return fm.fileExists(atPath: url.path) ? .downloaded : .missing
        }
    }

    /// Asks iCloud to bring `url` down to local storage. No-op for
    /// sandbox paths or unavailable container. Best-effort: failures
    /// are logged but not surfaced, since the UI is already polling
    /// via `downloadStatus(at:)`.
    func startDownload(at url: URL) {
        guard isUnderContainer(url) else { return }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            NSLog("[HiMem][Ubiquity] startDownloadingUbiquitousItem failed for \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func isUnderContainer(_ url: URL) -> Bool {
        guard let containerURL else { return false }
        return url.path.hasPrefix(containerURL.path)
    }

    // MARK: - File operations (coordinated)

    /// Moves a file into the ubiquity container (or into the sandbox
    /// fallback) under the given destination URL. Uses NSFileCoordinator
    /// for the destination side so a concurrent sync read sees a
    /// consistent state. Returns the actual destination URL on success.
    @discardableResult
    func moveIntoStore(sourceURL: URL, destinationURL: URL) throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var moveError: Error?
        var resultURL: URL = destinationURL
        coordinator.coordinate(writingItemAt: destinationURL, options: .forReplacing, error: &coordinationError) { writeURL in
            do {
                try fm.moveItem(at: sourceURL, to: writeURL)
                resultURL = writeURL
            } catch {
                moveError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let moveError { throw moveError }
        return resultURL
    }

    /// Writes raw `Data` into the store at `destinationURL` via
    /// `NSFileCoordinator`. Used by PHPicker import and CameraService
    /// to drop bytes from PHAsset extracts into the ubiquity container.
    func writeData(_ data: Data, to destinationURL: URL) throws {
        let fm = FileManager.default
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: destinationURL, options: .forReplacing, error: &coordinationError) { writeURL in
            do {
                if fm.fileExists(atPath: writeURL.path) {
                    try fm.removeItem(at: writeURL)
                }
                try data.write(to: writeURL, options: [.atomic])
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
