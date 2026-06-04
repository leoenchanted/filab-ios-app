import Foundation
import Metal
import MetalKit
import CoreImage
import simd

// MARK: - Metal Film Processor

final class MetalFilmProcessor: @unchecked Sendable {
    // MARK: - Properties

    static let shared = MetalFilmProcessor()

    nonisolated(unsafe) private var device: MTLDevice?
    nonisolated(unsafe) private var commandQueue: MTLCommandQueue?
    nonisolated(unsafe) private var library: MTLLibrary?

    // Pipeline states
    nonisolated(unsafe) private var filmPipelineState: MTLRenderPipelineState?
    nonisolated(unsafe) private var adjustPipelineState: MTLRenderPipelineState?
    nonisolated(unsafe) private var blurPipelineState: MTLRenderPipelineState?
    nonisolated(unsafe) private var halationPipelineState: MTLRenderPipelineState?
    nonisolated(unsafe) private var compositePipelineState: MTLRenderPipelineState?

    // Textures
    nonisolated(unsafe) private var sourceTexture: MTLTexture?
    nonisolated(unsafe) private var filmSimulatedTexture: MTLTexture?  // 胶片模拟后的纹理
    nonisolated(unsafe) private var processedTexture: MTLTexture?
    nonisolated(unsafe) private var bloomTexture: MTLTexture?
    nonisolated(unsafe) private var intermediateTexture: MTLTexture?

    // Flag: 是否需要重新跑胶片管线
    nonisolated(unsafe) private var needsFilmUpdate = true

    // Vertex buffer
    nonisolated(unsafe) private var vertexBuffer: MTLBuffer?

    // Current processing state
    nonisolated(unsafe) private(set) var isProcessing = false
    nonisolated(unsafe) private(set) var progress: Float = 0

    // Time for grain animation
    nonisolated(unsafe) private var grainTime: Float = 0
    private let processingLock = NSLock()

    // MARK: - Initialization

    init() {
        setupMetal()
        setupPipelines()
        setupVertexBuffer()
    }

