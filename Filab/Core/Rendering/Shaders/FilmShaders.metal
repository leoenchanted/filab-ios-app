#include "ShaderShared.h"

// MARK: - Main Film Fragment Shader

fragment float4 fragmentFilmShader(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    constant FilmUniforms &uniforms [[buffer(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    // Sample source texture (sRGB input)
    float4 sourceColor = sourceTexture.sample(textureSampler, in.texCoord);
    float3 originalColor = sourceColor.rgb;
    float3 color = originalColor;

    // === STEP 1: Convert to linear space ===
    color = srgbToLinear(color);

    // === STEP 2: White balance (linear) ===
    color *= float3(uniforms.whiteBalanceR, uniforms.whiteBalanceG, uniforms.whiteBalanceB);
    color = clamp(color, 0.0, 1.0);

    // === STEP 3: Color matrix (linear) ===
    if (uniforms.colorMatrix[0][0] != 1.0 || uniforms.colorMatrix[1][1] != 1.0 || uniforms.colorMatrix[2][2] != 1.0) {
        color = uniforms.colorMatrix * color;
        color = clamp(color, 0.0, 1.0);
    }

    // === STEP 4: Convert to sRGB for curve operations ===
    color = linearToSrgb(color);

    // === STEP 5: Master tone curve ===
    if (uniforms.useCurve == 1) {
        color = applyToneCurve(color, uniforms);
    }

    // === STEP 6: Separate RGB curves ===
    if (uniforms.useCurveR == 1 || uniforms.useCurveG == 1 || uniforms.useCurveB == 1) {
        color = applyRGBCurves(color, uniforms);
    }

    // === STEP 7: Convert back to linear for remaining operations ===
    color = srgbToLinear(color);

    // === STEP 8: Exposure (linear) ===
    float exposureFactor = exp2(uniforms.exposure);
    color *= exposureFactor;

    // === STEP 9: Contrast (linear) ===
    color = applySCurve(color, uniforms.contrast);

    // === STEP 9.5: Temperature/Tint ===
    if (abs(uniforms.temperature) > 0.001 || abs(uniforms.tint) > 0.001) {
        color = applyTemperatureTint(color, uniforms.temperature, uniforms.tint);
    }

    // === STEP 10: Highlight/Shadow adjustments ===
    color = applyToneRange(color, uniforms.highlights, uniforms.shadows);

    // === STEP 10.5: Clarity ===
    if (abs(uniforms.clarity) > 0.001) {
        color = applyClarity(color, uniforms.clarity);
    }

    // === STEP 11: Saturation ===
    color = applySaturation(color, uniforms.saturation);

    // === STEP 12: Monochrome conversion ===
    if (uniforms.isMonochrome > 0) {
        float gray = luminance(color);
        color = float3(gray);
    }

    // === STEP 13: Convert to sRGB for output ===
    color = linearToSrgb(color);

    // === STEP 14: Post-effects (sRGB space) ===

    // Soft glow
    color = applySoftGlow(color, sourceTexture, textureSampler, in.texCoord,
                          float2(sourceTexture.get_width(), sourceTexture.get_height()),
                          uniforms.softGlow, uniforms.time);

    // Vignette
    color = applyVignette(color, in.texCoord, uniforms.vignette);

    // Fade
    color = applyFade(color, uniforms.fade);

    // Grain
    if (uniforms.grainIntensity > 0.001) {
        color = applyGrain(color, in.texCoord, uniforms.time,
                          uniforms.grainIntensity, uniforms.grainSoftness,
                          uniforms.grainFineSoftness, uniforms.grainFineWeight,
                          uniforms.grainCoarseWeight, uniforms.highlightReduction,
                          uniforms.grainMode, uniforms.grainColorVariance, 0.5, 0.5);
    }

    // Bloom effect
    if (uniforms.bloomSigma > 0.001 && uniforms.bloomStrength > 0.001) {
        float2 texel = 1.0 / float2(sourceTexture.get_width(), sourceTexture.get_height());
        float radius = uniforms.bloomSigma * 0.5;

        float3 bloom = float3(0.0);
        float totalWeight = 0.0;

        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                float2 offset = float2(float(x), float(y)) * texel * radius;
                float2 sampleCoord = clamp(in.texCoord + offset, float2(0.0), float2(1.0));
                float3 sampleColor = sourceTexture.sample(textureSampler, sampleCoord).rgb;

                float sampleLuma = luminance(srgbToLinear(sampleColor));
                float highlightMask = smoothstep(0.5, 0.8, sampleLuma);

                float weight = (abs(x) + abs(y) == 0) ? 1.0 : 0.5;
                weight *= highlightMask;

                bloom += sampleColor * weight;
                totalWeight += weight;
            }
        }

        bloom /= max(totalWeight, 0.0001);
        bloom = saturate(bloom * uniforms.bloomStrength);

        float3 screenBlend = 1.0 - (1.0 - color) * (1.0 - bloom);
        color = mix(color, screenBlend, uniforms.bloomStrength * 0.5);
    }

    // === STEP 15: Blend with original (opacity) ===
    color = mix(originalColor, color, uniforms.opacity);

    return float4(saturate(color), sourceColor.a);
}

// MARK: - Blur Shader (Gaussian, separable)

fragment float4 fragmentBlurShader(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    constant float &sigma [[buffer(0)]],
    constant float2 &direction [[buffer(1)]],
    sampler textureSampler [[sampler(0)]]
) {
    float2 texSize = float2(sourceTexture.get_width(), sourceTexture.get_height());
    float2 texel = 1.0 / texSize;

    float3 result = float3(0.0);
    float weightSum = 0.0;

    int radius = int(sigma * 3.0);
    radius = clamp(radius, 1, 15);

    for (int i = -radius; i <= radius; i++) {
        float2 offset = float2(i) * texel * direction;
        float2 sampleCoord = clamp(in.texCoord + offset, float2(0.0), float2(1.0));

        float weight = exp(-float(i * i) / (2.0 * sigma * sigma));

        result += sourceTexture.sample(textureSampler, sampleCoord).rgb * weight;
        weightSum += weight;
    }

    result /= weightSum;
    return float4(result, 1.0);
}

// MARK: - Halation Blend Shader

fragment float4 fragmentHalationShader(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    texture2d<float> bloomTexture [[texture(1)]],
    constant HalationUniforms &uniforms [[buffer(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    float3 source = sourceTexture.sample(textureSampler, in.texCoord).rgb;
    float3 bloom = bloomTexture.sample(textureSampler, in.texCoord).rgb;

    float luma = luminance(bloom);
    float highlightMask = smoothstep(uniforms.threshold - 0.1, uniforms.threshold + 0.1, luma);

    bloom *= float3(uniforms.colorShiftR, uniforms.colorShiftG, uniforms.colorShiftB);

    float3 result = source + bloom * highlightMask * uniforms.strength;

    return float4(saturate(result), 1.0);
}

// MARK: - Curve LUT Shader

fragment float4 fragmentCurveShader(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    texture2d<float> lutTexture [[texture(1)]],
    sampler textureSampler [[sampler(0)]]
) {
    float3 color = sourceTexture.sample(textureSampler, in.texCoord).rgb;

    float r = lutTexture.sample(textureSampler, float2(color.r, 0.5)).r;
    float g = lutTexture.sample(textureSampler, float2(color.g, 0.5)).r;
    float b = lutTexture.sample(textureSampler, float2(color.b, 0.5)).r;

    return float4(r, g, b, 1.0);
}

// MARK: - Composite Shader

fragment float4 fragmentCompositeShader(
    VertexOut in [[stage_in]],
    texture2d<float> originalTexture [[texture(0)]],
    texture2d<float> processedTexture [[texture(1)]],
    texture2d<float> bloomTexture [[texture(2)]],
    constant float &opacity [[buffer(0)]],
    constant int &showCompare [[buffer(1)]],
    sampler textureSampler [[sampler(0)]]
) {
    float2 uv = in.texCoord;

    float3 original = originalTexture.sample(textureSampler, uv).rgb;
    float3 processed = processedTexture.sample(textureSampler, uv).rgb;

    if (bloomTexture.get_width() > 0) {
        float3 bloom = bloomTexture.sample(textureSampler, uv).rgb;
        processed += bloom * 0.3;
        processed = saturate(processed);
    }

    float3 result = mix(original, processed, opacity);

    if (showCompare > 0) {
        if (uv.x < 0.5) {
            result = original;
        }
        if (abs(uv.x - 0.5) < 0.002) {
            result = float3(1.0, 0.6, 0.2);
        }
    }

    return float4(result, 1.0);
}

// MARK: - Simple Preview Shader (legacy)

fragment float4 fragmentSimplePreview(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    constant FilmUniforms &uniforms [[buffer(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    float4 color = sourceTexture.sample(textureSampler, in.texCoord);
    float3 rgb = color.rgb;

    rgb *= exp2(uniforms.exposure);
    rgb = (rgb - 0.5) * uniforms.contrast + 0.5;
    float luma = luminance(rgb);
    rgb = mix(float3(luma), rgb, uniforms.saturation);
    rgb *= float3(uniforms.whiteBalanceR, uniforms.whiteBalanceG, uniforms.whiteBalanceB);

    return float4(saturate(rgb), color.a);
}
