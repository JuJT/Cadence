import AVFoundation
import CadenceCore
import SwiftUI
import UIKit

struct PronoteQRScanner: View {
    let onScan: (PronotePairingCode) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var access: CameraAccess = .checking
    @State private var invalidCode = false

    private enum CameraAccess { case checking, authorized, denied, unavailable }

    var body: some View {
        NavigationStack {
            AtelierPage {
                CadenceSectionHeader(title: "Scannez le QR code", subtitle: "Ouvrez le bouton QR code dans votre espace élève PRONOTE sur un autre écran.")
                switch access {
                case .checking:
                    ProgressView("Ouverture de la caméra…")
                case .authorized:
                    if scenePhase == .active {
                        PronoteCameraView { value in
                            guard let code = PronotePairingCode.parse(value) else { invalidCode = true; return false }
                            onScan(code)
                            dismiss()
                            return true
                        } onFailure: { access = .unavailable }
                            .frame(height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .accessibilityLabel("Caméra pour lire le QR code PRONOTE")
                    }
                    if invalidCode {
                        Label("Ce QR code ne correspond pas à un espace élève PRONOTE.", systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                case .denied:
                    EmptyCard(title: "Caméra désactivée", symbol: "camera", description: "Autorisez la caméra dans les réglages iOS ou choisissez une autre connexion.")
                    if let settings = URL(string: UIApplication.openSettingsURLString) {
                        Button("Ouvrir les réglages iOS") { openURL(settings) }
                    }
                case .unavailable:
                    EmptyCard(title: "Caméra indisponible", symbol: "camera", description: "Vous pouvez continuer avec l’adresse PRONOTE de votre établissement.")
                }
            }
            .navigationTitle("QR code PRONOTE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        .task { await updateAccess(request: true) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await updateAccess(request: false) } }
        }
    }

    @MainActor private func updateAccess(request: Bool) async {
        guard AVCaptureDevice.default(for: .video) != nil else { access = .unavailable; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: access = .authorized
        case .notDetermined where request:
            access = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
        case .notDetermined: break
        case .denied, .restricted: access = .denied
        @unknown default: access = .unavailable
        }
    }
}

private struct PronoteCameraView: UIViewRepresentable {
    let onScan: (String) -> Bool
    let onFailure: () -> Void

    func makeUIView(context: Context) -> Preview {
        let preview = Preview()
        preview.cameraLayer.session = context.coordinator.session
        preview.cameraLayer.videoGravity = .resizeAspectFill
        context.coordinator.start()
        return preview
    }

    func updateUIView(_ uiView: Preview, context: Context) {}
    static func dismantleUIView(_ uiView: Preview, coordinator: Coordinator) { coordinator.stop() }
    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onFailure: onFailure) }

    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var cameraLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "com.cadence.study.pronote-camera")
        private let onScan: (String) -> Bool
        private let onFailure: () -> Void
        private var delivered = false

        init(onScan: @escaping (String) -> Bool, onFailure: @escaping () -> Void) {
            self.onScan = onScan
            self.onFailure = onFailure
        }

        func start() {
            queue.async { [self] in
                let output = AVCaptureMetadataOutput()
                guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else { reportFailure(); return }
                session.beginConfiguration()
                session.addInput(input)
                guard session.canAddOutput(output) else { session.commitConfiguration(); reportFailure(); return }
                session.addOutput(output)
                guard output.availableMetadataObjectTypes.contains(.qr) else { session.commitConfiguration(); reportFailure(); return }
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
                session.commitConfiguration()
                session.startRunning()
            }
        }

        func stop() { queue.async { [session] in if session.isRunning { session.stopRunning() } } }

        private func reportFailure() { DispatchQueue.main.async { [weak self] in self?.onFailure() } }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !delivered else { return }
            for case let code as AVMetadataMachineReadableCodeObject in metadataObjects {
                if let value = code.stringValue, onScan(value) {
                    delivered = true
                    stop()
                    break
                }
            }
        }
    }
}
