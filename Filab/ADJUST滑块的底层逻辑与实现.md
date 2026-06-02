# Filab ADJUST 滑块的底层逻辑与实现

## 一、整体架构

```
用户在 AdjustView 拖动滑块
  │
  ↓
AdjustmentParams 属性变化（@Published）
  │
  ↓
Combine $adjustments.throttle(50ms)
  │
  ↓
processImage()
  │
  ├─→ Metal 路径（主路径）
  │     MetalFilmProcessor.processImage()
  │     → applyAdjustEffect() → fragmentAdjustShader
  │
  └─→ Core Image 路径（后备，仅当 Metal 不可用）
        processWithCoreImageAsync()
        → 逐项 CIFilter 链
```

### 数据绑定（FilmEditorViewModel.swift:57-63）

```swift
$adjustments
    .dropFirst()
    .throttle(for: .milliseconds(50), scheduler: RunLoop.main, latest: true)
    .sink { [weak self] _ in
        self?.processImage()
    }
```

- `.throttle(for: .milliseconds(50))` — 滑块拖动期间每 50ms 发射一次最新值
- `latest: true` — 只保留最新的值，丢弃中间值，保证实时性
- 拖动结束时自动处理最后一个值

### Adjust Pass 在 Metal 中的处理顺序

```
filmSimulatedTexture（胶片模拟结果）
  │
  sRGB → Linear
  → Exposure（exp2 乘法）
  → Contrast（S-curve）
  → Temperature/Tint（亮度保持算法）
  → Highlights/Shadows（按亮度区域）
  → Whites/Blacks（按亮度区域，不同算法）
  → Clarity（局部对比度）
  → Sharpness（拉普拉斯锐化/模糊）
  → Saturation
  → sRGB
  → HSL（8 色相带，HSV 空间操作）
  → Split Toning（阴影色/高光色染色）
  → Soft Glow（DeepGlow 径向采样）
  → Halation（高斯模糊 + 红色染色）
  → Fade（色彩 overlay）
  → Vignette（径向渐变遮罩）
  → Grain（双层噪声）
  → Opacity 混合回原图
  │
 最终输出
```

---

## 二、调光（Light）— 5 个滑块

### 2.1 Exposure（曝光）

| 属性 | 值 |
|---|---|
| 范围 | -50 ~ +50 |
| 默认 | 0 |
| UI 图标 | sun.max.fill |

**Swift → Uniforms 映射**：
```swift
uniforms.exposure = Float(adjustments.exposure / 50.0)  // -1.0 ~ 1.0
```

**Metal 算法**（FilmShaders.metal:886-889）：
```metal
color *= exp2(uniforms.exposure);
```
- `exposure=0` → `exp2(0)` = 1.0（不变化）
- `exposure=50` → `exp2(1.0)` = 2.0 倍亮度（+1 EV）
- `exposure=-50` → `exp2(-1.0)` = 0.5 倍亮度（-1 EV）
- 在线性空间操作，符合物理曝光原理

**Core Image 后备**：
```swift
let filter = CIFilter.exposureAdjust()
filter.ev = Float(value / 50.0)  // -1.0 ~ 1.0 EV
```

---

### 2.2 Contrast（对比度）

| 属性 | 值 |
|---|---|
| 范围 | -50 ~ +50 |
| 默认 | 0 |
| UI 图标 | circle.lefthalf.filled |

**Swift → Uniforms 映射**：
```swift
uniforms.contrast = Float(1.0 + adjustments.contrast / 100.0)  // 0.5 ~ 1.5
```

**Metal 算法**（applySCurve, FilmShaders.metal:295-299）：
```metal
float3 applySCurve(float3 color, float contrast) {
    float3 result = (color - 0.5) * contrast + 0.5;
    return saturate(result);
}
```
- 以 0.5 为中心点的缩放，在线性空间操作
- `contrast=1.0` → 不变化
- `contrast>1.0` → 亮部更亮、暗部更暗
- `contrast<1.0` → 整体向 0.5 靠拢（降低对比）

---

### 2.3 Highlights / Shadows（高光 / 阴影）

| 属性 | 值 |
|---|---|
| 范围 | -50 ~ +50 |
| 默认 | 0 |
| UI 图标 | sparkle / moon.fill |

**Swift → Uniforms 映射**：
```swift
uniforms.highlights = Float(adjustments.highlights)   // -50 ~ 50
uniforms.shadows = Float(adjustments.shadows)         // -50 ~ 50
```