    // MARK: - Setup

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Failed to create Metal device")
            return
        }
        self.device = device
        self.commandQueue = device.makeCommandQueue()

        // Load default library (shaders compiled from .metal file)
        do {
            library = try device.makeDefaultLibrary(bundle: Bundle.main)
        } catch {
            print("Failed to load Metal library: \(error)")
            // Try to load from source
            let shaderSource = try? String(contentsOfFile: Bundle.main.path(forResource: "FilmShaders", ofType: "metal") ?? "", encoding: .utf8)
            if let source = shaderSource {
                do {
                    library = try device.makeLibrary(source: source, options: nil)
                } catch {
                    print("Failed to compile shaders from source: \(error)")
                }
            }
        }
    }

    private func setupPipelines() {
        guard let library = library else {
            print("Metal library not loaded")
            return
        }

        // Get shader functions with error checking
        guard let vertexFunction = library.makeFunction(name: "vertexShader"),
              let filmFragmentFunction = library.makeFunction(name: "fragmentFilmShader"),
              let adjustFragmentFunction = library.makeFunction(name: "fragmentAdjustShader"),
              let blurFragmentFunction = library.makeFunction(name: "fragmentBlurShader") else {
            print("Failed to load shader functions")
            return
        }

        // Film processing pipeline (full pipeline - run on preset change)
        let filmDescriptor = MTLRenderPipelineDescriptor()
        filmDescriptor.vertexFunction = vertexFunction
        filmDescriptor.fragmentFunction = filmFragmentFunction
        filmDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm

        // ADJUST-only pipeline (lightweight - run on slider drag)
        let adjustDescriptor = MTLRenderPipelineDescriptor()
        adjustDescriptor.vertexFunction = vertexFunction
        adjustDescriptor.fragmentFunction = adjustFragmentFunction
        adjustDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm

        // Blur pipeline
        let blurDescriptor = MTLRenderPipelineDescriptor()
        blurDescriptor.vertexFunction = vertexFunction
        blurDescriptor.fragmentFunction = blurFragmentFunction
        blurDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm

        // Halation pipeline
        let halationDescriptor = MTLRenderPipelineDescriptor()
        halationDescriptor.vertexFunction = vertexFunction
        halationDescriptor.fragmentFunction = library.makeFunction(name: "fragmentHalationShader")
        halationDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm

        // Composite pipeline
        let compositeDescriptor = MTLRenderPipelineDescriptor()
        compositeDescriptor.vertexFunction = vertexFunction
        compositeDescriptor.fragmentFunction = library.makeFunction(name: "fragmentCompositeShader")
        compositeDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm

        do {
            filmPipelineState = try device?.makeRenderPipelineState(descriptor: filmDescriptor)
            adjustPipelineState = try device?.makeRenderPipelineState(descriptor: adjustDescriptor)
            blurPipelineState = try device?.makeRenderPipelineState(descriptor: blurDescriptor)
            halationPipelineState = try device?.makeRenderPipelineState(descriptor: halationDescriptor)
            compositePipelineState = try device?.makeRenderPipelineState(descriptor: compositeDescriptor)
            print("Metal pipelines created successfully")
        } catch {
            print("Failed to create pipeline states: \(error)")
        }
    }

    private func setupVertexBuffer() {
        guard let device = device else {
            print("Device not available for vertex buffer")
            return
        }

        // Full-screen quad vertices (position only - texCoord calculated in shader)
        let vertices: [Float] = [
            -1.0, -1.0,   // Bottom-left
             1.0, -1.0,   // Bottom-right
            -1.0,  1.0,   // Top-left
             1.0,  1.0    // Top-right
        ]

        let bufferSize = vertices.count * MemoryLayout<Float>.size
        vertexBuffer = device.makeBuffer(bytes: vertices,
                                         length: bufferSize,
                                         options: .storageModeShared)

        if vertexBuffer == nil {
            print("Failed to create vertex buffer")
        } else {
            print("Vertex buffer created: \(bufferSize) bytes")
        }
    }

    // MARK: - Texture Management

    nonisolated func loadImage(_ image: UIImage) -> Bool {
        processingLock.lock()
        defer { processingLock.unlock() }

        guard let device = device else {
            print("Metal device not available")
            return false
        }

        let textureLoader = MTKTextureLoader(device: device)

        guard let cgImage = image.cgImage else {
            print("No CGImage available")
            return false
        }

        // Check image dimensions
        let width = cgImage.width
        let height = cgImage.height
        if width == 0 || height == 0 {
            print("Invalid image dimensions: \(width)x\(height)")
            return false
        }

        do {
            let textureOptions: [MTKTextureLoader.Option: Any] = [
                .SRGB: false,
                .generateMipmaps: false
            ]
            sourceTexture = try textureLoader.newTexture(cgImage: cgImage, options: textureOptions)

            // Verify source texture was created
            guard let sourceTexture = sourceTexture,
                  sourceTexture.width > 0,
                  sourceTexture.height > 0 else {
                print("Failed to create source texture")
                return false
            }

            // Create intermediate textures
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: sourceTexture.width,
                height: sourceTexture.height,
                mipmapped: false
            )
            textureDescriptor.usage = [.renderTarget, .shaderRead]

            filmSimulatedTexture = device.makeTexture(descriptor: textureDescriptor)
            processedTexture = device.makeTexture(descriptor: textureDescriptor)
            intermediateTexture = device.makeTexture(descriptor: textureDescriptor)
            bloomTexture = device.makeTexture(descriptor: textureDescriptor)

            // Verify textures were created
            guard processedTexture != nil, filmSimulatedTexture != nil else {
                print("Failed to create textures")
                return false
            }

            // 关键修复：新纹理没有内容，必须重新跑胶片管线
            needsFilmUpdate = true

            print("Metal textures created successfully: \(sourceTexture.width)x\(sourceTexture.height)")
            return true
        } catch {
            print("Failed to load image into Metal: \(error)")
            return false
        }
    }

    // MARK: - Processing

    nonisolated func processImage(preset: FilmPreset, adjustments: AdjustmentParams,
                      isCompare: Bool = false) -> UIImage? {
        processingLock.lock()
        defer { processingLock.unlock() }

        guard device != nil,
              let commandQueue = commandQueue,
              let sourceTexture = sourceTexture,
              let processedTexture = processedTexture,
              let filmSimulatedTexture = filmSimulatedTexture,
              filmPipelineState != nil,
              adjustPipelineState != nil,
              vertexBuffer != nil else {
            print("Metal resources not available, skipping Metal processing")
            return nil
        }

        guard sourceTexture.width > 0, sourceTexture.height > 0,
              processedTexture.width > 0, processedTexture.height > 0 else {
            print("Invalid texture dimensions")
            return nil
        }

        isProcessing = true
        progress = 0.1

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("Failed to create command buffer")
            isProcessing = false
            return nil
        }

        // === Pass 1: 胶片模拟（仅在预设切换或 opacity 改变时运行） ===
        if needsFilmUpdate {
            progress = 0.3
            applyFilmEffect(commandBuffer: commandBuffer,
                           preset: preset,
                           adjustments: adjustments,
                           outputTexture: filmSimulatedTexture)

            if let halation = preset.halation {
                progress = 0.5
                applyHalation(commandBuffer: commandBuffer,
                             config: halation)
            }
            needsFilmUpdate = false
        }

        // === Pass 2: ADJUST 调整（始终运行，从 filmSimulatedTexture 读取） ===
        progress = 0.7
        applyAdjustEffect(commandBuffer: commandBuffer,
                         adjustments: adjustments,
                         outputTexture: processedTexture)

        progress = 0.9

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        progress = 1.0
        isProcessing = false

        return getResultImage()
    }

    /// 标记胶片管线需要重新运行（预设切换时调用）
    nonisolated func markFilmDirty() {
        processingLock.lock()
        defer { processingLock.unlock() }
        needsFilmUpdate = true
    }

    /// 检测 opacity 是否变化，如果变化也标记胶片管线脏
    nonisolated func markFilmDirtyIfOpacityChanged(_ oldOpacity: Double, _ newOpacity: Double) {
        if abs(oldOpacity - newOpacity) > 0.01 {
            processingLock.lock()
            defer { processingLock.unlock() }
            needsFilmUpdate = true
        }
    }

    nonisolated private func applyFilmEffect(commandBuffer: MTLCommandBuffer,
                                             preset: FilmPreset,
                                             adjustments _: AdjustmentParams,
                                             outputTexture: MTLTexture? = nil) {
        let targetTexture = outputTexture ?? processedTexture!

        guard let device = device else {
            print("Device is nil")
            return
        }
        guard let filmPipelineState = filmPipelineState else {
            print("filmPipelineState is nil")
            return
        }
        guard let vertexBuffer = vertexBuffer else {
            print("vertexBuffer is nil")
            return
        }
        guard let sourceTexture = sourceTexture else {
            print("sourceTexture is nil")
            return
        }

        guard sourceTexture.width > 0, sourceTexture.height > 0,
              targetTexture.width > 0, targetTexture.height > 0 else {
            print("Invalid texture dimensions")
            return
        }

        // Validate buffer size
        guard vertexBuffer.length >= 32 else {
            print("Vertex buffer too small: \(vertexBuffer.length)")
            return
        }

        // Create uniforms with curve data
        var uniforms = FilmUniforms()

        // Basic parameters
        uniforms.colorMatrix = preset.colorMatrix.toSIMD()
        // whiteBalance is split into separate Floats to match Metal's float3 layout
        let wb = preset.whiteBalance.toRGB()
        uniforms.whiteBalanceR = wb.x
        uniforms.whiteBalanceG = wb.y
        uniforms.whiteBalanceB = wb.z
        uniforms.exposure = 0
        uniforms.contrast = Float(preset.contrast)
        uniforms.saturation = Float(max(0, preset.saturation))
        uniforms.vignette = Float(max(-1.0, min(1.0, preset.vignette)))
        uniforms.softGlow = 0
        uniforms.fade = Float(preset.fade)
        uniforms.grainIntensity = Float(preset.grain.intensity)
        uniforms.grainSoftness = Float(preset.grain.softness)
        uniforms.grainFineSoftness = Float(preset.grain.fineSoftness)
        uniforms.grainFineWeight = Float(preset.grain.fineWeight)
        uniforms.grainCoarseWeight = Float(preset.grain.coarseWeight)
        uniforms.highlightReduction = Float(preset.grain.highlightReduction)
        uniforms.grainColorVariance = Float(preset.grain.colorVariance)
        uniforms.grainMode = Int32(preset.grain.mode.rawValue)
        uniforms.bloomSigma = preset.bloom != nil ? Float(preset.bloom!.sigma) : 0.0
        uniforms.bloomStrength = preset.bloom != nil ? Float(preset.bloom!.strength) : 0.0
        // 胶片 pass 始终用 opacity=1.0（完整效果），adjust pass 处理 opacity 混合
        uniforms.opacity = 1.0
        uniforms.highlights = 0
        uniforms.shadows = 0
        uniforms.isMonochrome = preset.saturation == 0 ? 1 : 0
        uniforms.time = grainTime
        uniforms.temperature = 0
        uniforms.tint = 0
        uniforms.clarity = 0

        // === Tone curve data ===
        // Master curve - check if it's not linear (has custom points)
        let isLinearCurve = preset.curve.points.count == 5 &&
            preset.curve.points[0][0] == 0 && preset.curve.points[0][1] == 0 &&
            preset.curve.points[4][0] == 255 && preset.curve.points[4][1] == 255 &&
            abs(preset.curve.points[2][0] - preset.curve.points[2][1]) < 10  // midpoint roughly linear

        uniforms.useCurve = isLinearCurve ? 0 : 1
        uniforms.curveCount = Int32(min(preset.curve.points.count, MAX_CURVE_POINTS))
        // Fill inline curve points
        let curvePoints = preset.curve.points
        if curvePoints.count > 0 { uniforms.curvePoint0 = SIMD2<Float>(Float(curvePoints[0][0]), Float(curvePoints[0][1])) }
        if curvePoints.count > 1 { uniforms.curvePoint1 = SIMD2<Float>(Float(curvePoints[1][0]), Float(curvePoints[1][1])) }
        if curvePoints.count > 2 { uniforms.curvePoint2 = SIMD2<Float>(Float(curvePoints[2][0]), Float(curvePoints[2][1])) }
        if curvePoints.count > 3 { uniforms.curvePoint3 = SIMD2<Float>(Float(curvePoints[3][0]), Float(curvePoints[3][1])) }
        if curvePoints.count > 4 { uniforms.curvePoint4 = SIMD2<Float>(Float(curvePoints[4][0]), Float(curvePoints[4][1])) }
        if curvePoints.count > 5 { uniforms.curvePoint5 = SIMD2<Float>(Float(curvePoints[5][0]), Float(curvePoints[5][1])) }
        if curvePoints.count > 6 { uniforms.curvePoint6 = SIMD2<Float>(Float(curvePoints[6][0]), Float(curvePoints[6][1])) }
        if curvePoints.count > 7 { uniforms.curvePoint7 = SIMD2<Float>(Float(curvePoints[7][0]), Float(curvePoints[7][1])) }

        // Red curve (Fuji: compresses highlights)
        if let curveR = preset.curveR {
            uniforms.useCurveR = 1
            uniforms.curveRCount = Int32(min(curveR.points.count, MAX_CURVE_POINTS))
            let points = curveR.points
            if points.count > 0 { uniforms.curveRPoint0 = SIMD2<Float>(Float(points[0][0]), Float(points[0][1])) }
            if points.count > 1 { uniforms.curveRPoint1 = SIMD2<Float>(Float(points[1][0]), Float(points[1][1])) }
            if points.count > 2 { uniforms.curveRPoint2 = SIMD2<Float>(Float(points[2][0]), Float(points[2][1])) }
            if points.count > 3 { uniforms.curveRPoint3 = SIMD2<Float>(Float(points[3][0]), Float(points[3][1])) }
            if points.count > 4 { uniforms.curveRPoint4 = SIMD2<Float>(Float(points[4][0]), Float(points[4][1])) }
            if points.count > 5 { uniforms.curveRPoint5 = SIMD2<Float>(Float(points[5][0]), Float(points[5][1])) }
            if points.count > 6 { uniforms.curveRPoint6 = SIMD2<Float>(Float(points[6][0]), Float(points[6][1])) }
            if points.count > 7 { uniforms.curveRPoint7 = SIMD2<Float>(Float(points[7][0]), Float(points[7][1])) }
        } else {
            uniforms.useCurveR = 0
            uniforms.curveRCount = 0
        }

        // Green curve (usually follows master)
        if let curveG = preset.curveG {
            uniforms.useCurveG = 1
            uniforms.curveGCount = Int32(min(curveG.points.count, MAX_CURVE_POINTS))
            let points = curveG.points
            if points.count > 0 { uniforms.curveGPoint0 = SIMD2<Float>(Float(points[0][0]), Float(points[0][1])) }
            if points.count > 1 { uniforms.curveGPoint1 = SIMD2<Float>(Float(points[1][0]), Float(points[1][1])) }
            if points.count > 2 { uniforms.curveGPoint2 = SIMD2<Float>(Float(points[2][0]), Float(points[2][1])) }
            if points.count > 3 { uniforms.curveGPoint3 = SIMD2<Float>(Float(points[3][0]), Float(points[3][1])) }
            if points.count > 4 { uniforms.curveGPoint4 = SIMD2<Float>(Float(points[4][0]), Float(points[4][1])) }
            if points.count > 5 { uniforms.curveGPoint5 = SIMD2<Float>(Float(points[5][0]), Float(points[5][1])) }
            if points.count > 6 { uniforms.curveGPoint6 = SIMD2<Float>(Float(points[6][0]), Float(points[6][1])) }
            if points.count > 7 { uniforms.curveGPoint7 = SIMD2<Float>(Float(points[7][0]), Float(points[7][1])) }
        } else {
            uniforms.useCurveG = 0
            uniforms.curveGCount = 0
        }

        // Blue curve (Fuji: lifts shadows, Polaroid: reduces blue)
        if let curveB = preset.curveB {
            uniforms.useCurveB = 1
            uniforms.curveBCount = Int32(min(curveB.points.count, MAX_CURVE_POINTS))
            let points = curveB.points
            if points.count > 0 { uniforms.curveBPoint0 = SIMD2<Float>(Float(points[0][0]), Float(points[0][1])) }
            if points.count > 1 { uniforms.curveBPoint1 = SIMD2<Float>(Float(points[1][0]), Float(points[1][1])) }
            if points.count > 2 { uniforms.curveBPoint2 = SIMD2<Float>(Float(points[2][0]), Float(points[2][1])) }
            if points.count > 3 { uniforms.curveBPoint3 = SIMD2<Float>(Float(points[3][0]), Float(points[3][1])) }
            if points.count > 4 { uniforms.curveBPoint4 = SIMD2<Float>(Float(points[4][0]), Float(points[4][1])) }
            if points.count > 5 { uniforms.curveBPoint5 = SIMD2<Float>(Float(points[5][0]), Float(points[5][1])) }
            if points.count > 6 { uniforms.curveBPoint6 = SIMD2<Float>(Float(points[6][0]), Float(points[6][1])) }
            if points.count > 7 { uniforms.curveBPoint7 = SIMD2<Float>(Float(points[7][0]), Float(points[7][1])) }
        } else {
            uniforms.useCurveB = 0
            uniforms.curveBCount = 0
        }

        grainTime += 1.0

        // Create uniform buffer - use actual size since FilmUniforms now has arrays
        let uniformBufferSize = MemoryLayout<FilmUniforms>.size
        guard let uniformBuffer = device.makeBuffer(bytes: &uniforms,
                                                     length: uniformBufferSize,
                                                     options: .storageModeShared) else {
            print("Failed to create uniform buffer")
            return
        }

        // Create render pass descriptor
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = targetTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        // Create render encoder
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            print("Failed to create render encoder")
            return
        }

        // Set pipeline state
        renderEncoder.setRenderPipelineState(filmPipelineState)

        // Set vertex buffer
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        // Create and set sampler
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        if let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) {
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        }

        // Set fragment resources
        renderEncoder.setFragmentTexture(sourceTexture, index: 0)
        renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)

        // Draw
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        // End encoding
        renderEncoder.endEncoding()
    }

    /// Lightweight ADJUST shader - reads from filmSimulatedTexture, applies only slider params
    nonisolated private func applyAdjustEffect(commandBuffer: MTLCommandBuffer,
                                               adjustments: AdjustmentParams,
                                               outputTexture: MTLTexture) {
        guard let device = device,
              let adjustPipelineState = adjustPipelineState,
              let filmSimulatedTexture = filmSimulatedTexture,
              let sourceTexture = sourceTexture,
              let vertexBuffer = vertexBuffer else {
            print("Missing resources for adjust pass")
            return
        }

        // Build lightweight adjust uniforms
        var uniforms = AdjustUniforms()

        let e = adjustments.exposure.clamped(to: -50.0...50.0)
        uniforms.exposure = Float(e / 16.666)

        let c = adjustments.contrast.clamped(to: -50.0...50.0)
        uniforms.contrast = Float(1.0 + c / 100.0)

        let s = adjustments.saturation.clamped(to: -50.0...50.0)
        uniforms.saturation = Float(1.0 + s / 50.0)

        uniforms.highlights = Float(adjustments.highlights.clamped(to: -100.0...100.0) / 100.0)
        uniforms.shadows = Float(adjustments.shadows.clamped(to: -100.0...100.0) / 100.0)
        uniforms.whites = Float(adjustments.whites.clamped(to: -100.0...100.0) / 100.0)
        uniforms.blacks = Float(adjustments.blacks.clamped(to: -100.0...100.0) / 100.0)
        uniforms.temperature = Float(adjustments.temperature.clamped(to: -50.0...50.0))
        uniforms.tint = Float(adjustments.tint.clamped(to: -50.0...50.0))
        uniforms.clarity = Float(adjustments.clarity.clamped(to: -50.0...50.0))
        uniforms.sharpness = Float(adjustments.sharpness.clamped(to: -50.0...50.0))
        uniforms.softGlow = Float(adjustments.softGlow / 100.0)
        uniforms.vignette = Float(adjustments.vignette.clamped(to: -100.0...100.0) / 100.0)
        uniforms.grainIntensity = Float(adjustments.grain.clamped(to: 0.0...100.0) / 100.0)
        uniforms.grainSoftness = Float(0.25 + adjustments.grainSize.clamped(to: 0.0...100.0) / 100.0 * 0.45)
        uniforms.grainSize = Float(adjustments.grainSize.clamped(to: 0.0...100.0) / 100.0)
        uniforms.grainRoughness = Float(adjustments.grainRoughness.clamped(to: 0.0...100.0) / 100.0)
        uniforms.grainColor = Float(adjustments.grainColor.clamped(to: 0.0...100.0) / 100.0)
        uniforms.opacity = Float(adjustments.opacity.clamped(to: 0.0...100.0) / 100.0)
        uniforms.halation = Float(adjustments.halation.clamped(to: 0.0...100.0))
        uniforms.bloom = Float(adjustments.bloom)
        uniforms.fade = Float(adjustments.fade.clamped(to: 0.0...100.0))
        uniforms.fadeWarmth = Float(adjustments.fadeWarmth.clamped(to: 0.0...100.0))
        uniforms.splitShadowHue = Float(adjustments.splitShadowHue.clamped(to: 0.0...360.0))
        uniforms.splitShadowSaturation = Float(adjustments.splitShadowSaturation.clamped(to: 0.0...100.0))
        uniforms.splitHighlightHue = Float(adjustments.splitHighlightHue.clamped(to: 0.0...360.0))
        uniforms.splitHighlightSaturation = Float(adjustments.splitHighlightSaturation.clamped(to: 0.0...100.0))
        uniforms.splitBalance = Float(adjustments.splitBalance.clamped(to: -50.0...50.0))
        uniforms.hslHueA = SIMD4<Float>(
            Float(adjustments.hslRedHue.clamped(to: -180.0...180.0)),
            Float(adjustments.hslOrangeHue.clamped(to: -180.0...180.0)),
            Float(adjustments.hslYellowHue.clamped(to: -180.0...180.0)),
            Float(adjustments.hslGreenHue.clamped(to: -180.0...180.0))
        )
        uniforms.hslHueB = SIMD4<Float>(
            Float(adjustments.hslCyanHue.clamped(to: -180.0...180.0)),
            Float(adjustments.hslBlueHue.clamped(to: -180.0...180.0)),
            Float(adjustments.hslPurpleHue.clamped(to: -180.0...180.0)),
            Float(adjustments.hslMagentaHue.clamped(to: -180.0...180.0))
        )
        uniforms.hslSatA = SIMD4<Float>(
            Float(adjustments.hslRedSaturation.clamped(to: -100.0...100.0)),
            Float(adjustments.hslOrangeSaturation.clamped(to: -100.0...100.0)),
            Float(adjustments.hslYellowSaturation.clamped(to: -100.0...100.0)),
            Float(adjustments.hslGreenSaturation.clamped(to: -100.0...100.0))
        )
        uniforms.hslSatB = SIMD4<Float>(
            Float(adjustments.hslCyanSaturation.clamped(to: -100.0...100.0)),
            Float(adjustments.hslBlueSaturation.clamped(to: -100.0...100.0)),
            Float(adjustments.hslPurpleSaturation.clamped(to: -100.0...100.0)),
            Float(adjustments.hslMagentaSaturation.clamped(to: -100.0...100.0))
        )
        uniforms.hslLumA = SIMD4<Float>(
            Float(adjustments.hslRedLuminance.clamped(to: -100.0...100.0)),
            Float(adjustments.hslOrangeLuminance.clamped(to: -100.0...100.0)),
            Float(adjustments.hslYellowLuminance.clamped(to: -100.0...100.0)),
            Float(adjustments.hslGreenLuminance.clamped(to: -100.0...100.0))
        )
        uniforms.hslLumB = SIMD4<Float>(
            Float(adjustments.hslCyanLuminance.clamped(to: -100.0...100.0)),
            Float(adjustments.hslBlueLuminance.clamped(to: -100.0...100.0)),
            Float(adjustments.hslPurpleLuminance.clamped(to: -100.0...100.0)),
            Float(adjustments.hslMagentaLuminance.clamped(to: -100.0...100.0))
        )
        uniforms.useSoftGlow = (adjustments.softGlow > 0 || adjustments.bloom > 0) ? 1 : 0
        uniforms.useGrain = adjustments.grain > 0 ? 1 : 0
        uniforms.useVignette = abs(adjustments.vignette) > 0 ? 1 : 0
        uniforms.time = grainTime

        grainTime += 0.5

        let uniformBufferSize = MemoryLayout<AdjustUniforms>.size
        guard let uniformBuffer = device.makeBuffer(bytes: &uniforms,
                                                     length: uniformBufferSize,
                                                     options: .storageModeShared) else {
            print("Failed to create adjust uniform buffer")
            return
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = outputTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            print("Failed to create adjust render encoder")
            return
        }

        renderEncoder.setRenderPipelineState(adjustPipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        if let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) {
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        }

        // Texture 0: film-simulated (base for adjust)
        // Texture 1: original (for opacity blend)
        renderEncoder.setFragmentTexture(filmSimulatedTexture, index: 0)
        renderEncoder.setFragmentTexture(sourceTexture, index: 1)
        renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)

        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
    }

    nonisolated private func applyHalation(commandBuffer: MTLCommandBuffer,
                                           config: HalationConfig) {
        guard let device = device,
              let filmSimulatedTexture = filmSimulatedTexture,
              let bloomTexture = bloomTexture,
              let intermediateTexture = intermediateTexture,
              let blurPipelineState = blurPipelineState,
              let halationPipelineState = halationPipelineState,
              let processedTexture = processedTexture,
              let vertexBuffer = vertexBuffer else {
            print("Missing resources for halation")
            return
        }

        // First blur pass - horizontal
        let blurPassDescriptor1 = MTLRenderPassDescriptor()
        blurPassDescriptor1.colorAttachments[0].texture = intermediateTexture
        blurPassDescriptor1.colorAttachments[0].loadAction = .clear
        blurPassDescriptor1.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        blurPassDescriptor1.colorAttachments[0].storeAction = .store

        guard let encoder1 = commandBuffer.makeRenderCommandEncoder(descriptor: blurPassDescriptor1) else {
            print("Failed to create blur encoder 1")
            return
        }

        var sigma1 = Float(config.sigmaSmall)
        var direction1 = SIMD2<Float>(1.0, 0.0)

        encoder1.setRenderPipelineState(blurPipelineState)
        encoder1.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        // Create sampler for blur
        let samplerDescriptor1 = MTLSamplerDescriptor()
        samplerDescriptor1.minFilter = .linear
        samplerDescriptor1.magFilter = .linear
        if let samplerState1 = device.makeSamplerState(descriptor: samplerDescriptor1) {
            encoder1.setFragmentSamplerState(samplerState1, index: 0)
        }

        encoder1.setFragmentTexture(filmSimulatedTexture, index: 0)
        encoder1.setFragmentBytes(&sigma1, length: MemoryLayout<Float>.size, index: 0)
        encoder1.setFragmentBytes(&direction1, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        encoder1.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder1.endEncoding()

        // Second blur pass - vertical
        let blurPassDescriptor2 = MTLRenderPassDescriptor()
        blurPassDescriptor2.colorAttachments[0].texture = bloomTexture
        blurPassDescriptor2.colorAttachments[0].loadAction = .clear
        blurPassDescriptor2.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        blurPassDescriptor2.colorAttachments[0].storeAction = .store

        guard let encoder2 = commandBuffer.makeRenderCommandEncoder(descriptor: blurPassDescriptor2) else {
            print("Failed to create blur encoder 2")
            return
        }

        var sigma2 = Float(config.sigmaLarge)
        var direction2 = SIMD2<Float>(0.0, 1.0)

        encoder2.setRenderPipelineState(blurPipelineState)
        encoder2.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        // Create sampler for blur
        let samplerDescriptor2 = MTLSamplerDescriptor()
        samplerDescriptor2.minFilter = .linear
        samplerDescriptor2.magFilter = .linear
        if let samplerState2 = device.makeSamplerState(descriptor: samplerDescriptor2) {
            encoder2.setFragmentSamplerState(samplerState2, index: 0)
        }

        encoder2.setFragmentTexture(intermediateTexture, index: 0)
        encoder2.setFragmentBytes(&sigma2, length: MemoryLayout<Float>.size, index: 0)
        encoder2.setFragmentBytes(&direction2, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        encoder2.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder2.endEncoding()

        let compositePassDescriptor = MTLRenderPassDescriptor()
        compositePassDescriptor.colorAttachments[0].texture = processedTexture
        compositePassDescriptor.colorAttachments[0].loadAction = .clear
        compositePassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        compositePassDescriptor.colorAttachments[0].storeAction = .store

        guard let compositeEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: compositePassDescriptor) else {
            print("Failed to create halation composite encoder")
            return
        }

        let colorShift = config.colorShift
        var uniforms = HalationUniforms(
            threshold: Float(config.threshold),
            strength: Float(config.strength),
            colorShiftR: Float(colorShift.indices.contains(0) ? colorShift[0] : 1.0),
            colorShiftG: Float(colorShift.indices.contains(1) ? colorShift[1] : 0.4),
            colorShiftB: Float(colorShift.indices.contains(2) ? colorShift[2] : 0.1),
            sigma: Float(config.sigmaLarge)
        )

        compositeEncoder.setRenderPipelineState(halationPipelineState)
        compositeEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        let compositeSamplerDescriptor = MTLSamplerDescriptor()
        compositeSamplerDescriptor.minFilter = .linear
        compositeSamplerDescriptor.magFilter = .linear
        if let samplerState = device.makeSamplerState(descriptor: compositeSamplerDescriptor) {
            compositeEncoder.setFragmentSamplerState(samplerState, index: 0)
        }

        compositeEncoder.setFragmentTexture(filmSimulatedTexture, index: 0)
        compositeEncoder.setFragmentTexture(bloomTexture, index: 1)
        compositeEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<HalationUniforms>.size, index: 0)
        compositeEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        compositeEncoder.endEncoding()

        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            print("Failed to create halation blit encoder")
            return
        }
        blitEncoder.copy(
            from: processedTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: processedTexture.width, height: processedTexture.height, depth: 1),
            to: filmSimulatedTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blitEncoder.endEncoding()
    }

    nonisolated private func compositeResult(commandBuffer: MTLCommandBuffer,
                                             opacity: Float,
                                             isCompare: Bool) {
        // Currently just copies processedTexture to itself or does nothing
        // This is a placeholder for future implementation
        progress = 0.95
    }

    nonisolated private func getResultImage() -> UIImage? {
        guard let processedTexture = processedTexture else { return nil }

        let width = processedTexture.width
        let height = processedTexture.height

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let dataSize = bytesPerRow * height

        var pixelBytes = [UInt8](repeating: 0, count: dataSize)

        processedTexture.getBytes(&pixelBytes,
                                  bytesPerRow: bytesPerRow,
                                  from: MTLRegionMake2D(0, 0, width, height),
                                  mipmapLevel: 0)

        // Create CGImage from pixel data
        guard let provider = CGDataProvider(data: Data(pixelBytes) as CFData) else { return nil }

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    // MARK: - Real-time Preview

    func processPreview(preset: FilmPreset, adjustments: AdjustmentParams) -> CIImage? {
        // For real-time preview, we can use Core Image filters
        // This is faster than Metal for quick previews
        guard let sourceTexture = sourceTexture else { return nil }

        // Create CIImage from texture
        let ciImage = CIImage(mtlTexture: sourceTexture, options: nil)
        return ciImage
    }
}

