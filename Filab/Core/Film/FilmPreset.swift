import Foundation
import SwiftUI
import simd

// MARK: - Film Preset Models

struct FilmPreset: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let description: String
    let category: FilmCategory
    let thumbnail: String

    // Display info
    let scene: String       // 适用场景
    let feature: String     // 主要特色
    let detail: String      // 详细介绍

    // Base adjustments
    let whiteBalance: WhiteBalance
    let colorMatrix: ColorMatrix
    let curve: ToneCurve           // Master curve (affects all RGB)
    let curveR: ToneCurve?         // Red channel curve (optional)
    let curveG: ToneCurve?         // Green channel curve (optional)
    let curveB: ToneCurve?         // Blue channel curve (optional)
    let saturation: Double
    let contrast: Double

    // Halation (bloom) effect - especially for CineStill
    let halation: HalationConfig?

    // Bloom effect - for Fuji, Polaroid, etc.
    let bloom: BloomConfig?

    // Grain configuration
    let grain: GrainConfig

    // Additional effects
    let vignette: Double  // 0-1, amount of vignette
    let fade: Double      // 0-1, fade amount (film base fog)

    var icon: String {
        "film_icon" // 统一使用胶片图标
    }

    var color: Color {
        switch category {
            case .kodak: return .orange
            case .fuji: return .green
            case .fujiDigital: return .mint
            case .panasonic: return .blue
            case .hasselblad: return .purple
            case .ricoh: return .cyan
            case .cinestill: return .red
            case .blackWhite: return .gray
            case .vintage: return .brown
        }
    }
}

enum FilmCategory: String, Codable, CaseIterable, Sendable {
    case kodak = "Kodak"
    case fuji = "Fuji"
    case fujiDigital = "Fuji X"      // 新增：富士数字机型模拟
    case panasonic = "Panasonic"
    case hasselblad = "Hasselblad"
    case ricoh = "Ricoh"
    case cinestill = "CineStill"
    case blackWhite = "B&W"
    case vintage = "Vintage"

    var displayName: String { rawValue }
}

// MARK: - White Balance

struct WhiteBalance: Codable, Equatable, Sendable {
    var temperature: Double  // -1 to 1, where -1 is cooler (blue), 1 is warmer (orange)
    var tint: Double         // -1 to 1, where -1 is greener, 1 is more magenta

    static let neutral = WhiteBalance(temperature: 0, tint: 0)

    // Convert to RGB multipliers for shader
    nonisolated func toRGB() -> SIMD3<Float> {
        let temp = Float(temperature)
        let tintValue = Float(tint)
        
        // Temperature: multiplicative model for natural response.
        // Warming boosts red / reduces blue; cooling does the opposite.
        // Slight green compensation preserves luminance neutrality.
        var r = 1.0 + temp * 0.25
        var g = 1.0 - temp * 0.02
        var b = 1.0 - temp * 0.30
        
        // Tint: multiplicative for consistent scaling across values.
        if tintValue > 0.0 {
            // Magenta: boost R/B, reduce G
            r *= 1.0 + tintValue * 0.15
            g *= 1.0 - tintValue * 0.10
            b *= 1.0 + tintValue * 0.15
        } else if tintValue < 0.0 {
            // Green: boost G, reduce R/B
            r *= 1.0 + tintValue * 0.10
            g *= 1.0 - tintValue * 0.15
            b *= 1.0 + tintValue * 0.10
        }
        
        return SIMD3<Float>(max(0.1, r), max(0.1, g), max(0.1, b))
    }
}

// MARK: - Color Matrix (3x3)

struct ColorMatrix: Codable, Equatable, Sendable {
    // Row-major 3x3 matrix: [r1, g1, b1, r2, g2, b2, r3, g3, b3]
    // Where row 1 affects red output, row 2 affects green, row 3 affects blue
    var values: [Double]

    static let identity = ColorMatrix(values: [
        1.0, 0.0, 0.0,  // Red output from R, G, B
        0.0, 1.0, 0.0,  // Green output from R, G, B
        0.0, 0.0, 1.0   // Blue output from R, G, B
    ])

    // Portra 400: warm skin tones, gentle saturation roll-off, slight shadow lift
    static let portra400 = ColorMatrix(values: [
        1.02,  0.05, -0.03,   // Boost red, protect skin warmth
        0.01,  0.98,  0.01,   // Subtle green shift for natural look
        0.03,  0.04,  0.93    // Cool shadows slightly via reduced blue diagonal
    ])

