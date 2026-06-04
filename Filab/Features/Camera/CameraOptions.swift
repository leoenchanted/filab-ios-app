import simd
import SwiftUI

enum CameraAspectRatio: String, CaseIterable, Identifiable {
    case full
    case threeFour
    case oneOne
    case sixteenNine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "FULL"
        case .threeFour: return "3:4"
        case .oneOne: return "1:1"
        case .sixteenNine: return "16:9"
        }
    }

    var frameRatio: CGFloat? {
        switch self {
        case .full:
            return nil
        case .threeFour:
            return 3.0 / 4.0
        case .oneOne:
            return 1.0
        case .sixteenNine:
            return 9.0 / 16.0
        }
    }
}

enum CameraCaptureFormat: String, CaseIterable, Identifiable {
    case jpeg
    case heif
    case proRaw
    case bayerRaw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jpeg: return "JPG"
        case .heif: return "HEIF"
        case .proRaw: return "ProRAW"
        case .bayerRaw: return "Bayer"
        }
    }

    var badgeTitle: String {
        switch self {
        case .jpeg: return "JPG 10-bit"
        case .heif: return "HEIF 10-bit"
        case .proRaw: return "ProRAW DNG"
        case .bayerRaw: return "Bayer DNG"
        }
    }

    var detail: String {
        switch self {
        case .jpeg:
            return "兼容"
        case .heif:
            return "高质量"
        case .proRaw:
            return "多帧融合 RAW"
        case .bayerRaw:
            return "传感器 RAW"
        }
    }

    var isRaw: Bool {
        switch self {
        case .proRaw, .bayerRaw:
            return true
        case .jpeg, .heif:
            return false
        }
    }

    var rawUnavailableMessage: String {
        switch self {
        case .proRaw:
            return "当前设备不支持 Apple ProRAW"
        case .bayerRaw:
            return "当前设备不支持 Bayer RAW"
        case .jpeg, .heif:
            return ""
        }
    }
}

enum CameraControlPanel: String, CaseIterable, Identifiable {
    case iso
    case shutter
    case exposure
    case whiteBalance
    case film

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iso: return "ISO"
        case .shutter: return "快门"
        case .exposure: return "EV"
        case .whiteBalance: return "WB"
        case .film: return "FILM"
        }
    }

    var icon: String {
        switch self {
        case .iso: return "camera.aperture"
        case .shutter: return "timer"
        case .exposure: return "plusminus.circle"
        case .whiteBalance: return "thermometer.medium"
        case .film: return "film"
        }
    }
}

extension FilmPreset {
    // 饱和度：直接使用预设值，让黑白(sat=0)正确去色，高饱和(如Velvia 1.38)更明显
    var cameraPreviewSaturation: Double {
        max(0, min(2.0, saturation))
    }

    // 对比度：基于 Metal applySCurve 与 SwiftUI .contrast() 的 gamma/色彩空间差异进行映射
    // Metal 在线性空间以 0.18 为中心操作，SwiftUI 在 sRGB 空间以 0.5 为中心操作
    // 0.18 线性 ≈ 0.487 sRGB，中心点差异很小，主要差异来自 gamma 压缩
    // 高对比度时 SwiftUI 需要更大的值来匹配暗部压缩；低对比度时稍小的值更匹配
    var cameraPreviewContrast: Double {
        if contrast >= 1.0 {
            // 高对比度：SwiftUI 需要比 Metal 更大的 contrast 来补偿 gamma 压缩
            // 映射：c_s = 1.0 + (c_m - 1.0) * 1.35
            // Velvia (1.15) → 1.20, Ektar (1.22) → 1.30, Lomo (1.20) → 1.27
            return min(2.0, 1.0 + (contrast - 1.0) * 1.35)
        } else {
            // 低对比度：SwiftUI 需要比 Metal 稍小的 contrast
            // 映射：c_s = 1.0 - (1.0 - c_m) * 0.5
            // Portra (0.96) → 0.98, Astia (0.88) → 0.94
            return max(0.5, 1.0 - (1.0 - contrast) * 0.5)
        }
    }

    // 亮度调整：基于主曲线中点偏移 + 对比度补偿
    // SwiftUI .contrast() 会让中间调偏移，需要补偿
    var cameraPreviewBrightness: Double {
        let midPoint = curve.points.count > 2 ? curve.points[2][1] / 255.0 : 0.5
        let curveBrightness = (midPoint - 0.5) * 0.18
        
        // 对比度补偿：contrast > 1 时中间调变暗，需要提亮；contrast < 1 时中间调变亮，需要压暗
        let previewContrast = cameraPreviewContrast
        let contrastCompensation = (previewContrast - 1.0) * 0.012
        
        return max(-0.08, min(0.08, curveBrightness + contrastCompensation))
    }

