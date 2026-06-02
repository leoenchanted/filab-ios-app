#include "ShaderShared.h"

// MARK: - Vertex Shader

vertex VertexOut vertexShader(
    uint vertexID [[vertex_id]],
    constant float2 *positions [[buffer(0)]]
) {
    VertexOut out;
    float2 pos = positions[vertexID];
    out.position = float4(pos, 0.0, 1.0);
    out.texCoord = float2(pos.x * 0.5 + 0.5, -pos.y * 0.5 + 0.5);
    return out;
}

// MARK: - Color Space Conversion

float3 srgbToLinear(float3 c) {
    float3 lower = c / 12.92;
    float3 higher = pow((c + 0.055) / 1.055, float3(2.4));
    return mix(higher, lower, step(c, float3(0.04045)));
}

float3 linearToSrgb(float3 c) {
    float3 lower = c * 12.92;
    float3 higher = 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055;
    return clamp(mix(higher, lower, step(c, float3(0.0031308))), 0.0, 1.0);
}

// BT.709 luminance (linear space)
float luminance(float3 color) {
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

// MARK: - Tone Curve

float applyCurve(float x, thread float2* points, int count) {
    if (count < 2) return x;

    float x255 = x * 255.0;
    float firstX = points[0].x;
    float lastX = points[count - 1].x;

    if (x255 <= firstX) return points[0].y / 255.0;
    if (x255 >= lastX) return points[count - 1].y / 255.0;

    for (int i = 0; i < count - 1; i++) {
        float x0 = points[i].x;
        float x1 = points[i + 1].x;

        if (x255 >= x0 && x255 <= x1) {
            float y0 = points[i].y;
            float y1 = points[i + 1].y;

            float t = (x255 - x0) / max(1.0, x1 - x0);
            float y = mix(y0, y1, t);
            return y / 255.0;
        }
    }

    return x;
}

void getCurvePointsArray(constant FilmUniforms& uniforms, thread float2* outPoints, int count) {
    if (count > 0) outPoints[0] = uniforms.curvePoint0;
    if (count > 1) outPoints[1] = uniforms.curvePoint1;
    if (count > 2) outPoints[2] = uniforms.curvePoint2;
    if (count > 3) outPoints[3] = uniforms.curvePoint3;
    if (count > 4) outPoints[4] = uniforms.curvePoint4;
    if (count > 5) outPoints[5] = uniforms.curvePoint5;
    if (count > 6) outPoints[6] = uniforms.curvePoint6;
    if (count > 7) outPoints[7] = uniforms.curvePoint7;
}

void getCurveRPointsArray(constant FilmUniforms& uniforms, thread float2* outPoints, int count) {
    if (count > 0) outPoints[0] = uniforms.curveRPoint0;
    if (count > 1) outPoints[1] = uniforms.curveRPoint1;
    if (count > 2) outPoints[2] = uniforms.curveRPoint2;
    if (count > 3) outPoints[3] = uniforms.curveRPoint3;
    if (count > 4) outPoints[4] = uniforms.curveRPoint4;
    if (count > 5) outPoints[5] = uniforms.curveRPoint5;
    if (count > 6) outPoints[6] = uniforms.curveRPoint6;
    if (count > 7) outPoints[7] = uniforms.curveRPoint7;
}

void getCurveGPointsArray(constant FilmUniforms& uniforms, thread float2* outPoints, int count) {
    if (count > 0) outPoints[0] = uniforms.curveGPoint0;
    if (count > 1) outPoints[1] = uniforms.curveGPoint1;
    if (count > 2) outPoints[2] = uniforms.curveGPoint2;
    if (count > 3) outPoints[3] = uniforms.curveGPoint3;
    if (count > 4) outPoints[4] = uniforms.curveGPoint4;
    if (count > 5) outPoints[5] = uniforms.curveGPoint5;
    if (count > 6) outPoints[6] = uniforms.curveGPoint6;
    if (count > 7) outPoints[7] = uniforms.curveGPoint7;
}

void getCurveBPointsArray(constant FilmUniforms& uniforms, thread float2* outPoints, int count) {
    if (count > 0) outPoints[0] = uniforms.curveBPoint0;
    if (count > 1) outPoints[1] = uniforms.curveBPoint1;
    if (count > 2) outPoints[2] = uniforms.curveBPoint2;
    if (count > 3) outPoints[3] = uniforms.curveBPoint3;
    if (count > 4) outPoints[4] = uniforms.curveBPoint4;
    if (count > 5) outPoints[5] = uniforms.curveBPoint5;
    if (count > 6) outPoints[6] = uniforms.curveBPoint6;
    if (count > 7) outPoints[7] = uniforms.curveBPoint7;
}

float3 applyToneCurve(float3 color, constant FilmUniforms& uniforms) {
    if (uniforms.useCurve == 0) return color;

    float2 points[8];
    getCurvePointsArray(uniforms, points, uniforms.curveCount);

    float3 result;
    result.r = applyCurve(color.r, points, uniforms.curveCount);
    result.g = applyCurve(color.g, points, uniforms.curveCount);
    result.b = applyCurve(color.b, points, uniforms.curveCount);

    return result;
}

float3 applyRGBCurves(float3 color, constant FilmUniforms& uniforms) {
    float3 result = color;

    if (uniforms.useCurveR == 1) {
        float2 points[8];
        getCurveRPointsArray(uniforms, points, uniforms.curveRCount);
        result.r = applyCurve(result.r, points, uniforms.curveRCount);
    }

    if (uniforms.useCurveG == 1) {
        float2 points[8];
        getCurveGPointsArray(uniforms, points, uniforms.curveGCount);
        result.g = applyCurve(result.g, points, uniforms.curveGCount);
    }

    if (uniforms.useCurveB == 1) {
        float2 points[8];
        getCurveBPointsArray(uniforms, points, uniforms.curveBCount);
        result.b = applyCurve(result.b, points, uniforms.curveBCount);
    }

    return result;
}

// MARK: - Noise / Grain

float hash(float n) { return fract(sin(n) * 1e4); }

float hash2(float2 p) { return fract(1e4 * sin(17.0 * p.x + p.y * 0.1) * (0.1 + abs(sin(p.y * 13.0 + p.x)))); }

float grainNoise(float2 x) {
    float2 i = floor(x);
    float2 f = fract(x);
    float a = hash2(i);
    float b = hash2(i + float2(1.0, 0.0));
    float c = hash2(i + float2(0.0, 1.0));
    float d = hash2(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// MARK: - Core Adjustments

float3 applySCurve(float3 color, float contrast) {
    if (contrast == 1.0) return color;
    // 采用摄影标准的 18% 中性灰锚点（线性空间）
    float3 result = (color - 0.18) * contrast + 0.18;
    return max(float3(0.0), result); 
}

float softShoulderLuma(float value) {
    value = max(value, 0.0);

    const float knee = 0.94;
    if (value <= knee) {
        return value;
    }

    return knee + (1.0 - knee) * (1.0 - exp(-(value - knee) / (1.0 - knee)));
}

float gamutFitAmountForChannel(float channel, float targetLuma) {
    if (channel < 0.0) {
        return (-channel) / max(targetLuma - channel, 0.00001);
    }

    if (channel > 1.0) {
        return (channel - 1.0) / max(channel - targetLuma, 0.00001);
    }

    return 0.0;
}

float3 remapLuminance(float3 color, float targetLuma) {
    float currentLuma = luminance(color);
    if (abs(targetLuma - currentLuma) < 0.00001) {
        return color;
    }

    targetLuma = softShoulderLuma(targetLuma);

    // YCbCr-style luminance move: change Y while keeping chroma offsets, then
    // gently desaturate only if the requested color falls outside display gamut.
    float3 shifted = color + (targetLuma - currentLuma);
    float fitAmount = 0.0;
    fitAmount = max(fitAmount, gamutFitAmountForChannel(shifted.r, targetLuma));
    fitAmount = max(fitAmount, gamutFitAmountForChannel(shifted.g, targetLuma));
    fitAmount = max(fitAmount, gamutFitAmountForChannel(shifted.b, targetLuma));

    float3 fitted = mix(shifted, float3(targetLuma), saturate(fitAmount));
    return max(float3(0.0), fitted);
}

float perceptualSliderAmount(float value) {
    return pow(saturate(abs(value)), 1.35);
}

float3 applyToneRange(float3 color, float highlights, float shadows) {
    float luma = max(luminance(color), 0.0);
    float luma01 = saturate(luma);
    float targetLuma = luma;

    if (abs(shadows) > 0.0001) {
        float amount = perceptualSliderAmount(shadows);
        float blackProtect = smoothstep(0.025, 0.14, luma01);
        float shadowMask = blackProtect * (1.0 - smoothstep(0.46, 0.76, luma01));

        if (shadows > 0.0) {
            float lifted = pow(luma01, 1.0 / (1.0 + amount * 0.58));
            targetLuma = mix(targetLuma, lifted, shadowMask * (0.58 + amount * 0.14));
        } else {
            float crushed = pow(luma01, 1.0 + amount * 0.72);
            targetLuma = mix(targetLuma, crushed, shadowMask * (0.52 + amount * 0.16));
        }
    }

    if (abs(highlights) > 0.0001) {
        float amount = min(abs(highlights), 1.0);
        float highlightMask = smoothstep(0.40, 0.95, luma01);

        if (highlights > 0.0) {
            float lifted = 1.0 - pow(1.0 - luma01, 1.0 + amount * 0.75);
            targetLuma = mix(targetLuma, lifted, highlightMask * 0.72);
        } else {
            float compressed = pow(luma01, 1.0 + amount * 1.20);
            compressed *= (1.0 - amount * 0.10 * highlightMask);
            targetLuma = mix(targetLuma, compressed, highlightMask);
        }
    }

    return remapLuminance(color, targetLuma);
}

float3 applyWhitesBlacks(float3 color, float whites, float blacks) {
    float luma = max(luminance(color), 0.0);
    float luma01 = saturate(luma);
    float targetLuma = luma;

    if (abs(blacks) > 0.0001) {
        float amount = perceptualSliderAmount(blacks);
        float blackProtect = smoothstep(0.025, 0.12, luma01);
        float blackMask = blackProtect * (1.0 - smoothstep(0.24, 0.48, luma01));

        if (blacks > 0.0) {
            float lifted = luma01 + amount * 0.052 * blackMask * (1.0 - luma01);
            targetLuma = mix(targetLuma, min(lifted, 1.0), 0.82);
        } else {
            float crushed = pow(luma01, 1.0 + amount * 0.62);
            crushed *= (1.0 - amount * 0.045 * blackMask);
            targetLuma = mix(targetLuma, crushed, blackMask * 0.62);
        }
    }

    if (abs(whites) > 0.0001) {
        float amount = min(abs(whites), 1.0);
        float whiteMask = smoothstep(0.68, 0.98, luma01);

        if (whites > 0.0) {
            float lifted = 1.0 - pow(1.0 - luma01, 1.0 + amount * 0.95);
            targetLuma = mix(targetLuma, lifted, whiteMask);
        } else {
            float compressed = pow(luma01, 1.0 + amount * 0.80);
            compressed *= (1.0 - amount * 0.16 * whiteMask);
            targetLuma = mix(targetLuma, compressed, whiteMask);
        }
    }

    return remapLuminance(color, targetLuma);
}

float3 applySaturation(float3 color, float saturation) {
    float luma = luminance(color);
    // 增加 max(0.0) 保护，防止极端去色时出现负值反色
    return max(float3(0.0), mix(float3(luma), color, saturation));
}

// MARK: - HSL

float3 rgbToHsv(float3 c) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 hsvToRgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, saturate(p - K.xxx), c.y);
}

float3 hueToRgb(float hueDegrees) {
    return hsvToRgb(float3(fract(hueDegrees / 360.0), 1.0, 1.0));
}

float hueBandMask(float hueDegrees, float centerDegrees) {
    float delta = abs(fract((hueDegrees - centerDegrees) / 360.0 + 0.5) - 0.5) * 360.0;
    return 1.0 - smoothstep(8.0, 50.0, delta);
}

float3 applyHSLBand(float3 color, float centerDegrees, float hueShift, float saturationShift, float luminanceShift) {
    if (abs(hueShift) < 0.001 && abs(saturationShift) < 0.001 && abs(luminanceShift) < 0.001) {
        return color;
    }

    float3 hsv = rgbToHsv(saturate(color));
    float mask = hueBandMask(hsv.x * 360.0, centerDegrees);
    hsv.x = fract(hsv.x + (hueShift / 360.0) * mask);
    hsv.y = clamp(hsv.y * (1.0 + saturationShift / 100.0 * mask), 0.0, 1.0);

    float3 shifted = hsvToRgb(hsv);
    shifted += (luminanceShift / 100.0) * 0.28 * mask;
    return saturate(shifted);
}

// MARK: - Split Toning

float3 applySplitToning(float3 color,
                        float shadowHue,
                        float shadowSaturation,
                        float highlightHue,
                        float highlightSaturation,
                        float balance) {
    if (shadowSaturation <= 0.001 && highlightSaturation <= 0.001) {
        return color;
    }

    float luma = luminance(srgbToLinear(color));
    float balanceOffset = balance / 50.0 * 0.22;
    float shadowMask = 1.0 - smoothstep(0.18 + balanceOffset, 0.62 + balanceOffset, luma);
    float highlightMask = smoothstep(0.38 + balanceOffset, 0.82 + balanceOffset, luma);

    float3 shadowColor = hueToRgb(shadowHue);
    float3 highlightColor = hueToRgb(highlightHue);

    color = mix(color, color * shadowColor, shadowMask * shadowSaturation / 100.0 * 0.35);
    color = mix(color, 1.0 - (1.0 - color) * (1.0 - highlightColor), highlightMask * highlightSaturation / 100.0 * 0.24);

    return saturate(color);
}

// MARK: - Fade

float3 applyAdjustFade(float3 color, float fade, float warmth) {
    if (fade <= 0.001) return color;

    float warmAmount = saturate(warmth / 100.0);
    float3 coolBase = float3(0.84, 0.88, 0.94);
    float3 warmBase = float3(0.98, 0.91, 0.82);
    float3 fadeColor = mix(coolBase, warmBase, warmAmount);

    return mix(color, fadeColor, fade / 100.0 * 0.34);
}

float3 applyFade(float3 color, float fade) {
    float3 fadeColor = float3(0.95, 0.92, 0.88);
    return mix(color, fadeColor, fade * 0.3);
}

// MARK: - Temperature / Tint

float3 applyTemperatureTint(float3 color, float temperature, float tint) {
    float tempStrength = temperature / 50.0;
    float tintStrength = tint / 50.0;

    // Temperature: warming boosts red, reduces blue; cooling does the opposite.
    // Keep green neutral for accurate Kelvin-style response.
    float tempR = 1.0 + tempStrength * 0.25;
    float tempG = 1.0;
    float tempB = 1.0 - tempStrength * 0.30;

    // Tint: magenta boosts R/B reduces G; green boosts G reduces R/B.
    float tintR = 1.0 + tintStrength * 0.20;
    float tintG = 1.0 - tintStrength * 0.15;
    float tintB = 1.0 + tintStrength * 0.20;

    float rScale = tempR * tintR;
    float gScale = tempG * tintG;
    float bScale = tempB * tintB;

    // Preserve perceptual luminance while applying colour balance
    float lumaScale = rScale * 0.2126 + gScale * 0.7152 + bScale * 0.0722;
    float normFactor = 1.0 / lumaScale;

    return color * float3(rScale * normFactor, gScale * normFactor, bScale * normFactor);
}

// MARK: - Clarity

float3 applyClarity(float3 color, float clarity) {
    float luma = luminance(color);
    float midPoint = 0.18; // 线性空间中性灰锚点
    
    // 中间调遮罩：0.05 ~ 0.45
    float midtoneMask = 1.0 - smoothstep(0.05, 0.45, abs(luma - midPoint));
    
    if (clarity > 0.0) {
        float amount = clarity / 50.0;
        // 提清晰度：增强中间调对比
        float3 punch = (color - midPoint) * (1.0 + amount * 0.6) + midPoint;
        // 补偿轻微饱和度
        float3 richer = mix(punch, applySaturation(punch, 1.0 + amount * 0.15), 0.5);
        return max(float3(0.0), mix(color, richer, midtoneMask));
    } else if (clarity < 0.0) {
        float softenAmount = abs(clarity) / 50.0;
        // 柔光：拉平对比，保留色彩纯度
        float3 flatter = (color - midPoint) * (1.0 - softenAmount * 0.4) + midPoint;
        return max(float3(0.0), mix(color, flatter, midtoneMask));
    }
    
    return color;
}

// MARK: - Grain

float3 applyGrain(float3 color, float2 texCoord, float time, float intensity,
                  float softness, float fineSoftness, float fineWeight,
                  float coarseWeight, float highlightReduction,
                  int mode, float colorVariance, float grainSize, float roughness) {
    float luma = luminance(color);
    float sizeScale = 1000.0 / mix(0.5, 2.4, saturate(grainSize));
    float rough = saturate(roughness);

    // Fine grain
    float2 fineUV = texCoord * sizeScale * 0.8;
    float fineGrain = 0.0;
    fineGrain += grainNoise(fineUV + float2(time * 0.01, 0.0)) * 0.5;
    fineGrain += grainNoise(fineUV * 2.0 + float2(0.0, time * 0.005)) * 0.25;
    fineGrain = (fineGrain - 0.5) * 2.0;

    // Coarse grain
    float2 coarseUV = texCoord * sizeScale * 0.4;
    float coarseGrain = 0.0;
    coarseGrain += grainNoise(coarseUV + float2(time * 0.005, time * 0.01)) * 0.5;
    coarseGrain += grainNoise(coarseUV * 1.5) * 0.3;
    coarseGrain = (coarseGrain - 0.5) * 2.0;

    // Combine
    float grain = fineGrain * mix(fineWeight * 1.15, fineWeight * 0.85, rough)
                + coarseGrain * mix(coarseWeight * 0.65, coarseWeight * 1.8, rough);
    grain = sign(grain) * pow(abs(grain), mix(1.25, 0.72, rough));
    grain = grain / (1.0 + abs(grain));

    float highlightFactor = 1.0 - smoothstep(0.0, highlightReduction, luma);
    grain *= highlightFactor;

    float grainAmount = intensity * 0.3;

    if (mode == 2 && colorVariance > 0.001) {
        float redNoise = (grainNoise(fineUV + float2(37.2, time * 0.017)) - 0.5) * 2.0;
        float greenNoise = (grainNoise(fineUV + float2(time * 0.013, 71.7)) - 0.5) * 2.0;
        float blueNoise = (grainNoise(fineUV + float2(113.4, 29.9 + time * 0.019)) - 0.5) * 2.0;
        float3 chromaticNoise = float3(redNoise, greenNoise, blueNoise) * highlightFactor;
        float3 chromaticGrain = mix(float3(grain), chromaticNoise, colorVariance);
        color += chromaticGrain * grainAmount;
    } else {
        color += grain * grainAmount;
    }

    return saturate(color);
}

// MARK: - Vignette

float3 applyVignette(float3 color, float2 texCoord, float strength) {
    float2 center = texCoord - float2(0.5);
    float dist = length(center);
    float edgeMask = smoothstep(0.35, 0.9, dist);

    if (strength >= 0.0) {
        float darken = 1.0 - edgeMask * strength;
        return saturate(color * darken);
    }

    float lift = abs(strength) * edgeMask * 0.22;
    float3 lifted = 1.0 - (1.0 - color) * (1.0 - float3(lift));
    return saturate(lifted);
}

// MARK: - Soft Glow (DeepGlow — 16-direction radial)

float3 applySoftGlow(float3 color,
                     texture2d<float> sourceTexture,
                     sampler textureSampler,
                     float2 texCoord,
                     float2 imageSize,
                     float strength,
                     float timeVal) {
    if (strength <= 0.001) return color;

    float amount = saturate(strength);
    float offset = (amount * 4.0 + 1.0) / min(imageSize.x, imageSize.y);

    float dither = fract(sin(timeVal * 12.9898 + texCoord.x * 1.0) * 43758.5453);

    constexpr int directions = 16;
    constexpr int quality = 4;
    constexpr float pi = 3.14159265359;

    float3 blurColor = float3(0.0);
    float totalWeight = 0.0;

    for (int d = 0; d < directions; d++) {
        float angle = (float(d) / float(directions)) * pi * 2.0;
        float2 dirVec = float2(cos(angle), sin(angle));

        for (int i = 1; i <= quality; i++) {
            float r = float(i) / float(quality) + (dither * 0.1 / float(quality));
            float2 uvOffset = dirVec * offset * r * 5.0;
            float2 sampleCoord = clamp(texCoord + uvOffset, float2(0.0), float2(1.0));

            float3 sampleC = sourceTexture.sample(textureSampler, sampleCoord).rgb;
            float luma = dot(sampleC, float3(0.299, 0.587, 0.114));
            float weight = 1.0 + (luma * 1.5);

            blurColor += sampleC * weight;
            totalWeight += weight;
        }
    }

    blurColor /= max(totalWeight, 0.0001);

    float gray = dot(blurColor, float3(0.299, 0.587, 0.114));
    blurColor = mix(float3(gray), blurColor, 1.3);

    float3 glow = 1.0 - ((1.0 - color) * (1.0 - saturate(blurColor)));

    float mixFactor = smoothstep(0.0, 1.0, amount * 0.8 + 0.1);
    float3 finalColor = mix(color, glow, mixFactor);

    finalColor += -0.02;
    finalColor = (finalColor - 0.5) * 1.05 + 0.5;

    return saturate(finalColor);
}

// MARK: - Sharpness (Unsharp Mask)

float3 applySharpness(float3 color,
                      texture2d<float> sourceTexture,
                      sampler textureSampler,
                      float2 texCoord,
                      float2 imageSize,
                      float sharpness) {
    if (abs(sharpness) <= 0.001) return color;

    float2 texel = 1.0 / imageSize;
    float3 left = srgbToLinear(sourceTexture.sample(textureSampler, clamp(texCoord + float2(-texel.x, 0.0), float2(0.0), float2(1.0))).rgb);
    float3 right = srgbToLinear(sourceTexture.sample(textureSampler, clamp(texCoord + float2(texel.x, 0.0), float2(0.0), float2(1.0))).rgb);
    float3 up = srgbToLinear(sourceTexture.sample(textureSampler, clamp(texCoord + float2(0.0, -texel.y), float2(0.0), float2(1.0))).rgb);
    float3 down = srgbToLinear(sourceTexture.sample(textureSampler, clamp(texCoord + float2(0.0, texel.y), float2(0.0), float2(1.0))).rgb);
    float3 blur = (left + right + up + down) * 0.25;

    if (sharpness > 0.0) {
        float amount = sharpness / 50.0 * 0.55;
        return saturate(color + (color - blur) * amount);
    }

    float amount = abs(sharpness) / 50.0 * 0.42;
    return mix(color, blur, amount);
}

// MARK: - Halation (ADJUST pass variant)

float3 applyAdjustHalation(float3 color,
                           texture2d<float> sourceTexture,
                           sampler textureSampler,
                           float2 texCoord,
                           float2 imageSize,
                           float strength) {
    if (strength <= 0.001) return color;

    float normalized = saturate(strength / 100.0) * 0.30;
    float2 texel = 1.0 / imageSize;
    float radius = 1.5 + normalized * 11.0;
    float3 glow = float3(0.0);
    float weightSum = 0.0;

    for (int y = -2; y <= 2; y++) {
        for (int x = -2; x <= 2; x++) {
            float2 offset = float2(float(x), float(y)) * texel * radius;
            float2 sampleCoord = clamp(texCoord + offset, float2(0.0), float2(1.0));
            float3 sampleColor = sourceTexture.sample(textureSampler, sampleCoord).rgb;
            float sampleLuma = luminance(srgbToLinear(sampleColor));
            float mask = smoothstep(0.72, 0.98, sampleLuma);
            float weight = 1.0 / (1.0 + length(float2(float(x), float(y))));
            glow += max(sampleColor - float3(0.34), float3(0.0)) * mask * weight;
            weightSum += mask * weight;
        }
    }

    glow /= max(weightSum, 0.0001);
    glow *= float3(1.34, 0.46, 0.24);

    float3 screenBlend = 1.0 - (1.0 - color) * (1.0 - saturate(glow));
    return mix(color, screenBlend, normalized * 0.48);
}
