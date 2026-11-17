import AVFoundation
import Photos
import UIKit
import SwiftUI
import VideoToolbox
import HudCore

/// The phone's camera, for the glasses: one capture session whose frames go to a display layer
/// on the glasses, into a movie while recording, and, in Host mode, into a plain image view the
/// film of the glasses can draw. Photos and videos go to the library.
///
/// It runs only while the camera is on the glasses and this app is on the phone's screen: iOS
/// gives the camera to the app in front, and to nothing in a pocket.
///
/// Three threads, each with its own things: the main thread has `state`; the session queue has
/// the session and the devices; the frames' queue has the frames, the freeze and the movie.
final class CameraService: NSObject {
    /// The picture on the glasses.
    let displayLayer = AVSampleBufferDisplayLayer()
    /// Host mode: the picture as a view the film can draw (a display layer films as black).
    let frameView = UIImageView()
    /// Main thread.
    private(set) var state = HudSnapshot.Camera()
    var onChange: (() -> Void)?
    /// Host mode is on: frames go to `frameView` too.
    var filmsFrames = false {
        didSet { let on = filmsFrames; framesQueue.async { self.films = on } }
    }
    private var wanted = false
    private var noticeTimer: Timer?

    // Session queue.
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "thehud.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationWatch: NSKeyValueObservation?
    /// The zoom factor the "1×" lens is at: where there is an ultra wide below it, 2.
    private var baseZoom: CGFloat = 1
    private var configured = false
    /// The picture's turn is held while recording: a movie is one way up.
    private var holdsRotation = false