    // 色彩矩阵色：基于色彩矩阵对角线和非对角线计算色彩偏移
    var cameraPreviewColorMatrixColor: Color {
        let values = colorMatrix.values
        // 红色通道偏移 = (R_out_R - 1) + R_out_G + R_out_B
        let rShift = (values[0] - 1.0) + values[1] + values[2]
        // 绿色通道偏移
        let gShift = values[3] + (values[4] - 1.0) + values[5]
        // 蓝色通道偏移
        let bShift = values[6] + values[7] + (values[8] - 1.0)

        return Color(
            red: min(1.0, max(0.0, 0.5 + rShift * 0.25)),
            green: min(1.0, max(0.0, 0.5 + gShift * 0.25)),
            blue: min(1.0, max(0.0, 0.5 + bShift * 0.25))
        )
    }

    // 叠加颜色：基于实际白平衡RGB + 色彩矩阵 + 分类色调
    var cameraPreviewOverlayColors: [Color] {
        let wb = whiteBalance.toRGB()
        let wbR = Double(wb.x)
        let wbG = Double(wb.y)
        let wbB = Double(wb.z)

        // 白平衡色（直接使用RGB乘数映射）
        let wbColor = Color(
            red: min(1.0, max(0.0, wbR)),
            green: min(1.0, max(0.0, wbG)),
            blue: min(1.0, max(0.0, wbB))
        )

        // 色彩矩阵色
        let matrixColor = cameraPreviewColorMatrixColor

        // 分类色调色（用于增强胶片分类特征）
        let categoryColor = category.accentColor

        return [wbColor, matrixColor, categoryColor]
    }

    // 叠加不透明度：综合白平衡、色彩矩阵、褪色、对比度影响
    var cameraPreviewOverlayOpacity: Double {
        let whiteBalanceWeight = abs(whiteBalance.temperature) * 0.12 + abs(whiteBalance.tint) * 0.08
        let matrixWeight = 0.06  // 色彩矩阵基础权重
        let fadeWeight = fade * 0.24
        // 高对比度增加 softLight 强度来增强对比度感
        let contrastBoost = max(0, (contrast - 1.0) * 0.25)
        return max(0.08, min(0.45, 0.1 + whiteBalanceWeight + matrixWeight + fadeWeight + contrastBoost))
    }

    var cameraPreviewVignetteOpacity: Double {
        max(0.08, min(0.28, 0.08 + vignette * 1.25))
    }

    // ===== .colorEffect Shader 参数 (iOS 17+) =====
    // 通过 SwiftUI Metal Shader 直接在预览层应用影调逻辑
    // 与 FilmShaders.metal 的数学公式完全同源，无需任何参数映射转换

    /// 白平衡 RGB 乘数向量 (与 FilmShaders Step 2 一致)
    var previewWBVector: SIMD3<Float> {
        whiteBalance.toRGB()
    }

    /// 色彩矩阵 (与 FilmShaders Step 3 一致)
    var previewColorMatrix: float3x3 {
        colorMatrix.toSIMD()
    }

    /// 主曲线 5 个 SIMD2<Float> 点 + 点数
    /// Velvia 6 点取前 5；4 点的 Polaroid/Lomo 用末点填充
    /// 与 FilmShaders Step 5 applyToneCurve 同源
    var previewCurveArgs: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, Float) {
        let raw = curve.points.map { SIMD2<Float>(Float($0[0]), Float($0[1])) }
        let padded: [SIMD2<Float>]
        if raw.count >= 5 {
            // Velvia: 截断第 6 点 [255, 255]（对曲线形状无影响）
            padded = Array(raw.prefix(5))
        } else {
            // Polaroid/Lomo: 4 点，用末点填充第 5 位
            let last = raw.last ?? SIMD2<Float>(255, 255)
            padded = raw + Array(repeating: last, count: 5 - raw.count)
        }
        return (padded[0], padded[1], padded[2], padded[3], padded[4], Float(min(raw.count, 5)))
    }

    var cameraShortName: String {
        if name.count <= 12 {
            return name
        }

        return String(name.prefix(11)) + "..."
    }
}
