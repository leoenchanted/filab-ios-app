import AVFoundation
import Combine
import UIKit

struct CameraCaptureResult {
    let format: CameraCaptureFormat
    let processedImage: UIImage?
    let processedData: Data?
    let rawData: Data?

    var isRaw: Bool {
        format.isRaw && rawData != nil
    }
}

// MARK: - Camera Controller

@MainActor
final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isConfigured = false
    @Published private(set) var isRunning = false
    @Published private(set) var isCapturing = false
    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .back
    @Published private(set) var minZoomFactor: CGFloat = 1
    @Published private(set) var maxZoomFactor: CGFloat = 1
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var minimumExposureBias: Float = -2
    @Published private(set) var maximumExposureBias: Float = 2
    @Published private(set) var exposureBias: Float = 0
    @Published private(set) var minimumISO: Float = 32
    @Published private(set) var maximumISO: Float = 1600
    @Published private(set) var isoValue: Float = 100
    @Published private(set) var minimumShutterDuration: Double = 1.0 / 10_000.0
    @Published private(set) var maximumShutterDuration: Double = 1
    @Published private(set) var shutterDuration: Double = 1.0 / 125.0
    @Published private(set) var isManualExposure = false
    @Published private(set) var whiteBalanceTemperature: Float = 5200
    @Published private(set) var whiteBalanceTint: Float = 0
    @Published private(set) var isWhiteBalanceLocked = false
    @Published private(set) var isRawCaptureAvailable = false
    @Published private(set) var isAppleProRAWCaptureAvailable = false
    @Published private(set) var isBayerRawCaptureAvailable = false
    @Published private(set) var histogramBins = CameraHistogramSampler.placeholderBins
    @Published private(set) var maxPhotoDimensionsDisplay = "--MP"
    @Published var selectedFilmPreset: FilmPreset? = FilmPreset.preset(withId: "portra400")
    @Published var aspectRatio: CameraAspectRatio = .threeFour
    @Published var captureFormat: CameraCaptureFormat = .jpeg
    @Published private var errorMessage: String?

    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    // FIX 1: 专用 session 队列，session 的阻塞操作全部在此队列执行，避免卡主线程
    private let sessionQueue = DispatchQueue(label: "filab.camera.session")
    private let videoDataOutputQueue = DispatchQueue(label: "filab.camera.histogram")
    private let histogramSampler = CameraHistogramSampler()
    private var videoInput: AVCaptureDeviceInput?
    private var photoCaptureDelegate: PhotoCaptureDelegate?
    private var pinchBaseZoomFactor: CGFloat = 1
    private var captureRotationAngle: CGFloat = 0
    private var configuredMaxPhotoDimensions: CMVideoDimensions?

    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    var isRunningCamera: Bool {
        isAuthorized && isConfigured && isRunning
    }

    var canCapture: Bool {
        isRunningCamera && !isCapturing
    }

    var canZoom: Bool {
        isRunningCamera && maxZoomFactor > minZoomFactor
    }

    var canSwitchCamera: Bool {
        isAuthorized && isConfigured
    }

    var availableCaptureFormats: [CameraCaptureFormat] {
        var formats: [CameraCaptureFormat] = [.jpeg, .heif]

        if isAppleProRAWCaptureAvailable {
            formats.append(.proRaw)
        }

        if isBayerRawCaptureAvailable {
            formats.append(.bayerRaw)
        }

        return formats
    }

    var currentDevice: AVCaptureDevice? {
        videoInput?.device
    }

    var exposureBiasDisplay: String {
        String(format: "%+.1f", exposureBias)
    }

    var isoDisplay: String {
        "\(Int(isoValue.rounded()))"
    }

    var shutterSpeedDisplay: String {
        Self.shutterSpeedDisplay(seconds: shutterDuration)
    }

    var whiteBalanceDisplay: String {
        isWhiteBalanceLocked ? "\(Int(whiteBalanceTemperature))K" : "AUTO"
    }

    var statusText: String {
        if isCapturing {
            return "CAPTURE"
        }

        switch authorizationStatus {
        case .authorized:
            return isRunning ? "READY" : "STANDBY"
        case .notDetermined:
            return "PERMIT"
        case .denied, .restricted:
            return "LOCKED"
        @unknown default:
            return "ERROR"
        }
    }

    var permissionTitle: String {
        if let errorMessage {
            return errorMessage
        }

        switch authorizationStatus {
        case .notDetermined:
            return "启用系统相机"
        case .denied, .restricted:
            return "相机权限未开启"
        default:
            return "相机准备中"
        }
    }

    var permissionMessage: String {
        switch authorizationStatus {
        case .notDetermined:
            return "允许后可以直接拍摄照片，并保存到系统相册。"
        case .denied, .restricted:
            return "请在系统设置里允许 Filab 使用相机。"
        default:
            return "正在连接设备相机。"
        }
    }

    // FIX 1: startRunning/stopRunning 移到 sessionQueue，不再阻塞主线程
    func start() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch authorizationStatus {
        case .authorized:
            configureSessionIfNeeded()
            guard isConfigured, !session.isRunning else {
                isRunning = session.isRunning
                return
            }
            sessionQueue.async { [weak self] in
                guard let self else { return }
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.isRunning = self.session.isRunning
                }
            }

        case .notDetermined:
            requestCameraAccess()

        case .denied, .restricted:
            isRunning = false

        @unknown default:
            isRunning = false
            errorMessage = "相机状态不可用"
        }
    }

    // FIX 1: stopRunning 同样移到 sessionQueue
    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    func requestPermissionOrOpenSettings() {
        if authorizationStatus == .notDetermined {
            requestCameraAccess()
            return
        }

        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }

    // FIX 1: switchCamera 的 session 配置操作也移到 sessionQueue
    func switchCamera() {
        guard canSwitchCamera else { return }

        let nextPosition: AVCaptureDevice.Position = cameraPosition == .back ? .front : .back

        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.session.beginConfiguration()

            do {
                // applyCamera 内部会更新 @Published 属性，需要回主线程
                // 但 session 配置本身在 sessionQueue 执行
                try self.applyCamera(position: nextPosition)
                self.updateRawCaptureAvailability()
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
            }

            self.session.commitConfiguration()
        }
    }

    func setZoomFactor(_ factor: CGFloat) {
        guard let device = videoInput?.device else { return }

        let clampedFactor = min(max(factor, minZoomFactor), maxZoomFactor)

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clampedFactor
            device.unlockForConfiguration()
            zoomFactor = clampedFactor
            pinchBaseZoomFactor = clampedFactor
        } catch {
            errorMessage = "变焦不可用"
        }
    }

    func focusAndExpose(at devicePoint: CGPoint) {
        guard let device = videoInput?.device else { return }

        do {
            try device.lockForConfiguration()

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint

                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                } else if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
            }

            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint

                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                } else if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                }
            }

            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
            errorMessage = nil
        } catch {
            errorMessage = "无法设置对焦点"
        }
    }

    func setExposureBias(_ bias: Float) {
        guard let device = videoInput?.device else { return }

        let clampedBias = min(max(bias, minimumExposureBias), maximumExposureBias)

        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(clampedBias, completionHandler: nil)
            device.unlockForConfiguration()
            exposureBias = clampedBias
            errorMessage = nil
        } catch {
            errorMessage = "EV 调节不可用"
        }
    }

    func setManualISO(_ iso: Float) {
        applyManualExposure(iso: iso, duration: shutterDuration)
    }

    func setManualShutterDuration(_ seconds: Double) {
        applyManualExposure(iso: isoValue, duration: seconds)
    }

    func resetAutoExposure() {
        guard let device = videoInput?.device else { return }

        do {
            try device.lockForConfiguration()

            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            } else if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            }

            device.unlockForConfiguration()
            isManualExposure = false
            updateExposureLimits(for: device)
            errorMessage = nil
        } catch {
            errorMessage = "自动曝光不可用"
        }
    }

    func setWhiteBalance(temperature: Float? = nil, tint: Float? = nil) {
        guard let device = videoInput?.device else { return }

        let nextTemperature = min(max(temperature ?? whiteBalanceTemperature, 2500), 9000)
        let nextTint = min(max(tint ?? whiteBalanceTint, -100), 100)

        do {
            try device.lockForConfiguration()

            guard device.isWhiteBalanceModeSupported(.locked) else {
                device.unlockForConfiguration()
                errorMessage = "WB 锁定不可用"
                return
            }

            let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                temperature: nextTemperature,
                tint: nextTint
            )
            let gains = clampedWhiteBalanceGains(
                device.deviceWhiteBalanceGains(for: values),
                maxGain: device.maxWhiteBalanceGain
            )

            device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            device.unlockForConfiguration()

            whiteBalanceTemperature = nextTemperature
            whiteBalanceTint = nextTint
            isWhiteBalanceLocked = true
            errorMessage = nil
        } catch {
            errorMessage = "WB 调节不可用"
        }
    }

    func resetWhiteBalance() {
        guard let device = videoInput?.device else { return }

        do {
            try device.lockForConfiguration()

            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            } else if device.isWhiteBalanceModeSupported(.autoWhiteBalance) {
                device.whiteBalanceMode = .autoWhiteBalance
            }

            device.unlockForConfiguration()
            isWhiteBalanceLocked = false
            errorMessage = nil
        } catch {
            errorMessage = "自动 WB 不可用"
        }
    }

    func updatePinchZoom(scale: CGFloat) {
        guard canZoom else { return }
        setZoomFactor(pinchBaseZoomFactor * scale)
    }

    func finishPinchZoom() {
        pinchBaseZoomFactor = zoomFactor
    }

    func updateCaptureRotationAngle(_ angle: CGFloat) {
        captureRotationAngle = Self.normalizedRotationAngle(angle)
    }

    func capturePhoto(completion: @escaping (Result<CameraCaptureResult, Error>) -> Void) {
        guard canCapture else { return }

        isCapturing = true

        let settings: AVCapturePhotoSettings

        do {
            settings = try makePhotoSettings()
            // FIX 2: photoQualityPrioritization 对纯 RAW settings 无效且会导致 pipeline 卡住
            // 只在 processed 格式（JPEG / HEIF）下设置
            if !captureFormat.isRaw {
                settings.photoQualityPrioritization = .quality
            }
        } catch {
            isCapturing = false
            errorMessage = error.localizedDescription
            completion(.failure(error))
            return
        }

        if let connection = photoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(captureRotationAngle) {
                connection.videoRotationAngle = captureRotationAngle
            }

            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = cameraPosition == .front
            }
        }

        let delegate = PhotoCaptureDelegate(expectedFormat: captureFormat) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }

                self.isCapturing = false
                self.photoCaptureDelegate = nil

                switch result {
                case .success:
                    self.errorMessage = nil
                    completion(result)
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }

        photoCaptureDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    private func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                self?.start()
            }
        }
    }

    // FIX 1: session 配置在 sessionQueue 上执行（由 start() 调用时已在 sessionQueue）
    // 注意：此方法必须只从 sessionQueue 或初始化时调用
    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }

        sessionQueue.async { [weak self] in
            guard let self, !self.isConfigured else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            do {
                try self.applyCamera(position: .back)
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
                self.session.commitConfiguration()
                return
            }

            guard self.session.canAddOutput(self.photoOutput) else {
                DispatchQueue.main.async {
                    self.errorMessage = "当前设备无法输出照片"
                }
                self.session.commitConfiguration()
                return
            }

            self.session.addOutput(self.photoOutput)
            self.photoOutput.maxPhotoQualityPrioritization = .quality
            self.photoOutput.isAppleProRAWEnabled = self.photoOutput.isAppleProRAWSupported
            self.configureMaximumPhotoDimensionsForCurrentFormat()
            self.updateRawCaptureAvailability()
            self.configureHistogramOutputIfPossible()
            self.session.commitConfiguration()

            DispatchQueue.main.async {
                self.isConfigured = true
            }

            // 配置完成后立即启动 session；startRunning 仍留在 sessionQueue，避免阻塞主线程。
            if !self.session.isRunning {
                self.session.startRunning()
            }

            DispatchQueue.main.async {
                self.isRunning = self.session.isRunning
            }
        }
    }

    // 注意：此方法需要在已持有 session.beginConfiguration 的上下文中调用
    // @Published 属性的更新通过 DispatchQueue.main.async 回到主线程
    private func applyCamera(position: AVCaptureDevice.Position) throws {
        if let videoInput {
            session.removeInput(videoInput)
        }

        guard let device = Self.bestCamera(for: position) else {
            throw CameraSetupError.noCamera
        }

        if let bestFormat = Self.bestPhotoFormat(for: device) {
            do {
                try device.lockForConfiguration()
                device.activeFormat = bestFormat
                device.unlockForConfiguration()
            } catch {
                throw error
            }
        }

        let input = try AVCaptureDeviceInput(device: device)

        guard session.canAddInput(input) else {
            throw CameraSetupError.inputUnavailable
        }

        session.addInput(input)

        // 读取设备参数（可在后台线程读）
        let zoomMin = max(device.minAvailableVideoZoomFactor, 0.5)
        let zoomMax = min(device.maxAvailableVideoZoomFactor, 12)
        let clampedZoomMin = min(zoomMin, zoomMax)
        let clampedZoomMax = max(1, zoomMax)
        let initialZoom = max(1, clampedZoomMin)

        let expBiasMin = max(device.minExposureTargetBias, -4)
        let expBiasMax = min(device.maxExposureTargetBias, 4)
        let expBias = min(max(device.exposureTargetBias, expBiasMin), expBiasMax)
        let isoMin = device.activeFormat.minISO
        let isoMax = device.activeFormat.maxISO
        let iso = min(max(device.iso, isoMin), isoMax)
        let shutterMin = max(device.activeFormat.minExposureDuration.seconds, 1.0 / 10_000.0)
        let shutterMax = min(device.activeFormat.maxExposureDuration.seconds, 1)
        let shutter = min(max(device.exposureDuration.seconds, shutterMin), shutterMax)
        let isManual = device.exposureMode == .custom

        let wbValues = device.temperatureAndTintValues(for: device.deviceWhiteBalanceGains)
        let wbTemp = min(max(wbValues.temperature, 2500), 9000)
        let wbTint = min(max(wbValues.tint, -100), 100)
        let wbLocked = device.whiteBalanceMode == .locked
        let bestDimensions = Self.bestPhotoDimensions(for: device.activeFormat)
        let photoDimensionsDisplay = Self.photoDimensionsDisplay(bestDimensions)

        // 设置初始 zoom
        try? device.lockForConfiguration()
        device.videoZoomFactor = initialZoom
        device.unlockForConfiguration()

        configuredMaxPhotoDimensions = bestDimensions
        if session.outputs.contains(photoOutput) {
            configureMaximumPhotoDimensionsForCurrentFormat()
        }

        if let bestDimensions {
            print("Filab camera device: \(device.localizedName)")
            print("Filab camera max photo dimensions: \(bestDimensions.width)x\(bestDimensions.height) (\(photoDimensionsDisplay))")
        }

        // 回主线程更新所有 @Published 状态
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.videoInput = input
            self.cameraPosition = position

            self.minZoomFactor = clampedZoomMin
            self.maxZoomFactor = clampedZoomMax
            self.zoomFactor = initialZoom
            self.pinchBaseZoomFactor = initialZoom

            self.minimumExposureBias = expBiasMin
            self.maximumExposureBias = expBiasMax
            self.exposureBias = expBias
            self.minimumISO = isoMin
            self.maximumISO = isoMax
            self.isoValue = iso
            self.minimumShutterDuration = shutterMin
            self.maximumShutterDuration = shutterMax
            self.shutterDuration = shutter
            self.isManualExposure = isManual

            self.whiteBalanceTemperature = wbTemp
            self.whiteBalanceTint = wbTint
            self.isWhiteBalanceLocked = wbLocked
            self.maxPhotoDimensionsDisplay = photoDimensionsDisplay
        }
    }

    private func updateZoomLimits(for device: AVCaptureDevice) {
        let deviceMinimum = max(device.minAvailableVideoZoomFactor, 0.5)
        let deviceMaximum = min(device.maxAvailableVideoZoomFactor, 12)
        minZoomFactor = min(deviceMinimum, deviceMaximum)
        maxZoomFactor = max(1, deviceMaximum)

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = max(1, minZoomFactor)
            device.unlockForConfiguration()
        } catch {
            errorMessage = "变焦初始化失败"
        }

        zoomFactor = max(1, minZoomFactor)
        pinchBaseZoomFactor = zoomFactor
    }

    private func updateExposureLimits(for device: AVCaptureDevice) {
        minimumExposureBias = max(device.minExposureTargetBias, -4)
        maximumExposureBias = min(device.maxExposureTargetBias, 4)
        exposureBias = min(max(device.exposureTargetBias, minimumExposureBias), maximumExposureBias)
        minimumISO = device.activeFormat.minISO
        maximumISO = device.activeFormat.maxISO
        isoValue = min(max(device.iso, minimumISO), maximumISO)
        minimumShutterDuration = max(device.activeFormat.minExposureDuration.seconds, 1.0 / 10_000.0)
        maximumShutterDuration = min(device.activeFormat.maxExposureDuration.seconds, 1)
        shutterDuration = min(max(device.exposureDuration.seconds, minimumShutterDuration), maximumShutterDuration)
        isManualExposure = device.exposureMode == .custom
    }

    private func updateWhiteBalanceState(for device: AVCaptureDevice) {
        let values = device.temperatureAndTintValues(for: device.deviceWhiteBalanceGains)
        whiteBalanceTemperature = min(max(values.temperature, 2500), 9000)
        whiteBalanceTint = min(max(values.tint, -100), 100)
        isWhiteBalanceLocked = device.whiteBalanceMode == .locked
    }

    private func configureHistogramOutputIfPossible() {
        guard session.canAddOutput(videoDataOutput) else { return }

        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        histogramSampler.onHistogram = { [weak self] bins in
            Task { @MainActor in
                self?.histogramBins = bins
            }
        }
        videoDataOutput.setSampleBufferDelegate(histogramSampler, queue: videoDataOutputQueue)
        session.addOutput(videoDataOutput)
    }

    private func updateRawCaptureAvailability() {
        let rawFormats = photoOutput.availableRawPhotoPixelFormatTypes
        let proRawAvailable = rawFormats.contains {
            AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
        }
        let bayerAvailable = rawFormats.contains {
            AVCapturePhotoOutput.isBayerRAWPixelFormat($0)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isAppleProRAWCaptureAvailable = proRawAvailable
            self.isBayerRawCaptureAvailable = bayerAvailable
            self.isRawCaptureAvailable = proRawAvailable || bayerAvailable

            if !self.availableCaptureFormats.contains(self.captureFormat) {
                self.captureFormat = self.photoOutput.availablePhotoCodecTypes.contains(.hevc) ? .heif : .jpeg
            }
        }
    }

    private func makePhotoSettings() throws -> AVCapturePhotoSettings {
        if captureFormat.isRaw {
            let query: (OSType) -> Bool

            switch captureFormat {
            case .proRaw:
                query = AVCapturePhotoOutput.isAppleProRAWPixelFormat(_:)
            case .bayerRaw:
                query = AVCapturePhotoOutput.isBayerRAWPixelFormat(_:)
            case .jpeg, .heif:
                query = { _ in false }
            }

            guard let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first(where: query) else {
                throw CameraCaptureError.rawUnsupported
            }

            // FIX 2: 纯 RAW 不附加 processedFormat，避免不必要的双路输出带来的 pipeline 压力
            return AVCapturePhotoSettings(
                rawPixelFormatType: rawFormat,
                rawFileType: .dng,
                processedFormat: nil,
                processedFileType: nil
            )
        }

        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: availableProcessedCodec()])

        if let configuredMaxPhotoDimensions {
            settings.maxPhotoDimensions = configuredMaxPhotoDimensions
        }

        return settings
    }

    private func availableProcessedCodec() -> AVVideoCodecType {
        if captureFormat == .heif,
           photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            return .hevc
        }

        return .jpeg
    }

    private func clampedWhiteBalanceGains(
        _ gains: AVCaptureDevice.WhiteBalanceGains,
        maxGain: Float
    ) -> AVCaptureDevice.WhiteBalanceGains {
        AVCaptureDevice.WhiteBalanceGains(
            redGain: min(max(gains.redGain, 1), maxGain),
            greenGain: min(max(gains.greenGain, 1), maxGain),
            blueGain: min(max(gains.blueGain, 1), maxGain)
        )
    }

    private func applyManualExposure(iso: Float, duration: Double) {
        guard let device = videoInput?.device else { return }

        let clampedISO = min(max(iso, device.activeFormat.minISO), device.activeFormat.maxISO)
        let minDuration = max(device.activeFormat.minExposureDuration.seconds, 1.0 / 10_000.0)
        let maxDuration = min(device.activeFormat.maxExposureDuration.seconds, 1)
        let clampedDuration = min(max(duration, minDuration), maxDuration)

        do {
            try device.lockForConfiguration()
            let cmDuration = CMTimeMakeWithSeconds(clampedDuration, preferredTimescale: 1_000_000)
            device.setExposureModeCustom(duration: cmDuration, iso: clampedISO, completionHandler: nil)
            device.unlockForConfiguration()

            isoValue = clampedISO
            shutterDuration = clampedDuration
            isManualExposure = true
            errorMessage = nil
        } catch {
            errorMessage = "手动曝光不可用"
        }
    }

    private static func shutterSpeedDisplay(seconds: Double) -> String {
        guard seconds > 0 else { return "--" }

        if seconds >= 1 {
            return String(format: "%.1fs", seconds)
        }

        return "1/\(Int((1 / seconds).rounded()))"
    }

    private static func normalizedRotationAngle(_ angle: CGFloat) -> CGFloat {
        let rounded = (angle / 90).rounded() * 90
        let normalized = rounded.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }

    private static func bestCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType]

        if position == .back {
            deviceTypes = [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ]
        } else {
            deviceTypes = [
                .builtInTrueDepthCamera,
                .builtInWideAngleCamera
            ]
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        )

        return discovery.devices.max { first, second in
            photoArea(bestPhotoDimensions(for: first)) < photoArea(bestPhotoDimensions(for: second))
        }
    }

    private func configureMaximumPhotoDimensionsForCurrentFormat() {
        guard let dimensions = configuredMaxPhotoDimensions else { return }
        photoOutput.maxPhotoDimensions = dimensions
    }

    private static func bestPhotoFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        device.formats.max { first, second in
            photoArea(bestPhotoDimensions(for: first)) < photoArea(bestPhotoDimensions(for: second))
        }
    }

    private static func bestPhotoDimensions(for device: AVCaptureDevice) -> CMVideoDimensions? {
        bestPhotoFormat(for: device).flatMap { bestPhotoDimensions(for: $0) }
    }

    private static func bestPhotoDimensions(for format: AVCaptureDevice.Format) -> CMVideoDimensions? {
        format.supportedMaxPhotoDimensions.max { first, second in
            photoArea(first) < photoArea(second)
        }
    }

    private static func photoArea(_ dimensions: CMVideoDimensions?) -> Int64 {
        guard let dimensions else { return 0 }
        return Int64(dimensions.width) * Int64(dimensions.height)
    }

    private static func photoDimensionsDisplay(_ dimensions: CMVideoDimensions?) -> String {
        guard let dimensions else { return "--MP" }
        let megapixels = Double(photoArea(dimensions)) / 1_000_000.0
        return "\(Int(megapixels.rounded()))MP"
    }
}

