import AVFoundation
import SwiftUI
import UIKit

// MARK: - Preview Layer

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?
    let isMirrored: Bool
    let onCaptureRotationAngleChanged: @MainActor (CGFloat) -> Void
    let onTapToFocus: (CGPoint, CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> CameraPreviewContainerView {
        let view = CameraPreviewContainerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onTapToFocus = onTapToFocus
        context.coordinator.configure(
            device: device,
            previewLayer: view.previewLayer,
            onCaptureRotationAngleChanged: onCaptureRotationAngleChanged
        )
        applyMirroring(to: view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewContainerView, context: Context) {
        uiView.previewLayer.session = session
        uiView.onTapToFocus = onTapToFocus
        context.coordinator.configure(
            device: device,
            previewLayer: uiView.previewLayer,
            onCaptureRotationAngleChanged: onCaptureRotationAngleChanged
        )
        applyMirroring(to: uiView.previewLayer)
    }

    private func applyMirroring(to previewLayer: AVCaptureVideoPreviewLayer) {
        guard let connection = previewLayer.connection else { return }
        connection.automaticallyAdjustsVideoMirroring = false

        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = isMirrored
        }
    }

    final class Coordinator: NSObject {
        private weak var configuredDevice: AVCaptureDevice?
        private weak var previewLayer: AVCaptureVideoPreviewLayer?
        private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
        private var previewObservation: NSKeyValueObservation?
        private var captureObservation: NSKeyValueObservation?
        private var onCaptureRotationAngleChanged: (@MainActor (CGFloat) -> Void)?

        func configure(
            device: AVCaptureDevice?,
            previewLayer: AVCaptureVideoPreviewLayer,
            onCaptureRotationAngleChanged: @escaping @MainActor (CGFloat) -> Void
        ) {
            self.onCaptureRotationAngleChanged = onCaptureRotationAngleChanged

            guard configuredDevice !== device || self.previewLayer !== previewLayer else {
                applyCurrentRotationAngles()
                return
            }

            configuredDevice = device
            self.previewLayer = previewLayer
            previewObservation = nil
            captureObservation = nil

            guard let device else {
                rotationCoordinator = nil
                onCaptureRotationAngleChanged(0)
                return
            }

            let coordinator = AVCaptureDevice.RotationCoordinator(
                device: device,
                previewLayer: previewLayer
            )
            rotationCoordinator = coordinator

            previewObservation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview,
                options: [.initial, .new]
            ) { [weak self] coordinator, _ in
                self?.applyPreviewRotationAngle(coordinator.videoRotationAngleForHorizonLevelPreview)
            }

            captureObservation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelCapture,
                options: [.initial, .new]
            ) { [weak self] coordinator, _ in
                self?.publishCaptureRotationAngle(coordinator.videoRotationAngleForHorizonLevelCapture)
            }
        }

        private func applyCurrentRotationAngles() {
            guard let rotationCoordinator else { return }
            applyPreviewRotationAngle(rotationCoordinator.videoRotationAngleForHorizonLevelPreview)
            publishCaptureRotationAngle(rotationCoordinator.videoRotationAngleForHorizonLevelCapture)
        }

        private func applyPreviewRotationAngle(_ angle: CGFloat) {
            let normalizedAngle = Self.normalizedRotationAngle(angle)

            guard let connection = previewLayer?.connection,
                  connection.isVideoRotationAngleSupported(normalizedAngle) else {
                return
            }

            connection.videoRotationAngle = normalizedAngle
        }

        private func publishCaptureRotationAngle(_ angle: CGFloat) {
            Task { @MainActor [onCaptureRotationAngleChanged] in
                onCaptureRotationAngleChanged?(angle)
            }
        }

        private static func normalizedRotationAngle(_ angle: CGFloat) -> CGFloat {
            let rounded = (angle / 90).rounded() * 90
            let normalized = rounded.truncatingRemainder(dividingBy: 360)
            return normalized >= 0 ? normalized : normalized + 360
        }
    }
}

final class CameraPreviewContainerView: UIView {
    var onTapToFocus: ((CGPoint, CGPoint) -> Void)?

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        installTapGesture()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installTapGesture()
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    private func installTapGesture() {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(recognizer)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let viewPoint = recognizer.location(in: self)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: viewPoint)
        onTapToFocus?(devicePoint, viewPoint)
    }
}
