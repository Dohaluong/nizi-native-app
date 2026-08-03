import AVFoundation
import SwiftUI
import UIKit

struct NiziMoveQRScannerView: UIViewControllerRepresentable {
    let onResult: (Result<NiziMoveQR, Error>) -> Void
    func makeUIViewController(context: Context) -> ScannerController { ScannerController(onResult: onResult) }
    func updateUIViewController(_ controller: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        private let captureSession = AVCaptureSession()
        private let onResult: (Result<NiziMoveQR, Error>) -> Void
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var isDelivering = false

        init(onResult: @escaping (Result<NiziMoveQR, Error>) -> Void) { self.onResult = onResult; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidLoad() { super.viewDidLoad(); configure() }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); previewLayer?.frame = view.bounds }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); stop() }

        private func configure() {
            Task { @MainActor in
                let granted: Bool
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized: granted = true
                case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
                default: granted = false
                }
                guard granted, let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), captureSession.canAddInput(input) else { return }
                captureSession.addInput(input)
                let output = AVCaptureMetadataOutput(); guard captureSession.canAddOutput(output) else { return }
                captureSession.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
                let preview = AVCaptureVideoPreviewLayer(session: captureSession); preview.videoGravity = .resizeAspectFill; preview.frame = view.bounds; view.layer.insertSublayer(preview, at: 0); previewLayer = preview
                DispatchQueue.global(qos: .userInitiated).async { [captureSession] in captureSession.startRunning() }
            }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !isDelivering, let raw = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            switch Result { try parseNiziMoveQR(raw) } {
            case .success(let qr): isDelivering = true; stop(); onResult(.success(qr))
            case .failure(let error): onResult(.failure(error)); DispatchQueue.global(qos: .userInitiated).async { [captureSession] in if !captureSession.isRunning { captureSession.startRunning() } }
            }
        }
        private func stop() { DispatchQueue.global(qos: .userInitiated).async { [captureSession] in if captureSession.isRunning { captureSession.stopRunning() } } }
    }
}
