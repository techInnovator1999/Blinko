import AVFoundation
import SwiftUI

// MARK: - Mirror

struct MirrorTile: View {
    @State private var active = false
    @State private var hovering = false

    var body: some View {
        let camera = CameraService.shared
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.fillSubtle)
            if active, camera.status == .authorized {
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(.opacity)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: camera.status == .denied ? "video.slash.fill" : "camera.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text(camera.status == .denied ? "No Access" : "Mirror")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(hovering ? Color.primaryText : .secondaryText)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            withAnimation(Motion.content) { active.toggle() }
            active ? camera.start() : camera.stop()
        }
        .onDisappear {
            if active { camera.stop() }
        }
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        layer.connection?.isVideoMirrored = true
        view.layer = layer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
