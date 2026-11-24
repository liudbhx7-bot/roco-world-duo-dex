import AVFoundation
import Combine
import SwiftUI
import UIKit

enum DexCameraState: Equatable {
    case idle, starting, ready, denied, unavailable
    case failed(String)
}

private enum CameraIssue: LocalizedError {
    case unavailable, interrupted, timedOut, noImage
    var errorDescription: String? {
        switch self {
        case .unavailable: "当前没有可用的后置相机，可从相册选图。"
        case .interrupted: "相机已暂停，请重试。"
        case .timedOut: "相机没有及时返回照片，请重试。"
        case .noImage: "照片读取失败，请重新拍摄。"
        }
    }
}

@MainActor
final class DexCamera: ObservableObject {
    @Published private(set) var state: DexCameraState = .idle
    fileprivate let worker = CaptureWorker()
    fileprivate weak var viewport: CameraViewport?
    fileprivate var lastAspectRatio: CGFloat?
    fileprivate var lastPreviewAngle: CGFloat = 90
    private var generation = UUID()
    private var notifications: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        for name in [AVCaptureSession.wasInterruptedNotification,
                     AVCaptureSession.interruptionEndedNotification,
                     AVCaptureSession.runtimeErrorNotification] {
            notifications.append(center.addObserver(forName: name, object: worker.session, queue: .main) { [weak self] note in
                let ended = note.name == AVCaptureSession.interruptionEndedNotification
                Task { @MainActor [weak self] in
                    guard let self, self.state != .idle else { return }
                    if ended { self.start() }
                    else { self.state = .failed("相机被中断，请重试或从相册选图。") }
                }
            })
        }
    }

    deinit {
        for token in notifications { NotificationCenter.default.removeObserver(token) }
        worker.stop()
    }

    func start() {
        guard state != .starting, state != .ready else { return }
        let token = UUID()
        generation = token
        state = .starting
        Task { [weak self] in
            guard let self else { return }
            guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
                if generation == token { state = .unavailable }
                return
            }
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
            default: allowed = false
            }
            guard generation == token else { return }
            guard allowed else { state = .denied; return }
            do {
                let device = try await worker.start()
                guard generation == token else { return }
                viewport?.configureRotation(device: device)
                state = .ready
            } catch {
                if generation == token { state = .failed(error.localizedDescription) }
            }
        }
    }

    func stop() {
        generation = UUID()
        state = .idle
        worker.stop()
    }

    func capture() async throws -> UIImage {
        guard state == .ready else { throw CameraIssue.unavailable }
        let token = generation
        let ratio = viewport?.aspectRatio ?? lastAspectRatio
        let angle = viewport?.preview.connection?.videoRotationAngle ?? lastPreviewAngle
        let data = try await worker.capture(angle: angle)
        guard token == generation else { throw CameraIssue.interrupted }
        guard let photo = ScanFrame.load(data) else { throw CameraIssue.noImage }
        return ScanFrame.fitPreview(photo, aspect:ratio)
    }
}

struct DexCameraPreview: UIViewRepresentable {
    let camera: DexCamera

    func makeUIView(context: Context) -> CameraViewport {
        let view = CameraViewport()
        view.camera = camera
        view.addGestureRecognizer(UITapGestureRecognizer(target:view, action:#selector(CameraViewport.focusAtTap)))
        view.preview.session = camera.worker.session
        view.preview.videoGravity = .resizeAspectFill
        view.clipsToBounds = true
        camera.viewport = view
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            view.configureRotation(device: device)
        }
        return view
    }

    func updateUIView(_ uiView: CameraViewport, context: Context) {
        camera.viewport = uiView
        uiView.applyRotation()
    }
}

final class CameraViewport: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var aspectRatio: CGFloat? { bounds.height > 0 ? bounds.width / bounds.height : nil }
    fileprivate weak var camera: DexCamera?
    override func layoutSubviews() {
        super.layoutSubviews()
        if let aspectRatio { camera?.lastAspectRatio = aspectRatio }
        applyRotation()
    }
    fileprivate var coordinator: AVCaptureDevice.RotationCoordinator?
    private var observation: NSKeyValueObservation?