**Metal 算法**（applyToneRange, FilmShaders.metal:302-314）：
```metal
float3 applyToneRange(float3 color, float highlights, float shadows) {
    float luma = luminance(color);

    float highlightFactor = smoothstep(0.3, 1.0, luma);
    color += highlights * highlightFactor * 0.01;

    float shadowFactor = 1.0 - smoothstep(0.0, 0.7, luma);
    color += shadows * shadowFactor * 0.01;

    return color;
}
```
- 基于亮度值的区域选择
- Highlights 影响 luma > 0.3 的区域，随亮度升高影响增大
- Shadows 影响 luma < 0.7 的区域，随亮度降低影响增大
- 正负值控制增加或减少该区域的亮度
- 在线性空间操作

**Core Image 后备**：
```swift
let filter = CIFilter.highlightShadowAdjust()
filter.highlightAmount = Float(1.0 + (highlights / 100.0))
filter.shadowAmount = Float(1.0 + (shadows / 100.0))
```

---

### 2.4 Whites / Blacks（白色色阶 / 黑色色阶）

| 属性 | 值 |
|---|---|
| 范围 | -50 ~ +50 |
| 默认 | 0 |

**Swift → Uniforms 映射**：
```swift
uniforms.whites = Float(adjustments.whites)   // -50 ~ 50
uniforms.blacks = Float(adjustments.blacks)    // -50 ~ 50
```

**Metal 算法**（applyWhitesBlacks, FilmShaders.metal:316-339）：
```metal
float3 applyWhitesBlacks(float3 color, float whites, float blacks) {
    float luma = luminance(color);
    float whiteMask = smoothstep(0.45, 0.92, luma);
    float blackMask = 1.0 - smoothstep(0.04, 0.48, luma);

    // Whites: 正值用 screen 提亮，负值用乘法压暗
    if (whites > 0.0) {
        float amount = whites / 50.0 * 0.42;
        float3 lifted = 1.0 - (1.0 - color) * (1.0 - float3(amount));
        color = mix(color, lifted, whiteMask);
    } else if (whites < 0.0) {
        float amount = abs(whites) / 50.0 * 0.38;
        color *= 1.0 - whiteMask * amount;
    }

    // Blacks: 正值加法提升，负值乘法压暗
    if (blacks > 0.0) {
        float amount = blacks / 50.0 * 0.24;
        color += blackMask * amount;
    } else if (blacks < 0.0) {
        float amount = abs(blacks) / 50.0 * 0.48;
        color *= 1.0 - blackMask * amount;
    }

    return saturate(color);
}
```
- 与 Highlights/Shadows 的区别：Whites 影响最亮端（0.45-0.92），Blacks 影响最暗端（0.04-0.48）
- Whites 正值用 Screen 混合（非加法），避免最亮区域过曝
- 在线性空间操作

---

## 三、颜色（Color）— 5 个滑块

### 3.1 Temperature（色温）

| 属性 | 值 |
|---|---|
| 范围 | -50 ~ +50 |
| 默认 | 0 |
| UI 图标 | thermometer.medium |

**Swift → Uniforms 映射**：
```swift
uniforms.temperature = Float(adjustments.temperature)  // -50 ~ 50
```

**Metal 算法**（applyTemperatureTint, FilmShaders.metal:422-451）：
```metal
float3 applyTemperatureTint(float3 color, float temperature, float tint) {
    float tempStrength = temperature / 50.0;       // -1.0 ~ 1.0
    float tintStrength = tint / 50.0;              // -1.0 ~ 1.0

    float tempR = 1.0 + tempStrength * 0.25;
    float tempG = 1.0 + tempStrength * 0.05;
    float tempB = 1.0 - tempStrength * 0.30;

    float tintR = 1.0 + tintStrength * 0.20;
    float tintG = 1.0 - tintStrength * 0.15;
    float tintB = 1.0 + tintStrength * 0.20;

    float rScale = tempR * tintR;
    float gScale = tempG * tintG;
    float bScale = tempB * tintB;

    // BT.709 亮度保持
    float lumaScale = rScale * 0.2126 + gScale * 0.7152 + bScale * 0.0722;
    float normFactor = 1.0 / lumaScale;

    return color * float3(rScale * normFactor, gScale * normFactor, bScale * normFactor);
}
```
- 色温正→暖（R↑, B↓），负→冷（R↓, B↑）
- 色调正→洋红（R↑, B↑, G↓），负→绿（R↓, B↓, G↑）
- **亮度保持**：用 BT.709 luma 系数归一化，调整色温色调时不会改变亮度
- 在线性空间操作