    // Fuji Pro 400H: airy highlights, subtle cyan-green shadows, low contrast
    static let fuji400H = ColorMatrix(values: [
        0.96,  0.05,  -0.01,  // Slight red reduction for airy feel
        0.02,  0.96,   0.02,  // Green channel borrows from red/blue
        0.02,  0.10,   0.88   // Strong shadow cyan via green->blue bleed
    ])

    // CineStill 800T: tungsten stock, deep shadows, cyan lift, reduced blue
    static let cineStill800T = ColorMatrix(values: [
        0.96,  0.03,   0.01,
        0.02,  0.93,   0.05,
        0.04,  0.14,   0.82   // Pronounced blue reduction for tungsten look
    ])

    // Kodak Gold 200: rich warm cast, yellow-orange shadows, nostalgic
    static let gold200 = ColorMatrix(values: [
        1.05,  0.04,  -0.04,  // Warm red boost
        0.03,  0.97,   0.00,  // Slightly subdued greens
        0.01,  0.05,   0.92   // Reduced blue for golden warmth
    ])

    // Polaroid: warm amber tones, lifted blacks, slightly desaturated
    static let polaroid = ColorMatrix(values: [
        1.04,  0.06,  -0.02,
        0.01,  0.96,   0.03,
        0.02,  0.10,   0.87
    ])

    nonisolated func toSIMD() -> float3x3 {
        // simd matrices are column-major. Preset values are stored row-major so
        // transpose here to keep Metal output aligned with the Core Image path.
        return float3x3(
            SIMD3<Float>(Float(values[0]), Float(values[3]), Float(values[6])),
            SIMD3<Float>(Float(values[1]), Float(values[4]), Float(values[7])),
            SIMD3<Float>(Float(values[2]), Float(values[5]), Float(values[8]))
        )
    }
}

// MARK: - Tone Curve

struct ToneCurve: Codable, Equatable, Sendable {
    var points: [[Double]]

    // ==================== 优化版曲线（全部基于你的 shader 线性插值特性） ====================

    static let linear = ToneCurve(points: [
        [0, 0], [64, 64], [128, 128], [192, 192], [255, 255]
    ])

    static let portra = ToneCurve(points: [      // Portra 400 优化
        [0, 8], [48, 55], [128, 132], [210, 225], [255, 242]
    ])

    static let ektar = ToneCurve(points: [       // Ektar 100 新增
        [0, 0], [45, 32], [120, 125], [190, 235], [255, 255]
    ])

    static let fuji = ToneCurve(points: [        // Pro 400H 优化（亮部更通透）
        [0, 5], [55, 52], [128, 138], [205, 235], [255, 248]
    ])

    static let fujiR = ToneCurve(points: [       // Fuji Red 优化
        [0, 0], [128, 122], [255, 235]
    ])
    static let fujiB = ToneCurve(points: [       // Fuji Blue 优化（Pro 400H 阴影冷调）
        [0, 28], [128, 132], [255, 245]
    ])

    static let classicChrome = ToneCurve(points: [ // Classic Chrome 优化
        [0, 0], [45, 28], [128, 118], [200, 210], [255, 232]
    ])

    static let cineStill = ToneCurve(points: [
        [0, 0], [52, 38], [135, 148], [205, 228], [255, 245]
    ])

    static let astia = ToneCurve(points: [       // Astia 100F 新增
        [0, 6], [64, 72], [128, 132], [192, 188], [255, 242]
    ])

    static let ilford = ToneCurve(points: [
        [0, 0], [50, 42], [128, 136], [195, 228], [255, 255]
    ])

    static let polaroid = ToneCurve(points: [
        [0, 38], [55, 72], [128, 140], [255, 232]
    ])
    static let polaroidB = ToneCurve(points: [
        [0, 0], [255, 215]
    ])

    static let ricoh = ToneCurve(points: [       // Ricoh GR Positive 优化
        [0, 0], [40, 18], [128, 148], [200, 245], [255, 255]
    ])

    static let hasselblad = ToneCurve(points: [  // Hasselblad Natural 新增
        [0, 5], [64, 68], [128, 135], [200, 208], [255, 250]
    ])

    static let velvia = ToneCurve(points: [      // Velvia 50 高对比 S 曲线
        [0, 0], [40, 22], [100, 90], [160, 175], [220, 240], [255, 255]
    ])

