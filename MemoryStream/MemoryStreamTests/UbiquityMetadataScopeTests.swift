import Testing
import Foundation
@testable import HiMem

/// **B29's guard: the download watcher must look where the files are.**
///
/// `WatchSessionDelegate.awaitDownloads` arms an `NSMetadataQuery` so a
/// stranded clip resumes when iCloud delivers its bytes — *"a file's arrival is
/// an EVENT, not a poll"* (B15, `8a36eea`). It was armed on
/// `NSMetadataQueryUbiquitousDataScope`, which the SDK defines as the container
/// **excluding** `Documents/` — and every file this app writes lives under
/// `Documents/`. The query could not match, so the event could never fire.
///
/// **Why a config-invariant test rather than a behavioural one.** Exercising
/// the resumption end-to-end needs a real iCloud download landing on a real
/// device; B15 recorded that as unreachable from the simulator suite, and it
/// still is. This is the same trade as `WatchAudioSessionConfigTests`, which
/// pins the capture mode to `.default` because measuring real input energy
/// needs mic hardware: the deterministic guard is that a refactor cannot
/// silently revert the constant.
///
/// **Stated limit, so the green is not over-read: this proves the query is
/// pointed at the right scope. It does NOT prove the resumption fires.** B29
/// stays open until `ubiquity update — re-entering sweep` is observed on
/// hardware.
struct UbiquityMetadataScopeTests {

    enum Failure: Error { case unreadable(String) }

    /// **The correspondence, which is the real invariant.** Asserting the
    /// constant alone would pin a literal; asserting it *against the layout*
    /// means moving the container's root breaks this test, which is what makes
    /// the two unable to drift apart.
    @Test func theSearchScopeMatchesTheDirectoryTheFilesAreIn() {
        #expect(UbiquityStore.metadataSearchScope == NSMetadataQueryUbiquitousDocumentsScope, """
            The watcher's scope is not the Documents scope. The SDK defines \
            NSMetadataQueryUbiquitousDataScope as the container EXCLUDING \
            Documents/, and every file this app writes lives under \
            documentsRoot — so that scope can never match, and a stranded clip \
            is never resumed (B29).
            """)

        // Both branches of `documentsRoot` end in "Documents" — the ubiquity
        // container's subdirectory, and the sandbox fallback — so this holds
        // in a test process, where the container is unavailable.
        #expect(UbiquityStore.shared.documentsRoot.lastPathComponent == "Documents", """
            The layout moved out of `Documents/`. If files no longer live \
            there, `metadataSearchScope` is now wrong and must move with them — \
            that is what this pairing exists to catch.
            """)
    }

    /// The audio the watcher waits for is under the scanned root, not beside
    /// it. Pins the specific path B29 was stranded in.
    @Test func theInboxAudioLivesUnderTheScannedRoot() {
        let root = UbiquityStore.shared.documentsRoot.standardizedFileURL.path
        let inbox = InboxManifest.audioURL(for: "probe.m4a").standardizedFileURL.path
        #expect(inbox.hasPrefix(root), """
            Inbox audio (\(inbox)) is not under the documents root (\(root)), \
            so the Documents-scoped query cannot see it either. The scope and \
            the write path have diverged.
            """)
    }

    // MARK: - The caller actually consults the owner

    /// **Verified red before the fix.** A correct constant nobody reads is the
    /// `MediaBlobOrphanSweep` shape — complete, tested, zero production
    /// callers. CLAUDE.md § Guard the Caller: assert the caller reaches the
    /// decision, not merely that the decision is right.
    @Test func theDownloadWatcherUsesTheOwnedScope() throws {
        let src = try Self.watchDelegateSource()
        let code = Self.codeLines(of: src)

        #expect(!code.contains("NSMetadataQueryUbiquitousDataScope"), """
            The download watcher still names the Data scope literal — the \
            container EXCLUDING Documents/, where none of our files are. This \
            is B29 exactly.
            """)
        #expect(code.contains("UbiquityStore.metadataSearchScope"), """
            The watcher sets a scope without asking the owner. A literal at the \
            call site is how this diverged from the layout in the first place.
            """)
    }

    /// Guards the guard, including **malformed input** — a scanner's input is
    /// every line of the file, not what a test constructs, and one that traps
    /// takes down the host rather than failing (CLAUDE.md § Guard the Caller).
    @Test func theScopeScannerStripsProseAndSurvivesDegenerateInput() {
        #expect(Self.codeLines(of: "let s = NSMetadataQueryUbiquitousDataScope")
            .contains("NSMetadataQueryUbiquitousDataScope"))
        #expect(!Self.codeLines(of: "/// was NSMetadataQueryUbiquitousDataScope before B29")
            .contains("NSMetadataQueryUbiquitousDataScope"), "prose is not code")
        #expect(!Self.codeLines(of: "// NSMetadataQueryUbiquitousDataScope")
            .contains("NSMetadataQueryUbiquitousDataScope"), "a comment is not code")
        #expect(Self.codeLines(of: "").isEmpty, "empty input must not match or trap")
        #expect(Self.codeLines(of: "   \n\t\n").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "whitespace-only input must not match or trap")
    }

    static func codeLines(of source: String) -> String {
        source.components(separatedBy: "\n")
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///")
            }
            .joined(separator: "\n")
    }

    /// Throws rather than returning empty, so the guard cannot pass by failing
    /// to find its subject.
    static func watchDelegateSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MemoryStream/Services/Watch/WatchSessionDelegate.swift")
        guard let s = try? String(contentsOf: url, encoding: .utf8) else {
            throw Failure.unreadable(url.path)
        }
        return s
    }
}