**Core Image 后备**：
```swift
// 使用 CITemperatureAndTint 原生滤镜
let baseTemp: CGFloat = 6500  // D65 标准白光
let tempDelta = -tempStrength * 3500
let targetTemp = baseTemp + tempDelta
let targetTint = tintStrength * 100
filter.neutral = CIVector(x: baseTemp, y: 0)
filter.targetNeutral = CIVector(x: targetTemp, y: targetTint)
```

---

### 3.2 Tint（色调）

| 属性 | 值 |
|---|---|
| 范围 | -50 ~ +50 |
| 默认 | 0 |
| UI 图标 | paintpalette.fill |

与 Temperature 共用同一个 `applyTemperatureTint` 函数（见 3.1）。tint 控制绿/洋红轴。

---

### 3.3 Saturation（饱和度）

| 属性 | 值 |
|---|---|
| 范围 | -50 ~ +50 |
| 默认 | 0 |
| UI 图标 | drop.fill |

**Swift → Uniforms 映射**：
```swift
uniforms.saturation = Float(max(0, 1.0 + adjustments.saturation / 100.0))  // 0.5 ~ 1.5
```

**Metal 算法**（applySaturation, FilmShaders.metal:342-345）：
```metal
float3 applySaturation(float3 color, float saturation) {
    float luma = luminance(color);
    return mix(float3(luma), color, saturation);
}
```
- 在 luma 和原始颜色之间线性插值
- `saturation=1.0` → 不变化
- `saturation=0.0` → 灰度
- `saturation>1.0` → 超过原始饱和度（最高 1.5）
- 在线性空间操作

---

### 3.4 Clarity（清晰度）

| 属性 | 值 |
|---|---|
| 范围 | -50 ~ +50 |
| 默认 | 0 |
| UI 图标 | eye.fill |

**Swift → Uniforms 映射**：
```swift
uniforms.clarity = Float(adjustments.clarity)  // -50 ~ 50
```

**Metal 算法**（applyClarity, FilmShaders.metal:454-471）：
```metal
float3 applyClarity(float3 color, float clarity) {
    float luma = luminance(color);
    float amount = clarity / 50.0;
    float midtoneMask = 1.0 - smoothstep(0.18, 0.48, abs(luma - 0.5));

    if (clarity > 0.0) {
        // 增强局部对比度
        float3 punch = (color - 0.5) * (1.0 + amount * 0.42) + 0.5;
        float3 richer = mix(punch, applySaturation(punch, 1.0 + amount * 0.10), 0.4);
        return saturate(mix(color, richer, midtoneMask));
    } else if (clarity < 0.0) {
        // 柔化
        float softenAmount = abs(amount);
        float3 muted = mix(color, float3(luma), softenAmount * 0.22);
        float3 flatter = (muted - 0.5) * (1.0 - softenAmount * 0.22) + 0.5;
        return saturate(mix(color, flatter, midtoneMask));
    }
    return color;
}
```
- 只影响中间调区域（luma 接近 0.5）
- 正值 = 局部对比增强 + 轻微饱和度提升
- 负值 = 柔化 + 轻微去饱和
- `midtoneMask` 控制在 luma 0.18-0.48 范围内的中间调

---

### 3.5 Sharpness（锐化）

| 属性 | 值 |
|---|---|
| 范围 | -50 ~ +50 |
| 默认 | 0 |

**Swift → Uniforms 映射**：
```swift
uniforms.sharpness = Float(adjustments.sharpness)  // -50 ~ 50
```

**Metal 算法**（applySharpness, FilmShaders.metal:604-626）：
```metal
float3 applySharpness(float3 color, texture2d<float> sourceTexture,
                      sampler textureSampler, float2 texCoord,
                      float2 imageSize, float sharpness) {
    float2 texel = 1.0 / imageSize;

    // 4 邻域平均值作为模糊层
    float3 left = srgbToLinear(sourceTexture.sample(... -texel.x ...));
    float3 right = srgbToLinear(... +texel.x ...);
    float3 up = srgbToLinear(... -texel.y ...);
    float3 down = srgbToLinear(... +texel.y ...);
    float3 blur = (left + right + up + down) * 0.25;

    if (sharpness > 0.0) {
        // 反锐化掩膜（Unsharp Mask）
        float amount = sharpness / 50.0 * 0.28;
        return saturate(color + (color - blur) * amount);
    }
    // 负值 = 高斯模糊（邻域平均）
    float amount = abs(sharpness) / 50.0 * 0.36;
    return mix(color, blur, amount);
}
```
- 锐化：原图 + (原图 - 模糊层) × 强度，即反锐化掩膜
- 负值 → 原图和模糊层混合，实现柔焦效果
- 采样在 sRGB→Linear 空间操作

