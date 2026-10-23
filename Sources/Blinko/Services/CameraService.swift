import AVFoundation
import Observation

/// Mirror camera. The session is created lazily and runs only while the mirror is visible.
/// Authorization is checked on transitions only (avoids the refresh-loop CPU bug seen elsewhere).
@MainActor
@Observable
final class CameraService {
    static let shared = CameraService()

    private(set) var status = AVCaptureDevice.authorizationStatus(for: .video)

    @ObservationIgnored private(set) lazy var session: AVCaptureSession = {
        let s = AVCaptureSession()
        s.sessionPreset = .medium
        if let device = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device), s.canAddInput(input) {
            s.addInput(input)
        }
        return s
    }()

    @ObservationIgnored private let queue = DispatchQueue(label: "app.blinko.camera")

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            status = .authorized
            let s = session
            queue.async { if !s.isRunning { s.startRunning() } }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { [weak self] in
                    self?.status = granted ? .authorized : .denied
                    if granted { self?.start() }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        guard status == .authorized else { return }
        let s = session
        queue.async { if s.isRunning { s.stopRunning() } }
    }
}
