import AVFoundation
import SwiftUI
import UIKit

// MARK: - Camera Page

struct CameraView: View {
    @Binding var showingImagePicker: Bool
    let onPhotoCaptured: (CameraCaptureResult, FilmPreset?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraController()
    @State private var isShutterFlashing = false
    @State private var isSavingCapture = false
    @State private var captureMessage: String?
    @State private var activePanel: CameraControlPanel? = .exposure
    @State private var selectedFilmCategory: FilmCategory?
    @State private var focusIndicator: CGPoint?
    @State private var toolPage = 0
    @State private var showGrid = true
    @State private var showLevel = false
    @State private var showFocusPeaking = false
    @State private var showZebra = false
    @State private var showReference = false

    private let cameraAccent = Color(red: 1.0, green: 0.48, blue: 0.10)
    private let shutterSpeeds: [CameraShutterSpeed] = CameraShutterSpeed.defaultSpeeds

    private var filteredFilmPresets: [FilmPreset] {
        if let selectedFilmCategory {
            return FilmPreset.allPresets.filter { $0.category == selectedFilmCategory }
        }

        return FilmPreset.allPresets
    }

    private var activePreviewPreset: FilmPreset? {
        camera.captureFormat.isRaw ? nil : camera.selectedFilmPreset
    }

    private var filmPanelStatus: String {
        if camera.captureFormat.isRaw {
            return "\(camera.captureFormat.title) 不烘焙胶片"
        }

        return camera.selectedFilmPreset?.cameraShortName ?? "OFF"
    }

    @ViewBuilder
    private var rawSupportMenuHints: some View {
        Section("RAW 提示") {
            if camera.isAppleProRAWCaptureAvailable {
                Text("ProRAW：多帧融合 RAW")
            } else {
                Text("ProRAW：当前设备不支持")
            }

            if camera.isBayerRawCaptureAvailable {
                Text("Bayer：传感器 RAW")
            } else {
                Text("Bayer：当前设备不支持")
            }
        }
    }

    private var batteryDisplay: String {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return "--" }
        return "\(Int(level * 100))%"
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 760
            let panelHeightAdjustment: CGFloat = activePanel == nil ? -82 : (activePanel == .film ? 48 : (activePanel == .whiteBalance ? 24 : 0))
            let viewfinderHeight = max(310, proxy.size.height - (isCompact ? 330 : 376) - panelHeightAdjustment)
            let isNarrow = proxy.size.width < 390

            ZStack {
                cameraBodyBackground

                VStack(spacing: isCompact ? 6 : 8) {
                    cameraHeader
                        .padding(.horizontal, 18)
                        .padding(.top, isCompact ? 6 : 12)

                    exposureReadoutStrip
                        .padding(.horizontal, 16)

                    viewfinderDeck(height: viewfinderHeight)
                        .padding(.horizontal, 14)

                    if let activePanel {
                        controlPanel(for: activePanel)
                            .padding(.horizontal, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    shutterDeck(isNarrow: isNarrow)
                        .padding(.horizontal, 18)

                    captureModeSwitch
                        .padding(.horizontal, 56)
                        .padding(.bottom, 8)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .clipped()

                if let captureMessage {
                    captureToast(captureMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if isShutterFlashing {
                    Color.white
                        .opacity(0.42)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .foregroundStyle(.white)
        .background(Color.black)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: activePanel)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: captureMessage)
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
    }

    private var cameraBodyBackground: some View {
        ZStack {
            Color(red: 0.025, green: 0.024, blue: 0.022)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    .clear,
                    Color.black.opacity(0.42)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Rectangle()
                .fill(.black.opacity(0.18))
                .overlay(CameraLeatherTexture().opacity(0.32))
        }
        .ignoresSafeArea()
    }

    private var cameraHeader: some View {
        ZStack {
            VStack(spacing: 3) {
                Text("FILAB")
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .tracking(7)
                    .foregroundStyle(Color(red: 0.92, green: 0.78, blue: 0.64))

                Text("- ANALOG -")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(cameraAccent.opacity(0.9))
            }

            HStack(alignment: .center) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 40, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭相机")

                Spacer()

                HStack(spacing: 10) {
                    Menu {
                        Picker("格式", selection: $camera.captureFormat) {
                            ForEach(camera.availableCaptureFormats) { format in
                                Text(format.title).tag(format)
                            }
                        }

                        rawSupportMenuHints
                    } label: {
                        CameraHeaderTool(icon: "camera.filters", title: camera.captureFormat.title)
                    }

                    Menu {
                        Picker("画幅", selection: $camera.aspectRatio) {
                            ForEach(CameraAspectRatio.allCases) { ratio in
                                Text(ratio.title).tag(ratio)
                            }
                        }
                    } label: {
                        CameraHeaderTool(icon: "rectangle.inset.filled", title: camera.aspectRatio.title)
                    }

                }
            }
        }
        .frame(height: 46)
    }

    private var exposureReadoutStrip: some View {
        HStack(spacing: 0) {
            readoutButton(panel: .iso, title: "ISO", value: camera.isoDisplay)
            CameraReadoutDivider()
            readoutButton(panel: .shutter, title: "快门", value: camera.shutterSpeedDisplay)
            CameraReadoutDivider()
            readoutButton(panel: .exposure, title: "EV", value: camera.exposureBiasDisplay)
            CameraReadoutDivider()
            CameraReadoutCell(title: "对焦", value: "AF-C")
            CameraReadoutDivider()
            readoutButton(panel: .whiteBalance, title: "白平衡", value: camera.whiteBalanceDisplay)
            CameraReadoutDivider()
            CameraReadoutCell(title: "电量", value: batteryDisplay)
        }
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .cameraBlackPanel(cornerRadius: 14)
    }

    private func readoutButton(panel: CameraControlPanel, title: String, value: String) -> some View {
        Button {
            togglePanel(panel)
        } label: {
            CameraReadoutCell(
                title: title,
                value: value,
                valueColor: activePanel == panel ? cameraAccent : Color(red: 0.86, green: 0.78, blue: 0.69)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func viewfinderDeck(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            toolRail
                .transition(.move(edge: .leading).combined(with: .opacity))

            ZStack {
                liveViewfinder

                if showGrid {
                    ViewfinderGrid()
                        .opacity(0.58)
                        .allowsHitTesting(false)
                }

                if showLevel {
                    LevelGuideOverlay(accent: cameraAccent)
                        .allowsHitTesting(false)
                }

                if showReference {
                    ReferenceGuideOverlay()
                        .allowsHitTesting(false)
                }

                if showZebra {
                    ZebraOverlay()
                        .blendMode(.screen)
                        .allowsHitTesting(false)
                }

                if showFocusPeaking {
                    FocusPeakingOverlay(accent: cameraAccent)
                        .allowsHitTesting(false)
                }

                FrameGuideOverlay(aspectRatio: camera.aspectRatio.frameRatio)
                    .allowsHitTesting(false)

                HistogramView(bins: camera.histogramBins)
                    .frame(width: 104, height: 58)
                    .padding(.top, 12)
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(camera.captureFormat.badgeTitle)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .cameraDarkCapsule()

                    Text(camera.maxPhotoDimensionsDisplay)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .cameraDarkCapsule()

                    Text(camera.aspectRatio.title)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .cameraDarkCapsule()
                }
                .padding(.top, 12)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                ZoomRail(
                    zoomFactor: camera.zoomFactor,
                    maxZoomFactor: camera.maxZoomFactor,
                    accent: cameraAccent,
                    onSelect: camera.setZoomFactor(_:)
                )
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

                if let focusIndicator {
                    FocusReticleView(accent: cameraAccent)
                        .position(focusIndicator)
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
            .padding(.vertical, 8)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .cameraBlackPanel(cornerRadius: 20)
    }

    private var liveViewfinder: some View {
        ZStack {
            if camera.isAuthorized, camera.isConfigured {
                CameraPreviewView(
                    session: camera.session,
                    device: camera.currentDevice,
                    isMirrored: camera.cameraPosition == .front,
                    onCaptureRotationAngleChanged: camera.updateCaptureRotationAngle(_:),
                    onTapToFocus: handleFocusTap(devicePoint:viewPoint:)
                )
                .saturation(activePreviewPreset?.cameraPreviewSaturation ?? 1)
                .contrast(activePreviewPreset?.cameraPreviewContrast ?? 1)
                .overlay(filmPreviewOverlay.allowsHitTesting(false))
                .overlay(vignetteOverlay.allowsHitTesting(false))
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            camera.updatePinchZoom(scale: value)
                        }
                        .onEnded { _ in
                            camera.finishPinchZoom()
                        }
                )
            } else {
                inactiveViewfinder
            }
        }
        .background(Color.black)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                collapseControlPanel()
            }
        )
    }

    private var toolRail: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(CameraSideTool.tools(for: toolPage)) { tool in
                    sideToolButton(tool)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)

            Button {
                toolPage = (toolPage + 1) % CameraSideTool.pageCount
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                    Text("\(toolPage + 1)/\(CameraSideTool.pageCount)")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 44, height: 34)
                .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .padding(.top, 10)
        .frame(width: 56)
    }

    private var evMeterStrip: some View {
        EVScaleStrip(
            value: Double(camera.exposureBias),
            minValue: Double(camera.minimumExposureBias),
            maxValue: Double(camera.maximumExposureBias),
            accent: cameraAccent
        ) { nextValue in
            camera.setExposureBias(Float(nextValue))
        }
        .frame(height: 74)
        .cameraBlackPanel(cornerRadius: 15)
    }

    private var parameterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Menu {
                    Picker("格式", selection: $camera.captureFormat) {
                        ForEach(camera.availableCaptureFormats) { format in
                            Text(format.title).tag(format)
                        }
                    }

                    rawSupportMenuHints
                } label: {
                    CameraParameterCell(title: "格式", value: camera.captureFormat.title, detail: camera.captureFormat.detail, accent: cameraAccent)
                }

                CameraDeckDivider()

                Menu {
                    Picker("画幅", selection: $camera.aspectRatio) {
                        ForEach(CameraAspectRatio.allCases) { ratio in
                            Text(ratio.title).tag(ratio)
                        }
                    }
                } label: {
                    CameraParameterCell(title: "画幅", value: camera.aspectRatio.title, detail: "中画幅", accent: cameraAccent)
                }

                CameraDeckDivider()

                CameraParameterCell(title: "质量", value: "高", detail: "无损压缩", accent: cameraAccent)

                CameraDeckDivider()

                Button {
                    togglePanel(.whiteBalance)
                } label: {
                    CameraParameterCell(title: "白平衡", value: camera.whiteBalanceDisplay, detail: camera.isWhiteBalanceLocked ? "锁定" : "日光", accent: cameraAccent)
                }
                .buttonStyle(.plain)

                CameraDeckDivider()

                CameraParameterCell(title: "对焦模式", value: "AF-C", detail: "连续自动对焦", accent: cameraAccent)

                CameraDeckDivider()

                CameraParameterCell(title: "测光模式", value: "◎", detail: "中央重点", accent: cameraAccent)
            }
            .frame(minWidth: 520)
        }
        .frame(height: 86)
        .frame(maxWidth: .infinity)
        .cameraBlackPanel(cornerRadius: 18)
    }