**Core Image 后备**：
```swift
// 锐化
image.applyingFilter("CIUnsharpMask", parameters: [
    kCIInputRadiusKey: 0.8 + value / 50.0 * 1.2,
    kCIInputIntensityKey: 0.18 + value / 50.0 * 0.42
])
// 柔化
image.applyingFilter("CIGaussianBlur", parameters: [
    kCIInputRadiusKey: abs(value) / 50.0 * 1.8
])
```

---

## 四、HSL（8 色带 × 3 参数）

选择颜色通道后调整色相/饱和/明度。

### 数据结构

```swift
// 红/橙/黄/绿 → hsl[Hue/Sat/Lum]A
// 青/蓝/紫/洋红 → hsl[Hue/Sat/Lum]B
var hslRedHue: Double = 0     // -180 ~ 180
var hslRedSaturation: Double = 0  // -100 ~ 100
var hslRedLuminance: Double = 0   // -100 ~ 100
// ...同上 for orange, yellow, green, cyan, blue, purple, magenta
```

### Metal 算法

**色带遮罩**（hueBandMask, FilmShaders.metal:366-370）：
```metal
float hueBandMask(float hueDegrees, float centerDegrees) {
    float delta = abs(fract((hueDegrees - centerDegrees) / 360.0 + 0.5) - 0.5) * 360.0;
    return 1.0 - smoothstep(8.0, 50.0, delta);
}
```
- 在色环上以 `centerDegrees` 为中心的 `8°-50°` 过渡带
- 每个色带覆盖约 50° 范围的色相，8° 内完全选中，8°-50° 渐变过渡

**HSL 调整**（applyHSLBand, FilmShaders.metal:371-384）：
```metal
float3 applyHSLBand(float3 color, float centerDegrees, float hueShift,
                     float saturationShift, float luminanceShift) {
    float3 hsv = rgbToHsv(saturate(color));
    float mask = hueBandMask(hsv.x * 360.0, centerDegrees);

    // 色相偏移（在色环上旋转）
    hsv.x = fract(hsv.x + (hueShift / 360.0) * mask);
    // 饱和度缩放
    hsv.y = clamp(hsv.y * (1.0 + saturationShift / 100.0 * mask), 0.0, 1.0);

    float3 shifted = hsvToRgb(hsv);
    // 明度偏移
    shifted += (luminanceShift / 100.0) * 0.28 * mask;
    return saturate(shifted);
}
```
- RGB→HSV 转换 → 按遮罩调整 → HSV→RGB 转换
- `mask` 控制调整量的区域权重
- 在 sRGB 空间操作

---

## 五、色调（Split Toning）— 5 个滑块

| 属性 | 范围 | 默认 |
|---|---|---|
| splitShadowHue | 0~360 | 220（蓝色区） |
| splitShadowSaturation | 0~100 | 0 |
| splitHighlightHue | 0~360 | 40（橙色区） |
| splitHighlightSaturation | 0~100 | 0 |
| splitBalance | -50~50 | 0 |

**Metal 算法**（applySplitToning, FilmShaders.metal:386-408）：
```metal
float3 applySplitToning(float3 color, float shadowHue, float shadowSaturation,
                         float highlightHue, float highlightSaturation, float balance) {
    float luma = luminance(srgbToLinear(color));

    // Balance 偏移分割点
    float balanceOffset = balance / 50.0 * 0.22;
    float shadowMask = 1.0 - smoothstep(0.18 + balanceOffset, 0.62 + balanceOffset, luma);
    float highlightMask = smoothstep(0.38 + balanceOffset, 0.82 + balanceOffset, luma);

    // 阴影染色（乘法混合）
    float3 shadowColor = hueToRgb(shadowHue);
    float3 highlightColor = hueToRgb(highlightHue);

    color = mix(color, color * shadowColor, shadowMask * shadowSaturation / 100.0 * 0.35);
    color = mix(color, 1.0 - (1.0 - color) * (1.0 - highlightColor),
                highlightMask * highlightSaturation / 100.0 * 0.24);

    return saturate(color);
}
```
- 阴影染色：乘法混合（颜色×阴影色），使暗部染上选定色相
- 高光染色：Screen 混合，使亮部染上选定色相
- Balance 控制阴影/高光的分割点（默认以 luma 0.38-0.62 为过渡区）
- `hueToRgb` 将色相角度转成 RGB 颜色向量

