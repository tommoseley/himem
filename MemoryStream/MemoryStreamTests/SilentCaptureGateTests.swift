import Testing
import Foundation
import AVFoundation
@testable import HiMem

/// **The `in_peak == 0` capture gate.**
///
/// A recording whose every sample is exactly zero is a capture failure.
/// Before this gate the app saved it, compressed it, transcribed it to
/// nothing, and said nothing — the silent-success class, in the one place
/// where it costs a *memory* rather than a tap. It is the defect B10 spent
/// most of a device pass chasing: a held capture device leaves every layer
/// we log perfectly plausible (session active, engine started, `isRecording`
/// true, buffers arriving with correct frame counts, a file written at
/// exactly the right size), and the *only* difference is that the samples
/// are zeros.
///
/// **What is ruled, and therefore pinned here** (2026-08-02):
///  - The copy: *"We didn't hear anything. Check that HiMem can use the
///    microphone, and try again."*
///  - The recording is **always kept**. We never discard audio on our own
///    judgment that it is empty; the user decides.
///  - **Exactly zero, no tolerance.** Any floor above zero is a judgment
///    about whether audio was *loud enough*, which we have no basis to
///    make (J5 — observe, don't conclude). Consequence, stated: the
///    `.measurement`-era under-gained clips (`in_peak ≈ 0.01`) had signal
///    and correctly do not trip this.
///  - **The shell owns the signal**, consulted for every landing — bench,
///    new memory, and memory-in-project. Wiring it into the Clips bench
///    alone would be an owner on one path and nothing on the other two,
///    which is the `.measurement`-on-the-watch / literal-on-the-phone
///    shape this codebase keeps paying for (F18, F6a).
///  - **The banner is suppressed under a debugger, the detection never
///    is** — gated on `P_TRACED`, not `#if DEBUG`, so an untethered
///    TestFlight build still speaks. The suppression announces itself, so
///    it is a stated skip and not the forbidden silent opt-out.
///
/// **Which tests are which, stated so a green count doesn't imply a cycle
/// it didn't have.** The three caller guards under "The reproduction" were
/// written first and **observed red against the shipped tree** — 0 compile
/// errors, `Test run with 7 tests in 1 suite`, four assertion failures at
/// the named assertions, with all four scanner self-tests green. Everything
/// below them is a *contract* test (ADR-050): written alongside the type,
/// passing on first run, pinning the contract going forward.
@Suite struct SilentCaptureGateTests {

    // MARK: - The reproduction (caller guards)