// MARK: - Adjust Uniforms Structure (matching Metal adjust shader)

private struct AdjustUniforms {
    nonisolated init() {}

    // Order must match the Metal AdjustUniforms struct
    var exposure: Float = 0.0
    var contrast: Float = 1.0
    var saturation: Float = 1.0
    var highlights: Float = 0.0

    var shadows: Float = 0.0
    var whites: Float = 0.0
    var blacks: Float = 0.0
    var temperature: Float = 0.0

    var tint: Float = 0.0
    var clarity: Float = 0.0
    var sharpness: Float = 0.0
    var softGlow: Float = 0.0

    var vignette: Float = 0.0
    var grainIntensity: Float = 0.0
    var grainSoftness: Float = 0.5
    var grainSize: Float = 0.5

    var grainRoughness: Float = 0.5
    var grainColor: Float = 0.0
    var opacity: Float = 1.0
    var time: Float = 0.0

    var halation: Float = 0.0
    var bloom: Float = 0.0
    var fade: Float = 0.0
    var fadeWarmth: Float = 50.0

    var splitShadowHue: Float = 220.0
    var splitShadowSaturation: Float = 0.0
    var splitHighlightHue: Float = 40.0
    var splitHighlightSaturation: Float = 0.0

    var splitBalance: Float = 0.0
    var _pad0: Float = 0.0
    var _pad1: Float = 0.0
    var _pad2: Float = 0.0

