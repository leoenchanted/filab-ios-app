#ifndef SHADER_SHARED_H
#define SHADER_SHARED_H

#include <metal_stdlib>
using namespace metal;

// MARK: - Constants
#define MAX_CURVE_POINTS 8

// MARK: - Structures

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct FilmUniforms {
    float3x3 colorMatrix;           // 48 bytes (offset 0-48), alignment 16
    float whiteBalanceR;            // 4 bytes (offset 48-52)
    float whiteBalanceG;            // 4 bytes (offset 52-56)
    float whiteBalanceB;            // 4 bytes (offset 56-60)
    float _pad1;                    // 4 bytes (offset 60-64)

    float exposure;                 // offset 64
    float contrast;
    float saturation;
    float vignette;
    float softGlow;
    float fade;
    float grainIntensity;
    float grainSoftness;
    float grainFineSoftness;
    float grainFineWeight;
    float grainCoarseWeight;
    float highlightReduction;
    float grainColorVariance;
    int grainMode;
    float _padGrain0;
    float _padGrain1;
    float bloomSigma;
    float bloomStrength;
    float opacity;
    float highlights;
    float shadows;
    int isMonochrome;
    float time;
    // ADJUST parameters: temperature/tint/clarity
    float temperature;
    float tint;
    float clarity;
    float _padAdjust;
    float _pad2a;

    // Master curve
    int useCurve;
    int curveCount;
    float _padCurve0;
    float _padCurve1;
    float2 curvePoint0;
    float2 curvePoint1;
    float2 curvePoint2;
    float2 curvePoint3;
    float2 curvePoint4;
    float2 curvePoint5;
    float2 curvePoint6;
    float2 curvePoint7;

    // Red curve
    int useCurveR;
    int curveRCount;
    float _padCurveR0;
    float _padCurveR1;
    float2 curveRPoint0;
    float2 curveRPoint1;
    float2 curveRPoint2;
    float2 curveRPoint3;
    float2 curveRPoint4;
    float2 curveRPoint5;
    float2 curveRPoint6;
    float2 curveRPoint7;

    // Green curve
    int useCurveG;
    int curveGCount;
    float _padCurveG0;
    float _padCurveG1;
    float2 curveGPoint0;
    float2 curveGPoint1;
    float2 curveGPoint2;
    float2 curveGPoint3;
    float2 curveGPoint4;
    float2 curveGPoint5;
    float2 curveGPoint6;
    float2 curveGPoint7;

    // Blue curve
    int useCurveB;
    int curveBCount;
    float _padCurveB0;
    float _padCurveB1;
    float2 curveBPoint0;
    float2 curveBPoint1;
    float2 curveBPoint2;
    float2 curveBPoint3;
    float2 curveBPoint4;
    float2 curveBPoint5;
    float2 curveBPoint6;
    float2 curveBPoint7;
};

struct HalationUniforms {
    float threshold;
    float strength;
    float colorShiftR;
    float colorShiftG;
    float colorShiftB;
    float sigma;
    float _pad0;
    float _pad1;
};

struct AdjustUniforms {
    float exposure;       // exposure (-1.0 to 1.0)
    float contrast;       // contrast multiplier
    float saturation;     // saturation multiplier
    float highlights;     // highlights adjustment

    float shadows;        // shadows adjustment
    float whites;         // whites adjustment
    float blacks;         // blacks adjustment
    float temperature;    // color temp (-50 to 50)

    float tint;           // tint (-50 to 50)
    float clarity;        // clarity (-50 to 50)
    float sharpness;      // sharpness (-50 to 50)
    float softGlow;       // soft glow (0 to 1)

    float vignette;       // vignette (-1 to 1)
    float grainIntensity; // grain amount
    float grainSoftness;  // grain softness
    float grainSize;      // grain size (0 to 1)

    float grainRoughness; // grain roughness (0 to 1)
    float grainColor;     // chromatic grain (0 to 1)
    float opacity;        // film strength (0 to 1)
    float time;           // time for grain animation