    static let lomo = ToneCurve(points: [         // Lomography 独立曲线
        [0, 12], [55, 55], [128, 145], [255, 232]
    ])
}

// MARK: - Category Accent Color
extension FilmCategory {
    var accentColor: Color {
        switch self {
        case .kodak:        return .orange
        case .fuji:         return .green
        case .fujiDigital:  return .mint
        case .panasonic:    return .blue
        case .hasselblad:   return .purple
        case .ricoh:        return .teal
        case .cinestill:    return .red
        case .blackWhite:   return .gray
        case .vintage:      return .brown
        }
    }
}


// MARK: - Halation Effect

struct HalationConfig: Codable, Equatable {
    var threshold: Double      // 0-1, brightness threshold for halation
    var strength: Double       // 0-1, intensity of the effect
    var colorShift: [Double]   // RGB shift for halation color [r, g, b]
    var sigmaSmall: Double     // Small blur radius
    var sigmaLarge: Double     // Large blur radius for diffusion

    // Default for CineStill red halation (from webgl.js)
    static let cineStill = HalationConfig(
        threshold: 0.85,
        strength: 0.6,
        colorShift: [1.8, 0.4, 0.1],  // Orange-red
        sigmaSmall: 8.0,
        sigmaLarge: 20.0
    )

    // Subtle halation for other films
    static let subtle = HalationConfig(
        threshold: 0.90,
        strength: 0.3,
        colorShift: [1.2, 0.9, 0.7],  // Warm
        sigmaSmall: 4.0,
        sigmaLarge: 12.0
    )
}

// MARK: - Bloom Effect

struct BloomConfig: Codable, Equatable {
    var sigma: Double          // Blur radius for bloom
    var strength: Double       // 0-1, bloom intensity

    // Fuji bloom (from webgl.js)
    static let fuji = BloomConfig(sigma: 13.0, strength: 0.25)

    // Polaroid bloom (from webgl.js) - large soft bloom
    static let polaroid = BloomConfig(sigma: 28.0, strength: 0.55)

    // Subtle bloom
    static let subtle = BloomConfig(sigma: 8.0, strength: 0.15)
}

// MARK: - Grain Configuration (updated to match webgl.js)

struct GrainConfig: Codable, Equatable {
    var intensity: Double      // 0-1, overall grain strength
    var softness: Double       // 0-1, grain blur/softness (coarse grain)
    var fineSoftness: Double   // 0-1, fine grain softness
    var fineWeight: Double     // 0-1, fine grain contribution
    var coarseWeight: Double   // 0-1, coarse grain contribution
    var highlightReduction: Double // 0-1, how much grain is reduced in highlights
    var colorVariance: Double  // 0-1, chromatic grain variance (for mode 2)
    var mode: GrainMode        // Grain type

    enum GrainMode: Int, Codable {
        case none = 0
        case spectral = 1      // Luminance grain (mode 1 in webgl.js)
        case chromatic = 2     // RGB grain (mode 2 in webgl.js)
    }

    // No grain
    static let none = GrainConfig(
        intensity: 0, softness: 0.5, fineSoftness: 0.22,
        fineWeight: 0.45, coarseWeight: 0.2, highlightReduction: 0.5,
        colorVariance: 0, mode: .none
    )

    // Kodak Portra grain (from webgl.js): mode=1, intensity=0.04, softness=1.0
    static let portra = GrainConfig(
        intensity: 0.04, softness: 1.0, fineSoftness: 0.24,
        fineWeight: 0.45, coarseWeight: 0.2, highlightReduction: 0.6,
        colorVariance: 0, mode: .spectral
    )

    // Fuji grain (from webgl.js): mode=1, intensity=0.06, softness=0.8
    static let fuji = GrainConfig(
        intensity: 0.06, softness: 0.8, fineSoftness: 0.22,
        fineWeight: 0.45, coarseWeight: 0.2, highlightReduction: 0.6,
        colorVariance: 0, mode: .spectral
    )

    // CineStill grain (from webgl.js): mode=2, intensity=0.08, colorVariance=0.3
    static let cineStill = GrainConfig(
        intensity: 0.08, softness: 0.5, fineSoftness: 0.22,
        fineWeight: 0.42, coarseWeight: 0.2, highlightReduction: 0.5,
        colorVariance: 0.3, mode: .chromatic
    )