    private let focusRing = CAShapeLayer()

    @objc fileprivate func focusAtTap(_ tap: UITapGestureRecognizer) {
        let location = tap.location(in:self)
        camera?.worker.focus(at:preview.captureDevicePointConverted(fromLayerPoint:location))
        focusRing.removeAllAnimations()
        focusRing.frame = CGRect(x:location.x-20,y:location.y-20,width:40,height:40)
        focusRing.path = UIBezierPath(roundedRect:focusRing.bounds,cornerRadius:4).cgPath
        focusRing.fillColor = UIColor.clear.cgColor
        focusRing.strokeColor = UIColor.systemYellow.cgColor
        focusRing.lineWidth = 1.5
        focusRing.opacity = 0
        layer.addSublayer(focusRing)
        let fade = CABasicAnimation(keyPath:"opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 1
        focusRing.add(fade,forKey:"focus")
    }

    fileprivate func configureRotation(device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
        self.coordinator = coordinator
        observation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.applyRotation() }
        }
    }

    fileprivate func applyRotation() {
        guard let angle = coordinator?.videoRotationAngleForHorizonLevelPreview,
              let connection = preview.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
        camera?.lastPreviewAngle = angle
    }
}

fileprivate final class CaptureWorker: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "roco.scanner.capture", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var pending: [Int64: PhotoRequest] = [:]

    func start() async throws -> AVCaptureDevice {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    if input == nil {
                        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw CameraIssue.unavailable }
                        let candidate = try AVCaptureDeviceInput(device: device)
                        session.beginConfiguration()
                        session.sessionPreset = .photo
                        guard session.canAddInput(candidate) else {
                            session.commitConfiguration()
                            throw CameraIssue.unavailable
                        }
                        session.addInput(candidate)
                        guard session.canAddOutput(output) else {
                            session.removeInput(candidate)
                            session.commitConfiguration()
                            throw CameraIssue.unavailable
                        }
                        session.addOutput(output)
                        output.maxPhotoQualityPrioritization = .quality
                        session.commitConfiguration()
                        input = candidate
                    }
                    if !session.isRunning { session.startRunning() }
                    guard session.isRunning, let device = input?.device else { throw CameraIssue.unavailable }
                    continuation.resume(returning: device)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func focus(at point: CGPoint) {
        queue.async { [self] in
            guard let device = input?.device, session.isRunning else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusPointOfInterest = point
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .continuousAutoExposure
                }
            } catch { return }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            for request in Array(pending.values) { request.finish(.failure(CameraIssue.interrupted)) }
        }
    }

    func capture(angle: CGFloat) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard session.isRunning, pending.isEmpty, let connection = output.connection(with: .video), connection.isEnabled, connection.isActive else {
                    continuation.resume(throwing: CameraIssue.unavailable)
                    return
                }
                if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .quality
                let id = settings.uniqueID
                let request = PhotoRequest { [weak self] result in
                    self?.queue.async { [weak self] in self?.pending.removeValue(forKey: id) }
                    continuation.resume(with: result)
                }
                pending[id] = request
                output.capturePhoto(with: settings, delegate: request)
                queue.asyncAfter(deadline: .now() + 12) { [weak request] in request?.finish(.failure(CameraIssue.timedOut)) }
            }
        }
    }
}

private final class PhotoRequest: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: ((Result<Data, Error>) -> Void)?

    init(callback: @escaping (Result<Data, Error>) -> Void) { self.callback = callback }

    func finish(_ result: Result<Data, Error>) {
        lock.lock()
        let action = callback
        callback = nil
        lock.unlock()
        action?(result)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { finish(.failure(error)) }
        else if let data = photo.fileDataRepresentation() { finish(.success(data)) }
        else { finish(.failure(CameraIssue.noImage)) }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error { finish(.failure(error)) }
    }
}