    // Frames' queue.
    private let framesQueue = DispatchQueue(label: "thehud.camera.frames")
    private var frozen = false
    private var films = false
    private var lastFilmed: CFTimeInterval = 0
    private var latest: CVPixelBuffer?
    private var writer: AVAssetWriter?
    private var writerVideo: AVAssetWriterInput?
    private var writerAudio: AVAssetWriterInput?
    private var writerStarted = false
    private var pendingMovie: (URL, [String: Any], [String: Any]?)?

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspectFill
        displayLayer.backgroundColor = UIColor.black.cgColor
        frameView.backgroundColor = .black
        frameView.clipsToBounds = true
        frameView.contentMode = .scaleAspectFill
        let center = NotificationCenter.default
        center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) {
            [weak self] _ in self?.change { $0.status = .paused }
        }
        center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) {
            [weak self] _ in
            guard let self, self.wanted else { return }
            self.change { $0.status = .running }
        }
    }

    /// Main thread.
    private func change(_ edit: (inout HudSnapshot.Camera) -> Void) {
        var next = state
        edit(&next)
        guard next != state else { return }
        state = next
        onChange?()
    }

    private func onMain(_ work: @escaping () -> Void) {
        DispatchQueue.main.async(execute: work)
    }

    // ------------------------------------------------------------------ running

    /// On while the camera is on the glasses and the phone's screen is this app's. Main thread.
    func run(_ on: Bool) {
        guard on != wanted else { return }
        wanted = on
        guard on else {
            if state.isRecording { stopRecording() }
            sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } }
            change { $0.status = .paused }
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                self.onMain {
                    if !granted { self.change { $0.status = .denied } } else if self.wanted { self.start() }
                }
            }
        default: change { $0.status = .denied }
        }
    }

    private func start() {
        let camera = state
        sessionQueue.async {
            if !self.configured { self.configure(camera) }
            if !self.session.isRunning { self.session.startRunning() }
            let status: HudSnapshot.Camera.Status = self.videoInput == nil ? .unavailable
                : (self.session.isRunning ? .running : .paused)
            self.onMain { if self.wanted { self.change { $0.status = status } } }
        }
    }

    /// Session queue: the session, once, with the camera the state asks for.
    private func configure(_ camera: HudSnapshot.Camera) {
        session.beginConfiguration()
        session.sessionPreset = .high
        if let device = Self.device(front: camera.front), let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
        }
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: framesQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        audioOutput.setSampleBufferDelegate(self, queue: framesQueue)
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
        session.commitConfiguration()
        configured = true
        deviceChanged(camera)
        if camera.mode == .video { setMicrophone(true) }
    }

    /// The back camera that covers the most (the ultra wide below "1×" where there is one), or
    /// the front one.
    private static func device(front: Bool) -> AVCaptureDevice? {
        if front { return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) }
        let kinds: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera,
                                                   .builtInWideAngleCamera]
        return AVCaptureDevice.DiscoverySession(deviceTypes: kinds, mediaType: .video, position: .back).devices.first
    }

    /// Session queue: a camera was put in. Its zoom, its way up, its mirror.
    private func deviceChanged(_ camera: HudSnapshot.Camera) {
        guard let device = videoInput?.device else { return }
        if device.constituentDevices.first?.deviceType == .builtInUltraWideCamera,
           let wide = device.virtualDeviceSwitchOverVideoZoomFactors.first {
            baseZoom = CGFloat(truncating: wide)
        } else {
            baseZoom = 1
        }
        let maxZoom = max(1, min(Double(device.maxAvailableVideoZoomFactor / baseZoom), 20).rounded(.down))
        if let largest = device.activeFormat.supportedMaxPhotoDimensions
            .max(by: { $0.width * $0.height < $1.width * $1.height }) {
            photoOutput.maxPhotoDimensions = largest
        }
        if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = camera.front
        }
        rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationWatch = rotation?.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial]) {
            [weak self] _, _ in self?.sessionQueue.async { self?.applyRotation() }
        }
        let zoom = min(camera.zoom, maxZoom)
        apply(camera, zoom: zoom, ramp: false)
        onMain {
            self.change {
                $0.maxZoom = maxZoom
                $0.zoom = zoom
            }
        }
    }

    /// Session queue: the picture the way up the phone is held, so it is upright on the glasses.
    private func applyRotation() {
        guard !holdsRotation, let angle = rotation?.videoRotationAngleForHorizonLevelCapture else { return }
        for connection in [videoOutput.connection(with: .video), photoOutput.connection(with: .video)] {
            if let connection, connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        }
    }

    /// Session queue: zoom, light, brightness and focus, as the state has them.
    private func apply(_ camera: HudSnapshot.Camera, zoom: Double? = nil, ramp: Bool = true) {
        guard let device = videoInput?.device, (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        let factor = min(max(CGFloat(zoom ?? camera.zoom) * baseZoom, device.minAvailableVideoZoomFactor),
                         device.maxAvailableVideoZoomFactor)
        if ramp { device.ramp(toVideoZoomFactor: factor, withRate: 8) } else { device.videoZoomFactor = factor }
        if device.hasTorch, device.isTorchAvailable {
            device.torchMode = camera.light && !camera.front ? .on : .off
        }
        let bias = camera.bright && camera.mode == .magnify ? min(device.maxExposureTargetBias, 2) : 0
        if device.exposureTargetBias != bias { device.setExposureTargetBias(bias, completionHandler: nil) }
        if device.isAutoFocusRangeRestrictionSupported {
            device.autoFocusRangeRestriction = camera.mode == .magnify ? .near : .none
        }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
    }

    /// Session queue: the microphone in for video (asked for once), out otherwise, so the camera
    /// takes the phone's sound only while it may record it.
    private func setMicrophone(_ on: Bool) {
        if on, audioInput == nil {
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        guard granted else { return }
                        self.sessionQueue.async { self.setMicrophone(true) }
                    }
                }
                return
            }
            guard let mic = AVCaptureDevice.default(for: .audio), let input = try? AVCaptureDeviceInput(device: mic)
            else { return }
            session.beginConfiguration()
            if session.canAddInput(input) {
                session.addInput(input)
                audioInput = input
            }
            session.commitConfiguration()
        } else if !on, let input = audioInput {
            session.beginConfiguration()
            session.removeInput(input)
            session.commitConfiguration()
            audioInput = nil
        }
    }

    // ------------------------------------------------------------------ the pad

    /// Main thread.
    func perform(_ action: CameraAction) {
        guard state.status == .running else { return }
        switch action {
        case .shutter:
            switch state.mode {
            case .photo: takePhoto()
            case .magnify: saveShown()
            case .video: state.isRecording ? stopRecording() : startRecording()
            }
        case let .mode(mode):
            guard mode != state.mode, !state.isRecording else { return }
            let wasVideo = state.mode == .video
            change {
                $0.mode = mode
                $0.frozen = false
                $0.bright = false
                $0.zoom = mode == .magnify ? min(HudSnapshot.Camera.magnifierZoom, $0.maxZoom) : 1
            }
            freeze(false)
            let camera = state
            sessionQueue.async {
                self.apply(camera)
                if wasVideo != (mode == .video) { self.setMicrophone(mode == .video) }
            }
        case let .zoom(by):
            let zoom = state.zoom(stepping: by)
            change { $0.zoom = zoom }
            let camera = state
            sessionQueue.async { self.apply(camera) }
        case .flip:
            guard !state.isRecording else { return }
            change {
                $0.front.toggle()
                $0.light = false
                $0.zoom = 1
                $0.frozen = false
            }
            freeze(false)
            let camera = state
            sessionQueue.async {
                guard let device = Self.device(front: camera.front),
                      let input = try? AVCaptureDeviceInput(device: device) else { return }
                self.session.beginConfiguration()
                if let old = self.videoInput { self.session.removeInput(old) }
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.videoInput = input
                } else if let old = self.videoInput {
                    self.session.addInput(old)
                }
                self.session.commitConfiguration()
                self.deviceChanged(camera)
            }
        case .freeze:
            change { $0.frozen.toggle() }
            freeze(state.frozen)
        case .light:
            guard !state.front else { return }
            change { $0.light.toggle() }
            let camera = state
            sessionQueue.async { self.apply(camera) }
        case .bright:
            change { $0.bright.toggle() }
            let camera = state
            sessionQueue.async { self.apply(camera) }
        }
    }

    private func freeze(_ on: Bool) {
        framesQueue.async { self.frozen = on }
    }

    /// Main thread: a few seconds on the glasses and the pad.
    private func notice(_ text: String) {
        change { $0.notice = text }
        noticeTimer?.invalidate()
        noticeTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.change { $0.notice = "" }
        }
    }

    // ------------------------------------------------------------------ photos and movies

    private func takePhoto() {
        change { $0.shotAt = Date() }
        sessionQueue.async {
            let settings = self.photoOutput.availablePhotoCodecTypes.contains(.hevc)
                ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc]) : AVCapturePhotoSettings()
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// The magnifier keeps what it shows, held still or not.
    private func saveShown() {
        change { $0.shotAt = Date() }
        framesQueue.async {
            guard let buffer = self.latest else { return }
            let image = CIImage(cvPixelBuffer: buffer)
            let data = CIContext().jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                    options: [:])
            guard let data else { return }
            self.save { PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil) }
        }
    }

    private func save(_ request: @escaping () -> Void, cleanup: (() -> Void)? = nil) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                cleanup?()
                self.onMain { self.notice("ALLOW PHOTOS TO SAVE") }
                return
            }
            PHPhotoLibrary.shared().performChanges(request) { ok, _ in
                cleanup?()
                self.onMain { self.notice(ok ? "SAVED TO PHOTOS" : "COULDN'T SAVE") }
            }
        }
    }

    private func startRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TheHud-\(UUID().uuidString).mov")
        change { $0.recordingSince = Date() }
        sessionQueue.async {
            self.holdsRotation = true
            let video = self.videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov) ?? [:]
            let audio = self.audioInput == nil ? nil
                : self.audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov)
            self.framesQueue.async { self.pendingMovie = (url, video, audio) }
        }
    }

    /// Frames' queue: the movie, made at its first frame so it is that frame's size and way up.
    private func makeWriter(for buffer: CVPixelBuffer) {
        guard let movie = pendingMovie else { return }
        let (url, settings, audioSettings) = movie
        pendingMovie = nil
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
        var videoSettings = settings
        videoSettings[AVVideoWidthKey] = CVPixelBufferGetWidth(buffer)
        videoSettings[AVVideoHeightKey] = CVPixelBufferGetHeight(buffer)
        if videoSettings[AVVideoCodecKey] == nil { videoSettings[AVVideoCodecKey] = AVVideoCodecType.h264 }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { return }
        writer.add(video)
        if let audioSettings {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audio.expectsMediaDataInRealTime = true
            if writer.canAdd(audio) {
                writer.add(audio)
                writerAudio = audio
            }
        }
        self.writer = writer
        writerVideo = video
        writerStarted = false
    }

    private func stopRecording() {
        change { $0.recordingSince = nil }
        framesQueue.async {
            self.pendingMovie = nil
            guard let writer = self.writer else {
                self.sessionQueue.async {
                    self.holdsRotation = false
                    self.applyRotation()
                }
                return
            }
            let started = self.writerStarted
            self.writer = nil
            self.writerVideo = nil
            self.writerAudio = nil
            self.writerStarted = false
            self.sessionQueue.async {
                self.holdsRotation = false
                self.applyRotation()
            }
            guard started else {
                writer.cancelWriting()
                return
            }
            writer.inputs.forEach { $0.markAsFinished() }
            writer.finishWriting {
                let url = writer.outputURL
                guard writer.status == .completed else {
                    try? FileManager.default.removeItem(at: url)
                    self.onMain { self.notice("COULDN'T SAVE") }
                    return
                }
                self.save({ PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil) },
                          cleanup: { try? FileManager.default.removeItem(at: url) })
            }
        }
    }
}