private enum CameraSetupError: LocalizedError {
    case noCamera
    case inputUnavailable

    var errorDescription: String? {
        switch self {
        case .noCamera:
            return "当前设备没有可用摄像头"
        case .inputUnavailable:
            return "无法连接系统摄像头"
        }
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<CameraCaptureResult, Error>) -> Void
    private var processedImage: UIImage?
    private var processedData: Data?
    private var rawData: Data?
    private let expectedFormat: CameraCaptureFormat
    private var captureError: Error?

    init(
        expectedFormat: CameraCaptureFormat,
        completion: @escaping (Result<CameraCaptureResult, Error>) -> Void
    ) {
        self.expectedFormat = expectedFormat
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            captureError = error
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            captureError = CameraCaptureError.invalidPhotoData
            return
        }

        if photo.isRawPhoto {
            rawData = data
            return
        }

        processedData = data
        processedImage = UIImage(data: data)

        if let cgImage = processedImage?.cgImage {
            print("Filab captured processed photo dimensions: \(cgImage.width)x\(cgImage.height)")
        }
    }

    // FIX 3: 修正错误分支优先级——顶层 error 最优先，避免 captureError 为 nil 时掩盖真实原因
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        // 顶层 error 优先：表示整个 capture 会话失败
        if let error {
            completion(.failure(error))
            return
        }

        if let rawData {
            completion(.success(CameraCaptureResult(
                format: expectedFormat,
                processedImage: nil,
                processedData: nil,
                rawData: rawData
            )))
        } else if let image = processedImage {
            completion(.success(CameraCaptureResult(
                format: expectedFormat == .heif ? .heif : .jpeg,
                processedImage: image,
                processedData: processedData,
                rawData: nil
            )))
        } else {
            // 没有 error 也没有数据：用 didFinishProcessingPhoto 阶段记录的错误
            completion(.failure(captureError ?? CameraCaptureError.invalidPhotoData))
        }
    }
}