    var hslHueA: SIMD4<Float> = SIMD4<Float>(repeating: 0.0)
    var hslHueB: SIMD4<Float> = SIMD4<Float>(repeating: 0.0)
    var hslSatA: SIMD4<Float> = SIMD4<Float>(repeating: 0.0)
    var hslSatB: SIMD4<Float> = SIMD4<Float>(repeating: 0.0)
    var hslLumA: SIMD4<Float> = SIMD4<Float>(repeating: 0.0)
    var hslLumB: SIMD4<Float> = SIMD4<Float>(repeating: 0.0)

    var useSoftGlow: Int32 = 0
    var useGrain: Int32 = 0
    var useVignette: Int32 = 0
    var _padI: Int32 = 0
}

private struct HalationUniforms {
    var threshold: Float = 0.85
    var strength: Float = 0.6
    var colorShiftR: Float = 1.8
    var colorShiftG: Float = 0.4
    var colorShiftB: Float = 0.1
    var sigma: Float = 20.0
    var _pad0: Float = 0.0
    var _pad1: Float = 0.0
}

// MARK: - Film Uniforms Structure (matching Metal shader)

// Maximum curve control points (matching Metal shader)
nonisolated private let MAX_CURVE_POINTS = 8

private struct FilmUniforms {
    nonisolated init() {}

