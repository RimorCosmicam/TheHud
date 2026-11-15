import Foundation
import AVFoundation
import Speech

/// Live captions of what is said nearby, transcribed on the phone and saved as it goes.
///
/// On iOS 26 this is `SpeechAnalyzer`, Apple's long-form on-device engine. Before that it is
/// `SFSpeechRecognizer` held on device, restarted after each finished stretch because a single
/// request is not meant to run for long.
@MainActor
public final class CaptionsEngine {
    public private(set) var state = HudSnapshot.Captions() {
        didSet { if state != oldValue { onChange?(state) } }
    }
    public var onChange: ((HudSnapshot.Captions) -> Void)?

    private let audio = AVAudioEngine()
    private var task: Task<Void, Never>?
    private var finish: (() async -> Void)?
    private var logURL: URL?
    private var startedAt: Date?
    /// Kept for the glasses; the file has everything.
    private let keptLines = 12

    public init() {}

    public func toggle() { state.isListening ? stop() : start() }

    public func start() {
        guard task == nil else { return }
        state.isListening = true
        state.status = "STARTING"
        state.lines = []
        state.partial = ""
        task = Task { [weak self] in
            guard let self else { return }
            do {
                guard await Self.microphoneAllowed() else {
                    self.fail("NO MICROPHONE ACCESS")
                    return
                }
                try self.activateAudioSession()
                let now = Date()
                self.startedAt = now
                self.logURL = CaptionsLog.begin(at: now)
                if #available(iOS 26.0, macOS 26.0, *) {
                    try await self.runAnalyzer()
                } else {
                    try await self.runRecognizer()
                }
            } catch is CancellationError {
            } catch {
                self.fail("CAPTIONS STOPPED")
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        tearDownAudio()
        if let finish {
            self.finish = nil
            Task { await finish() }
        }
        if !state.partial.isEmpty { commit(state.partial) }
        state.partial = ""
        state.isListening = false
        state.status = "OFF"
        startedAt = nil
        logURL = nil
    }

    /// Once a second, for the session's running time.
    public func tick(now: Date = Date()) {
        guard let startedAt else { return }
        state.elapsed = HudSnapshot.NowPlaying.time(now.timeIntervalSince(startedAt))
    }

    private func fail(_ status: String) {
        stop()
        state.status = status
    }

    private func commit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.lines = Array((state.lines + [trimmed]).suffix(keptLines))
        if let logURL { CaptionsLog.append(trimmed, at: Date(), to: logURL) }
    }

    private func heard(_ text: String, final: Bool) {
        if final {
            commit(text)
            state.partial = ""
        } else {
            state.partial = text
        }
    }

    // MARK: audio

    private static func microphoneAllowed() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    private func activateAudioSession() throws {
        #if os(iOS)
        // Mixed with whatever plays, so captions never stop the music.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
        #endif
    }

    private func tearDownAudio() {
        audio.inputNode.removeTap(onBus: 0)
        audio.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Starts the microphone, handing each buffer on in `format` (converted if it differs).
    private func startMicrophone(format: AVAudioFormat?,
                                 _ deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let input = audio.inputNode
        let natural = input.outputFormat(forBus: 0)
        let target = format ?? natural
        let converter = target == natural ? nil : AVAudioConverter(from: natural, to: target)
        input.installTap(onBus: 0, bufferSize: 4096, format: natural) { buffer, _ in
            guard let converter else { return deliver(buffer) }
            let ratio = target.sampleRate / natural.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var fed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if fed {
                    status.pointee = .noDataNow
                    return nil
                }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, out.frameLength > 0 { deliver(out) }
        }
        audio.prepare()
        try audio.start()
    }

    // MARK: iOS 26: SpeechAnalyzer

    @available(iOS 26.0, macOS 26.0, *)
    private func runAnalyzer() async throws {
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
            ?? Locale(identifier: "en-US")
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults],
                                            attributeOptions: [])
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            state.status = "GETTING THE SPEECH MODEL"
            try await install.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try startMicrophone(format: format) { buffer in
            continuation.yield(AnalyzerInput(buffer: buffer))
        }
        finish = {
            continuation.finish()
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        try await analyzer.start(inputSequence: stream)
        state.status = "LISTENING"
        for try await result in transcriber.results {
            try Task.checkCancellation()
            heard(String(result.text.characters), final: result.isFinal)
        }
    }

    // MARK: before iOS 26: SFSpeechRecognizer

    /// The request the microphone feeds, swapped for a fresh one after each finished stretch.
    private final class RequestBox: @unchecked Sendable {
        private let lock = NSLock()
        private var request: SFSpeechAudioBufferRecognitionRequest?
        func set(_ new: SFSpeechAudioBufferRecognitionRequest?) {
            lock.lock(); request = new; lock.unlock()
        }
        func append(_ buffer: AVAudioPCMBuffer) {
            lock.lock(); let current = request; lock.unlock()
            current?.append(buffer)
        }
    }

    private func runRecognizer() async throws {
        let allowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard allowed else { return fail("NO SPEECH RECOGNITION ACCESS") }
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else { return fail("NO SPEECH RECOGNIZER") }
        let box = RequestBox()
        try startMicrophone(format: nil) { buffer in box.append(buffer) }
        state.status = "LISTENING"

        while !Task.isCancelled {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            box.set(request)
            // One stretch: until the recognizer calls it final, errs, or a minute passes.
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                var finished = false
                let task = recognizer.recognitionTask(with: request) { result, error in
                    Task { @MainActor in
                        guard !finished else { return }
                        if let result {
                            self.heard(result.bestTranscription.formattedString, final: result.isFinal)
                        }
                        if error != nil || result?.isFinal == true {
                            finished = true
                            done.resume()
                        }
                    }
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(55))
                    if !finished { task.finish() }
                }
            }
            box.set(nil)
            request.endAudio()
            if !state.partial.isEmpty { heard(state.partial, final: true) }
        }
    }
}
