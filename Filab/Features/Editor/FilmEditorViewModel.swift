import SwiftUI
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Film Editor ViewModel

@MainActor
class FilmEditorViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var originalImage: UIImage?
    @Published var processedImage: UIImage?
    @Published var selectedPreset: FilmPreset?
    @Published var adjustments: AdjustmentParams = AdjustmentParams()

    @Published var isProcessing = false
    @Published var isComparing = false
    @Published var isControlsExpanded = true

    @Published var showError = false
    @Published var errorMessage = ""

    // Track the current editing record ID (nil if creating new)
    @Published var editingRecordId: String? = nil

    // MARK: - Private Properties

    private let metalProcessor = MetalFilmProcessor.shared
    private var previewImage: UIImage?
    private var processingTask: Task<Void, Never>?
    private var processingGeneration = 0
    private var cancellables = Set<AnyCancellable>()

    // CIContext for Core Image processing (fallback)
    private let ciContext = CIContext()

    // MARK: - Initialization

    init() {
        setupBindings()
    }

    private func setupBindings() {
        // React to preset changes
        $selectedPreset
            .dropFirst()
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.metalProcessor.markFilmDirty()
                self?.processImage()
            }
            .store(in: &cancellables)

        // React to adjustment changes with throttle for smooth slider performance
        // throttle: 在拖动期间定期发射最新值，保证实时性同时避免过度处理
        $adjustments
            .dropFirst()
            .throttle(for: .milliseconds(50), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                self?.processImage()
            }
            .store(in: &cancellables)
    }

    // MARK: - Image Loading

    func loadImage(_ image: UIImage) {
        // Normalize image orientation
        let normalizedImage = image.normalizedOrientation()
        originalImage = normalizedImage
        previewImage = normalizedImage.resizedForProcessing(maxDimension: 1600)

        // Load into Metal processor (may fail on simulator or unsupported devices)
        let metalSuccess = metalProcessor.loadImage(previewImage ?? normalizedImage)
        metalProcessor.markFilmDirty()

        // Select default preset if none selected
        if selectedPreset == nil {
            selectedPreset = FilmPreset.allPresets.first { $0.id == "portra400" }
        } else if metalSuccess {
            // Only auto-process if Metal is available
            processImage()
        }
    }

    // MARK: - Preset Selection

    func selectPreset(_ preset: FilmPreset) {
        selectedPreset = preset

        // 重置所有 ADJUST 参数为默认值（只保留胶片强度 opacity）
        adjustments = AdjustmentParams(opacity: 100)

        // 标记胶片管线需要重新运行
        metalProcessor.markFilmDirty()

        // Auto-expand controls when selecting a preset
        withAnimation {
            isControlsExpanded = false
        }
    }

    // MARK: - Image Processing

    func triggerProcessing() {
        processImage()
    }

    func clearProcessingState() {
        processingTask?.cancel()
        processingGeneration += 1
        previewImage = nil
        isProcessing = false
        metalProcessor.markFilmDirty()
    }

    private func processImage() {
        guard let originalImage = originalImage,
              let preset = selectedPreset else { return }

        // Cancel previous task
        processingTask?.cancel()
        processingGeneration += 1
        let generation = processingGeneration

        // Capture current adjustment values to avoid actor isolation issues
        let currentAdjustments = adjustments
        let processor = metalProcessor
        let targetImage = previewImage ?? originalImage
        isProcessing = true

        processingTask = Task { [weak self] in
            if let metalResult = await Self.processWithMetal(
                processor: processor,
                preset: preset,
                adjustments: currentAdjustments
            ) {
                await MainActor.run {
                    guard let self, !Task.isCancelled, generation == self.processingGeneration else { return }
                    self.processedImage = metalResult
                    self.isProcessing = false
                }
                return
            }

            guard !Task.isCancelled else { return }

            guard let result = await self?.processWithCoreImageAsync(
                image: targetImage,
                preset: preset,
                adjustments: currentAdjustments
            ) else {
                await MainActor.run {
                    guard let self, generation == self.processingGeneration else { return }
                    self.isProcessing = false
                }
                return
            }

            await MainActor.run {
                guard let self, !Task.isCancelled, generation == self.processingGeneration else { return }
                self.processedImage = result
                self.isProcessing = false
            }
        }
    }

    /// Create a smaller preview image for faster processing during adjustments
    private func createPreviewImage(from image: UIImage) async -> UIImage {
        let maxDimension: CGFloat = 1200
        let maxCurrent = max(image.size.width, image.size.height)

        guard maxCurrent > maxDimension else { return image }

        let scale = maxDimension / maxCurrent
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        return await Task.detached(priority: .userInitiated) {
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resized = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return resized ?? image
        }.value
    }

    nonisolated private static func processWithMetal(
        processor: MetalFilmProcessor,
        preset: FilmPreset,
        adjustments: AdjustmentParams
    ) async -> UIImage? {
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard !Task.isCancelled else { return nil }
            return processor.processImage(
                preset: preset,
                adjustments: adjustments,
                isCompare: false
            )
        }

        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Async version of Core Image processing on background thread
    private func processWithCoreImageAsync(
        image: UIImage,
        preset: FilmPreset,
        adjustments: AdjustmentParams
    ) async -> UIImage? {
        // Capture all needed values before entering detached task
        let whiteBalanceRGB = preset.whiteBalance.toRGB()
        let neutralRGB = WhiteBalance.neutral.toRGB()
        let colorMatrix = preset.colorMatrix
        let presetContrast = preset.contrast
        let presetSaturation = preset.saturation
        let presetVignette = preset.vignette
        let scale = image.scale

        return await Task.detached(priority: .userInitiated) {
            guard let ciImage = CIImage(image: image) else { return nil }

            var outputImage = ciImage
            let blendFactor = adjustments.opacity / 100.0
            let context = CIContext()

            // Apply white balance
            let blendedWhiteBalance = self.mix(neutralRGB, whiteBalanceRGB, t: Float(blendFactor))
            outputImage = self.applyWhiteBalance(to: outputImage, rgb: blendedWhiteBalance)

            // Apply color matrix
            if blendFactor > 0 {
                let blendedMatrix = self.blendMatrix(colorMatrix, strength: blendFactor)
                outputImage = self.applyColorMatrix(to: outputImage, matrix: blendedMatrix)
            }

            // Apply exposure
            if adjustments.exposure != 0 {
                outputImage = self.applyExposure(to: outputImage, value: adjustments.exposure)
            }

            // Apply contrast
            if adjustments.contrast != 0 || presetContrast != 1.0 {
                let contrast = 1.0 + (adjustments.contrast / 100.0)
                let finalPresetContrast = 1.0 + (presetContrast - 1.0) * blendFactor
                outputImage = self.applyContrast(to: outputImage, value: finalPresetContrast * contrast)
            }

            // Apply highlights/shadows and white/black levels
            if adjustments.highlights != 0 || adjustments.shadows != 0 {
                outputImage = self.applyHighlightsShadows(
                    to: outputImage,
                    highlights: adjustments.highlights,
                    shadows: adjustments.shadows
                )
            }

            if adjustments.whites != 0 || adjustments.blacks != 0 {
                outputImage = self.applyWhitesBlacks(
                    to: outputImage,
                    whites: adjustments.whites,
                    blacks: adjustments.blacks
                )
            }

            // Apply saturation
            if adjustments.saturation != 0 || presetSaturation != 1.0 {
                let saturation = 1.0 + (adjustments.saturation / 100.0)
                let finalPresetSaturation = 1.0 + (presetSaturation - 1.0) * blendFactor
                outputImage = self.applySaturation(to: outputImage, value: max(0, finalPresetSaturation * saturation))
            }

            // Apply temperature/tint
            if adjustments.temperature != 0 || adjustments.tint != 0 {
                outputImage = self.applyTemperatureTint(
                    to: outputImage,
                    temperature: adjustments.temperature,
                    tint: adjustments.tint
                )
            }

            // Apply clarity
            if adjustments.clarity != 0 {
                outputImage = self.applyClarity(to: outputImage, value: adjustments.clarity)
            }

            if adjustments.sharpness != 0 {
                outputImage = self.applySharpness(to: outputImage, value: adjustments.sharpness)
            }

            if !self.isHSLDefault(adjustments) {
                outputImage = self.applyHSLApproximation(to: outputImage, adjustments: adjustments)
            }

            if adjustments.splitShadowSaturation > 0 || adjustments.splitHighlightSaturation > 0 {
                outputImage = self.applySplitToningApproximation(to: outputImage, adjustments: adjustments)
            }

            // Apply soft glow / bloom
            let glowValue = adjustments.softGlow + adjustments.bloom * 0.75
            if glowValue > 0 {
                outputImage = self.applySoftGlow(to: outputImage, value: min(100, glowValue))
            }

            if adjustments.halation > 0 {
                outputImage = self.applyHalation(to: outputImage, value: adjustments.halation)
            }

            if adjustments.fade > 0 {
                outputImage = self.applyFade(to: outputImage, value: adjustments.fade, warmth: adjustments.fadeWarmth)
            }

            // Apply vignette
            let vignette = (presetVignette * blendFactor) + (adjustments.vignette / 100.0)
            if vignette != 0 {
                outputImage = self.applyVignette(to: outputImage, intensity: vignette)
            }

            // Apply grain - 只使用用户调节的 adjustments.grain，不再叠加 preset 的 grain
            // preset 的 grain 已作为默认值设置在 adjustments.grain 中
            let grain = adjustments.grain / 100.0
            if grain > 0 {
                outputImage = self.applyGrain(to: outputImage, intensity: grain, softness: adjustments.grainSize / 100.0)
            }

            // Render on background thread
            guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
                return nil
            }

            return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        }.value
    }

    // MARK: - Core Image Fallback Processing

    private func processWithCoreImage(image: UIImage, preset: FilmPreset) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }

        var outputImage = ciImage

        // Calculate blend factor based on opacity (film effect strength)
        let blendFactor = adjustments.opacity / 100.0

        // Apply white balance with strength
        let whiteBalance = preset.whiteBalance.toRGB()
        let neutralBalance = WhiteBalance.neutral.toRGB()
        let blendedWhiteBalance = mix(neutralBalance, whiteBalance, t: Float(blendFactor))
        outputImage = applyWhiteBalance(to: outputImage, rgb: blendedWhiteBalance)

        // Apply color matrix with strength
        if blendFactor > 0 {
            let blendedMatrix = blendMatrix(preset.colorMatrix, strength: blendFactor)
            outputImage = applyColorMatrix(to: outputImage, matrix: blendedMatrix)
        }

        // Apply exposure
        if adjustments.exposure != 0 {
            outputImage = applyExposure(to: outputImage, value: adjustments.exposure)
        }

        // Apply contrast
        if adjustments.contrast != 0 || preset.contrast != 1.0 {
            let contrast = 1.0 + (adjustments.contrast / 100.0)
            let presetContrast = 1.0 + (preset.contrast - 1.0) * blendFactor
            outputImage = applyContrast(to: outputImage, value: presetContrast * contrast)
        }

        // Apply saturation
        if adjustments.saturation != 0 || preset.saturation != 1.0 {
            let saturation = 1.0 + (adjustments.saturation / 100.0)
            let presetSaturation = 1.0 + (preset.saturation - 1.0) * blendFactor
            outputImage = applySaturation(to: outputImage, value: max(0, presetSaturation * saturation))
        }

        // Apply temperature/tint
        if adjustments.temperature != 0 || adjustments.tint != 0 {
            outputImage = applyTemperatureTint(
                to: outputImage,
                temperature: adjustments.temperature,
                tint: adjustments.tint
            )
        }

        // Apply clarity
        if adjustments.clarity != 0 {
            outputImage = applyClarity(to: outputImage, value: adjustments.clarity)
        }

        // Apply highlights/shadows
        if adjustments.highlights != 0 || adjustments.shadows != 0 {
            outputImage = applyHighlightsShadows(
                to: outputImage,
                highlights: adjustments.highlights,
                shadows: adjustments.shadows
            )
        }

        if adjustments.whites != 0 || adjustments.blacks != 0 {
            outputImage = applyWhitesBlacks(
                to: outputImage,
                whites: adjustments.whites,
                blacks: adjustments.blacks
            )
        }

        // Apply soft glow before edge shading so the glow still feels optically natural.
        if adjustments.softGlow > 0 {
            outputImage = applySoftGlow(to: outputImage, value: adjustments.softGlow)
        }

        // Apply vignette
        let vignette = (preset.vignette * blendFactor) + (adjustments.vignette / 100.0)
        if vignette != 0 {
            outputImage = applyVignette(to: outputImage, intensity: vignette)
        }

        // Apply grain - 只使用用户调节的 adjustments.grain，不再叠加 preset 的 grain
        let grain = adjustments.grain / 100.0
        if grain > 0 {
            outputImage = applyGrain(to: outputImage, intensity: grain, softness: 0.5)
        }

        // Render to UIImage
        guard let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    // MARK: - Helper Functions for Blending

    nonisolated private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        return a + (b - a) * t
    }

    nonisolated private func blendMatrix(_ matrix: ColorMatrix, strength: Double) -> ColorMatrix {
        // Inline identity values to avoid MainActor isolation issues
        let identityValues: [Double] = [
            1.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            0.0, 0.0, 1.0
        ]
        let values = matrix.values

        var blendedValues = [Double]()
        for i in 0..<values.count {
            let blended = identityValues[i] + (values[i] - identityValues[i]) * strength
            blendedValues.append(blended)
        }

        return ColorMatrix(values: blendedValues)
    }

    // MARK: - Core Image Filter Helpers

    nonisolated private func applyWhiteBalance(to image: CIImage, rgb: SIMD3<Float>) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: CGFloat(rgb.x), y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: CGFloat(rgb.y), z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: CGFloat(rgb.z), w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return filter.outputImage ?? image
    }

    nonisolated private func applyColorMatrix(to image: CIImage, matrix: ColorMatrix) -> CIImage {
        let values = matrix.values
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image

        filter.rVector = CIVector(x: CGFloat(values[0]), y: CGFloat(values[1]), z: CGFloat(values[2]), w: 0)
        filter.gVector = CIVector(x: CGFloat(values[3]), y: CGFloat(values[4]), z: CGFloat(values[5]), w: 0)
        filter.bVector = CIVector(x: CGFloat(values[6]), y: CGFloat(values[7]), z: CGFloat(values[8]), w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)

        return filter.outputImage ?? image
    }

    nonisolated private func applyExposure(to image: CIImage, value: Double) -> CIImage {
        let filter = CIFilter.exposureAdjust()
        filter.inputImage = image
        filter.ev = Float(value / 50.0)
        return filter.outputImage ?? image
    }

    nonisolated private func applyContrast(to image: CIImage, value: Double) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.contrast = Float(value)
        return filter.outputImage ?? image
    }

    nonisolated private func applySaturation(to image: CIImage, value: Double) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.saturation = Float(value)
        return filter.outputImage ?? image
    }

    nonisolated private func applyTemperatureTint(to image: CIImage, temperature: Double, tint: Double) -> CIImage {
        // 使用 CITemperatureAndTint - 与 Lightroom 色温/色调相同的算法
        // temperature: -50~+50, 正值变暖，负值变冷
        // tint: -50~+50, 正值偏洋红，负值偏绿

        guard temperature != 0 || tint != 0 else { return image }

        // CITemperatureAndTint 参数说明：
        // neutral: 当前白点 (x=色温K值, y=色调偏移)
        // targetNeutral: 目标白点
        // 原理：计算从 neutral 到 targetNeutral 的色适应变换矩阵

        let tempStrength = temperature / 50.0  // -1.0 ~ 1.0
        let tintStrength = tint / 50.0         // -1.0 ~ 1.0

        // 基础色温 6500K（D65 标准白光）
        let baseTemp: CGFloat = 6500

        // 计算目标色温：正值变暖（降低色温），负值变冷（提高色温）
        // 范围：约 3000K（暖）到 10000K（冷）
        let tempDelta = -tempStrength * 3500  // 负号：正值变暖
        let targetTemp = baseTemp + tempDelta

        // 色调偏移：±100 范围对应 ±100 色调单位
        let targetTint = tintStrength * 100

        let filter = CIFilter.temperatureAndTint()
        filter.inputImage = image

        // 源白点（当前图像的白点）
        filter.neutral = CIVector(x: baseTemp, y: 0)

        // 目标白点（要校正到的白点）
        // 通过设置不同的目标白点，实现色温/色调偏移效果
        filter.targetNeutral = CIVector(x: targetTemp, y: targetTint)

        return filter.outputImage ?? image
    }

    nonisolated private func applyClarity(to image: CIImage, value: Double) -> CIImage {
        let normalized = value / 50.0
        let contrast = max(0.65, 1.0 + normalized * 0.22)
        let saturation = max(0.75, 1.0 + normalized * 0.06)
        let brightness = normalized > 0 ? 0 : normalized * 0.02

        return image.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: contrast,
            kCIInputSaturationKey: saturation,
            kCIInputBrightnessKey: brightness
        ])
    }

    nonisolated private func applySoftGlow(to image: CIImage, value: Double) -> CIImage {
        let normalizedStrength = min(max(value / 100.0, 0), 1) * 0.62
        let radius = 4.0 + normalizedStrength * 18.0
        let intensity = normalizedStrength * 0.42

        return image.applyingFilter("CIBloom", parameters: [
            kCIInputRadiusKey: radius,
            kCIInputIntensityKey: intensity
        ]).cropped(to: image.extent)
    }

    nonisolated private func applyVignette(to image: CIImage, intensity: Double) -> CIImage {
        let extent = image.extent
        let minDimension = min(extent.width, extent.height)

        let maskFilter = CIFilter.radialGradient()
        maskFilter.center = CGPoint(x: extent.midX, y: extent.midY)
        maskFilter.radius0 = Float(minDimension * 0.22)
        maskFilter.radius1 = Float(minDimension * 0.7)
        maskFilter.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        maskFilter.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)

        let maskImage = (maskFilter.outputImage ?? image).cropped(to: extent)
        let amount = min(abs(intensity), 1.0)

        let edgeAdjusted: CIImage
        if intensity > 0 {
            edgeAdjusted = image.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: -amount * 0.28,
                kCIInputContrastKey: 1.0 + amount * 0.08
            ])
        } else {
            edgeAdjusted = image.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: amount * 0.2,
                kCIInputContrastKey: max(0.7, 1.0 - amount * 0.06)
            ])
        }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = edgeAdjusted
        blend.backgroundImage = image
        blend.maskImage = maskImage
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    nonisolated private func applyHighlightsShadows(to image: CIImage, highlights: Double, shadows: Double) -> CIImage {
        return applyToneColorCube(to: image, highlights: highlights, shadows: shadows, whites: 0, blacks: 0)
    }

    nonisolated private func applyWhitesBlacks(to image: CIImage, whites: Double, blacks: Double) -> CIImage {
        return applyToneColorCube(to: image, highlights: 0, shadows: 0, whites: whites, blacks: blacks)
    }

    nonisolated private func applyToneColorCube(
        to image: CIImage,
        highlights: Double,
        shadows: Double,
        whites: Double,
        blacks: Double
    ) -> CIImage {
        let dimension = 32
        let maxIndex = Float(dimension - 1)
        let normalizedHighlights = Float(min(max(highlights / 100.0, -1.0), 1.0))
        let normalizedShadows = Float(min(max(shadows / 100.0, -1.0), 1.0))
        let normalizedWhites = Float(min(max(whites / 100.0, -1.0), 1.0))
        let normalizedBlacks = Float(min(max(blacks / 100.0, -1.0), 1.0))

        var cubeData = [Float]()
        cubeData.reserveCapacity(dimension * dimension * dimension * 4)

        for blueIndex in 0..<dimension {
            let blue = Float(blueIndex) / maxIndex
            for greenIndex in 0..<dimension {
                let green = Float(greenIndex) / maxIndex
                for redIndex in 0..<dimension {
                    let red = Float(redIndex) / maxIndex
                    var color = SIMD3<Float>(
                        linearFromSRGB(red),
                        linearFromSRGB(green),
                        linearFromSRGB(blue)
                    )

                    if abs(normalizedHighlights) > 0.0001 || abs(normalizedShadows) > 0.0001 {
                        color = applyToneRangeCPU(color, highlights: normalizedHighlights, shadows: normalizedShadows)
                    }

                    if abs(normalizedWhites) > 0.0001 || abs(normalizedBlacks) > 0.0001 {
                        color = applyWhitesBlacksCPU(color, whites: normalizedWhites, blacks: normalizedBlacks)
                    }

                    cubeData.append(srgbFromLinear(color.x))
                    cubeData.append(srgbFromLinear(color.y))
                    cubeData.append(srgbFromLinear(color.z))
                    cubeData.append(1.0)
                }
            }
        }

        let cube = cubeData.withUnsafeBufferPointer { buffer in
            Data(bytes: buffer.baseAddress!, count: buffer.count * MemoryLayout<Float>.size)
        }

        return image.applyingFilter("CIColorCube", parameters: [
            "inputCubeDimension": dimension,
            "inputCubeData": cube
        ])
    }

    nonisolated private func applyToneRangeCPU(
        _ color: SIMD3<Float>,
        highlights: Float,
        shadows: Float
    ) -> SIMD3<Float> {
        let luma = max(luminanceCPU(color), 0)
        let luma01 = clamp(luma, min: 0, max: 1)
        var targetLuma = luma

        if abs(shadows) > 0.0001 {
            let amount = perceptualSliderAmount(shadows)
            let blackProtect = smoothstep(edge0: 0.025, edge1: 0.14, x: luma01)
            let shadowMask = blackProtect * (1 - smoothstep(edge0: 0.46, edge1: 0.76, x: luma01))

            if shadows > 0 {
                let lifted = powf(luma01, 1 / (1 + amount * 0.58))
                targetLuma = mix(targetLuma, lifted, t: shadowMask * (0.58 + amount * 0.14))
            } else {
                let crushed = powf(luma01, 1 + amount * 0.72)
                targetLuma = mix(targetLuma, crushed, t: shadowMask * (0.52 + amount * 0.16))
            }
        }

        if abs(highlights) > 0.0001 {
            let amount = min(abs(highlights), 1)
            let highlightMask = smoothstep(edge0: 0.40, edge1: 0.95, x: luma01)

            if highlights > 0 {
                let lifted = 1 - powf(1 - luma01, 1 + amount * 0.75)
                targetLuma = mix(targetLuma, lifted, t: highlightMask * 0.72)
            } else {
                var compressed = powf(luma01, 1 + amount * 1.20)
                compressed *= 1 - amount * 0.10 * highlightMask
                targetLuma = mix(targetLuma, compressed, t: highlightMask)
            }
        }

        return remapLuminanceCPU(color, targetLuma: targetLuma)
    }

    nonisolated private func applyWhitesBlacksCPU(
        _ color: SIMD3<Float>,
        whites: Float,
        blacks: Float
    ) -> SIMD3<Float> {
        let luma = max(luminanceCPU(color), 0)
        let luma01 = clamp(luma, min: 0, max: 1)
        var targetLuma = luma

        if abs(blacks) > 0.0001 {
            let amount = perceptualSliderAmount(blacks)
            let blackProtect = smoothstep(edge0: 0.025, edge1: 0.12, x: luma01)
            let blackMask = blackProtect * (1 - smoothstep(edge0: 0.24, edge1: 0.48, x: luma01))

            if blacks > 0 {
                let lifted = luma01 + amount * 0.052 * blackMask * (1 - luma01)
                targetLuma = mix(targetLuma, min(lifted, 1), t: 0.82)
            } else {
                var crushed = powf(luma01, 1 + amount * 0.62)
                crushed *= 1 - amount * 0.045 * blackMask
                targetLuma = mix(targetLuma, crushed, t: blackMask * 0.62)
            }
        }

        if abs(whites) > 0.0001 {
            let amount = min(abs(whites), 1)
            let whiteMask = smoothstep(edge0: 0.68, edge1: 0.98, x: luma01)

            if whites > 0 {
                let lifted = 1 - powf(1 - luma01, 1 + amount * 0.95)
                targetLuma = mix(targetLuma, lifted, t: whiteMask)
            } else {
                var compressed = powf(luma01, 1 + amount * 0.80)
                compressed *= 1 - amount * 0.16 * whiteMask
                targetLuma = mix(targetLuma, compressed, t: whiteMask)
            }
        }

        return remapLuminanceCPU(color, targetLuma: targetLuma)
    }

    nonisolated private func remapLuminanceCPU(
        _ color: SIMD3<Float>,
        targetLuma: Float
    ) -> SIMD3<Float> {
        let currentLuma = luminanceCPU(color)
        if abs(targetLuma - currentLuma) < 0.00001 {
            return color
        }

        let target = softShoulderLumaCPU(targetLuma)
        let shifted = color + SIMD3<Float>(repeating: target - currentLuma)

        var fitAmount: Float = 0
        fitAmount = max(fitAmount, gamutFitAmount(channel: shifted.x, targetLuma: target))
        fitAmount = max(fitAmount, gamutFitAmount(channel: shifted.y, targetLuma: target))
        fitAmount = max(fitAmount, gamutFitAmount(channel: shifted.z, targetLuma: target))

        let fitted = mix(shifted, SIMD3<Float>(repeating: target), t: clamp(fitAmount, min: 0, max: 1))
        return SIMD3<Float>(
            max(fitted.x, 0),
            max(fitted.y, 0),
            max(fitted.z, 0)
        )
    }

    nonisolated private func softShoulderLumaCPU(_ value: Float) -> Float {
        let value = max(value, 0)
        let knee: Float = 0.94
        guard value > knee else { return value }
        return knee + (1 - knee) * (1 - expf(-(value - knee) / (1 - knee)))
    }

    nonisolated private func gamutFitAmount(channel: Float, targetLuma: Float) -> Float {
        if channel < 0 {
            return -channel / max(targetLuma - channel, 0.00001)
        }

        if channel > 1 {
            return (channel - 1) / max(channel - targetLuma, 0.00001)
        }

        return 0
    }

    nonisolated private func luminanceCPU(_ color: SIMD3<Float>) -> Float {
        color.x * 0.2126 + color.y * 0.7152 + color.z * 0.0722
    }

    nonisolated private func linearFromSRGB(_ value: Float) -> Float {
        if value <= 0.04045 {
            return value / 12.92
        }
        return powf((value + 0.055) / 1.055, 2.4)
    }

    nonisolated private func srgbFromLinear(_ value: Float) -> Float {
        let value = clamp(value, min: 0, max: 1)
        if value <= 0.0031308 {
            return value * 12.92
        }
        return 1.055 * powf(value, 1 / 2.4) - 0.055
    }

    nonisolated private func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        let t = clamp((x - edge0) / (edge1 - edge0), min: 0, max: 1)
        return t * t * (3 - 2 * t)
    }

    nonisolated private func perceptualSliderAmount(_ value: Float) -> Float {
        powf(clamp(abs(value), min: 0, max: 1), 1.35)
    }

    nonisolated private func mix(_ a: Float, _ b: Float, t: Float) -> Float {
        a + (b - a) * t
    }

    nonisolated private func clamp(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
        min(max(value, minValue), maxValue)
    }

    nonisolated private func applySharpness(to image: CIImage, value: Double) -> CIImage {
        if value > 0 {
            return image.applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: 0.8 + value / 50.0 * 1.2,
                kCIInputIntensityKey: 0.18 + value / 50.0 * 0.42
            ])
        }

        let blurRadius = abs(value) / 50.0 * 1.8
        let blurred = image.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: blurRadius
        ]).cropped(to: image.extent)

        return blurred
    }

    nonisolated private func isHSLDefault(_ adjustments: AdjustmentParams) -> Bool {
        adjustments.hslRedHue == 0 && adjustments.hslRedSaturation == 0 && adjustments.hslRedLuminance == 0 &&
        adjustments.hslOrangeHue == 0 && adjustments.hslOrangeSaturation == 0 && adjustments.hslOrangeLuminance == 0 &&
        adjustments.hslYellowHue == 0 && adjustments.hslYellowSaturation == 0 && adjustments.hslYellowLuminance == 0 &&
        adjustments.hslGreenHue == 0 && adjustments.hslGreenSaturation == 0 && adjustments.hslGreenLuminance == 0 &&
        adjustments.hslCyanHue == 0 && adjustments.hslCyanSaturation == 0 && adjustments.hslCyanLuminance == 0 &&
        adjustments.hslBlueHue == 0 && adjustments.hslBlueSaturation == 0 && adjustments.hslBlueLuminance == 0 &&
        adjustments.hslPurpleHue == 0 && adjustments.hslPurpleSaturation == 0 && adjustments.hslPurpleLuminance == 0 &&
        adjustments.hslMagentaHue == 0 && adjustments.hslMagentaSaturation == 0 && adjustments.hslMagentaLuminance == 0
    }

    nonisolated private func applyHSLApproximation(to image: CIImage, adjustments: AdjustmentParams) -> CIImage {
        let hueValues = [
            adjustments.hslRedHue, adjustments.hslOrangeHue, adjustments.hslYellowHue, adjustments.hslGreenHue,
            adjustments.hslCyanHue, adjustments.hslBlueHue, adjustments.hslPurpleHue, adjustments.hslMagentaHue
        ]
        let satValues = [
            adjustments.hslRedSaturation, adjustments.hslOrangeSaturation, adjustments.hslYellowSaturation, adjustments.hslGreenSaturation,
            adjustments.hslCyanSaturation, adjustments.hslBlueSaturation, adjustments.hslPurpleSaturation, adjustments.hslMagentaSaturation
        ]
        let lumValues = [
            adjustments.hslRedLuminance, adjustments.hslOrangeLuminance, adjustments.hslYellowLuminance, adjustments.hslGreenLuminance,
            adjustments.hslCyanLuminance, adjustments.hslBlueLuminance, adjustments.hslPurpleLuminance, adjustments.hslMagentaLuminance
        ]

        let hueTotal = hueValues.reduce(0, +)
        let satTotal = satValues.reduce(0, +)
        let lumTotal = lumValues.reduce(0, +)
        var activeBandCount = 0
        for index in hueValues.indices {
            if hueValues[index] != 0 || satValues[index] != 0 || lumValues[index] != 0 {
                activeBandCount += 1
            }
        }

        let activeCount = Double(activeBandCount)

        guard activeCount > 0 else { return image }

        var output = image
        let hueAverage = hueTotal / activeCount
        if hueAverage != 0 {
            output = output.applyingFilter("CIHueAdjust", parameters: [
                kCIInputAngleKey: hueAverage / 180.0 * Double.pi
            ])
        }

        let saturation = max(0, 1.0 + (satTotal / activeCount) / 100.0)
        let brightness = (lumTotal / activeCount) / 100.0 * 0.18
        output = output.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: saturation,
            kCIInputBrightnessKey: brightness
        ])

        return output
    }

    nonisolated private func applySplitToningApproximation(to image: CIImage, adjustments: AdjustmentParams) -> CIImage {
        let shadow = rgbForHue(adjustments.splitShadowHue)
        let highlight = rgbForHue(adjustments.splitHighlightHue)
        let shadowAmount = adjustments.splitShadowSaturation / 100.0 * 0.10
        let highlightAmount = adjustments.splitHighlightSaturation / 100.0 * 0.08

        let rScale = 1.0 + (shadow.x - 1.0) * shadowAmount + (highlight.x - 1.0) * highlightAmount
        let gScale = 1.0 + (shadow.y - 1.0) * shadowAmount + (highlight.y - 1.0) * highlightAmount
        let bScale = 1.0 + (shadow.z - 1.0) * shadowAmount + (highlight.z - 1.0) * highlightAmount

        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: rScale, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gScale, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: bScale, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
    }

    nonisolated private func applyFade(to image: CIImage, value: Double, warmth: Double) -> CIImage {
        let amount = min(max(value / 100.0 * 0.28, 0), 0.28)
        let warm = min(max(warmth / 100.0, 0), 1)
        let red = 0.84 + (0.98 - 0.84) * warm
        let green = 0.88 + (0.91 - 0.88) * warm
        let blue = 0.94 + (0.82 - 0.94) * warm
        let overlay = CIImage(color: CIColor(red: red, green: green, blue: blue, alpha: amount)).cropped(to: image.extent)

        return overlay.applyingFilter("CISourceOverCompositing", parameters: [
            kCIInputBackgroundImageKey: image
        ]).cropped(to: image.extent)
    }

    nonisolated private func applyHalation(to image: CIImage, value: Double) -> CIImage {
        let normalized = min(max(value / 100.0, 0), 1) * 0.30
        let blurred = image.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: 2.0 + normalized * 14.0
        ]).cropped(to: image.extent)

        let redGlow = blurred.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1.25 * normalized, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0.34 * normalized, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0.16 * normalized, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])

        return redGlow.applyingFilter("CIScreenBlendMode", parameters: [
            kCIInputBackgroundImageKey: image
        ]).cropped(to: image.extent)
    }

    nonisolated private func rgbForHue(_ hue: Double) -> SIMD3<Double> {
        let normalized = ((hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)) / 60.0
        let x = 1.0 - abs(normalized.truncatingRemainder(dividingBy: 2.0) - 1.0)

        switch normalized {
        case 0..<1: return SIMD3<Double>(1, x, 0)
        case 1..<2: return SIMD3<Double>(x, 1, 0)
        case 2..<3: return SIMD3<Double>(0, 1, x)
        case 3..<4: return SIMD3<Double>(0, x, 1)
        case 4..<5: return SIMD3<Double>(x, 0, 1)
        default: return SIMD3<Double>(1, 0, x)
        }
    }

    nonisolated private func applyGrain(to image: CIImage, intensity: Double, softness: Double) -> CIImage {
        let noiseFilter = CIFilter.randomGenerator()
        guard var noiseImage = noiseFilter.outputImage else { return image }

        let scale = 0.3 + softness * 0.4
        noiseImage = noiseImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = noiseImage
        blendFilter.backgroundImage = image
        blendFilter.maskImage = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])

        let alpha = intensity * 0.3
        let filter = CIFilter.sourceOverCompositing()
        filter.inputImage = blendFilter.outputImage?.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 1.0 + alpha,
            kCIInputBrightnessKey: -alpha * 0.5
        ])
        filter.backgroundImage = image

        return filter.outputImage ?? image
    }

    // MARK: - Adjustments Management

    func resetAdjustments() {
        // Reset all adjustments but keep opacity at 100 (full film effect)
        adjustments = AdjustmentParams(opacity: 100)
    }

    func resetGrain() {
        adjustments.grain = 0
    }

    func setGrainPreset(_ preset: String) {
        switch preset {
        case "无": adjustments.grain = 0
        case "轻": adjustments.grain = 15
        case "中": adjustments.grain = 30
        case "重": adjustments.grain = 50
        default: break
        }
    }

    // MARK: - Export

    func exportImage() -> UIImage? {
        return processedImage
    }

    func renderFullResolutionImage() async -> UIImage? {
        guard let originalImage,
              let preset = selectedPreset else {
            return processedImage
        }

        let exportProcessor = MetalFilmProcessor()
        if exportProcessor.loadImage(originalImage) {
            exportProcessor.markFilmDirty()
            if let result = await Self.processWithMetal(
                processor: exportProcessor,
                preset: preset,
                adjustments: adjustments
            ) {
                return result
            }
        }

        return await processWithCoreImageAsync(
            image: originalImage,
            preset: preset,
            adjustments: adjustments
        )
    }

    func exportWithWatermark() -> UIImage? {
        guard let image = processedImage else { return nil }

        // Create watermarked version
        let size = image.size
        UIGraphicsBeginImageContextWithOptions(size, false, image.scale)

        image.draw(at: .zero)

        // Add watermark
        let watermark = "Film Lab"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.7)
        ]
        let textSize = watermark.size(withAttributes: attributes)
        let textRect = CGRect(
            x: size.width - textSize.width - 20,
            y: size.height - textSize.height - 20,
            width: textSize.width,
            height: textSize.height
        )
        watermark.draw(in: textRect, withAttributes: attributes)

        let watermarkedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return watermarkedImage
    }
}

// MARK: - UIImage Extension

extension UIImage {
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up {
            return self
        }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalizedImage ?? self
    }

    func resizedForProcessing(maxDimension: CGFloat) -> UIImage {
        let maxCurrent = max(size.width, size.height)
        guard maxCurrent > maxDimension else { return self }

        let scaleFactor = maxDimension / maxCurrent
        let newSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