    // Simplified layout - use inline SIMD2<Float> instead of struct wrapper
    // This avoids Swift's automatic padding for nested struct alignment

    var colorMatrix: float3x3 = float3x3(1.0)       // 48 bytes (0-48), alignment 16
    var whiteBalanceR: Float = 1.0                 // 4 bytes (48-52)
    var whiteBalanceG: Float = 1.0                 // 4 bytes (52-56)
    var whiteBalanceB: Float = 1.0                 // 4 bytes (56-60)
    var _pad1: Float = 0.0                         // 4 bytes (60-64) - align next to 16

    // Floats and Int32 (all 4-byte aligned)
    var exposure: Float = 0.0                      // 64
    var contrast: Float = 1.0                      // 68
    var saturation: Float = 1.0                    // 72
    var vignette: Float = 0.0                      // 76
    var softGlow: Float = 0.0                      // 80
    var fade: Float = 0.0                          // 84
    var grainIntensity: Float = 0.0                // 88
    var grainSoftness: Float = 0.5                 // 92
    var grainFineSoftness: Float = 0.22            // 96
    var grainFineWeight: Float = 0.45              // 100
    var grainCoarseWeight: Float = 0.2             // 104
    var highlightReduction: Float = 0.5            // 108
    var grainColorVariance: Float = 0.0            // 112
    var grainMode: Int32 = 0                       // 116
    var _padGrain0: Float = 0.0                    // 120
    var _padGrain1: Float = 0.0                    // 124
    var bloomSigma: Float = 0.0                    // 128
    var bloomStrength: Float = 0.0                 // 132
    var opacity: Float = 1.0                       // 136
    var highlights: Float = 0.0                    // 140
    var shadows: Float = 0.0                       // 144
    var isMonochrome: Int32 = 0                    // 148
    var time: Float = 0.0                          // 152
    // === ADJUST 参数：温度/色调/清晰度 ===
    var temperature: Float = 0.0                   // 156 - 色温 (-50 to 50)
    var tint: Float = 0.0                          // 160 - 色调 (-50 to 50)
    var clarity: Float = 0.0                       // 164 - 清晰度 (-50 to 50)
    // Padding to maintain alignment
    var _padAdjust: Float = 0.0                    // 168
    var _pad2a: Float = 0.0                        // 172