    private func shutterDeck(isNarrow: Bool) -> some View {
        let sideWidth: CGFloat = isNarrow ? 104 : 112

        return ZStack {
            HStack(alignment: .center) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        activePanel = activePanel == .film ? nil : .film
                    }
                } label: {
                    CameraFilmLauncher(preset: camera.captureFormat.isRaw ? nil : camera.selectedFilmPreset)
                }
                .buttonStyle(.plain)
                .frame(width: sideWidth, alignment: .leading)

                Spacer()

                HStack(spacing: isNarrow ? 8 : 10) {
                    Button {
                        camera.switchCamera()
                    } label: {
                        CameraRoundTool(icon: "arrow.triangle.2.circlepath.camera", title: "翻转")
                    }
                    .buttonStyle(.plain)
                    .disabled(!camera.canSwitchCamera)
                    .opacity(camera.canSwitchCamera ? 1 : 0.45)

                    Button {
                        showCaptureMessage("更多相机功能入口已预留")
                    } label: {
                        CameraRoundTool(icon: "ellipsis", title: "更多")
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: sideWidth, alignment: .trailing)
            }

            Button {
                triggerShutter()
            } label: {
                CameraShutterButton(
                    isBusy: camera.isCapturing || isSavingCapture,
                    canCapture: camera.canCapture,
                    diameter: isNarrow ? 74 : 86
                )
            }
            .buttonStyle(.plain)
            .disabled(!camera.canCapture || isSavingCapture)
            .accessibilityLabel("快门")
        }
        .frame(height: 88)
        .frame(maxWidth: .infinity)
    }

    private var captureModeSwitch: some View {
        HStack(spacing: 4) {
            Text("照片")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(cameraAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(cameraAccent.opacity(0.45), lineWidth: 1)
                )

            Text("视频")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(4)
        .frame(height: 42)
        .cameraBlackPanel(cornerRadius: 22)
    }

    @ViewBuilder
    private func controlPanel(for panel: CameraControlPanel) -> some View {
        switch panel {
        case .iso:
            isoPanel
        case .shutter:
            shutterPanel
        case .exposure:
            evMeterStrip
        case .whiteBalance:
            whiteBalancePanel
        case .film:
            filmPickerPanel
        }
    }

    private var isoPanel: some View {
        VStack(spacing: 8) {
            panelHeader(title: "ISO", value: camera.isManualExposure ? camera.isoDisplay : "AUTO")

            controlSlider(
                label: "ISO",
                value: Double(camera.isoValue),
                range: Double(camera.minimumISO)...Double(max(camera.maximumISO, camera.minimumISO + 1)),
                display: camera.isoDisplay
            ) { camera.setManualISO(Float($0)) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 74)
        .cameraBlackPanel(cornerRadius: 15)
    }

    private var shutterPanel: some View {
        VStack(spacing: 8) {
            panelHeader(title: "快门", value: camera.isManualExposure ? camera.shutterSpeedDisplay : "AUTO")

            HStack(spacing: 10) {
                Text("TIME")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))
                    .frame(width: 38, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { nearestShutterIndex },
                        set: { nextIndex in
                            let index = min(max(Int(nextIndex.rounded()), 0), shutterSpeeds.count - 1)
                            camera.setManualShutterDuration(shutterSpeeds[index].duration)
                        }
                    ),
                    in: 0...Double(max(shutterSpeeds.count - 1, 1)),
                    step: 1
                )
                .tint(cameraAccent)

                Text(camera.shutterSpeedDisplay)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 58, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 74)
        .cameraBlackPanel(cornerRadius: 15)
    }

    private var nearestShutterIndex: Double {
        guard let index = shutterSpeeds.enumerated().min(by: { left, right in
            abs(left.element.duration - camera.shutterDuration) < abs(right.element.duration - camera.shutterDuration)
        })?.offset else {
            return 0
        }

        return Double(index)
    }

    private var whiteBalancePanel: some View {
        VStack(spacing: 8) {
            HStack {
                panelHeader(title: "白平衡", value: camera.whiteBalanceDisplay)

                Button {
                    camera.resetWhiteBalance()
                } label: {
                    Text("AUTO")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(camera.isWhiteBalanceLocked ? .white.opacity(0.78) : .black)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(camera.isWhiteBalanceLocked ? .white.opacity(0.12) : .white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            controlSlider(
                label: "TEMP",
                value: Double(camera.whiteBalanceTemperature),
                range: 2500...9000,
                display: "\(Int(camera.whiteBalanceTemperature))K"
            ) { camera.setWhiteBalance(temperature: Float($0)) }

            controlSlider(
                label: "TINT",
                value: Double(camera.whiteBalanceTint),
                range: -100...100,
                display: String(format: "%+.0f", camera.whiteBalanceTint)
            ) { camera.setWhiteBalance(tint: Float($0)) }
        }
        .padding(12)
        .frame(height: 98)
        .cameraBlackPanel(cornerRadius: 15)
    }

    private var filmPickerPanel: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                panelHeader(title: "胶片模拟", value: filmPanelStatus)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    filmCategoryChip(title: "全部", color: cameraAccent, isSelected: selectedFilmCategory == nil) {
                        selectedFilmCategory = nil
                    }

                    ForEach(FilmCategory.allCases, id: \.self) { category in
                        filmCategoryChip(
                            title: category.displayName,
                            color: category.accentColor,
                            isSelected: selectedFilmCategory == category
                        ) {
                            selectedFilmCategory = selectedFilmCategory == category ? nil : category
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 28)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        camera.selectedFilmPreset = nil
                    } label: {
                        CameraFilmChoiceButton(
                            title: "OFF",
                            icon: nil,
                            color: .white.opacity(0.16),
                            isSelected: camera.selectedFilmPreset == nil,
                            accent: cameraAccent
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(camera.captureFormat.isRaw)

                    ForEach(filteredFilmPresets) { preset in
                        Button {
                            guard !camera.captureFormat.isRaw else {
                                showCaptureMessage("\(camera.captureFormat.title) 会保存 DNG，不应用胶片效果")
                                return
                            }

                            camera.selectedFilmPreset = preset
                        } label: {
                            CameraFilmChoiceButton(
                                title: preset.cameraShortName,
                                icon: preset.icon,
                                color: preset.category.accentColor,
                                isSelected: camera.selectedFilmPreset?.id == preset.id,
                                accent: cameraAccent
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 52)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 122)
        .cameraBlackPanel(cornerRadius: 15)
    }

    private func filmCategoryChip(
        title: String,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.56)
                .foregroundStyle(isSelected ? .black : .white.opacity(0.78))
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(isSelected ? color : Color.white.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var filmPreviewOverlay: some View {
        LinearGradient(
            colors: activePreviewPreset?.cameraPreviewOverlayColors ?? [.clear, .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .blendMode(.softLight)
        .opacity(activePreviewPreset?.cameraPreviewOverlayOpacity ?? 0)
    }

    private var vignetteOverlay: some View {
        RadialGradient(
            colors: [
                .clear,
                .black.opacity(activePreviewPreset?.cameraPreviewVignetteOpacity ?? 0.08)
            ],
            center: .center,
            startRadius: 80,
            endRadius: 520
        )
        .blendMode(.multiply)
    }

    private var inactiveViewfinder: some View {
        VStack(spacing: 16) {
            Image(systemName: camera.authorizationStatus == .denied ? "camera.fill.badge.ellipsis" : "camera.aperture")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))

            VStack(spacing: 7) {
                Text(camera.permissionTitle)
                    .font(.system(size: 17, weight: .semibold))

                Text(camera.permissionMessage)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            Button {
                camera.requestPermissionOrOpenSettings()
            } label: {
                Text(camera.authorizationStatus == .notDetermined ? "允许相机权限" : "打开系统设置")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .cameraDarkCapsule()
            }
            .buttonStyle(.plain)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(white: 0.02),
                    Color(red: 0.11, green: 0.12, blue: 0.13),
                    Color(white: 0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func sideToolButton(_ tool: CameraSideTool) -> some View {
        Button {
            handleSideTool(tool)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tool.icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(height: 16)

                Text(tool.title)
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
            }
            .foregroundStyle(isSideToolActive(tool) ? cameraAccent : .white.opacity(0.78))
            .frame(width: 46, height: 36)
            .background(isSideToolActive(tool) ? cameraAccent.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func handleSideTool(_ tool: CameraSideTool) {
        switch tool {
        case .flash:
            showCaptureMessage("闪光灯入口已加入")
        case .timer:
            showCaptureMessage("定时器入口已加入")
        case .grid:
            showGrid.toggle()
        case .level:
            showLevel.toggle()
        case .focusPeaking:
            showFocusPeaking.toggle()
        case .zebra:
            showZebra.toggle()
        case .reference:
            showReference.toggle()
        case .histogram:
            showCaptureMessage("直方图已开启")
        case .exposure:
            togglePanel(.exposure)
        case .whiteBalance:
            togglePanel(.whiteBalance)
        }
    }

    private func isSideToolActive(_ tool: CameraSideTool) -> Bool {
        switch tool {
        case .grid:
            return showGrid
        case .level:
            return showLevel
        case .focusPeaking:
            return showFocusPeaking
        case .zebra:
            return showZebra
        case .reference:
            return showReference
        case .exposure:
            return activePanel == .exposure
        case .whiteBalance:
            return activePanel == .whiteBalance
        case .histogram:
            return true
        default:
            return false
        }
    }

    private func togglePanel(_ panel: CameraControlPanel) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            activePanel = activePanel == panel ? nil : panel
        }
    }

    private func collapseControlPanel() {
        guard activePanel != nil else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            activePanel = nil
        }
    }

    private func panelHeader(title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
    }

    private func controlSlider(
        label: String,
        value: Double,
        range: ClosedRange<Double>,
        display: String,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.52))
                .frame(width: 38, alignment: .leading)

            Slider(
                value: Binding(
                    get: { value },
                    set: { onChange($0) }
                ),
                in: range
            )
            .tint(cameraAccent)

            Text(display)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 58, alignment: .trailing)
        }
    }

    private func captureToast(_ message: String) -> some View {
        VStack {
            HStack(spacing: 9) {
                Image(systemName: message.contains("失败") || message.contains("不可用") || message.contains("权限") ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))

                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .cameraDarkCapsule()
            .padding(.top, 68)

            Spacer()
        }
        .padding(.horizontal, 24)
        .allowsHitTesting(false)
    }

    private func triggerShutter() {
        flashViewfinder()

        camera.capturePhoto { result in
            Task {
                switch result {
                case .success(let capture):
                    await saveCapture(capture)
                case .failure(let error):
                    showCaptureMessage(error.localizedDescription)
                }
            }
        }
    }

    private func saveCapture(_ capture: CameraCaptureResult) async {
        let preset = capture.isRaw ? nil : camera.selectedFilmPreset

        isSavingCapture = true
        defer { isSavingCapture = false }

        do {
            try await onPhotoCaptured(capture, preset)
            showCaptureMessage(capture.isRaw ? "\(capture.format.title) DNG 已保存到系统相册" : "已应用胶片并保存到系统相册")
        } catch {
            showCaptureMessage(error.localizedDescription)
        }
    }

    private func showCaptureMessage(_ message: String) {
        captureMessage = message

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if captureMessage == message {
                captureMessage = nil
            }
        }
    }

    private func handleFocusTap(devicePoint: CGPoint, viewPoint: CGPoint) {
        camera.focusAndExpose(at: devicePoint)
        collapseControlPanel()

        withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
            focusIndicator = viewPoint
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeOut(duration: 0.2)) {
                focusIndicator = nil
            }
        }
    }

    private func flashViewfinder() {
        withAnimation(.easeOut(duration: 0.08)) {
            isShutterFlashing = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.easeIn(duration: 0.16)) {
                isShutterFlashing = false
            }
        }
    }
}

