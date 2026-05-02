import SwiftUI

struct VoiceSearchView: View {
    @ObservedObject var speechService: SpeechService
    let knownTopics: [String]
    let onCommit: (_ query: String, _ submit: Bool) -> Void
    let onCancel: () -> Void

    @State private var phase: Phase = .listening
    @State private var interpreted: VoiceIntentParser.Result?
    @State private var heardTranscript: String = ""
    @State private var silenceWatcher = VoiceSilenceWatcher()

    enum Phase { case listening, interpreted }

    var body: some View {
        ZStack {
            Crucible.Color.paper.ignoresSafeArea()
            switch phase {
            case .listening: listeningBody
            case .interpreted: interpretedBody
            }
        }
        .onAppear {
            speechService.transcribedText = ""
            speechService.startRecording()
            startSilenceWatcher()
        }
        .onDisappear {
            silenceWatcher.cancel()
            if speechService.isRecording { speechService.stopRecording() }
        }
    }

    // MARK: - Listening

    private var listeningBody: some View {
        ZStack(alignment: .topLeading) {
            // Back chevron, anchored top-left
            Button { cancel() } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundStyle(Crucible.Color.ink)
                    .padding(Crucible.Space.lg)
            }

            // Vertically-centered listening group
            VStack(spacing: Crucible.Space.lg) {
                // Orange dot + LISTENING label
                HStack(spacing: 6) {
                    Circle()
                        .fill(Crucible.Color.captureAudio)
                        .frame(width: 6, height: 6)
                    Text("LISTENING")
                        .font(.footnote.weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(Crucible.Color.accent)
                }

                BreathingWaveform(isActive: speechService.isRecording)
                    .frame(width: 160, height: 36)

                if !speechService.transcribedText.isEmpty {
                    Text("\u{201C}\(speechService.transcribedText)\u{201D}")
                        .font(.system(size: 22, design: .serif))
                        .italic()
                        .foregroundStyle(Crucible.Color.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Crucible.Space.xxl)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // Reserves vertical space so the helper + Done don't jump
                    // when the transcript first appears.
                    Color.clear.frame(height: 30)
                }

                Text("Speak naturally. Tap Done when finished.")
                    .font(.footnote)
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.top, Crucible.Space.xs)

                Button { confirm() } label: {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(Crucible.Color.captureAudio)
                        .clipShape(Capsule())
                }
                .padding(.top, Crucible.Space.sm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Interpreted

    private var interpretedBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Crucible.Space.xl) {
                    heardBlock
                    if let result = interpreted {
                        lookingForCard(result: result)
                        thinksYouMeanCard(result: result)
                    }
                }
                .padding(.horizontal, Crucible.Space.lg)
                .padding(.top, Crucible.Space.xxl + Crucible.Space.lg)
                .padding(.bottom, Crucible.Space.lg)
            }

            // Fixed bottom button bar
            HStack(spacing: Crucible.Space.md) {
                Button { commit(submit: false) } label: {
                    Text("Edit")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Crucible.Color.ink)
                        .padding(.horizontal, Crucible.Space.xxl)
                        .padding(.vertical, 12)
                        .background(Crucible.Color.sunk)
                        .clipShape(Capsule())
                }
                Button { commit(submit: true) } label: {
                    Text("Search")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Crucible.Space.xxl + Crucible.Space.sm)
                        .padding(.vertical, 12)
                        .background(Crucible.Color.captureAudio)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, Crucible.Space.lg)
            .padding(.vertical, Crucible.Space.md)
        }
        .overlay(alignment: .topLeading) {
            Button { cancel() } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundStyle(Crucible.Color.ink)
                    .padding(Crucible.Space.lg)
            }
        }
    }

    private var heardBlock: some View {
        VStack(alignment: .leading, spacing: Crucible.Space.sm) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Crucible.Color.captureAudio)
                    .frame(width: 6, height: 6)
                Text("HEARD")
                    .font(.footnote.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(Crucible.Color.accent)
            }
            Text("\u{201C}\(heardTranscript)\u{201D}")
                .font(.system(.title3, design: .serif))
                .italic()
                .foregroundStyle(Crucible.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lookingForCard(result: VoiceIntentParser.Result) -> some View {
        cardSection(title: "LOOKING FOR") {
            FlowLayout(spacing: 6) {
                ForEach(result.termPhrases, id: \.self) { phrase in
                    termPill(phrase)
                }
                ForEach(result.scopes, id: \.self) { scope in
                    scopePill(scope)
                }
            }
        }
    }

    private func thinksYouMeanCard(result: VoiceIntentParser.Result) -> some View {
        cardSection(title: "WHAT HIMEM THINKS YOU MEAN") {
            Text(summary(for: result))
                .font(.callout)
                .foregroundStyle(Crucible.Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func cardSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Crucible.Space.sm) {
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Crucible.Color.ink3)
            content()
        }
        .padding(Crucible.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Crucible.Color.card)
        .overlay(
            RoundedRectangle(cornerRadius: Crucible.Radius.lg)
                .stroke(Crucible.Color.divider, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Crucible.Radius.lg))
    }

    private func termPill(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Crucible.Color.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Crucible.Color.sunk)
            .clipShape(Capsule())
    }

    private func scopePill(_ scope: String) -> some View {
        // "topic:garden" → italic "topic:" + " garden"
        let parts = scope.split(separator: ":", maxSplits: 1).map(String.init)
        let key = parts.first ?? scope
        let value = parts.count > 1 ? parts[1] : ""
        return HStack(spacing: 0) {
            Text("\(key): ")
                .italic()
            Text(value)
        }
        .font(.footnote)
        .foregroundStyle(Crucible.Color.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Crucible.Color.accentTint)
        .clipShape(Capsule())
    }

    // MARK: - Actions

    private func cancel() {
        silenceWatcher.cancel()
        speechService.stopRecording()
        onCancel()
    }

    private func confirm() {
        silenceWatcher.cancel()
        // Capture the transcript before stopRecording — the async cancel
        // callback may overwrite speechService.transcribedText afterward.
        heardTranscript = speechService.transcribedText
        speechService.stopRecording()
        let result = VoiceIntentParser.parse(heardTranscript, knownTopics: knownTopics)
        interpreted = result
        phase = .interpreted
    }

    private func commit(submit: Bool) {
        guard let result = interpreted, !result.query.isEmpty else { onCancel(); return }
        onCommit(result.query, submit)
    }

    private func summary(for result: VoiceIntentParser.Result) -> String {
        var parts: [String] = []
        if !result.terms.isEmpty { parts.append("matching \u{201C}\(result.terms)\u{201D}") }
        for scope in result.scopes {
            if scope.hasPrefix("topic:") { parts.append("in topic \(scope.replacingOccurrences(of: "topic:", with: ""))") }
            if scope.hasPrefix("type:") { parts.append("of type \(scope.replacingOccurrences(of: "type:", with: ""))") }
            if scope.hasPrefix("date:") { parts.append("from \(scope.replacingOccurrences(of: "date:", with: ""))") }
        }
        return parts.isEmpty ? "I didn\u{2019}t catch a clear search." : "Looking for entries " + parts.joined(separator: ", ") + "."
    }

    // MARK: - Silence watch

    private func startSilenceWatcher() {
        silenceWatcher.start(
            textProvider: { speechService.transcribedText },
            onSilence: {
                if phase == .listening { confirm() }
            }
        )
    }
}

// MARK: - Breathing waveform

private struct BreathingWaveform: View {
    let isActive: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSinceReferenceDate
                let midY = size.height / 2
                let bars = 24
                let barWidth = size.width / CGFloat(bars * 2)
                for i in 0..<bars {
                    let x = (CGFloat(i) + 0.5) * (size.width / CGFloat(bars))
                    let phaseOffset = Double(i) * 0.4
                    let amplitude = isActive
                        ? CGFloat((sin(t * 2 + phaseOffset) * 0.5 + 0.5) * 0.6 + 0.2)
                        : 0.2
                    let h = size.height * amplitude
                    let rect = CGRect(x: x - barWidth / 2, y: midY - h / 2, width: barWidth, height: h)
                    let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                    ctx.fill(path, with: .color(Crucible.Color.captureAudio.opacity(0.85)))
                }
            }
        }
    }
}