    // Master curve - curvePoints[8] needs 8-byte alignment, start at 160
    // 176 is divisible by 8
    var useCurve: Int32 = 0                        // 176-180
    var curveCount: Int32 = 0                      // 180-184
    var _padCurve0: Float = 0.0                    // 184-188
    var _padCurve1: Float = 0.0                    // 188-192
    // Need 176 to be divisible by 8 for SIMD2<Float>... 176/8=22 ✓
    var curvePoint0: SIMD2<Float> = SIMD2<Float>(0, 0)  // 192-200
    var curvePoint1: SIMD2<Float> = SIMD2<Float>(0, 0)  // 200-208
    var curvePoint2: SIMD2<Float> = SIMD2<Float>(0, 0)  // 208-216
    var curvePoint3: SIMD2<Float> = SIMD2<Float>(0, 0)  // 216-224
    var curvePoint4: SIMD2<Float> = SIMD2<Float>(0, 0)  // 224-232
    var curvePoint5: SIMD2<Float> = SIMD2<Float>(0, 0)  // 232-240
    var curvePoint6: SIMD2<Float> = SIMD2<Float>(0, 0)  // 240-248
    var curvePoint7: SIMD2<Float> = SIMD2<Float>(0, 0)  // 248-256

    // Red curve - starts at 240, 240/8=30 ✓
    var useCurveR: Int32 = 0                       // 240-244
    var curveRCount: Int32 = 0                     // 244-248
    var _padCurveR0: Float = 0.0                   // 248-252
    var _padCurveR1: Float = 0.0                   // 252-256
    // 256/8=32 ✓
    var curveRPoint0: SIMD2<Float> = SIMD2<Float>(0, 0)  // 256-264
    var curveRPoint1: SIMD2<Float> = SIMD2<Float>(0, 0)  // 264-272
    var curveRPoint2: SIMD2<Float> = SIMD2<Float>(0, 0)  // 272-280
    var curveRPoint3: SIMD2<Float> = SIMD2<Float>(0, 0)  // 280-288
    var curveRPoint4: SIMD2<Float> = SIMD2<Float>(0, 0)  // 288-296
    var curveRPoint5: SIMD2<Float> = SIMD2<Float>(0, 0)  // 296-304
    var curveRPoint6: SIMD2<Float> = SIMD2<Float>(0, 0)  // 304-312
    var curveRPoint7: SIMD2<Float> = SIMD2<Float>(0, 0)  // 312-320