    /// **The gate must measure every buffer.** `[Amp]` samples buffers 1–3
    /// and every 50th — that is an *instrument*, not a gate: a recording
    /// silent everywhere except one unsampled buffer would read as silent,
    /// and one silent only in the sampled windows would read as heard.
    /// The observer has to see the whole session.
    @Test func theTapMeasuresEveryBuffer_notOnlyTheSampledOnes() throws {
        let src = try Self.speechSource()
        let closure = try Self.requireBlockBody(startingAtLineContaining: "inputNode.installTap(", in: src)
        #expect(
            Self.measuresOnlyInsideTheSampledWindow(tapClosure: closure) == false,
            """
            The silence observer is not fed on every buffer. `[Amp]`'s \
            `if n <= 3 || n % 50 == 0` window is a sampled instrument; a gate \
            reading from inside it measures the samples, not the recording. \
            Tap closure was:
            \(closure)
            """
        )
    }

    /// **The save path must consult what was measured.** The observer being
    /// correct says nothing about whether anyone reads it — the whole point
    /// of Guard-the-Caller. `stopRecording` is where the session's peak
    /// becomes a fact, beside `lastRecordingPath`.
    @Test func stopRecordingPublishesTheOutcome() throws {
        let src = try Self.speechSource()
        let body = try Self.requireBlockBody(startingAtLineContaining: "func stopRecording()", in: src)
        #expect(body.contains("silenceObserver"),
                "`stopRecording` never reads the silence observer, so nothing downstream can know. Body:\n\(body)")
        #expect(body.contains("lastCaptureSilence"),
                "`stopRecording` measures and never publishes the outcome. Body:\n\(body)")
    }

    /// **Every landing, not one.** The reference must sit outside the
    /// `switch landing` — a silent recording that becomes a *memory* is the
    /// more expensive loss, and the memory landings have no toast slot of
    /// their own, so they are exactly the ones a bench-only fix would miss.
    @Test func theShellConsultsTheGateOnEveryLanding() throws {
        let src = try Self.shellSource()
        let body = try Self.requireBlockBody(startingAtLineContaining: "private func handleCapturedItem(", in: src)
        #expect(
            Self.consultsTheGateOutsideTheSwitch(body: body),
            """
            `handleCapturedItem` does not consult the silent-capture gate for \
            every landing. A reference that lives inside `switch landing` covers \
            one path and silently drops the other two. Body was:
            \(body)
            """
        )
        // …and assigns from `bannerMessage`, which returns nil for a
        // recording that was heard. A conditional set-only assignment
        // leaves a banner standing after a later recording that worked.
        #expect(
            Self.codeOnly(body).contains("silentCaptureMessage = SilentCaptureDecision.bannerMessage("),
            """
            The shell does not assign the banner unconditionally from \
            `bannerMessage`, so a message can outlive the recording it \
            describes — the frozen-snapshot class (F24 D2, F25). Body was:
            \(body)
            """
        )
    }

    /// `nil` means *show nothing*, never *leave what was there*. This is
    /// what makes the caller's unconditional assignment safe.
    @Test func bannerMessageClearsItselfForEveryNonSilentOutcome() {
        #expect(SilentCaptureDecision.bannerMessage(for: .silent) == SilentCaptureDecision.message)
        #expect(SilentCaptureDecision.bannerMessage(for: .heard) == nil)
        #expect(SilentCaptureDecision.bannerMessage(for: .notMeasured) == nil)
        #expect(SilentCaptureDecision.bannerMessage(for: .silentDebuggerAttached) == nil)
    }

    // MARK: - Self-tests (a guard that cannot fail is not a guard)

    @Test func scanner_flagsATapThatMeasuresOnlyInsideTheSampledWindow() {
        let offending = """
        { [weak self] buffer, _ in
            let n = bufferCounter.increment()
            if n <= 3 || n % 50 == 0 {
                var peak: Float = 0
                self?.silenceObserver.observe(buffer)
                NSLog("[Amp] tap")
            }
            self?.streamBuffer(buffer)
        }
        """
        #expect(Self.measuresOnlyInsideTheSampledWindow(tapClosure: offending) == true)
    }

    @Test func scanner_acceptsATapThatMeasuresUnconditionally() {
        let fixed = """
        { [weak self] buffer, _ in
            let n = bufferCounter.increment()
            self?.silenceObserver.observe(buffer)
            if n <= 3 || n % 50 == 0 {
                NSLog("[Amp] tap")
            }
            self?.streamBuffer(buffer)
        }
        """
        #expect(Self.measuresOnlyInsideTheSampledWindow(tapClosure: fixed) == false)
    }

    @Test func scanner_flagsAGateConsultedInsideOneLandingOnly() {
        let offending = """
        {
            switch landing {
            case .dropOnBench:
                if SilentCaptureDecision.showsBanner(speechService.lastCaptureSilence) {
                    silentCaptureMessage = SilentCaptureDecision.message
                }
            case .createMemory:
                break
            }
        }
        """
        #expect(Self.consultsTheGateOutsideTheSwitch(body: offending) == false)
    }

    @Test func scanner_acceptsAGateConsultedBeforeTheSwitch() {
        let fixed = """
        {
            if SilentCaptureDecision.showsBanner(speechService.lastCaptureSilence) {
                silentCaptureMessage = SilentCaptureDecision.message
            }
            switch landing {
            case .dropOnBench:
                break
            }
        }
        """
        #expect(Self.consultsTheGateOutsideTheSwitch(body: fixed) == true)
    }

    // MARK: - Suppression is presentation-only (contract)

    /// Under a debugger the banner is withheld; the detection, the outcome,
    /// and the log line are not. A gate that stopped *detecting* when
    /// attached would be the silent skip this project forbids — and it
    /// would have hidden B10 rather than caught it.
    @Test func theDebuggerSuppressesTheBannerAndNothingElse() throws {
        let attached = SilentCaptureDecision.evaluate(peak: 0, buffersMeasured: 240, debuggerAttached: true)
        let untethered = SilentCaptureDecision.evaluate(peak: 0, buffersMeasured: 240, debuggerAttached: false)
        // Detection happens in BOTH cases — the outcomes differ only in
        // whether they are shown.
        #expect(attached == .silentDebuggerAttached)
        #expect(untethered == .silent)
        #expect(SilentCaptureDecision.showsBanner(attached) == false)
        #expect(SilentCaptureDecision.showsBanner(untethered))

        // Gated on P_TRACED, never on the build configuration: a TestFlight
        // build is a release build, and Judi's is the case that matters.
        //
        // Read from CODE, not from the file's text. The first version of
        // this assertion scanned the raw source and failed on the detector's
        // own doc comment — which says "deliberately not `#if DEBUG`". A
        // scanner that cannot tell prose from code measures the wrong thing;
        // caught here rather than by someone later deleting a true sentence
        // to make a test pass.
        let code = Self.codeOnly(try Self.detectorSource())
        #expect(code.contains("#if DEBUG") == false,
                "The gate is gated on the build configuration. Ruled: P_TRACED, so an untethered TestFlight build still shows it.")
        #expect(code.contains("P_TRACED"),
                "Debugger detection no longer reads P_TRACED.")
    }

    /// Self-test: the configuration scanner sees a real `#if DEBUG`…
    @Test func scanner_flagsARealBuildConfigurationGate() {
        let offending = """
        static var isAttached: Bool {
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
        """
        #expect(Self.codeOnly(offending).contains("#if DEBUG"))
    }

    /// …and does not see one that is only being talked about.
    @Test func scanner_ignoresABuildConfigurationMentionedInProse() {
        let fine = """
        /// P_TRACED, deliberately not `#if DEBUG` — a TestFlight build is a
        /// release build.
        static var isAttached: Bool { checkP_TRACED() } // not #if DEBUG
        """
        #expect(Self.codeOnly(fine).contains("#if DEBUG") == false)
        #expect(Self.codeOnly(fine).contains("P_TRACED"))
    }

    /// The suppression announces itself. A `print`-and-return reports as
    /// PASSED, and a suppression nobody can see is that same shape one
    /// layer out — so the log line is part of the contract, not decoration.
    @Test func theSuppressedCaseAnnouncesItself() {
        #expect(SilentCaptureDecision.logLine(for: .silentDebuggerAttached)
                == "[HiMem][Speech][Amp] capture was silent — banner suppressed (debugger attached)")
        #expect(SilentCaptureDecision.logLine(for: .silent)?.isEmpty == false)
        #expect(SilentCaptureDecision.logLine(for: .heard) == nil)
        #expect(SilentCaptureDecision.logLine(for: .notMeasured) == nil)
    }

    // MARK: - The decision table (contract)

    /// Exactly zero and nothing else. `Float.leastNonzeroMagnitude` is
    /// signal — vanishingly quiet signal, but not the flat line a dead
    /// capture path produces, and we are not entitled to call it silence.
    @Test func onlyExactZeroIsSilence() {
        #expect(SilentCaptureDecision.evaluate(peak: 0, buffersMeasured: 100, debuggerAttached: false) == .silent)
        #expect(SilentCaptureDecision.evaluate(peak: .leastNonzeroMagnitude, buffersMeasured: 100, debuggerAttached: false) == .heard)
        // The `.measurement`-era population: suppressed gain, real audio.
        // It must NOT trip this gate — that is a separate item (D9/D9b),
        // not a hole in this one.
        #expect(SilentCaptureDecision.evaluate(peak: 0.01, buffersMeasured: 100, debuggerAttached: false) == .heard)
    }

    /// **Never claim silence we did not measure.** Zero buffers means the
    /// capture never ran, which is F18's *"We couldn't start recording."* —
    /// a different fact with a different message. Reporting it as silence
    /// would be a confident falsehood, the sin this gate exists to end.
    @Test func nothingMeasuredIsNotSilence() {
        let outcome = SilentCaptureDecision.evaluate(peak: 0, buffersMeasured: 0, debuggerAttached: false)
        #expect(outcome == .notMeasured)
        #expect(SilentCaptureDecision.showsBanner(outcome) == false)
    }

    /// The wording IS the promise here (ruled copy, 2026-08-02), so the
    /// literal is pinned deliberately: a failure of this test means the
    /// promise moved, not that phrasing drifted. Crucible voice — names the
    /// state, never blames the user, offers the one useful action.
    @Test func theMessageIsTheRuledString() {
        #expect(SilentCaptureDecision.message
                == "We didn't hear anything. Check that HiMem can use the microphone, and try again.")
        #expect(SilentCaptureDecision.message.hasPrefix("You") == false)
    }

    /// It must not share a string with the two neighbouring states. All
    /// three can be true of one clip and they answer different questions:
    /// this one at save, "No words in this recording." on opening the clip,
    /// "We couldn't start recording." when capture never began — F24 D4's
    /// rule, one state further out.
    @Test func theMessageIsDistinctFromItsNeighbours() {
        let neighbours = ["No words in this recording.", CaptureUnavailableView.audioMessage]
        for other in neighbours {
            #expect(SilentCaptureDecision.message != other)
        }
    }

    // MARK: - The observer (contract)

    /// The B10 shape, reproduced from buffers: correct frame counts, a
    /// plausible session length, every sample zero.
    @Test func observer_allZeroBuffers_readSilent() {
        let observer = SilentCaptureObserver()
        for _ in 0..<300 { observer.observe(Self.buffer(peak: 0)) }
        #expect(observer.buffersMeasured == 300)
        #expect(observer.measuredPeak == 0)
        #expect(observer.outcome(debuggerAttached: false) == .silent)
    }

    /// One non-zero sample anywhere in the session is signal. **This is the
    /// ceiling on the assertion above** — a gate that only ever said
    /// "silent" would pass the previous test and be worthless (the
    /// `ratio >= 10.0` lesson: bound both sides).
    @Test func observer_oneLiveBufferAmongZeros_readsHeard() {
        let observer = SilentCaptureObserver()
        for i in 0..<300 {
            observer.observe(Self.buffer(peak: i == 217 ? 0.02 : 0))
        }
        #expect(observer.outcome(debuggerAttached: false) == .heard)
    }

    /// A fresh session must not inherit the previous one's peak.
    @Test func observer_resetsBetweenRecordings() {
        let observer = SilentCaptureObserver()
        observer.observe(Self.buffer(peak: 0.5))
        observer.reset()
        for _ in 0..<10 { observer.observe(Self.buffer(peak: 0)) }
        #expect(observer.outcome(debuggerAttached: false) == .silent)
    }

    /// Every channel is read, not just channel 0. The watch's 3-channel
    /// input put the downlink reference on channel 0 and the mic elsewhere;
    /// a channel-0-only peak would call that recording dead.
    @Test func observer_readsEveryChannel() {
        let observer = SilentCaptureObserver()
        observer.observe(Self.buffer(peak: 0.3, channels: 2, liveChannel: 1))
        #expect(observer.outcome(debuggerAttached: false) == .heard)
    }

    /// Nothing observed yet is `.notMeasured`, not `.silent` — the same
    /// distinction as the decision table, at the observer's own boundary.
    @Test func observer_beforeAnyBuffer_isNotMeasured() {
        #expect(SilentCaptureObserver().outcome(debuggerAttached: false) == .notMeasured)
    }

    // MARK: - Fixtures

    /// A buffer that is zero everywhere except one sample of `peak` on
    /// `liveChannel` — the smallest thing that is honestly a buffer.
    static func buffer(peak: Float, channels: AVAudioChannelCount = 1, liveChannel: Int = 0) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: channels)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        for c in 0..<Int(channels) {
            let samples = buffer.floatChannelData![c]
            for i in 0..<1024 { samples[i] = 0 }
            if c == liveChannel { samples[512] = peak }
        }
        return buffer
    }

    // MARK: - Scanners

    /// True when the observer is fed *only* from inside `[Amp]`'s sampled
    /// window — i.e. the gate is reading the instrument's samples rather
    /// than the recording.
    static func measuresOnlyInsideTheSampledWindow(tapClosure: String) -> Bool {
        let sampled = blockBody(startingAtLineContaining: "if n <= 3 || n % 50 == 0", in: tapClosure) ?? ""
        let outsideSampledWindow = tapClosure.replacingOccurrences(of: sampled, with: "")
        return outsideSampledWindow.contains("silenceObserver.observe(") == false
    }

    /// True when the gate is consulted outside `switch landing` — once, for
    /// every landing — rather than inside one of its cases.
    static func consultsTheGateOutsideTheSwitch(body: String) -> Bool {
        let landingSwitch = blockBody(startingAtLineContaining: "switch landing {", in: body) ?? ""
        let outsideTheSwitch = body.replacingOccurrences(of: landingSwitch, with: "")
        return outsideTheSwitch.contains("SilentCaptureDecision")
    }

    /// Source with `//`-comments removed, so an assertion about what the
    /// code *does* cannot be satisfied — or broken — by what it *says*.
    static func codeOnly(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let marker = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<marker.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - Source access

    /// Brace-matched body of the block introduced on the first line
    /// containing `needle`, that line included.
    static func blockBody(startingAtLineContaining needle: String, in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else { return nil }
        var depth = 0
        var started = false
        var out: [String] = []
        for line in lines[start...] {
            for ch in line {
                if ch == "{" { depth += 1; started = true }
                if ch == "}" { depth -= 1 }
            }
            if started { out.append(line) }
            if started && depth == 0 { return out.joined(separator: "\n") }
        }
        return nil
    }

    static func requireBlockBody(startingAtLineContaining needle: String, in source: String) throws -> String {
        guard let body = blockBody(startingAtLineContaining: needle, in: source) else {
            throw Failure.blockNotFound(needle)
        }
        return body
    }

    static func speechSource() throws -> String {
        try source("MemoryStream/Services/AI/SpeechService.swift")
    }

    static func shellSource() throws -> String {
        try source("MemoryStream/Views/HiMemTabView.swift")
    }

    static func detectorSource() throws -> String {
        try source("MemoryStream/Services/AI/SilentCapture.swift")
    }

    /// Throws rather than returning empty if the walk reaches no source — a
    /// scanner that silently matches nothing reports a clean sweep forever
    /// (the `loudPeakThenSilence` lesson).
    static func source(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String), blockNotFound(String) }
}