    // Polaroid grain (from webgl.js): mode=2, intensity=0.10, colorVariance=0.35
    static let polaroid = GrainConfig(
        intensity: 0.10, softness: 0.5, fineSoftness: 0.26,
        fineWeight: 0.42, coarseWeight: 0.22, highlightReduction: 0.5,
        colorVariance: 0.35, mode: .chromatic
    )

    // Ilford grain (from webgl.js): mode=1, intensity=0.15, softness=0.45
    static let ilford = GrainConfig(
        intensity: 0.15, softness: 0.45, fineSoftness: 0.20,
        fineWeight: 0.5, coarseWeight: 0.25, highlightReduction: 0.5,
        colorVariance: 0, mode: .spectral
    )

    // Ricoh grain (from webgl.js): mode=1, intensity=0.12, softness=0.2
    static let ricoh = GrainConfig(
        intensity: 0.12, softness: 0.2, fineSoftness: 0.18,
        fineWeight: 0.45, coarseWeight: 0.22, highlightReduction: 0.5,
        colorVariance: 0, mode: .spectral
    )

    // Legacy presets for backward compatibility
    static let light = GrainConfig(
        intensity: 0.15, softness: 0.4, fineSoftness: 0.22,
        fineWeight: 0.45, coarseWeight: 0.2, highlightReduction: 0.6,
        colorVariance: 0, mode: .spectral
    )
    static let medium = GrainConfig(
        intensity: 0.3, softness: 0.5, fineSoftness: 0.22,
        fineWeight: 0.45, coarseWeight: 0.2, highlightReduction: 0.5,
        colorVariance: 0, mode: .spectral
    )
    static let heavy = GrainConfig(
        intensity: 0.5, softness: 0.6, fineSoftness: 0.22,
        fineWeight: 0.45, coarseWeight: 0.2, highlightReduction: 0.4,
        colorVariance: 0, mode: .spectral
    )
}

// MARK: - Adjustment Parameters

struct AdjustmentParams: Equatable, Codable, Sendable {
    var opacity: Double = 100       // 0-100, film effect strength
    var exposure: Double = 0        // -50 to 50
    var contrast: Double = 0        // -50 to 50
    var highlights: Double = 0      // -100 to 100, mapped to shader -1...1
    var shadows: Double = 0         // -100 to 100, mapped to shader -1...1
    var whites: Double = 0          // -100 to 100, mapped to shader -1...1
    var blacks: Double = 0          // -100 to 100, mapped to shader -1...1
    var temperature: Double = 0     // -50 to 50
    var tint: Double = 0            // -50 to 50
    var saturation: Double = 0      // -50 to 50
    var sharpness: Double = 0       // -50 to 50
    var grain: Double = 0           // 0-100, additional grain
    var grainSize: Double = 50      // 0-100
    var grainRoughness: Double = 50 // 0-100
    var grainColor: Double = 0      // 0-100
    var vignette: Double = 0        // -100 to 100, edge darken / brighten
    var clarity: Double = 0         // -50 to 50, soften / clarify
    var softGlow: Double = 0        // 0-100, soft glow intensity
    var halation: Double = 0        // 0-100
    var bloom: Double = 0           // 0-100
    var fade: Double = 0            // 0-100
    var fadeWarmth: Double = 50     // 0-100

    var splitShadowHue: Double = 220       // 0-360
    var splitShadowSaturation: Double = 0  // 0-100
    var splitHighlightHue: Double = 40     // 0-360
    var splitHighlightSaturation: Double = 0 // 0-100
    var splitBalance: Double = 0           // -50 to 50

    var hslRedHue: Double = 0
    var hslRedSaturation: Double = 0
    var hslRedLuminance: Double = 0
    var hslOrangeHue: Double = 0
    var hslOrangeSaturation: Double = 0
    var hslOrangeLuminance: Double = 0
    var hslYellowHue: Double = 0
    var hslYellowSaturation: Double = 0
    var hslYellowLuminance: Double = 0
    var hslGreenHue: Double = 0
    var hslGreenSaturation: Double = 0
    var hslGreenLuminance: Double = 0
    var hslCyanHue: Double = 0
    var hslCyanSaturation: Double = 0
    var hslCyanLuminance: Double = 0
    var hslBlueHue: Double = 0
    var hslBlueSaturation: Double = 0
    var hslBlueLuminance: Double = 0
    var hslPurpleHue: Double = 0
    var hslPurpleSaturation: Double = 0
    var hslPurpleLuminance: Double = 0
    var hslMagentaHue: Double = 0
    var hslMagentaSaturation: Double = 0
    var hslMagentaLuminance: Double = 0