    float halation;       // halation (0 to 100)
    float bloom;          // bloom (0 to 100)
    float fade;           // fade (0 to 100)
    float fadeWarmth;     // fade warmth (0 to 100)

    float splitShadowHue;
    float splitShadowSaturation;
    float splitHighlightHue;
    float splitHighlightSaturation;

    float splitBalance;
    float _pad0;
    float _pad1;
    float _pad2;

    float4 hslHueA;       // red, orange, yellow, green
    float4 hslHueB;       // cyan, blue, purple, magenta
    float4 hslSatA;
    float4 hslSatB;
    float4 hslLumA;
    float4 hslLumB;

    int useSoftGlow;      // whether to apply soft glow/bloom
    int useGrain;         // whether to apply grain
    int useVignette;      // whether vignette != 0
    int _padI;
};

// MARK: - Vertex Shader

vertex VertexOut vertexShader(
    uint vertexID [[vertex_id]],
    constant float2 *positions [[buffer(0)]]
);

// MARK: - Helper Function Prototypes

// Color space conversion
float3 srgbToLinear(float3 c);
float3 linearToSrgb(float3 c);
float luminance(float3 color);

// Tone curve
float applyCurve(float x, thread float2* points, int count);
void getCurvePointsArray(constant FilmUniforms& uniforms, thread float2* outPoints, int count);
void getCurveRPointsArray(constant FilmUniforms& uniforms, thread float2* outPoints, int count);
void getCurveGPointsArray(constant FilmUniforms& uniforms, thread float2* outPoints, int count);
void getCurveBPointsArray(constant FilmUniforms& uniforms, thread float2* outPoints, int count);
float3 applyToneCurve(float3 color, constant FilmUniforms& uniforms);
float3 applyRGBCurves(float3 color, constant FilmUniforms& uniforms);

// Noise / Grain
float hash(float n);
float hash2(float2 p);
float grainNoise(float2 x);

// Core image adjustments
float3 applySCurve(float3 color, float contrast);
float3 applyToneRange(float3 color, float highlights, float shadows);
float3 applyWhitesBlacks(float3 color, float whites, float blacks);
float3 applySaturation(float3 color, float saturation);

// HSL
float3 rgbToHsv(float3 c);
float3 hsvToRgb(float3 c);
float3 hueToRgb(float hueDegrees);
float hueBandMask(float hueDegrees, float centerDegrees);
float3 applyHSLBand(float3 color, float centerDegrees, float hueShift, float saturationShift, float luminanceShift);

// Split toning
float3 applySplitToning(float3 color,
                        float shadowHue,
                        float shadowSaturation,
                        float highlightHue,
                        float highlightSaturation,
                        float balance);

// Fade
float3 applyAdjustFade(float3 color, float fade, float warmth);
float3 applyFade(float3 color, float fade);

// White balance / Temperature
float3 applyTemperatureTint(float3 color, float temperature, float tint);

// Clarity
float3 applyClarity(float3 color, float clarity);

// Grain
float3 applyGrain(float3 color, float2 texCoord, float time, float intensity,
                  float softness, float fineSoftness, float fineWeight,
                  float coarseWeight, float highlightReduction,
                  int mode, float colorVariance, float grainSize, float roughness);

// Vignette
float3 applyVignette(float3 color, float2 texCoord, float strength);

// Soft Glow (DeepGlow)
float3 applySoftGlow(float3 color,
                     texture2d<float> sourceTexture,
                     sampler textureSampler,
                     float2 texCoord,
                     float2 imageSize,
                     float strength,
                     float timeVal);

// Sharpness (Unsharp Mask)
float3 applySharpness(float3 color,
                      texture2d<float> sourceTexture,
                      sampler textureSampler,
                      float2 texCoord,
                      float2 imageSize,
                      float sharpness);

// Halation (adjust pass variant)
float3 applyAdjustHalation(float3 color,
                           texture2d<float> sourceTexture,
                           sampler textureSampler,
                           float2 texCoord,
                           float2 imageSize,
                           float strength);

#endif /* SHADER_SHARED_H */