// MARK: - Camera Tools

private enum CameraSideTool: String, CaseIterable, Identifiable {
    case flash
    case timer
    case grid
    case level
    case focusPeaking
    case zebra
    case reference
    case histogram
    case exposure
    case whiteBalance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flash: return "闪光灯"
        case .timer: return "定时器"
        case .grid: return "网格"
        case .level: return "水平仪"
        case .focusPeaking: return "峰值"
        case .zebra: return "斑马纹"
        case .reference: return "参考线"
        case .histogram: return "直方图"
        case .exposure: return "EV"
        case .whiteBalance: return "白平衡"
        }
    }

    var icon: String {
        switch self {
        case .flash: return "bolt.fill"
        case .timer: return "timer"
        case .grid: return "grid"
        case .level: return "gyroscope"
        case .focusPeaking: return "scope"
        case .zebra: return "line.diagonal"
        case .reference: return "xmark.circle"
        case .histogram: return "chart.bar.xaxis"
        case .exposure: return "plusminus.circle"
        case .whiteBalance: return "thermometer.medium"
        }
    }

    static var pageCount: Int { 2 }

    static func tools(for page: Int) -> [CameraSideTool] {
        if page % pageCount == 0 {
            return [.flash, .timer, .grid, .level, .focusPeaking]
        }

        return [.zebra, .reference, .histogram, .exposure, .whiteBalance]
    }
}