    var isDefault: Bool {
        opacity == 100 &&
        exposure == 0 &&
        contrast == 0 &&
        highlights == 0 &&
        shadows == 0 &&
        whites == 0 &&
        blacks == 0 &&
        temperature == 0 &&
        tint == 0 &&
        saturation == 0 &&
        sharpness == 0 &&
        grain == 0 &&
        grainSize == 50 &&
        grainRoughness == 50 &&
        grainColor == 0 &&
        vignette == 0 &&
        clarity == 0 &&
        softGlow == 0 &&
        halation == 0 &&
        bloom == 0 &&
        fade == 0 &&
        fadeWarmth == 50 &&
        splitShadowHue == 220 &&
        splitShadowSaturation == 0 &&
        splitHighlightHue == 40 &&
        splitHighlightSaturation == 0 &&
        splitBalance == 0 &&
        hslRedHue == 0 && hslRedSaturation == 0 && hslRedLuminance == 0 &&
        hslOrangeHue == 0 && hslOrangeSaturation == 0 && hslOrangeLuminance == 0 &&
        hslYellowHue == 0 && hslYellowSaturation == 0 && hslYellowLuminance == 0 &&
        hslGreenHue == 0 && hslGreenSaturation == 0 && hslGreenLuminance == 0 &&
        hslCyanHue == 0 && hslCyanSaturation == 0 && hslCyanLuminance == 0 &&
        hslBlueHue == 0 && hslBlueSaturation == 0 && hslBlueLuminance == 0 &&
        hslPurpleHue == 0 && hslPurpleSaturation == 0 && hslPurpleLuminance == 0 &&
        hslMagentaHue == 0 && hslMagentaSaturation == 0 && hslMagentaLuminance == 0
    }

    enum CodingKeys: String, CodingKey {
        case opacity
        case exposure
        case contrast
        case highlights
        case shadows
        case whites
        case blacks
        case temperature
        case tint
        case saturation
        case sharpness
        case grain
        case grainSize
        case grainRoughness
        case grainColor
        case vignette
        case clarity
        case softGlow
        case halation
        case bloom
        case fade
        case fadeWarmth
        case splitShadowHue
        case splitShadowSaturation
        case splitHighlightHue
        case splitHighlightSaturation
        case splitBalance
        case hslRedHue, hslRedSaturation, hslRedLuminance
        case hslOrangeHue, hslOrangeSaturation, hslOrangeLuminance
        case hslYellowHue, hslYellowSaturation, hslYellowLuminance
        case hslGreenHue, hslGreenSaturation, hslGreenLuminance
        case hslCyanHue, hslCyanSaturation, hslCyanLuminance
        case hslBlueHue, hslBlueSaturation, hslBlueLuminance
        case hslPurpleHue, hslPurpleSaturation, hslPurpleLuminance
        case hslMagentaHue, hslMagentaSaturation, hslMagentaLuminance
    }

