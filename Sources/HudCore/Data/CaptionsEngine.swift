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

    /// The language being spoken, as a BCP 47 tag. Changing it while listening starts over.
    public var language: String = CaptionsEngine.defaultLanguage {
        didSet {
            guard language != oldValue, state.isListening else { return }
            stop()
            start()
        }
    }

    /// The languages offered, by tag and by their own name.
    public static let languages: [(id: String, name: String)] = [
        ("pt-BR", "Português (Brasil)"),
        ("pt-PT", "Português (Portugal)"),
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("es-ES", "Español (España)"),
        ("es-MX", "Español (México)"),
        ("fr-FR", "Français"),
        ("de-DE", "Deutsch"),
        ("it-IT", "Italiano"),
    ]

    /// The phone's own language where it is offered; Portuguese for a Brazilian phone whatever
    /// language its menus are in, since that is what will be spoken around it.
    public static var defaultLanguage: String {
        let locale = Locale.current
        if locale.region?.identifier == "BR" { return "pt-BR" }
        let tag = locale.identifier(.bcp47)
        if languages.contains(where: { $0.id == tag }) { return tag }
        let code = locale.language.languageCode?.identifier ?? "en"
        return languages.first { $0.id.hasPrefix(code + "-") }?.id ?? "en-US"
    }

    private var languageTag: String { language.uppercased() }

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
                let wanted = Locale(identifier: self.language)
                if #available(iOS 26.0, macOS 26.0, *) {
                    do {
                        try await self.runAnalyzer(wanted)
                        return
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // The new engine has no model for this language here, or could not
                        // get one: the older recognizer knows more languages, and the network.
                        await self.finishAnalyzer()
                        self.releaseMicrophone()
                    }
                }
                try await self.runRecognizer(wanted)
            } catch is CancellationError {
            } catch {
                self.fail("STOPPED: " + Self.reason(error))
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

    /// An error, short enough for the glasses.
    private static func reason(_ error: Error) -> String {
        String(error.localizedDescription.prefix(60)).uppercased()
    }

    private func finishAnalyzer() async {
        guard let finish else { return }
        self.finish = nil
        await finish()
    }

    /// The microphone off, ready to be tapped again.
    private func releaseMicrophone() {
        audio.inputNode.removeTap(onBus: 0)
        audio.stop()
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
        releaseMicrophone()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Starts the microphone, handing each buffer on in `format` (converted if it differs).
    private func startMicrophone(format: AVAudioFormat?,
                                 _ deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let input = audio.inputNode
        // A tap left over from an engine that gave up would make installing another fatal.
        input.removeTap(onBus: 0)
        let natural = input.outputFormat(forBus: 0)
        guard natural.sampleRate > 0, natural.channelCount > 0 else { throw CaptionsError.noMicrophone }
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

    enum CaptionsError: LocalizedError {
        case noMicrophone, languageUnavailable(String)
        var errorDescription: String? {
            switch self {
            case .noMicrophone: return "No microphone"
            case let .languageUnavailable(tag): return "No speech recognition for \(tag)"
            }
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func runAnalyzer(_ wanted: Locale) async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) else {
            throw CaptionsError.languageUnavailable(languageTag)
        }
        // Each language's model has to be reserved before it can be used, and only so many can
        // be: make room by giving back the oldest.
        let tag = locale.identifier(.bcp47)
        let reserved = await AssetInventory.reservedLocales
        if !reserved.contains(where: { $0.identifier(.bcp47) == tag }) {
            if reserved.count >= AssetInventory.maximumReservedLocales, let oldest = reserved.first {
                _ = await AssetInventory.release(reservedLocale: oldest)
            }
            _ = try? await AssetInventory.reserve(locale: locale)
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults],
                                            attributeOptions: [])
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            state.status = "GETTING THE \(languageTag) MODEL"
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
        state.status = "LISTENING · \(languageTag)"
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

    private func runRecognizer(_ wanted: Locale) async throws {
        let allowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard allowed else { return fail("NO SPEECH RECOGNITION ACCESS") }
        guard let recognizer = SFSpeechRecognizer(locale: wanted) else {
            return fail("NO SPEECH RECOGNITION FOR \(languageTag)")
        }
        guard recognizer.isAvailable else { return fail("\(languageTag) RECOGNITION UNAVAILABLE") }
        let box = RequestBox()
        try startMicrophone(format: nil) { buffer in box.append(buffer) }
        state.status = "LISTENING · \(languageTag)"

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