private struct CameraShutterSpeed: Identifiable {
    let title: String
    let duration: Double

    var id: String { title }

    static let defaultSpeeds: [CameraShutterSpeed] = [
        CameraShutterSpeed(title: "1/4000", duration: 1.0 / 4000.0),
        CameraShutterSpeed(title: "1/2000", duration: 1.0 / 2000.0),
        CameraShutterSpeed(title: "1/1000", duration: 1.0 / 1000.0),
        CameraShutterSpeed(title: "1/500", duration: 1.0 / 500.0),
        CameraShutterSpeed(title: "1/250", duration: 1.0 / 250.0),
        CameraShutterSpeed(title: "1/125", duration: 1.0 / 125.0),
        CameraShutterSpeed(title: "1/60", duration: 1.0 / 60.0),
        CameraShutterSpeed(title: "1/30", duration: 1.0 / 30.0),
        CameraShutterSpeed(title: "1/15", duration: 1.0 / 15.0),
        CameraShutterSpeed(title: "1/8", duration: 1.0 / 8.0),
        CameraShutterSpeed(title: "1/4", duration: 1.0 / 4.0),
        CameraShutterSpeed(title: "1/2", duration: 1.0 / 2.0),
        CameraShutterSpeed(title: "1s", duration: 1)
    ]
}