---

## 六、效果（Effects）— 6 个滑块

### 6.1 Opacity / 胶片强度

| 属性 | 值 |
|---|---|
| 范围 | 0~100 |
| 默认 | 100 |

**Swift → Uniforms**：
```swift
uniforms.opacity = Float(adjustments.opacity / 100.0)  // 0.0 ~ 1.0
```

**Metal**（Fragment shader 末尾）：
```metal
if (uniforms.opacity < 0.999) {
    float3 originalColor = originalTex.sample(textureSampler, in.texCoord).rgb;
    color = mix(originalColor, color, uniforms.opacity);
}
```
- `opacity=100` → 完全显示胶片效果
- `opacity=0` → 完全显示原图
- 使用 `originalTex`（原始纹理）直接在 GPU 端混合，无需回读

### 6.2 Soft Glow（柔光）

| 属性 | 值 |
|---|---|
| 范围 | 0~100 |
| 默认 | 0 |
| UI 图标 | sparkles |

**算法**：DeepGlow 径向采样（见 [FilmShaders.metal:543-602](Shaders/FilmShaders.metal#L543-L602)）
- 16 方向 × 4 采样 = 64 点径向卷积
- 亮度加权：`weight = 1.0 + luma * 1.5`（高光区扩散更明显）
- Blur 层提饱和：`mix(gray, blurColor, 1.3)` 防止发灰
- Screen 混合回原图
- 最终压暗 -0.02 + 微对比 1.05

**Core Image 后备**：
```swift
image.applyingFilter("CIBloom", parameters: [
    kCIInputRadiusKey: 4.0 + normalizedStrength * 18.0,
    kCIInputIntensityKey: normalizedStrength * 0.42
])
```

### 6.3 Halation（红色光晕）

| 属性 | 值 |
|---|---|
| 范围 | 0~100 |
| 默认 | 0 |

**Metal 算法**（applyAdjustHalation, FilmShaders.metal:628-691）：
- 5×5 Gaussian blur → 提取高光（smoothstep 0.72-0.98）
- 红色染色（1.34, 0.46, 0.24）
- Screen 混合回原图

### 6.4 Fade（褪色）

| 属性 | 值 |
|---|---|
| 范围 | 0~100 |
| 默认 | 0 |

**Metal 算法**（applyAdjustFade, FilmShaders.metal:410-419）：
```metal
float warmAmount = saturate(warmth / 100.0);
float3 coolBase = float3(0.84, 0.88, 0.94);  // 冷褪色
float3 warmBase = float3(0.98, 0.91, 0.82);   // 暖褪色
float3 fadeColor = mix(coolBase, warmBase, warmAmount);
return mix(color, fadeColor, fade / 100.0 * 0.34);
```
- 在原始颜色和褪色色之间混合（最大 34%）
- 褪色色由 `fadeWarmth` 控制在冷暖之间插值

### 6.5 Fade Warmth（褪色冷暖）

| 属性 | 值 |
|---|---|
| 范围 | 0~100 |
| 默认 | 50 |

与 Fade 共用同一个函数（见 6.4）。0=冷褪色（蓝灰），100=暖褪色（橙灰）。

### 6.6 Vignette（暗角）

| 属性 | 值 |
|---|---|
| 范围 | -100~+100 |
| 默认 | 0 |
| UI 图标 | inset.filled.rectangle |

**Metal 算法**（applyVignette, FilmShaders.metal:523-536）：
```metal
float2 center = texCoord - float2(0.5);
float dist = length(center);
float edgeMask = smoothstep(0.35, 0.9, dist);

if (strength >= 0.0) {
    // 暗角：边缘乘法压暗
    float darken = 1.0 - edgeMask * strength;
    return saturate(color * darken);
}
// 负值 = 边缘提亮（镜头补偿）
float lift = abs(strength) * edgeMask * 0.22;
float3 lifted = 1.0 - (1.0 - color) * (1.0 - float3(lift));
return saturate(lifted);
```
- 从画面中心（dist=0）到边缘（dist=0.5）渐变
- `smoothstep(0.35, 0.9, dist)` 使暗角从 35%-90% 半径过渡
- 正值 = 暗角，负值 = 边缘提亮（vignette 反转）

---

## 七、颗粒（Grain）— 4 个滑块

### 7.1 Grain Intensity（颗粒强度）

| 属性 | 值 |
|---|---|
| 范围 | 0~100 |
| 默认 | 0 |

```swift
uniforms.grainIntensity = Float(adjustments.grain / 100.0)  // 0~1
```

### 7.2 Grain Size（颗粒大小）

| 属性 | 值 |
|---|---|
| 范围 | 0~100 |
| 默认 | 50 |

```swift
uniforms.grainSize = Float(adjustments.grainSize / 100.0)  // 0~1
```

### 7.3 Grain Roughness（颗粒粗糙度）

| 属性 | 值 |
|---|---|
| 范围 | 0~100 |
| 默认 | 50 |

```swift
uniforms.grainRoughness = Float(adjustments.grainRoughness / 100.0)  // 0~1
```

### 7.4 Grain Color（彩色颗粒）

| 属性 | 值 |
|---|---|
| 范围 | 0~100 |
| 默认 | 0 |

```swift
uniforms.grainColor = Float(adjustments.grainColor / 100.0)  // 0~1
```

### Metal 算法（applyGrain, FilmShaders.metal:474-520）

```
双层噪声 + 亮度衰减：
  fineUV = texCoord * sizeScale * 0.8          // 细颗粒（高频）
  coarseUV = texCoord * sizeScale * 0.4         // 粗颗粒（低频）

  细颗粒：hash2 × 2 层叠加
  粗颗粒：hash2 × 2 层叠加（不同频率）

  grain = fineGrain * fineWeight + coarseGrain * coarseWeight
  grain = sign(grain) * pow(|grain|, roughness)  // 粗糙度整形
  grain = grain / (1 + |grain|)                  // Soft clamp

  highlightFactor = 1 - smoothstep(0, highlightReduction, luma)
  grain *= highlightFactor                        // 高光区减少颗粒

  // mode=2 时 RGB 各通道独立噪声
  if (mode==2 && colorVariance>0) {
      三通道独立噪声 → mix(单色颗粒, 彩色颗粒, colorVariance)
  }

  color += grain * intensity * 0.3
```

- `grainSize` 控制 `sizeScale` 缩放，值越大颗粒越粗
- `grainRoughness` 控制颗粒分布曲线的形状（0.72-1.25 指数）
- `grainColor` 控制单色→彩色颗粒的混合比例
- `highlightReduction` 控制高光区颗粒衰减程度（ADJUST pass 固定 0.5）

---

## 八、Swift ↔ Metal Uniform 数据流

### AdjustUniforms 结构体（Swift 侧）

```swift
struct AdjustUniforms {
    var exposure: Float = 0.0        // -1.0 ~ 1.0
    var contrast: Float = 1.0        // 0.5 ~ 1.5
    var saturation: Float = 1.0      // 0.5 ~ 1.5
    var highlights: Float = 0.0      // -50 ~ 50
    var shadows: Float = 0.0         // -50 ~ 50
    var whites: Float = 0.0          // -50 ~ 50
    var blacks: Float = 0.0          // -50 ~ 50
    var temperature: Float = 0.0     // -50 ~ 50
    var tint: Float = 0.0            // -50 ~ 50
    var clarity: Float = 0.0         // -50 ~ 50
    var sharpness: Float = 0.0       // -50 ~ 50
    var softGlow: Float = 0.0        // 0 ~ 1
    var vignette: Float = 0.0        // -1 ~ 1
    var grainIntensity: Float = 0.0  // 0 ~ 1
    var grainSoftness: Float = 0.5
    var grainSize: Float = 0.5
    var grainRoughness: Float = 0.5
    var grainColor: Float = 0.0
    var opacity: Float = 1.0         // 0 ~ 1
    var time: Float = 0.0
    var halation: Float = 0.0        // 0 ~ 100
    var bloom: Float = 0.0
    var fade: Float = 0.0
    var fadeWarmth: Float = 50.0
    var splitShadowHue: Float = 220.0
    var splitShadowSaturation: Float = 0.0
    var splitHighlightHue: Float = 40.0
    var splitHighlightSaturation: Float = 0.0
    var splitBalance: Float = 0.0
    var hslHueA: SIMD4<Float>        // red, orange, yellow, green
    var hslHueB: SIMD4<Float>        // cyan, blue, purple, magenta
    var hslSatA: SIMD4<Float>
    var hslSatB: SIMD4<Float>
    var hslLumA: SIMD4<Float>
    var hslLumB: SIMD4<Float>
    var useSoftGlow: Int32 = 0
    var useGrain: Int32 = 0
    var useVignette: Int32 = 0
}
```

### Uniforms 映射（MetalFilmProcessor.swift:527-595）

```swift
// 每个 AdjustmentParams 属性到 AdjustUniforms 的映射：
uniforms.exposure   = Float(adjustments.exposure / 50.0)           // ±50 → ±1.0
uniforms.contrast   = Float(1.0 + adjustments.contrast / 100.0)   // ±50 → 0.5~1.5
uniforms.saturation = Float(max(0, 1.0 + adjustments.saturation / 100.0))
uniforms.temperature = Float(adjustments.temperature)              // 直接传递
uniforms.tint        = Float(adjustments.tint)
uniforms.softGlow    = Float(adjustments.softGlow / 100.0)         // 0~100 → 0~1
uniforms.opacity     = Float(adjustments.opacity / 100.0)          // 0~100 → 0~1
uniforms.grainIntensity = Float(adjustments.grain / 100.0)
uniforms.grainSize   = Float(adjustments.grainSize / 100.0)
uniforms.grainRoughness = Float(adjustments.grainRoughness / 100.0)
uniforms.grainColor  = Float(adjustments.grainColor / 100.0)
uniforms.vignette    = Float(adjustments.vignette / 100.0)         // ±100 → ±1

// 条件开关
uniforms.useSoftGlow = (softGlow > 0 || bloom > 0) ? 1 : 0
uniforms.useGrain    = grain > 0 ? 1 : 0
uniforms.useVignette = abs(vignette) > 0 ? 1 : 0
```

---

## 九、管线调用时序

```
用户拖动滑块
  │
  ┌─↓────────────────────────────────────────────┐
  │ $adjustments.throttle(50ms)                   │
  │ 在 RunLoop.main 上节流，丢弃中间值             │
  └──────────────────────────────────────────────┘
  │
  ┌─↓────────────────────────────────────────────┐
  │ processImage()                                │
  │ 1. 取消上一个 Task                            │
  │ 2. processingGeneration++                     │
  │ 3. 创建新 Task.detached                       │
  └──────────────────────────────────────────────┘
  │
  ┌─↓────────────────────────────────────────────┐
  │ MetalFilmProcessor.processImage()             │
  │ → needsFilmUpdate?                            │
  │   YES: applyFilmEffect() ← 不触发（只预设时）  │
  │   NO:  跳过 Film pass                         │
  │ → applyAdjustEffect() ← 每次都运行            │
  └──────────────────────────────────────────────┘
  │
  ┌─↓────────────────────────────────────────────┐
  │ fragmentAdjustShader                          │
  │ filmSimulatedTex[index 0] → 处理 → processedTex│
  └──────────────────────────────────────────────┘
  │
  ┌─↓────────────────────────────────────────────┐
  │ getResultImage()                              │
  │ GPU 纹理回读到 CPU → UIImage                  │
  └──────────────────────────────────────────────┘
  │
  ↓
  MainActor.run { processedImage = result }
```

---

## 十、关键设计原则

1. **双通道分离** — 胶片模拟（重）和 ADJUST 调整（轻）在两个不同的 shader 中，前者缓存在 `filmSimulatedTexture`，后者读取它作为输入
2. **线性空间处理** — 所有曝光/对比/色温/色调操作都在 Linear 空间，sRGB→Linear→处理→Linear→sRGB
3. **亮度保持** — 色温/色调调整用 BT.709 luma 归一化，调整时不会改变亮度
4. **条件渲染** — Metal shader 中用 `if` 跳过值为 0/默认的参数，减少冗余计算
5. **节流** — Combine `.throttle(50ms)` 确保滑块拖动期间不会过载
6. **粒度隔离** — 调光/颜色/HSL/色调/效果/颗粒各模块独立，可在 shader 中单独开启/关闭
