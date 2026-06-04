// PreviewCore.metal
// SwiftUI Stitchable Shader — 相机实时预览的影调核心
// 与 FilmShaders.metal 的 Step 1-9 逻辑完全同源，确保预览和导出的色彩一致
// 不包含纹理/质感效果（Grain, Halation, Bloom, Sharpen），留给后处理

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// MARK: - Color Space Conversion (自包含版本，避免与 ShaderHelpers.metal 的 include 冲突)

static float3 pSrgbToLinear(float3 c) {
    float3 lower = c / 12.92;
    float3 higher = pow((c + 0.055) / 1.055, float3(2.4));
    return mix(higher, lower, step(c, float3(0.04045)));
}

static float3 pLinearToSrgb(float3 c) {
    float3 lower = c * 12.92;
    float3 higher = 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055;
    return clamp(mix(higher, lower, step(c, float3(0.0031308))), 0.0, 1.0);
}

// MARK: - Tone Curve (5-point linear interpolation, 与 FilmShaders.metal applyCurve 同源)

static float pApplyCurve(float x, float2 p0, float2 p1, float2 p2, float2 p3, float2 p4, float countF) {
    int count = int(countF);
    if (count < 2) return x;

    float x255 = x * 255.0;
    float2 pts[5] = { p0, p1, p2, p3, p4 };

    if (x255 <= pts[0].x) return pts[0].y / 255.0;
    int last = min(count - 1, 4);
    if (x255 >= pts[last].x) return pts[last].y / 255.0;

    for (int i = 0; i < last; i++) {
        if (x255 >= pts[i].x && x255 <= pts[i + 1].x) {
            float t = (x255 - pts[i].x) / max(1.0, pts[i + 1].x - pts[i].x);
            return mix(pts[i].y, pts[i + 1].y, t) / 255.0;
        }
    }

    return x;
}

// MARK: - Core Preview Shader
// 与 FilmShaders.metal fragmentFilmShader 的 Step 1-9 数学逻辑完全一致
// 差异：无 texture sampling（无 grain/halation/bloom），无 RGB 分通道曲线

[[ stitchable ]] half4 filmPreviewCore(
    half4 color,
    float3 wb,            // 白平衡 RGB 乘数 (from WhiteBalance.toRGB())
    float3 colorMatrixC0, // 色彩矩阵 column 0 (from ColorMatrix.toSIMD())
    float3 colorMatrixC1, // 色彩矩阵 column 1
    float3 colorMatrixC2, // 色彩矩阵 column 2
    float contrast,       // 对比度 (0.18 基准, 与 applySCurve 完全一致)
    float saturation,     // 饱和度 (luma-based, 与 applySaturation 完全一致)
    float fade,           // 褪色量 (与 applyFade 完全一致)
    float2 curveP0,       // 主曲线点 0
    float2 curveP1,       // 主曲线点 1
    float2 curveP2,       // 主曲线点 2
    float2 curveP3,       // 主曲线点 3
    float2 curveP4,       // 主曲线点 4
    float curveCount      // 曲线点数 (float 传递, shader 内转 int)
) {
    float3 c = float3(color.rgb);
    float3x3 colorMatrix = float3x3(colorMatrixC0, colorMatrixC1, colorMatrixC2);

    // === Step 1: sRGB -> Linear ===
    float3 linear = pSrgbToLinear(c);

    // === Step 2: White Balance (linear, 与 FilmShaders Step 2 完全一致) ===
    linear *= wb;
    linear = clamp(linear, 0.0, 1.0);

    // === Step 3: Color Matrix (linear, 与 FilmShaders Step 3 完全一致) ===
    linear = colorMatrix * linear;
    linear = clamp(linear, 0.0, 1.0);

    // === Step 4: Linear -> sRGB (for curve operations) ===
    float3 srgb = pLinearToSrgb(linear);

    // === Step 5: Master Tone Curve (sRGB, 与 FilmShaders Step 5 同源) ===
    if (curveCount >= 2.0) {
        srgb.r = pApplyCurve(srgb.r, curveP0, curveP1, curveP2, curveP3, curveP4, curveCount);
        srgb.g = pApplyCurve(srgb.g, curveP0, curveP1, curveP2, curveP3, curveP4, curveCount);
        srgb.b = pApplyCurve(srgb.b, curveP0, curveP1, curveP2, curveP3, curveP4, curveCount);
    }

    // === Step 6: sRGB -> Linear ===
    linear = pSrgbToLinear(srgb);

    // === Step 7: Contrast (linear, 0.18 center — 与 ShaderHelpers.metal applySCurve 完全一致) ===
    // 这里彻底解决了 SwiftUI .contrast() 的 0.5 中心与 Metal 0.18 中心的冲突
    linear = (linear - 0.18) * contrast + 0.18;
    linear = max(float3(0.0), linear);

    // === Step 8: Saturation (linear, 与 ShaderHelpers.metal applySaturation 完全一致) ===
    float luma = dot(linear, float3(0.2126, 0.7152, 0.0722));
    linear = max(float3(0.0), mix(float3(luma), linear, saturation));

    // === Step 9: Fade (linear, 与 ShaderHelpers.metal applyFade 完全一致) ===
    if (fade > 0.001) {
        float3 fadeColor = float3(0.95, 0.92, 0.88);
        linear = mix(linear, fadeColor, fade * 0.3);
    }

    // === Step 10: Linear -> sRGB (output) ===
    float3 result = pLinearToSrgb(linear);

    return half4(half3(result), color.a);
}