    // Green curve - starts at 320, 320/8=40 ✓
    var useCurveG: Int32 = 0                       // 320-324
    var curveGCount: Int32 = 0                     // 324-328
    var _padCurveG0: Float = 0.0                   // 328-332
    var _padCurveG1: Float = 0.0                   // 332-336
    // 336/8=42 ✓
    var curveGPoint0: SIMD2<Float> = SIMD2<Float>(0, 0)  // 336-344
    var curveGPoint1: SIMD2<Float> = SIMD2<Float>(0, 0)  // 344-352
    var curveGPoint2: SIMD2<Float> = SIMD2<Float>(0, 0)  // 352-360
    var curveGPoint3: SIMD2<Float> = SIMD2<Float>(0, 0)  // 360-368
    var curveGPoint4: SIMD2<Float> = SIMD2<Float>(0, 0)  // 368-376
    var curveGPoint5: SIMD2<Float> = SIMD2<Float>(0, 0)  // 376-384
    var curveGPoint6: SIMD2<Float> = SIMD2<Float>(0, 0)  // 384-392
    var curveGPoint7: SIMD2<Float> = SIMD2<Float>(0, 0)  // 392-400

    // Blue curve - starts at 400, 400/8=50 ✓
    var useCurveB: Int32 = 0                       // 400-404
    var curveBCount: Int32 = 0                     // 404-408
    var _padCurveB0: Float = 0.0                   // 408-412
    var _padCurveB1: Float = 0.0                   // 412-416
    // 416/8=52 ✓
    var curveBPoint0: SIMD2<Float> = SIMD2<Float>(0, 0)  // 416-424
    var curveBPoint1: SIMD2<Float> = SIMD2<Float>(0, 0)  // 424-432
    var curveBPoint2: SIMD2<Float> = SIMD2<Float>(0, 0)  // 432-440
    var curveBPoint3: SIMD2<Float> = SIMD2<Float>(0, 0)  // 440-448
    var curveBPoint4: SIMD2<Float> = SIMD2<Float>(0, 0)  // 448-456
    var curveBPoint5: SIMD2<Float> = SIMD2<Float>(0, 0)  // 456-464
    var curveBPoint6: SIMD2<Float> = SIMD2<Float>(0, 0)  // 464-472
    var curveBPoint7: SIMD2<Float> = SIMD2<Float>(0, 0)  // 472-480
}

// MARK: - Comparable Clamping Extension

private extension Comparable {
    nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - UIImage Extension

extension UIImage {
    func toCIImage() -> CIImage? {
        guard let cgImage = cgImage else { return nil }
        return CIImage(cgImage: cgImage)
    }
}
