#include "ShaderShared.h"

// MARK: - ADJUST-Only Fragment Shader

fragment float4 fragmentAdjustShader(
    VertexOut in [[stage_in]],
    texture2d<float> filmSimulatedTex [[texture(0)]],  // 胶片模拟后的纹理
    texture2d<float> originalTex [[texture(1)]],       // 原始纹理（用于 opacity 混合）
    constant AdjustUniforms &uniforms [[buffer(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    // 从胶片模拟纹理采样
    float4 filmColor = filmSimulatedTex.sample(textureSampler, in.texCoord);
    float3 color = filmColor.rgb;
    float alpha = filmColor.a;

    // === ADJUST 步骤（在 sRGB 或线性空间，取决于操作） ===

    // STEP A: 线性空间操作
    color = srgbToLinear(color);

    // Exposure
    if (abs(uniforms.exposure) > 0.0001) {
        color *= exp2(uniforms.exposure);
    }

    // Contrast
    if (abs(uniforms.contrast - 1.0) > 0.0001) {
        color = applySCurve(color, uniforms.contrast);
    }

    // Temperature/Tint
    if (abs(uniforms.temperature) > 0.001 || abs(uniforms.tint) > 0.001) {
        color = applyTemperatureTint(color, uniforms.temperature, uniforms.tint);
    }

    // Highlights/Shadows
    if (abs(uniforms.highlights) > 0.001 || abs(uniforms.shadows) > 0.001) {
        color = applyToneRange(color, uniforms.highlights, uniforms.shadows);
    }

    if (abs(uniforms.whites) > 0.001 || abs(uniforms.blacks) > 0.001) {
        color = applyWhitesBlacks(color, uniforms.whites, uniforms.blacks);
    }

    // Clarity
    if (abs(uniforms.clarity) > 0.001) {
        color = applyClarity(color, uniforms.clarity);
    }

    if (abs(uniforms.sharpness) > 0.001) {
        color = applySharpness(color, filmSimulatedTex, textureSampler, in.texCoord,
                               float2(filmSimulatedTex.get_width(), filmSimulatedTex.get_height()),
                               uniforms.sharpness);
    }

    // Saturation
    if (abs(uniforms.saturation - 1.0) > 0.0001) {
        color = applySaturation(color, uniforms.saturation);
    }

    // Back to sRGB for post-effects
    color = linearToSrgb(color);

    color = applyHSLBand(color, 0.0, uniforms.hslHueA.x, uniforms.hslSatA.x, uniforms.hslLumA.x);
    color = applyHSLBand(color, 30.0, uniforms.hslHueA.y, uniforms.hslSatA.y, uniforms.hslLumA.y);
    color = applyHSLBand(color, 60.0, uniforms.hslHueA.z, uniforms.hslSatA.z, uniforms.hslLumA.z);
    color = applyHSLBand(color, 120.0, uniforms.hslHueA.w, uniforms.hslSatA.w, uniforms.hslLumA.w);
    color = applyHSLBand(color, 180.0, uniforms.hslHueB.x, uniforms.hslSatB.x, uniforms.hslLumB.x);
    color = applyHSLBand(color, 240.0, uniforms.hslHueB.y, uniforms.hslSatB.y, uniforms.hslLumB.y);
    color = applyHSLBand(color, 280.0, uniforms.hslHueB.z, uniforms.hslSatB.z, uniforms.hslLumB.z);
    color = applyHSLBand(color, 320.0, uniforms.hslHueB.w, uniforms.hslSatB.w, uniforms.hslLumB.w);

    color = applySplitToning(color,
                             uniforms.splitShadowHue,
                             uniforms.splitShadowSaturation,
                             uniforms.splitHighlightHue,
                             uniforms.splitHighlightSaturation,
                             uniforms.splitBalance);

    // Soft glow
    if (uniforms.useSoftGlow > 0) {
        float glowStrength = saturate(uniforms.softGlow + uniforms.bloom / 100.0 * 0.75);
        color = applySoftGlow(color, filmSimulatedTex, textureSampler, in.texCoord,
                              float2(filmSimulatedTex.get_width(), filmSimulatedTex.get_height()),
                              glowStrength, uniforms.time);
    }

    if (uniforms.halation > 0.001) {
        color = applyAdjustHalation(color, filmSimulatedTex, textureSampler, in.texCoord,
                                    float2(filmSimulatedTex.get_width(), filmSimulatedTex.get_height()),
                                    uniforms.halation);
    }

    color = applyAdjustFade(color, uniforms.fade, uniforms.fadeWarmth);

    // Vignette
    if (uniforms.useVignette > 0) {
        color = applyVignette(color, in.texCoord, uniforms.vignette);
    }

    // Grain
    if (uniforms.useGrain > 0 && uniforms.grainIntensity > 0.001) {
        color = applyGrain(color, in.texCoord, uniforms.time,
                          uniforms.grainIntensity, uniforms.grainSoftness,
                          0.22, 0.45, 0.2, 0.5,
                          uniforms.grainColor > 0.001 ? 2 : 1,
                          uniforms.grainColor,
                          uniforms.grainSize,
                          uniforms.grainRoughness);
    }

    // Opacity blend with original
    if (uniforms.opacity < 0.999) {
        float3 originalColor = originalTex.sample(textureSampler, in.texCoord).rgb;
        color = mix(originalColor, color, uniforms.opacity);
    }

    return float4(saturate(color), alpha);
}
