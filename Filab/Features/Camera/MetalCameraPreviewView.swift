import AVFoundation
import Metal
import MetalKit
import simd
import SwiftUI
import UIKit

// MARK: - Metal Camera Preview

struct MetalCameraPreviewView: UIViewRepresentable {
    let frameSource: CameraPreviewFrameSource
    let preset: FilmPreset?
    let rawPreviewExposureBiasEV: Float
    let isMirrored: Bool
    let onTapToFocus: (CGPoint, CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MetalCameraPreviewContainerView {
        let renderer = MetalCameraPreviewRenderer(frameSource: frameSource)
        context.coordinator.renderer = renderer

        let view = MetalCameraPreviewContainerView(frameSource: frameSource)
        view.onTapToFocus = onTapToFocus
        view.isMirrored = isMirrored
        view.configure(renderer: renderer)
        renderer.update(
            preset: preset,
            rawPreviewExposureBiasEV: rawPreviewExposureBiasEV,
            isMirrored: isMirrored
        )
        return view
    }

    func updateUIView(_ uiView: MetalCameraPreviewContainerView, context: Context) {
        uiView.frameSource = frameSource
        uiView.onTapToFocus = onTapToFocus
        uiView.isMirrored = isMirrored
        context.coordinator.renderer?.frameSource = frameSource
        context.coordinator.renderer?.update(
            preset: preset,
            rawPreviewExposureBiasEV: rawPreviewExposureBiasEV,
            isMirrored: isMirrored
        )
    }

    final class Coordinator {
        var renderer: MetalCameraPreviewRenderer?
    }
}

final class MetalCameraPreviewContainerView: UIView {
    var frameSource: CameraPreviewFrameSource
    var onTapToFocus: ((CGPoint, CGPoint) -> Void)?
    var isMirrored = false

    private let metalView: MTKView
    private var renderer: MetalCameraPreviewRenderer?

    init(frameSource: CameraPreviewFrameSource) {
        self.frameSource = frameSource
        metalView = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        super.init(frame: .zero)
        configureView()
    }

    required init?(coder: NSCoder) {
        frameSource = CameraPreviewFrameSource()
        metalView = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        super.init(coder: coder)
        configureView()
    }

    func configure(renderer: MetalCameraPreviewRenderer) {
        self.renderer = renderer
        metalView.delegate = renderer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalView.frame = bounds
    }

    private func configureView() {
        backgroundColor = .black
        isOpaque = true

        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.framebufferOnly = true
        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false
        metalView.preferredFramesPerSecond = 30
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        metalView.contentMode = .scaleAspectFill
        addSubview(metalView)

        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            metalView.topAnchor.constraint(equalTo: topAnchor),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(recognizer)

    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let viewPoint = recognizer.location(in: self)
        let devicePoint = captureDevicePoint(for: viewPoint)
        onTapToFocus?(devicePoint, viewPoint)
    }

    private func captureDevicePoint(for viewPoint: CGPoint) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        let frameSize = frameSource.latestFrameSize()
        var normalized = CGPoint(
            x: viewPoint.x / bounds.width,
            y: viewPoint.y / bounds.height
        )

        if frameSize.width > 0, frameSize.height > 0 {
            let imageAspect = frameSize.width / frameSize.height
            let viewAspect = bounds.width / bounds.height

            if viewAspect > imageAspect {
                let scale = viewAspect / imageAspect
                normalized.y = (normalized.y - 0.5) * scale + 0.5
            } else {
                let scale = imageAspect / viewAspect
                normalized.x = (normalized.x - 0.5) * scale + 0.5
            }
        }

        if isMirrored {
            normalized.x = 1 - normalized.x
        }

        return CGPoint(
            x: min(max(normalized.x, 0), 1),
            y: min(max(normalized.y, 0), 1)
        )
    }

}

final class MetalCameraPreviewRenderer: NSObject, MTKViewDelegate {
    nonisolated(unsafe) var frameSource: CameraPreviewFrameSource

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    nonisolated(unsafe) private var textureCache: CVMetalTextureCache?
    nonisolated(unsafe) private var pipelineState: MTLRenderPipelineState?
    nonisolated(unsafe) private var samplerState: MTLSamplerState?
    nonisolated(unsafe) private var uniforms = CameraPreviewUniforms()
    nonisolated(unsafe) private var curveTexture: MTLTexture?
    nonisolated(unsafe) private var lastPreset: FilmPreset?

    private let stateLock = NSLock()

    init(frameSource: CameraPreviewFrameSource) {
        self.frameSource = frameSource
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
        super.init()
        setupMetal()
    }

