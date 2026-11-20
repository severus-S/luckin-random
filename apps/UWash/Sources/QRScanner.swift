import SwiftUI
import AVFoundation

struct QRScanner: UIViewControllerRepresentable {
    let result: (String) -> Void
    let failure: (String) -> Void
    func makeUIViewController(context: Context) -> ScanController { ScanController(result: result, failure: failure) }
    func updateUIViewController(_ controller: ScanController, context: Context) {}
    static func dismantleUIViewController(_ controller: ScanController, coordinator: ()) { controller.stop() }
}

final class ScanController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let capture = AVCaptureSession()
    private let queue = DispatchQueue(label: "uwash.qr.capture")
    private let result: (String) -> Void
    private let failure: (String) -> Void
    private var preview: AVCaptureVideoPreviewLayer?
    private var finished = false
    private var closed = false
    init(result: @escaping (String) -> Void, failure: @escaping (String) -> Void) { self.result = result; self.failure = failure; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            guard let self else { return }
            DispatchQueue.main.async { if !self.closed { allowed ? self.configure() : self.failure("相机权限未开启。可在系统设置中允许相机，或返回粘贴二维码内容。") } }
        }
    }
    private func configure() {
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), capture.canAddInput(input) else { failure("相机暂不可用，可粘贴二维码内容或设备编号。"); return }
        capture.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard capture.canAddOutput(output) else { failure("无法启动二维码识别。"); return }
        capture.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: capture)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
        layer.frame = view.bounds
        queue.async { [capture] in capture.startRunning() }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    func stop() { closed = true; queue.async { [capture] in if capture.isRunning { capture.stopRunning() } } }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !finished, let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        finished = true
        stop()
        result(value)
    }
}