// MARK: - Components

private struct CameraHeaderTool: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 28, height: 20)

            Text(title)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(Color(red: 0.84, green: 0.73, blue: 0.63))
        .frame(width: 36)
    }
}

private struct CameraReadoutCell: View {
    let title: String
    let value: String
    var valueColor: Color = Color(red: 0.86, green: 0.78, blue: 0.69)

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.54)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
    }
}

private struct CameraReadoutDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.10))
            .frame(width: 1, height: 26)
    }
}

private struct CameraDeckDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.10))
            .frame(width: 1)
            .padding(.vertical, 10)
    }
}

private struct HistogramView: View {
    let bins: [CGFloat]

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.2) {
            ForEach(Array(bins.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.92), .white.opacity(0.42)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, value * 38))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ZoomRail: View {
    let zoomFactor: CGFloat
    let maxZoomFactor: CGFloat
    let accent: Color
    let onSelect: (CGFloat) -> Void

    var body: some View {
        VStack(spacing: 8) {
            zoomButton(title: "2", factor: 2)
            zoomButton(title: "1x", factor: 1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 12)
        .background(.black.opacity(0.58), in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func zoomButton(title: String, factor: CGFloat) -> some View {
        let isAvailable = factor <= maxZoomFactor
        let isSelected = abs(zoomFactor - factor) < 0.08

        return Button {
            onSelect(factor)
        } label: {
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? accent : .white.opacity(isAvailable ? 0.86 : 0.32))

                if isSelected {
                    Rectangle()
                        .fill(accent)
                        .frame(width: 21, height: 1.5)
                }
            }
            .frame(width: 30, height: 34)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
    }
}

private struct EVScaleStrip: View {
    let value: Double
    let minValue: Double
    let maxValue: Double
    let accent: Color
    let onChange: (Double) -> Void

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Text("EV")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 34)
                    .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )

                VStack(spacing: 2) {
                    HStack {
                        Text("-2.0")
                        Spacer()
                        Text("-1.0")
                        Spacer()
                        Text("0")
                        Spacer()
                        Text("+1.0")
                        Spacer()
                        Text("+2.0")
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))

                    ZStack {
                        CameraTickScale(accent: accent)
                            .frame(height: 22)

                        Slider(
                            value: Binding(
                                get: { value },
                                set: { onChange($0) }
                            ),
                            in: minValue...maxValue,
                            step: 0.1
                        )
                        .tint(accent)
                        .opacity(0.88)
                    }

                    Text(String(format: "%+.1f", value))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                }

                Button {
                    onChange(0)
                } label: {
                    Text("自动")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.84))
                        .frame(width: 44, height: 34)
                        .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
    }
}

