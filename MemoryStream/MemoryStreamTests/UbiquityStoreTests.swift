import Testing
import Foundation
@testable import HiMem

/// Foundation tests for `UbiquityStore` — path resolution + sandbox
/// fallback behavior. Tests never hit real iCloud; the container is
/// always unavailable in the test environment, so every test
/// effectively exercises the sandbox-fallback path. That's the right
/// invariant: sandbox-fallback is what runs for users without iCloud
/// signed in, and it must keep working.
///
/// The ubiquity download-state machinery (download status, startDownload)
/// can only be meaningfully tested on a real device with iCloud. We
/// cover the sandbox-side of `downloadStatus` here; the ubiquity-side
/// paths are exercised manually on device.
@MainActor
struct UbiquityStoreTests {

    private func scratchSandbox() throws -> (URL, () -> Void) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ubiquity-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return (url, { try? FileManager.default.removeItem(at: url) })
    }

    @Test func sandboxFallback_audioURL_lookupComposes() throws {
        let (root, cleanup) = try scratchSandbox()
        defer { cleanup() }
        let store = UbiquityStore(sandboxOverride: root)
        let url = store.audioURL(for: "abc.caf")
        #expect(url.lastPathComponent == "abc.caf")
        #expect(url.path.contains("/Audio/"))
        // Audio directory should have been created on access.
        #expect(FileManager.default.fileExists(atPath: store.audioDirectory.path))
    }

    @Test func sandboxFallback_photoURL_lookupComposes() throws {
        let (root, cleanup) = try scratchSandbox()
        defer { cleanup() }
        let store = UbiquityStore(sandboxOverride: root)
        let url = store.photoURL(for: "abc.jpg")
        #expect(url.lastPathComponent == "abc.jpg")
        #expect(url.path.contains("/Photos/"))
    }

    @Test func sandboxFallback_videoURL_lookupComposes() throws {
        let (root, cleanup) = try scratchSandbox()
        defer { cleanup() }
        let store = UbiquityStore(sandboxOverride: root)
        let url = store.videoURL(for: "abc.mov")
        #expect(url.lastPathComponent == "abc.mov")
        #expect(url.path.contains("/Videos/"))
    }

    @Test func sandboxFallback_inboxURL_lookupComposes() throws {
        let (root, cleanup) = try scratchSandbox()
        defer { cleanup() }
        let store = UbiquityStore(sandboxOverride: root)
        let url = store.inboxURL(for: "abc.caf")
        #expect(url.lastPathComponent == "abc.caf")
        #expect(url.path.contains("/Inbox/"))
    }

    @Test func sandboxFallback_directoriesAreIndependent() throws {
        let (root, cleanup) = try scratchSandbox()
        defer { cleanup() }
        let store = UbiquityStore(sandboxOverride: root)
        #expect(store.audioDirectory != store.photosDirectory)
        #expect(store.photosDirectory != store.videosDirectory)
        #expect(store.audioDirectory != store.inboxDirectory)
    }

    /// Sandbox download status: present → `.downloaded`, missing → `.missing`.
    @Test func sandboxDownloadStatus_distinguishesPresentFromMissing() throws {
        let (root, cleanup) = try scratchSandbox()
        defer { cleanup() }
        let store = UbiquityStore(sandboxOverride: root)
        let url = store.audioURL(for: "abc.caf")
        // Missing.
        #expect(store.downloadStatus(at: url) == .missing)
        // Create it.
        FileManager.default.createFile(atPath: url.path, contents: Data("hello".utf8))
        #expect(store.downloadStatus(at: url) == .downloaded)
    }

    /// `startDownload` is a safe no-op for sandbox-backed paths.
    @Test func startDownload_sandboxPath_isNoOp() throws {
        let (root, cleanup) = try scratchSandbox()
        defer { cleanup() }
        let store = UbiquityStore(sandboxOverride: root)
        let url = store.audioURL(for: "abc.caf")
        // Should not throw or crash.
        store.startDownload(at: url)
    }

    /// `moveIntoStore` relocates a file from an external source to a
    /// store-managed destination, preserving the bytes and removing
    /// the source.
    @Test func moveIntoStore_relocatesFile() throws {
        let (root, cleanup) = try scratchSandbox()
        defer { cleanup() }
        let store = UbiquityStore(sandboxOverride: root)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("src-\(UUID().uuidString).caf")
        try Data("audio".utf8).write(to: source)
        let dest = store.audioURL(for: "moved.caf")
        let resultURL = try store.moveIntoStore(sourceURL: source, destinationURL: dest)
        #expect(FileManager.default.fileExists(atPath: resultURL.path))
        #expect(!FileManager.default.fileExists(atPath: source.path))
        let bytes = try Data(contentsOf: resultURL)
        #expect(String(decoding: bytes, as: UTF8.self) == "audio")
    }

    /// `writeData` lays down raw bytes via NSFileCoordinator at a
    /// store-managed destination.
    @Test func writeData_writesAtDestination() throws {
        let (root, cleanup) = try scratchSandbox()
        defer { cleanup() }
        let store = UbiquityStore(sandboxOverride: root)
        let dest = store.photoURL(for: "test.jpg")
        try store.writeData(Data("photo".utf8), to: dest)
        let bytes = try Data(contentsOf: dest)
        #expect(String(decoding: bytes, as: UTF8.self) == "photo")
    }

    /// `writeData` replaces an existing file at the destination
    /// without leaving stale bytes behind.
    @Test func writeData_replacesExistingFile() throws {
        let (root, cleanup) = try scratchSandbox()
        defer { cleanup() }
        let store = UbiquityStore(sandboxOverride: root)
        let dest = store.photoURL(for: "test.jpg")
        try store.writeData(Data("first".utf8), to: dest)
        try store.writeData(Data("second".utf8), to: dest)
        let bytes = try Data(contentsOf: dest)
        #expect(String(decoding: bytes, as: UTF8.self) == "second")
    }
}