// MARK: - Live Camera Preview Render Pipeline

struct CameraPreviewVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct CameraPreviewUniforms {
    float4 wbContrast;          // xyz: white balance, w: contrast
    float4 matrixC0Saturation;  // xyz: color matrix column 0, w: saturation
    float4 matrixC1Fade;        // xyz: color matrix column 1, w: fade
    float4 matrixC2Flags;       // xyz: color matrix column 2, w: mirrored flag
    float4 aspect;              // x: drawable aspect, y: source aspect, z: linear preview gain
};

vertex CameraPreviewVertexOut cameraPreviewVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };

    constexpr float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    CameraPreviewVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

static float2 pAspectFillUV(float2 uv, float drawableAspect, float sourceAspect) {
    if (drawableAspect > sourceAspect) {
        float visibleHeight = sourceAspect / max(drawableAspect, 0.001);
        uv.y = (uv.y - 0.5) * visibleHeight + 0.5;
    } else {
        float visibleWidth = drawableAspect / max(sourceAspect, 0.001);
        uv.x = (uv.x - 0.5) * visibleWidth + 0.5;
    }
    return uv;
}

static float3 pFullRangeYuvToRgb(float y, float2 cbcr) {
    float cb = cbcr.x - 0.5;
    float cr = cbcr.y - 0.5;
    return float3(
        y + 1.5748 * cr,
        y - 0.1873 * cb - 0.4681 * cr,
        y + 1.8556 * cb
    );
}

fragment half4 cameraPreviewFragment(
    CameraPreviewVertexOut in [[stage_in]],
    texture2d<float, access::sample> lumaTexture [[texture(0)]],
    texture2d<float, access::sample> chromaTexture [[texture(1)]],
    texture2d<float, access::sample> curveTexture [[texture(2)]],
    constant CameraPreviewUniforms& uniforms [[buffer(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    float2 uv = pAspectFillUV(in.texCoord, uniforms.aspect.x, uniforms.aspect.y);
    if (uniforms.matrixC2Flags.w > 0.5) {
        uv.x = 1.0 - uv.x;
    }

    float y = lumaTexture.sample(textureSampler, uv).r;
    float2 cbcr = chromaTexture.sample(textureSampler, uv).rg;
    float3 srgb = clamp(pFullRangeYuvToRgb(y, cbcr), 0.0, 1.0);

    float3 linear = pSrgbToLinear(srgb);
    linear *= max(uniforms.aspect.z, 0.001);
    linear *= uniforms.wbContrast.xyz;
    linear = clamp(linear, 0.0, 1.0);

    float3x3 colorMatrix = float3x3(
        uniforms.matrixC0Saturation.xyz,
        uniforms.matrixC1Fade.xyz,
        uniforms.matrixC2Flags.xyz
    );
    linear = clamp(colorMatrix * linear, 0.0, 1.0);

    srgb = pLinearToSrgb(linear);
    srgb.r = curveTexture.sample(textureSampler, float2(srgb.r, 0.5)).r;
    srgb.g = curveTexture.sample(textureSampler, float2(srgb.g, 0.5)).r;
    srgb.b = curveTexture.sample(textureSampler, float2(srgb.b, 0.5)).r;

    linear = pSrgbToLinear(srgb);
    linear = max(float3(0.0), (linear - 0.18) * uniforms.wbContrast.w + 0.18);

    float luma = dot(linear, float3(0.2126, 0.7152, 0.0722));
    linear = max(float3(0.0), mix(float3(luma), linear, uniforms.matrixC0Saturation.w));

    float fade = uniforms.matrixC1Fade.w;
    if (fade > 0.001) {
        linear = mix(linear, float3(0.95, 0.92, 0.88), fade * 0.3);
    }

    return half4(half3(pLinearToSrgb(linear)), 1.0);
}