private struct CameraTickScale: View {
    let accent: Color

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<41, id: \.self) { index in
                Rectangle()
                    .fill(index == 20 ? accent : .white.opacity(index % 10 == 0 ? 0.68 : 0.34))
                    .frame(width: index == 20 ? 2 : 1, height: index % 10 == 0 ? 13 : 6)
            }
        }
    }
}

private struct CameraParameterCell: View {
    let title: String
    let value: String
    let detail: String
    let accent: Color

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))

            Text(value)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )

            Text(detail)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .padding(.horizontal, 8)
        .frame(width: 86)
    }
}

private struct CameraFilmChoiceButton: View {
    let title: String
    let icon: String?
    let color: Color
    let isSelected: Bool
    let accent: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                color.opacity(isSelected ? 0.86 : 0.28),
                                Color.white.opacity(isSelected ? 0.22 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 34)

                if let icon {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                } else {
                    Image(systemName: "slash.circle")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? accent.opacity(0.95) : .white.opacity(0.10), lineWidth: 1)
            )

            Text(title)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.48)
                .foregroundStyle(.white.opacity(isSelected ? 0.96 : 0.64))
                .frame(width: 48)
        }
        .frame(width: 50)
    }
}

private struct CameraFilmLauncher: View {
    let preset: FilmPreset?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.60, green: 0.42, blue: 0.26))
                    .frame(width: 38, height: 48)

                if let preset {
                    Image(preset.icon)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.72))
                }
            }

            Text("胶片模拟")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
        }
        .frame(width: 54)
    }
}

