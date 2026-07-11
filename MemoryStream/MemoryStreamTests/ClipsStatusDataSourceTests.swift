import Testing
import Foundation
@testable import HiMem

/// Money tests for `ClipsStatusDataSource.compute(...)` — the pure
/// counting function behind the "Clips" status sheet (`ClipsStatusSheet`).
///
/// Bug-first (2026-07-11): field-observed screenshot showed a 3-clip
/// session on the bench (`"3 new clips · 1 session · today, 10:32
/// AM–10:35 AM"`) but the status sheet reported `Apple Watch: 0`,
/// `iPhone: 0`, `Siri: 0`, and `Loose clips: 1` — only 1 of the 3
/// visible clips accounted for anywhere in the sheet. Root cause:
/// `phoneArrivals` was hardcoded to `0` from before Slice D added
/// phone captures to the inbox bench (`PhoneCaptureBenchDispatcher`
/// with `source == "phone"`). Post-Slice-D those phone clips ARE
/// on the bench but the sheet's honesty contract silently missed
/// them.
///
/// The reproducing test is
/// `phoneSourceClips_areCounted_asPhoneArrivals` — it fails against
/// the pre-fix code (returns 0), passes after the fix (returns the
/// filter count).
@Suite
struct ClipsStatusDataSourceTests {

    // MARK: - Watch source counting

    @Test func watchSourceClips_areCounted_asWatchArrivals() {
        let clips = [
            Self.clip(source: "watch"),
            Self.clip(source: "watch"),
            Self.clip(source: "phone")
        ]
        let data = ClipsStatusDataSource.compute(
            clips: clips,
            organizing: 0,
            looseClips: 0,
            photoArrivals: 0,
            videoArrivals: 0,
            noteArrivals: 0
        )
        #expect(data.watchArrivals == 2)
    }

    // MARK: - Phone source counting (bug-fix money test)

    /// Money test for the field-observed bug. Before the fix,
    /// `phoneArrivals` was hardcoded to `0`; the assertion below
    /// failed with `actual == 0`. After the fix,
    /// `phoneArrivals` equals the filter count.
    @Test func phoneSourceClips_areCounted_asPhoneArrivals() {
        let clips = [
            Self.clip(source: "phone"),
            Self.clip(source: "phone"),
            Self.clip(source: "watch")
        ]
        let data = ClipsStatusDataSource.compute(
            clips: clips,
            organizing: 0,
            looseClips: 0,
            photoArrivals: 0,
            videoArrivals: 0,
            noteArrivals: 0
        )
        #expect(data.phoneArrivals == 2,
                "Phone-source clips must be counted as phone arrivals — Slice D added phone captures to the inbox bench, so the sheet must report them")
    }

    // MARK: - Siri stays out of the manifest

    @Test func siriArrivals_alwaysZero_becauseSiriSkipsTheBench() {
        // Siri captures still land as memories directly, per the
        // sheet's spec. Even if a rogue clip claimed source == "siri",
        // the sheet reports 0 until the capture path routes them
        // through the manifest.
        let clips = [Self.clip(source: "siri")]
        let data = ClipsStatusDataSource.compute(
            clips: clips,
            organizing: 0,
            looseClips: 0,
            photoArrivals: 0,
            videoArrivals: 0,
            noteArrivals: 0
        )
        #expect(data.siriArrivals == 0)
    }

    // MARK: - Downloading status counting

    @Test func announcedAndReceived_countAsDownloading() {
        let clips = [
            Self.clip(source: "watch", status: .announced),
            Self.clip(source: "watch", status: .received),
            Self.clip(source: "watch", status: .transcribed),
            Self.clip(source: "watch", status: .disposed)
        ]
        let data = ClipsStatusDataSource.compute(
            clips: clips,
            organizing: 0,
            looseClips: 0,
            photoArrivals: 0,
            videoArrivals: 0,
            noteArrivals: 0
        )
        #expect(data.downloading == 2,
                "Only .announced and .received should count as downloading — .transcribing is post-file, .transcribed and .disposed are terminal")
    }

    // MARK: - Loose + organizing pass through

    @Test func organizingAndLoose_areHandedThroughUnchanged() {
        let data = ClipsStatusDataSource.compute(
            clips: [],
            organizing: 7,
            looseClips: 12,
            photoArrivals: 0,
            videoArrivals: 0,
            noteArrivals: 0
        )
        #expect(data.organizing == 7)
        #expect(data.looseClips == 12)
    }

    // MARK: - Media-type arrivals (Tom 2026-07-11)

    /// Photos / Videos / Notes get their own rows under
    /// **New arrivals** so the sheet reads the same media
    /// vocabulary as the mixed session card (`MediaRow`).
    /// `compute` plumbs the caller-supplied counts through — the
    /// loose-by-kind Core Data fetch lives on `snapshot()`.
    @Test func mediaTypeArrivals_areHandedThroughUnchanged() {
        let data = ClipsStatusDataSource.compute(
            clips: [],
            organizing: 0,
            looseClips: 6,
            photoArrivals: 3,
            videoArrivals: 2,
            noteArrivals: 1
        )
        #expect(data.photoArrivals == 3)
        #expect(data.videoArrivals == 2)
        #expect(data.noteArrivals == 1)
        // The aggregate `looseClips` stays honest — the sheet's
        // "Available to shape" line reads the total; the per-
        // kind rows read the breakdown.
        #expect(data.looseClips == 6)
    }

    // MARK: - Field-observed scenario

    /// The exact shape of the screenshot: 2 phone-source voice
    /// clips in a session + 1 loose photo (a `MediaReference` with
    /// no edges — passed through as `looseClips`). After the fix,
    /// every one of the three visible clips is accounted for.
    @Test func fieldScenario_3ClipSession_2PhoneVoice_1LoosePhoto_accountsForAllThree() {
        let clips = [
            Self.clip(source: "phone", status: .transcribed),
            Self.clip(source: "phone", status: .transcribed)
        ]
        let data = ClipsStatusDataSource.compute(
            clips: clips,
            organizing: 0,
            looseClips: 1,
            photoArrivals: 1,
            videoArrivals: 0,
            noteArrivals: 0
        )
        // Two voice clips visible in the session → phoneArrivals.
        #expect(data.phoneArrivals == 2)
        // One photo visible → photoArrivals row (per Tom 2026-07-11)
        // and folded into the aggregate `looseClips` total.
        #expect(data.photoArrivals == 1)
        #expect(data.looseClips == 1)
        // Sum of the per-source + per-media-type arrivals =
        // every clip the user sees on the bench. Before the phone-
        // source fix this was 1 (only the photo, via looseClips);
        // after both fixes it's 3.
        let arrivalsTotal =
            data.watchArrivals + data.phoneArrivals + data.siriArrivals
            + data.photoArrivals + data.videoArrivals + data.noteArrivals
        #expect(arrivalsTotal == 3,
                "The sheet's arrival counters must together account for every clip the user sees on the bench — silent undercount broke the honesty contract")
    }

    // MARK: - Helpers

    private static func clip(source: String, status: InboxClip.Status = .transcribed) -> InboxClip {
        InboxClip(
            clipId: UUID(),
            capturedAt: Date(),
            duration: 2.0,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: source,
            audioFilename: "\(UUID().uuidString).caf",
            transcriptionAttempted: true,
            rollGroupId: nil,
            status: status,
            disposedAt: nil,
            announcedAt: nil,
            fileSizeBytes: nil
        )
    }
}