    func update(preset: FilmPreset?, rawPreviewExposureBiasEV: Float, isMirrored: Bool) {
        guard let device else { return }

        let previewUniforms = CameraPreviewUniforms(
            preset: preset,
            rawPreviewExposureBiasEV: rawPreviewExposureBiasEV,
            isMirrored: isMirrored
        )
        let updatedCurveTexture: MTLTexture?
        if lastPreset != preset || curveTexture == nil {
            updatedCurveTexture = Self.makeCurveTexture(for: preset, device: device)
        } else {
            updatedCurveTexture = nil
        }

        stateLock.lock()
        uniforms = previewUniforms
        if let updatedCurveTexture {
            curveTexture = updatedCurveTexture
            lastPreset = preset
        }
        stateLock.unlock()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let device,
              let commandQueue,
              let pipelineState,
              let samplerState,
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let frame = frameSource.latestFrame(),
              let textures = makeTextures(from: frame.pixelBuffer),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        stateLock.lock()
        var currentUniforms = uniforms
        let currentCurveTexture = curveTexture
        stateLock.unlock()

        let frameWidth = Float(CVPixelBufferGetWidthOfPlane(frame.pixelBuffer, 0))
        let frameHeight = Float(CVPixelBufferGetHeightOfPlane(frame.pixelBuffer, 0))
        currentUniforms.aspect.x = max(Float(view.drawableSize.width / max(view.drawableSize.height, 1)), 0.001)
        currentUniforms.aspect.y = max(frameWidth / max(frameHeight, 1), 0.001)

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentTexture(textures.luma, index: 0)
        renderEncoder.setFragmentTexture(textures.chroma, index: 1)
        renderEncoder.setFragmentTexture(currentCurveTexture, index: 2)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        renderEncoder.setFragmentBytes(
            &currentUniforms,
            length: MemoryLayout<CameraPreviewUniforms>.stride,
            index: 0
        )
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()

        commandBuffer.addCompletedHandler { _ in
            _ = textures
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        _ = device
    }

    private func setupMetal() {
        guard let device else { return }

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        textureCache = cache

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)

        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "cameraPreviewVertex"),
              let fragmentFunction = library.makeFunction(name: "cameraPreviewFragment") else {
            return
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    nonisolated private func makeTextures(from pixelBuffer: CVPixelBuffer) -> CameraPreviewTextures? {
        guard let textureCache else { return nil }

        let lumaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let lumaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let chromaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let chromaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)

        var lumaTextureRef: CVMetalTexture?
        var chromaTextureRef: CVMetalTexture?

        let lumaStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .r8Unorm,
            lumaWidth,
            lumaHeight,
            0,
            &lumaTextureRef
        )

        let chromaStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .rg8Unorm,
            chromaWidth,
            chromaHeight,
            1,
            &chromaTextureRef
        )

        guard lumaStatus == kCVReturnSuccess,
              chromaStatus == kCVReturnSuccess,
              let lumaTextureRef,
              let chromaTextureRef,
              let lumaTexture = CVMetalTextureGetTexture(lumaTextureRef),
              let chromaTexture = CVMetalTextureGetTexture(chromaTextureRef) else {
            return nil
        }

        return CameraPreviewTextures(
            lumaRef: lumaTextureRef,
            chromaRef: chromaTextureRef,
            luma: lumaTexture,
            chroma: chromaTexture
        )
    }

    private static func makeCurveTexture(for preset: FilmPreset?, device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: 256,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = .shaderRead

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        var lut = [UInt8](repeating: 0, count: 256)
        for index in 0..<256 {
            let value = preset.map {
                applyCurve(Float(index), points: $0.curve.points)
            } ?? Float(index)
            lut[index] = UInt8(min(max(value.rounded(), 0), 255))
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, 256, 1),
            mipmapLevel: 0,
            withBytes: lut,
            bytesPerRow: 256
        )
        return texture
    }

    private static func applyCurve(_ x: Float, points: [[Double]]) -> Float {
        guard points.count >= 2 else { return x }

        let curvePoints = Array(points.prefix(8)).map {
            SIMD2<Float>(Float($0[0]), Float($0[1]))
        }

        guard let first = curvePoints.first,
              let last = curvePoints.last else {
            return x
        }

        if x <= first.x { return first.y }
        if x >= last.x { return last.y }

        for index in 0..<(curvePoints.count - 1) {
            let left = curvePoints[index]
            let right = curvePoints[index + 1]
            if x >= left.x && x <= right.x {
                let t = (x - left.x) / max(1, right.x - left.x)
                return left.y + (right.y - left.y) * t
            }
        }

        return x
    }
}

private struct CameraPreviewTextures {
    let lumaRef: CVMetalTexture
    let chromaRef: CVMetalTexture
    let luma: MTLTexture
    let chroma: MTLTexture
}

private struct CameraPreviewUniforms {
    var wbContrast = SIMD4<Float>(1, 1, 1, 1)
    var matrixC0Saturation = SIMD4<Float>(1, 0, 0, 1)
    var matrixC1Fade = SIMD4<Float>(0, 1, 0, 0)
    var matrixC2Flags = SIMD4<Float>(0, 0, 1, 0)
    var aspect = SIMD4<Float>(1, 1, 1, 0)

    init() {}

    init(preset: FilmPreset?, rawPreviewExposureBiasEV: Float, isMirrored: Bool) {
        if let preset {
            let wb = preset.previewWBVector
            let matrix = preset.previewColorMatrix
            let c0 = matrix.columns.0
            let c1 = matrix.columns.1
            let c2 = matrix.columns.2

            wbContrast = SIMD4<Float>(wb.x, wb.y, wb.z, Float(preset.contrast))
            matrixC0Saturation = SIMD4<Float>(c0.x, c0.y, c0.z, Float(preset.saturation))
            matrixC1Fade = SIMD4<Float>(c1.x, c1.y, c1.z, Float(preset.fade))
            matrixC2Flags = SIMD4<Float>(c2.x, c2.y, c2.z, isMirrored ? 1 : 0)
            aspect.z = 1
        } else {
            let rawPreviewGain = powf(2, rawPreviewExposureBiasEV)
            wbContrast = SIMD4<Float>(1, 1, 1, 1)
            matrixC0Saturation = SIMD4<Float>(1, 0, 0, 1)
            matrixC1Fade = SIMD4<Float>(0, 1, 0, 0)
            matrixC2Flags = SIMD4<Float>(0, 0, 1, isMirrored ? 1 : 0)
            aspect.z = max(rawPreviewGain, 0.01)
        }
    }
}