private struct CameraLibraryLauncher: View {
    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.75, green: 0.86, blue: 0.86),
                            Color(red: 0.20, green: 0.25, blue: 0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                )

            Text("相册")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
        }
        .frame(width: 54)
    }
}

private struct CameraShutterButton: View {
    let isBusy: Bool
    let canCapture: Bool
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.53, blue: 0.11),
                            Color(red: 0.84, green: 0.22, blue: 0.03)
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 42
                    )
                )
                .frame(width: diameter * 0.79, height: diameter * 0.79)

            Circle()
                .stroke(.black.opacity(0.72), lineWidth: max(5, diameter * 0.075))
                .frame(width: diameter * 0.94, height: diameter * 0.94)

            Circle()
                .stroke(.white.opacity(canCapture ? 0.42 : 0.14), lineWidth: 2)
                .frame(width: diameter, height: diameter)

            if isBusy {
                ProgressView()
                    .tint(.white)
            }
        }
        .opacity(canCapture ? 1 : 0.48)
        .frame(width: diameter, height: diameter)
    }
}

private struct CameraRoundTool: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 46, height: 46)
                .background(.black.opacity(0.34), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 1))

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
        }
        .frame(width: 48)
    }
}

private struct CameraFilmRailButton: View {
    let preset: FilmPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isSelected ? 0.88 : 0.12),
                                    preset.category.accentColor.opacity(isSelected ? 0.82 : 0.30)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 44)

                    Image(preset.icon)
                        .resizable()
                        .scaledToFit()
                        .padding(7)
                        .opacity(isSelected ? 0.96 : 0.72)
                }

                Text(preset.cameraShortName.uppercased())
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(width: 54)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ViewfinderGrid: View {
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Spacer()
                gridLine(width: 1)
                Spacer()
                gridLine(width: 1)
                Spacer()
            }

            VStack(spacing: 0) {
                Spacer()
                gridLine(height: 1)
                Spacer()
                gridLine(height: 1)
                Spacer()
            }
        }
    }

    private func gridLine(width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
        Rectangle()
            .fill(.white.opacity(0.22))
            .frame(width: width, height: height)
    }
}