// MARK: - Frames

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    /// Frames' queue: to the glasses unless held still, and into the movie while recording.
    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === audioOutput {
            if writerStarted, let audio = writerAudio, audio.isReadyForMoreMediaData { audio.append(sample) }
            return
        }
        if pendingMovie != nil, let buffer = CMSampleBufferGetImageBuffer(sample) { makeWriter(for: buffer) }
        if let writer, let video = writerVideo {
            if !writerStarted, writer.startWriting() {
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sample))
                writerStarted = true
            }
            if writerStarted, video.isReadyForMoreMediaData { video.append(sample) }
        }
        guard !frozen, let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        latest = buffer
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        let renderer = displayLayer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sample)
        // Host mode: as an image for the film, at most thirty times a second.
        let now = CACurrentMediaTime()
        if films, now - lastFilmed > 1 / 31 {
            lastFilmed = now
            var image: CGImage?
            VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
            if let image {
                let picture = UIImage(cgImage: image)
                DispatchQueue.main.async { self.frameView.image = picture }
            }
        }
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            onMain { self.notice("COULDN'T TAKE THE PHOTO") }
            return
        }
        save { PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil) }
    }
}

// MARK: - On the glasses

/// The camera's picture in its place on the glasses: the display layer, or in Host mode the
/// image view the film can see. Fill or fit as the place asks.
struct CameraPictureView: UIViewRepresentable {
    let camera: CameraService
    let filmed: Bool
    let fill: Bool

    func makeUIView(context: Context) -> Host { Host() }

    func updateUIView(_ view: Host, context: Context) {
        if filmed {
            camera.frameView.contentMode = fill ? .scaleAspectFill : .scaleAspectFit
            view.show(camera.frameView)
        } else {
            camera.displayLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
            view.show(camera.displayLayer)
        }
    }

    final class Host: UIView {
        private weak var shownLayer: CALayer?
        private weak var shownView: UIView?

        func show(_ layer: CALayer) {
            guard shownLayer !== layer else { return }
            layer.removeFromSuperlayer()
            self.layer.addSublayer(layer)
            shownLayer = layer
            setNeedsLayout()
        }

        func show(_ view: UIView) {
            guard shownView !== view else { return }
            view.removeFromSuperview()
            addSubview(view)
            shownView = view
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shownLayer?.frame = bounds
            shownView?.frame = bounds
            CATransaction.commit()
        }
    }
}