private final class CameraHistogramSampler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let placeholderBins: [CGFloat] = [
        0.14, 0.24, 0.44, 0.68, 0.82, 0.74, 0.55, 0.39,
        0.33, 0.28, 0.24, 0.22, 0.20, 0.18, 0.22, 0.26,
        0.31, 0.37, 0.43, 0.48, 0.51, 0.46, 0.37, 0.29,
        0.24, 0.20, 0.18, 0.16, 0.13, 0.10, 0.08, 0.06
    ]

    var onHistogram: (([CGFloat]) -> Void)?

    private var frameIndex = 0
    private let binCount = 32

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameIndex += 1
        guard frameIndex % 8 == 0,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        guard width > 0,
              height > 0,
              let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return
        }

        var bins = [Int](repeating: 0, count: binCount)
        let sampleStepX = max(width / 96, 1)
        let sampleStepY = max(height / 72, 1)

        for y in stride(from: 0, to: height, by: sampleStepY) {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)

            for x in stride(from: 0, to: width, by: sampleStepX) {
                let luminance = Int(row[x])
                let index = min(binCount - 1, luminance * binCount / 256)
                bins[index] += 1
            }
        }

        guard let peak = bins.max(), peak > 0 else { return }

        let normalized = bins.map { count in
            let value = CGFloat(count) / CGFloat(peak)
            return max(0.04, sqrt(value))
        }

        onHistogram?(normalized)
    }
}

private enum CameraCaptureError: LocalizedError {
    case invalidPhotoData
    case rawUnsupported

    var errorDescription: String? {
        switch self {
        case .invalidPhotoData:
            return "照片数据不可用"
        case .rawUnsupported:
            return "当前设备不支持所选 RAW 格式"
        }
    }
}