private struct FrameGuideOverlay: View {
    let aspectRatio: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            if let aspectRatio {
                let cropSize = cropSize(in: proxy.size, aspectRatio: aspectRatio)
                let x = (proxy.size.width - cropSize.width) / 2
                let y = (proxy.size.height - cropSize.height) / 2

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.black.opacity(0.56))
                        .frame(width: proxy.size.width, height: y)

                    Rectangle()
                        .fill(.black.opacity(0.56))
                        .frame(width: proxy.size.width, height: y)
                        .offset(y: y + cropSize.height)

                    Rectangle()
                        .fill(.black.opacity(0.56))
                        .frame(width: x, height: cropSize.height)
                        .offset(y: y)

                    Rectangle()
                        .fill(.black.opacity(0.56))
                        .frame(width: x, height: cropSize.height)
                        .offset(x: x + cropSize.width, y: y)

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(.white.opacity(0.34), lineWidth: 1)
                        .frame(width: cropSize.width, height: cropSize.height)
                        .offset(x: x, y: y)
                }
            }
        }
    }

    private func cropSize(in size: CGSize, aspectRatio: CGFloat) -> CGSize {
        let candidateHeight = size.width / aspectRatio

        if candidateHeight <= size.height {
            return CGSize(width: size.width, height: candidateHeight)
        }

        return CGSize(width: size.height * aspectRatio, height: size.height)
    }
}

private struct LevelGuideOverlay: View {
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let centerY = proxy.size.height / 2

            HStack(spacing: 10) {
                Rectangle()
                    .fill(accent.opacity(0.9))
                    .frame(width: 72, height: 2)
                Circle()
                    .stroke(accent.opacity(0.9), lineWidth: 2)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(accent.opacity(0.9))
                    .frame(width: 72, height: 2)
            }
            .position(x: proxy.size.width / 2, y: centerY)
        }
    }
}

private struct ReferenceGuideOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: proxy.size.width * 0.5, y: 0))
                path.addLine(to: CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height))
                path.move(to: CGPoint(x: 0, y: proxy.size.height * 0.5))
                path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height * 0.5))
            }
            .stroke(.white.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [6, 8]))
        }
    }
}

private struct ZebraOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                var path = Path()
                let spacing: CGFloat = 15

                for offset in stride(from: -size.height, through: size.width, by: spacing) {
                    path.move(to: CGPoint(x: offset, y: size.height))
                    path.addLine(to: CGPoint(x: offset + size.height, y: 0))
                }

                context.stroke(path, with: .color(.white.opacity(0.16)), lineWidth: 2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .mask(
            LinearGradient(
                colors: [.clear, .white.opacity(0.65), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct FocusPeakingOverlay: View {
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            Path { path in
                path.addRect(CGRect(x: width * 0.18, y: height * 0.28, width: width * 0.16, height: height * 0.12))
                path.addRect(CGRect(x: width * 0.62, y: height * 0.38, width: width * 0.20, height: height * 0.16))
                path.addRect(CGRect(x: width * 0.36, y: height * 0.58, width: width * 0.18, height: height * 0.14))
            }
            .stroke(accent.opacity(0.62), lineWidth: 1)
        }
    }
}

private struct FocusReticleView: View {
    let accent: Color

    var body: some View {
        ZStack {
            HStack(spacing: 52) {
                cornerTick
                cornerTick.rotationEffect(.degrees(180))
            }

            VStack(spacing: 52) {
                cornerTick.rotationEffect(.degrees(90))
                cornerTick.rotationEffect(.degrees(270))
            }

            Image(systemName: "plus")
                .font(.system(size: 22, weight: .regular))
        }
        .foregroundStyle(accent.opacity(0.96))
        .frame(width: 86, height: 86)
    }

    private var cornerTick: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 22))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 22, y: 0))
        }
        .stroke(accent.opacity(0.96), lineWidth: 1.6)
        .frame(width: 22, height: 22)
    }
}

private struct CameraLeatherTexture: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 5

            for x in stride(from: CGFloat(0), through: size.width, by: step) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height * 0.26, y: size.height))
                context.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: 0.5)
            }

            for y in stride(from: CGFloat(0), through: size.height, by: step * 1.4) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y + 9))
                context.stroke(path, with: .color(.black.opacity(0.18)), lineWidth: 0.6)
            }
        }
    }
}

private extension View {
    func cameraBlackPanel(cornerRadius: CGFloat) -> some View {
        self
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.055, green: 0.052, blue: 0.048).opacity(0.96),
                        Color(red: 0.018, green: 0.017, blue: 0.016).opacity(0.98)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 10)
    }

    func cameraDarkCapsule() -> some View {
        self
            .background(.black.opacity(0.46), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
    }
}