    init(
        opacity: Double = 100,
        exposure: Double = 0,
        contrast: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        whites: Double = 0,
        blacks: Double = 0,
        temperature: Double = 0,
        tint: Double = 0,
        saturation: Double = 0,
        sharpness: Double = 0,
        grain: Double = 0,
        grainSize: Double = 50,
        grainRoughness: Double = 50,
        grainColor: Double = 0,
        vignette: Double = 0,
        clarity: Double = 0,
        softGlow: Double = 0,
        halation: Double = 0,
        bloom: Double = 0,
        fade: Double = 0,
        fadeWarmth: Double = 50,
        splitShadowHue: Double = 220,
        splitShadowSaturation: Double = 0,
        splitHighlightHue: Double = 40,
        splitHighlightSaturation: Double = 0,
        splitBalance: Double = 0
    ) {
        self.opacity = opacity
        self.exposure = exposure
        self.contrast = contrast
        self.highlights = highlights
        self.shadows = shadows
        self.whites = whites
        self.blacks = blacks
        self.temperature = temperature
        self.tint = tint
        self.saturation = saturation
        self.sharpness = sharpness
        self.grain = grain
        self.grainSize = grainSize
        self.grainRoughness = grainRoughness
        self.grainColor = grainColor
        self.vignette = vignette
        self.clarity = clarity
        self.softGlow = softGlow
        self.halation = halation
        self.bloom = bloom
        self.fade = fade
        self.fadeWarmth = fadeWarmth
        self.splitShadowHue = splitShadowHue
        self.splitShadowSaturation = splitShadowSaturation
        self.splitHighlightHue = splitHighlightHue
        self.splitHighlightSaturation = splitHighlightSaturation
        self.splitBalance = splitBalance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 100
        exposure = try container.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        contrast = try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
        highlights = try container.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadows = try container.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        whites = try container.decodeIfPresent(Double.self, forKey: .whites) ?? 0
        blacks = try container.decodeIfPresent(Double.self, forKey: .blacks) ?? 0
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0
        tint = try container.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        sharpness = try container.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
        grain = try container.decodeIfPresent(Double.self, forKey: .grain) ?? 0
        grainSize = try container.decodeIfPresent(Double.self, forKey: .grainSize) ?? 50
        grainRoughness = try container.decodeIfPresent(Double.self, forKey: .grainRoughness) ?? 50
        grainColor = try container.decodeIfPresent(Double.self, forKey: .grainColor) ?? 0
        vignette = try container.decodeIfPresent(Double.self, forKey: .vignette) ?? 0
        clarity = try container.decodeIfPresent(Double.self, forKey: .clarity) ?? 0
        softGlow = try container.decodeIfPresent(Double.self, forKey: .softGlow) ?? 0
        halation = try container.decodeIfPresent(Double.self, forKey: .halation) ?? 0
        bloom = try container.decodeIfPresent(Double.self, forKey: .bloom) ?? 0
        fade = try container.decodeIfPresent(Double.self, forKey: .fade) ?? 0
        fadeWarmth = try container.decodeIfPresent(Double.self, forKey: .fadeWarmth) ?? 50
        splitShadowHue = try container.decodeIfPresent(Double.self, forKey: .splitShadowHue) ?? 220
        splitShadowSaturation = try container.decodeIfPresent(Double.self, forKey: .splitShadowSaturation) ?? 0
        splitHighlightHue = try container.decodeIfPresent(Double.self, forKey: .splitHighlightHue) ?? 40
        splitHighlightSaturation = try container.decodeIfPresent(Double.self, forKey: .splitHighlightSaturation) ?? 0
        splitBalance = try container.decodeIfPresent(Double.self, forKey: .splitBalance) ?? 0

        hslRedHue = try container.decodeIfPresent(Double.self, forKey: .hslRedHue) ?? 0
        hslRedSaturation = try container.decodeIfPresent(Double.self, forKey: .hslRedSaturation) ?? 0
        hslRedLuminance = try container.decodeIfPresent(Double.self, forKey: .hslRedLuminance) ?? 0
        hslOrangeHue = try container.decodeIfPresent(Double.self, forKey: .hslOrangeHue) ?? 0
        hslOrangeSaturation = try container.decodeIfPresent(Double.self, forKey: .hslOrangeSaturation) ?? 0
        hslOrangeLuminance = try container.decodeIfPresent(Double.self, forKey: .hslOrangeLuminance) ?? 0
        hslYellowHue = try container.decodeIfPresent(Double.self, forKey: .hslYellowHue) ?? 0
        hslYellowSaturation = try container.decodeIfPresent(Double.self, forKey: .hslYellowSaturation) ?? 0
        hslYellowLuminance = try container.decodeIfPresent(Double.self, forKey: .hslYellowLuminance) ?? 0
        hslGreenHue = try container.decodeIfPresent(Double.self, forKey: .hslGreenHue) ?? 0
        hslGreenSaturation = try container.decodeIfPresent(Double.self, forKey: .hslGreenSaturation) ?? 0
        hslGreenLuminance = try container.decodeIfPresent(Double.self, forKey: .hslGreenLuminance) ?? 0
        hslCyanHue = try container.decodeIfPresent(Double.self, forKey: .hslCyanHue) ?? 0
        hslCyanSaturation = try container.decodeIfPresent(Double.self, forKey: .hslCyanSaturation) ?? 0
        hslCyanLuminance = try container.decodeIfPresent(Double.self, forKey: .hslCyanLuminance) ?? 0
        hslBlueHue = try container.decodeIfPresent(Double.self, forKey: .hslBlueHue) ?? 0
        hslBlueSaturation = try container.decodeIfPresent(Double.self, forKey: .hslBlueSaturation) ?? 0
        hslBlueLuminance = try container.decodeIfPresent(Double.self, forKey: .hslBlueLuminance) ?? 0
        hslPurpleHue = try container.decodeIfPresent(Double.self, forKey: .hslPurpleHue) ?? 0
        hslPurpleSaturation = try container.decodeIfPresent(Double.self, forKey: .hslPurpleSaturation) ?? 0
        hslPurpleLuminance = try container.decodeIfPresent(Double.self, forKey: .hslPurpleLuminance) ?? 0
        hslMagentaHue = try container.decodeIfPresent(Double.self, forKey: .hslMagentaHue) ?? 0
        hslMagentaSaturation = try container.decodeIfPresent(Double.self, forKey: .hslMagentaSaturation) ?? 0
        hslMagentaLuminance = try container.decodeIfPresent(Double.self, forKey: .hslMagentaLuminance) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(exposure, forKey: .exposure)
        try container.encode(contrast, forKey: .contrast)
        try container.encode(highlights, forKey: .highlights)
        try container.encode(shadows, forKey: .shadows)
        try container.encode(whites, forKey: .whites)
        try container.encode(blacks, forKey: .blacks)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(tint, forKey: .tint)
        try container.encode(saturation, forKey: .saturation)
        try container.encode(sharpness, forKey: .sharpness)
        try container.encode(grain, forKey: .grain)
        try container.encode(grainSize, forKey: .grainSize)
        try container.encode(grainRoughness, forKey: .grainRoughness)
        try container.encode(grainColor, forKey: .grainColor)
        try container.encode(vignette, forKey: .vignette)
        try container.encode(clarity, forKey: .clarity)
        try container.encode(softGlow, forKey: .softGlow)
        try container.encode(halation, forKey: .halation)
        try container.encode(bloom, forKey: .bloom)
        try container.encode(fade, forKey: .fade)
        try container.encode(fadeWarmth, forKey: .fadeWarmth)
        try container.encode(splitShadowHue, forKey: .splitShadowHue)
        try container.encode(splitShadowSaturation, forKey: .splitShadowSaturation)
        try container.encode(splitHighlightHue, forKey: .splitHighlightHue)
        try container.encode(splitHighlightSaturation, forKey: .splitHighlightSaturation)
        try container.encode(splitBalance, forKey: .splitBalance)
        try container.encode(hslRedHue, forKey: .hslRedHue)
        try container.encode(hslRedSaturation, forKey: .hslRedSaturation)
        try container.encode(hslRedLuminance, forKey: .hslRedLuminance)
        try container.encode(hslOrangeHue, forKey: .hslOrangeHue)
        try container.encode(hslOrangeSaturation, forKey: .hslOrangeSaturation)
        try container.encode(hslOrangeLuminance, forKey: .hslOrangeLuminance)
        try container.encode(hslYellowHue, forKey: .hslYellowHue)
        try container.encode(hslYellowSaturation, forKey: .hslYellowSaturation)
        try container.encode(hslYellowLuminance, forKey: .hslYellowLuminance)
        try container.encode(hslGreenHue, forKey: .hslGreenHue)
        try container.encode(hslGreenSaturation, forKey: .hslGreenSaturation)
        try container.encode(hslGreenLuminance, forKey: .hslGreenLuminance)
        try container.encode(hslCyanHue, forKey: .hslCyanHue)
        try container.encode(hslCyanSaturation, forKey: .hslCyanSaturation)
        try container.encode(hslCyanLuminance, forKey: .hslCyanLuminance)
        try container.encode(hslBlueHue, forKey: .hslBlueHue)
        try container.encode(hslBlueSaturation, forKey: .hslBlueSaturation)
        try container.encode(hslBlueLuminance, forKey: .hslBlueLuminance)
        try container.encode(hslPurpleHue, forKey: .hslPurpleHue)
        try container.encode(hslPurpleSaturation, forKey: .hslPurpleSaturation)
        try container.encode(hslPurpleLuminance, forKey: .hslPurpleLuminance)
        try container.encode(hslMagentaHue, forKey: .hslMagentaHue)
        try container.encode(hslMagentaSaturation, forKey: .hslMagentaSaturation)
        try container.encode(hslMagentaLuminance, forKey: .hslMagentaLuminance)
    }
}
