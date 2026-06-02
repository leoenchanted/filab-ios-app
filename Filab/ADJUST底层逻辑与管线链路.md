# ADJUST 滑块底层逻辑与完整管线链路

## 一、文件结构与数据流架构

### 1.1 涉及文件

| 文件 | 角色 | 关键职责 |
|------|------|---------|
| `Views/EditorView.swift` | UI 层 | 绘制所有滑块，绑定 `adjustments` 属性 |
| `ViewModels/FilmEditorViewModel.swift` | ViewModel | `$adjustments.throttle(50ms)` 节流，调用 `processImage()` |
| `Models/FilmPreset.swift` | 数据模型 | `AdjustmentParams` 结构体定义（40+ 属性） |
| `Utilities/MetalFilmProcessor.swift` | CPU→GPU 桥接 | Uniforms 映射、双 Pass 调度、纹理管理 |
| `Shaders/AdjustShaders.metal` | GPU 入口 | `fragmentAdjustShader` — ADJUST 核心处理 |
| `Shaders/ShaderHelpers.metal` | GPU 辅助 | 所有算法实现（曲线、HSL、颗粒等 30+ 函数） |
| `Shaders/ShaderShared.h` | 共用声明 | `AdjustUniforms` 结构体、函数 prototypes |

### 1.2 完整数据链路

```
EditorView.swift（滑块 UI）
  │  @Binding var adjustments: AdjustmentParams
  │
  ▼
FilmEditorViewModel.swift（ViewModel）
  │  $adjustments.throttle(for: .milliseconds(50), latest: true)
  │  → processImage() → metalProcessor.processImage()
  │
  ▼
MetalFilmProcessor.swift（CPU→GPU）
  │  1. 读取 AdjustmentParams（40+ Double 值）
  │  2. Clamp 校验（防止越界）
  │  3. 数学映射（÷25、÷100、/100.0 等）
  │  4. 填充 AdjustUniforms 结构体
  │  5. memcpy → MTLBuffer（GPU 可读）
  │  6. setFragmentBuffer(index:0) → GPU
  │
  ▼
AdjustShaders.metal（GPU 入口）
  │  fragmentAdjustShader(
  │    texture[0] = filmSimulatedTex,
  │    texture[1] = originalTex,
  │    buffer[0]  = AdjustUniforms,
  │    sampler[0] = linear
  │  )
  │
  ▼
ShaderHelpers.metal（算法执行）
  │  applySCurve() → applyToneRange() → applyClarity() → ...
  │  每个函数读取 AdjustUniforms 中的对应字段
  │
  ▼
return float4(saturate(color), alpha) → processedTexture
  │
  ▼
MetalFilmProcessor.getResultImage()（GPU→CPU 回读）
  │  processedTexture.getBytes() → CGImage → UIImage
  │
  ▼
EditorView 显示 processedImage
```

---

## 二、AdjustmentParams → AdjustUniforms 映射总表

### 2.1 定义位置

```swift
// Models/FilmPreset.swift:399 — 所有滑块参数的原始定义
struct AdjustmentParams: Equatable, Codable {
    var exposure: Double = 0        // -50 ~ +50
    var contrast: Double = 0        // -50 ~ +50
    // ...共 40+ 属性
}

// Utilities/MetalFilmProcessor.swift:838 — GPU 端 uniform 结构体
struct AdjustUniforms {
    var exposure: Float = 0.0       // Metal 用浮点
    // ...顺序必须和 .metal 文件完全一致
}

// Shaders/ShaderShared.h:76 — Metal 端 uniform 结构体
struct AdjustUniforms {
    float exposure;
    // ...完全对齐 Swift 侧
}
```

### 2.2 滑块 → Uniforms 映射详解

每条记录格式：
> **滑块名** | UI 范围 | Uniforms 映射公式 | Metal 范围 | Metal 变量

| # | 滑块 | UI 范围 | Swift 映射代码 | GPU 值域 | GPU 变量 |
|---|------|---------|---------------|---------|---------|
| 1 | **Exposure** | -50 ~ +50 | `e.clamped(to: -50...50) / 25.0` | -2.0 ~ +2.0 | `uniforms.exposure` |
| 2 | **Contrast** | -50 ~ +50 | `1.0 + c.clamped(to: -50...50) / 100.0` | 0.5 ~ 1.5 | `uniforms.contrast` |
| 3 | **Saturation** | -50 ~ +50 | `min(2.0, max(0.0, 1.0 + s/100.0))` | 0.5 ~ 1.5 | `uniforms.saturation` |
| 4 | **Highlights** | -50 ~ +50 | `highlights.clamped(to: -50...50)` | -50 ~ +50 | `uniforms.highlights` |
| 5 | **Shadows** | -50 ~ +50 | `shadows.clamped(to: -50...50)` | -50 ~ +50 | `uniforms.shadows` |
| 6 | **Whites** | -50 ~ +50 | `whites.clamped(to: -50...50)` | -50 ~ +50 | `uniforms.whites` |
| 7 | **Blacks** | -50 ~ +50 | `blacks.clamped(to: -50...50)` | -50 ~ +50 | `uniforms.blacks` |
| 8 | **Temperature** | -50 ~ +50 | `temperature.clamped(to: -50...50)` | -50 ~ +50 | `uniforms.temperature` |
| 9 | **Tint** | -50 ~ +50 | `tint.clamped(to: -50...50)` | -50 ~ +50 | `uniforms.tint` |
| 10 | **Clarity** | -50 ~ +50 | `clarity.clamped(to: -50...50)` | -50 ~ +50 | `uniforms.clarity` |
| 11 | **Sharpness** | -50 ~ +50 | `sharpness.clamped(to: -50...50)` | -50 ~ +50 | `uniforms.sharpness` |
| 12 | **Soft Glow** | 0 ~ 100 | `softGlow / 100.0` | 0.0 ~ 1.0 | `uniforms.softGlow` |
| 13 | **Vignette** | -100 ~ +100 | `vignette.clamped(to: -100...100) / 100.0` | -1.0 ~ +1.0 | `uniforms.vignette` |
| 14 | **Opacity** | 0 ~ 100 | `opacity.clamped(to: 0...100) / 100.0` | 0.0 ~ 1.0 | `uniforms.opacity` |
| 15 | **Halation** | 0 ~ 100 | `halation.clamped(to: 0...100)` | 0.0 ~ 100.0 | `uniforms.halation` |
| 16 | **Bloom** | 0 ~ 100 | `bloom`（直传） | 0.0 ~ 100.0 | `uniforms.bloom` |
| 17 | **Fade** | 0 ~ 100 | `fade.clamped(to: 0...100)` | 0.0 ~ 100.0 | `uniforms.fade` |
| 18 | **Fade Warmth** | 0 ~ 100 | `fadeWarmth.clamped(to: 0...100)` | 0.0 ~ 100.0 | `uniforms.fadeWarmth` |
| 19 | **Split Shadow Hue** | 0 ~ 360 | `splitShadowHue.clamped(to: 0...360)` | 0.0 ~ 360.0 | `uniforms.splitShadowHue` |
| 20 | **Split Shadow Sat** | 0 ~ 100 | `splitShadowSaturation.clamped(to: 0...100)` | 0.0 ~ 100.0 | `uniforms.splitShadowSaturation` |
| 21 | **Split Highlight Hue** | 0 ~ 360 | `splitHighlightHue.clamped(to: 0...360)` | 0.0 ~ 360.0 | `uniforms.splitHighlightHue` |
| 22 | **Split Highlight Sat** | 0 ~ 100 | `splitHighlightSaturation.clamped(to: 0...100)` | 0.0 ~ 100.0 | `uniforms.splitHighlightSaturation` |
| 23 | **Split Balance** | -50 ~ +50 | `splitBalance.clamped(to: -50...50)` | -50 ~ +50 | `uniforms.splitBalance` |
| 24-31 | **HSL Hue × 8** | -180 ~ +180 | 各 `hslXxxHue.clamped(to: -180...180)` | -180 ~ +180 | `uniforms.hslHueA/B` |
| 32-39 | **HSL Sat × 8** | -100 ~ +100 | 各 `hslXxxSat.clamped(to: -100...100)` | -100 ~ +100 | `uniforms.hslSatA/B` |
| 40-47 | **HSL Lum × 8** | -100 ~ +100 | 各 `hslXxxLum.clamped(to: -100...100)` | -100 ~ +100 | `uniforms.hslLumA/B` |
| — | **Grain Intensity** | 0 ~ 100 | `grain.clamped(to: 0...100) / 100.0` | 0.0 ~ 1.0 | `uniforms.grainIntensity` |
| — | **Grain Size** | 0 ~ 100 | `grainSize.clamped(to: 0...100) / 100.0` | 0.0 ~ 1.0 | `uniforms.grainSize` |
| — | **Grain Softness** | 0 ~ 100 | `0.25 + grainSize/100.0 * 0.45` | 0.25 ~ 0.70 | `uniforms.grainSoftness` |
| — | **Grain Roughness** | 0 ~ 100 | `grainRoughness.clamped(to: 0...100) / 100.0` | 0.0 ~ 1.0 | `uniforms.grainRoughness` |
| — | **Grain Color** | 0 ~ 100 | `grainColor.clamped(to: 0...100) / 100.0` | 0.0 ~ 1.0 | `uniforms.grainColor` |

### 2.3 条件开关（条件渲染优化）

```swift
uniforms.useSoftGlow = (adjustments.softGlow > 0 || adjustments.bloom > 0) ? 1 : 0
uniforms.useGrain    = adjustments.grain > 0 ? 1 : 0
uniforms.useVignette = abs(adjustments.vignette) > 0 ? 1 : 0
uniforms.time        = grainTime  // 每帧递增 0.5，驱动颗粒动画
```

---

## 三、滑块底层算法详解

### 3.1 Exposure（曝光）

**位置**：[AdjustShaders.metal:22-25](Shaders/AdjustShaders.metal#L22-L25) | 辅助函数：无，直接 `exp2`

```
线性空间操作
color *= exp2(uniforms.exposure)

exposure=  0 → exp2( 0) = 1.00× → 不变
exposure=+25 → exp2(+1) = 2.00× → +1 EV 提亮一倍
exposure=-25 → exp2(-1) = 0.50× → -1 EV 压暗一半
exposure=+50 → exp2(+2) = 4.00× → +2 EV（修复后范围，原 ±1 EV）
exposure=-50 → exp2(-2) = 0.25× → -2 EV
```

- `exp2()` 是标准 EV 曝光公式，2^EV
- 线性空间操作，保持物理正确性
- 修复变更：映射从 `/ 50.0` → `/ 25.0`（±1 EV → ±2 EV）

---

### 3.2 Contrast（对比度）

**位置**：[AdjustShaders.metal:28-30](Shaders/AdjustShaders.metal#L28-L30) | 辅助函数：`applySCurve` → [ShaderHelpers.metal:143-147](Shaders/ShaderHelpers.metal#L143-L147)

```
color = (color - 0.5) * contrast + 0.5

contrast=1.0 → color = color           → 不变
contrast=1.5 → 亮部更亮，暗部更暗，差值放大 1.5 倍
contrast=0.5 → 整体向中灰收敛
```

- S-Curve：以 0.5 为中心的线性缩放，末尾 `saturate()` 保护
- 在线性空间操作

---

### 3.3 Highlights / Shadows（高光 / 阴影）

**位置**：[AdjustShaders.metal:38-40](Shaders/AdjustShaders.metal#L38-L40) | 辅助函数：`applyToneRange` → [ShaderHelpers.metal:149-163](Shaders/ShaderHelpers.metal#L149-L163)

```
luma = dot(color, float3(0.2126, 0.7152, 0.0722))  // BT.709 亮度

// 高光因子：luma > 0.3 时逐渐激活，1.0 时完全激活
highlightFactor = smoothstep(0.3, 1.0, luma)

// 阴影因子：luma < 0.7 时逐渐激活，0.0 时完全激活
shadowFactor   = 1.0 - smoothstep(0.0, 0.7, luma)

color += highlights * highlightFactor * 0.01
color += shadows   * shadowFactor   * 0.01
```

- 加法偏移（非乘法）
- `smoothstep` 提供软过渡，避免断层
- 末尾 `saturate()` 防止颜色值越界

---

### 3.4 Whites / Blacks（白色色阶 / 黑色色阶）

**位置**：[AdjustShaders.metal:42-44](Shaders/AdjustShaders.metal#L42-L44) | 辅助函数：`applyWhitesBlacks` → [ShaderHelpers.metal:165-191](Shaders/ShaderHelpers.metal#L165-L191)

```
与 Highlights/Shadows 区别：
  Whites  → whiteMask = smoothstep(0.45, 0.92, luma)  // 仅最亮端
  Blacks  → blackMask = 1.0 - smoothstep(0.04, 0.48, luma)  // 仅最暗端

Whites > 0: Screen 混合提亮（不烧高光）
  lifted = 1.0 - (1.0 - color) * (1.0 - amount)
  color  = mix(color, lifted, whiteMask)

Whites < 0: 乘法压暗
  color *= 1.0 - whiteMask * amount

Blacks > 0: 加法提亮
  color += blackMask * amount

Blacks < 0: 乘法压暗
  color *= 1.0 - blackMask * amount
```

- Whites/Blacks 影响范围更窄、更极端（仅调整色阶端点）
- Highlights/Shadows 影响范围更宽（调整整个亮部/暗部区域）

---

### 3.5 Temperature / Tint（色温 / 色调）

**位置**：[AdjustShaders.metal:33-35](Shaders/AdjustShaders.metal#L33-L35) | 辅助函数：`applyTemperatureTint` → [ShaderHelpers.metal:299-324](Shaders/ShaderHelpers.metal#L299-L324)

```
tempStrength = temperature / 50.0    // -1.0 ~ +1.0
tintStrength = tint / 50.0           // -1.0 ~ +1.0

// 色温 RGB 缩放
tempR = 1.0 + tempStrength * 0.25    // 暖：R↑
tempG = 1.0 + tempStrength * 0.05    // 暖：G 微↑
tempB = 1.0 - tempStrength * 0.30    // 暖：B↓↓

// 色调 RGB 缩放
tintR = 1.0 + tintStrength * 0.20    // 洋红：R↑
tintG = 1.0 - tintStrength * 0.15    // 洋红：G↓
tintB = 1.0 + tintStrength * 0.20    // 洋红：B↑

// 亮度保持归一化
lumaScale = R*0.2126 + G*0.7152 + B*0.0722
normFactor = 1.0 / lumaScale
color *= float3(R, G, B) * normFactor
```

- **亮度保持核心**：`normFactor = 1.0 / (R*0.2126 + G*0.7152 + B*0.0722)`
- 色温 ±50 对应 R/B 通道 ±25%/±30% 缩放，幅度合理
- 在线性空间操作

---

### 3.6 Saturation（饱和度）

**位置**：[AdjustShaders.metal:58-60](Shaders/AdjustShaders.metal#L58-L60) | 辅助函数：`applySaturation` → [ShaderHelpers.metal:193-197](Shaders/ShaderHelpers.metal#L193-L197)

```
luma = luminance(color)
color = mix(float3(luma), color, saturation)

saturation=1.0 → color = color         → 不变
saturation=0.5 → 去饱和 50%
saturation=1.5 → 过饱和 50%（上限保护）
```

- 在亮度向量和原始颜色之间线性插值
- 下限 0.5 保证不会完全灰化，上限 1.5 防止过度饱和

---

### 3.7 Clarity（清晰度）

**位置**：[AdjustShaders.metal:47-49](Shaders/AdjustShaders.metal#L47-L49) | 辅助函数：`applyClarity` → [ShaderHelpers.metal:267-288](Shaders/ShaderHelpers.metal#L267-L288)

```
luma = luminance(color)
amount = clarity / 50.0

// 中间调遮罩：只影响 luma 接近 0.5 的区域
midtoneMask = 1.0 - smoothstep(0.18, 0.48, abs(luma - 0.5))

clarity > 0（增强）：
  punch = (color - 0.5) * (1.0 + amount * 0.42) + 0.5   // 局部对比
  richer = mix(punch, applySaturation(punch, 1.0 + amount*0.10), 0.4)  // 微提饱和
  color = mix(color, richer, midtoneMask)

clarity < 0（柔化）：
  muted = mix(color, float3(luma), softenAmount * 0.22)  // 去饱和
  flatter = (muted - 0.5) * (1.0 - softenAmount * 0.22) + 0.5  // 压平对比
  color = mix(color, flatter, midtoneMask)
```

- 区别于 Contrast：Contrast 影响全局，Clarity 只影响**中间调**
- 类似 Lightroom 的 Clarity：局部对比度增强 + 轻微提饱和

---

### 3.8 Sharpness（锐化）

**位置**：[AdjustShaders.metal:51-55](Shaders/AdjustShaders.metal#L51-L55) | 辅助函数：`applySharpness` → [ShaderHelpers.metal:309-328](Shaders/ShaderHelpers.metal#L309-L328)

```
// 4 邻域均值模糊
texel = 1.0 / imageSize
blur = (sample(left) + sample(right) + sample(up) + sample(down)) * 0.25

// 正值：反锐化掩膜（Unsharp Mask）
amount = sharpness / 50.0 * 0.55
color += (color - blur) * amount
return saturate(color)

// 负值：柔焦（混合模糊层）
amount = abs(sharpness) / 50.0 * 0.42
return mix(color, blur, amount)
```

- 锐化强度 0.55（修复后）对标 Lightroom 默认锐化（40-60%）
- 负值柔焦 0.42（修复后）比原来 0.36 更明显
- 采样在 sRGB→Linear 空间操作

---

### 3.9 HSL（8 色带 × 3 参数 = 24 参数）

**位置**：[AdjustShaders.metal:65-72](Shaders/AdjustShaders.metal#L65-L72) | 辅助函数：`applyHSLBand` → [ShaderHelpers.metal:236-255](Shaders/ShaderHelpers.metal#L236-L255)

```
// 8 色带对应的中心色相角度
Red=0°, Orange=30°, Yellow=60°, Green=120°
Cyan=180°, Blue=240°, Purple=280°, Magenta=320°

// 色带遮罩函数
hueBandMask(hueDegrees, centerDegrees):
  delta = abs(fract((hue - center) / 360 + 0.5) - 0.5) * 360
  return 1.0 - smoothstep(8.0, 50.0, delta)
  → 8° 内完全选中，8°~50° 渐变过渡，50°+ 无影响

// HSL 调整
hsv = rgbToHsv(color)
mask = hueBandMask(hsv.hue, centerDegrees)
hsv.hue += (hueShift / 360) * mask           // 色相旋转
hsv.sat *= (1.0 + satShift/100.0 * mask)     // 饱和度缩放
shifted = hsvToRgb(hsv)
shifted += (lumShift / 100.0) * 0.28 * mask  // 明度偏移
return saturate(shifted)
```

- 在 sRGB 空间操作（先转 HSV，调完转回 RGB）
- 每个色带独立计算，8 次调用累加效果

---

### 3.10 Split Toning（色调分离）

**位置**：[AdjustShaders.metal:74-79](Shaders/AdjustShaders.metal#L74-L79) | 辅助函数：`applySplitToning` → [ShaderHelpers.metal:205-229](Shaders/ShaderHelpers.metal#L205-L229)

```
// 亮度分割
balanceOffset = balance / 50.0 * 0.22
shadowMask   = 1.0 - smoothstep(0.18 + offset, 0.62 + offset, luma)
highlightMask = smoothstep(0.38 + offset, 0.82 + offset, luma)

// 阴影染色（乘法混合）
shadowColor = hueToRgb(shadowHue)
color = mix(color, color * shadowColor, shadowMask * shadowSat/100 * 0.35)

// 高光染色（Screen 混合）
highlightColor = hueToRgb(highlightHue)
color = mix(color, 1.0 - (1.0-color)*(1.0-highlightColor),
            highlightMask * highlightSat/100 * 0.24)
```

- Balance 偏移分割点：-50 → 分割点左移（更多区域被算作高光）
- 阴影染色用**乘法**（压暗区域染色），高光用**Screen**（叠加不烧）
- 在线性空间评估亮度，sRGB 空间染色

---

### 3.11 Soft Glow（柔光）

**位置**：[AdjustShaders.metal:81-87](Shaders/AdjustShaders.metal#L81-L87) | 辅助函数：`applySoftGlow` → [ShaderHelpers.metal:337-370](Shaders/ShaderHelpers.metal#L337-L370)

```
glowStrength = saturate(softGlow + bloom/100 * 0.75)

// DeepGlow 径向卷积
16 方向 × 4 质量 = 64 个采样点
每个采样：weight = 1.0 + luma * 1.5（亮度加权）
blurColor = Σ(sample × weight) / Σ(weight)

// 饱和度增强（防止发灰）
gray = luminance(blurColor)
blurColor = mix(gray, blurColor, 1.3)  // 饱和度 ×1.3

// Screen 混合
glow = 1.0 - (1.0 - color) * (1.0 - blurColor)
color = mix(color, glow, smoothstep(0, 1, amount*0.8+0.1))

// 最终微调：压暗 + 微对比
color += -0.02
color = (color - 0.5) * 1.05 + 0.5
```

- 64 点径向采样（远多于传统 13 点十字+对角线）
- 亮度加权让高光区扩散更自然
- 饱和度增强 ×1.3 防止脏白
- 时序抖动（dither）防止闪烁

---

### 3.12 Halation（红色光晕）

**位置**：[AdjustShaders.metal:89-93](Shaders/AdjustShaders.metal#L89-L93) | 辅助函数：`applyAdjustHalation` → [ShaderHelpers.metal:372-399](Shaders/ShaderHelpers.metal#L372-L399)

```
normalized = saturate(strength / 100.0) * 0.30
radius = 1.5 + normalized * 11.0

// 5×5 高光提取高斯卷积
for y in -2...2, x in -2...2:
  mask = smoothstep(0.72, 0.98, luminance(sample))
  weight = 1.0 / (1.0 + distance)
  glow += max(sample - 0.34, 0) * mask * weight

glow /= sumWeight
glow *= float3(1.34, 0.46, 0.24)  // 红色染色

// Screen 混合
return mix(color, 1.0 - (1.0-color)*(1.0-glow), normalized * 0.48)
```

- 模拟胶片高光溢出的红光晕（类似 Cinestill 效果）
- 红色染色因子 (1.34, 0.46, 0.24)

---

### 3.13 Fade / Fade Warmth（褪色）

**位置**：[AdjustShaders.metal:95](Shaders/AdjustShaders.metal#L95) | 辅助函数：`applyAdjustFade` → [ShaderHelpers.metal:233-244](Shaders/ShaderHelpers.metal#L233-L244)

```
warmAmount = saturate(warmth / 100.0)
coolBase   = float3(0.84, 0.88, 0.94)  // 冷褪色（蓝灰）
warmBase   = float3(0.98, 0.91, 0.82)  // 暖褪色（橙灰）
fadeColor  = mix(coolBase, warmBase, warmAmount)

color = mix(color, fadeColor, fade/100.0 * 0.34)
// 最大混合 34%
```

- Fade=0 时跳过（`if (fade <= 0.001) return color`）
- Warmth=0→冷褪色（模拟过期胶片），Warmth=100→暖褪色（模拟老照片）

---

### 3.14 Vignette（暗角）

**位置**：[AdjustShaders.metal:98-100](Shaders/AdjustShaders.metal#L98-L100) | 辅助函数：`applyVignette` → [ShaderHelpers.metal:257-269](Shaders/ShaderHelpers.metal#L257-L269)

```
dist = length(texCoord - 0.5)
edgeMask = smoothstep(0.35, 0.9, dist)

strength ≥ 0（暗角）:
  color *= 1.0 - edgeMask * strength
strength < 0（逆暗角/边缘提亮）:
  lift = abs(strength) * edgeMask * 0.22
  color = 1.0 - (1.0 - color) * (1.0 - lift)
```

- `smoothstep(0.35, 0.9, dist)` 控制暗角从画面 35%~90% 半径开始渐出
- 正值=暗角（乘法压暗），负值=边缘提亮（Screen 混合）

---

### 3.15 Grain（颗粒）

**位置**：[AdjustShaders.metal:103-111](Shaders/AdjustShaders.metal#L103-L111) | 辅助函数：`applyGrain` → [ShaderHelpers.metal:131-230](Shaders/ShaderHelpers.metal#L131-L230)

```
// 双层噪声结构
sizeScale = 1000.0 / mix(0.5, 2.4, grainSize)

fineUV = texCoord * sizeScale * 0.8     // 细颗粒（高频）
fineGrain = 2 层 hash2 噪声叠加 → 归一化到 -1~1

coarseUV = texCoord * sizeScale * 0.4   // 粗颗粒（低频）
coarseGrain = 2 层 hash2 噪声叠加 → 归一化到 -1~1

// 粗细混合 + 粗糙度整形
grain = fineGrain * fineWeight + coarseGrain * coarseWeight
grain = sign(grain) * pow(|grain|, roughness)  // 粗糙度指数
grain = grain / (1.0 + |grain|)               // Soft clamp

// 高光减少
grain *= 1.0 - smoothstep(0, highlightReduction, luma)

// 彩色颗粒（mode=2）
R/G/B 三通道独立 hash2 噪声
color += mix(float3(grain), chromaticNoise, colorVariance) * intensity * 0.3
```

- 全部用 `hash2` 伪随机函数（无外部纹理依赖）
- ADJUST pass 固定参数：fineWeight=0.22, coarseWeight=0.2, highlightReduction=0.5
- `grainSoftness` 在 ADJUST 中用 `0.25 + grainSize/100*0.45`（0.25~0.70）

---

### 3.16 Opacity（混合回原图）

**位置**：[AdjustShaders.metal:114-117](Shaders/AdjustShaders.metal#L114-L117)

```
if (uniforms.opacity < 0.999) {
    originalColor = originalTex.sample(textureSampler, texCoord).rgb
    color = mix(originalColor, color, uniforms.opacity)
}
```

- `originalTex` = 原始输入纹理（texture index 1）
- 在 GPU 端直接混合，无需回读 CPU
- 值为 100 时跳过（`< 0.999` 判断）

---

## 四、Uniform 结构体内存布局

### 4.1 AdjustUniforms（Swift 侧 → MetalFilmProcessor.swift:838）

```swift
private struct AdjustUniforms {
    // 顺序必须和 Metal AdjustUniforms 完全一致！
    var exposure: Float = 0.0       //  0: 偏移 0
    var contrast: Float = 1.0       //  1: 偏移 4
    var saturation: Float = 1.0     //  2: 偏移 8
    var highlights: Float = 0.0     //  3: 偏移 12
    var shadows: Float = 0.0        //  4: 偏移 16
    var whites: Float = 0.0         //  5: 偏移 20
    var blacks: Float = 0.0         //  6: 偏移 24
    var temperature: Float = 0.0    //  7: 偏移 28
    var tint: Float = 0.0           //  8: 偏移 32
    var clarity: Float = 0.0        //  9: 偏移 36
    var sharpness: Float = 0.0      // 10: 偏移 40
    var softGlow: Float = 0.0       // 11: 偏移 44
    var vignette: Float = 0.0       // 12: 偏移 48
    var grainIntensity: Float = 0.0 // 13: 偏移 52
    var grainSoftness: Float = 0.5  // 14: 偏移 56
    var grainSize: Float = 0.5      // 15: 偏移 60
    var grainRoughness: Float = 0.5 // 16: 偏移 64
    var grainColor: Float = 0.0     // 17: 偏移 68
    var opacity: Float = 1.0        // 18: 偏移 72
    var time: Float = 0.0           // 19: 偏移 76
    var halation: Float = 0.0       // 20: 偏移 80
    var bloom: Float = 0.0          // 21: 偏移 84
    var fade: Float = 0.0           // 22: 偏移 88
    var fadeWarmth: Float = 50.0    // 23: 偏移 92
    var splitShadowHue: Float = 220.0        // 24: 偏移 96
    var splitShadowSaturation: Float = 0.0   // 25: 偏移 100
    var splitHighlightHue: Float = 40.0      // 26: 偏移 104
    var splitHighlightSaturation: Float = 0.0 // 27: 偏移 108
    var splitBalance: Float = 0.0   // 28: 偏移 112
    var _pad0: Float = 0.0          // 29: 偏移 116
    var _pad1: Float = 0.0          // 30: 偏移 120
    var _pad2: Float = 0.0          // 31: 偏移 124
    var hslHueA: SIMD4<Float>       // 32: 偏移 128 (16字节)
    var hslHueB: SIMD4<Float>       // 36: 偏移 144
    var hslSatA: SIMD4<Float>       // 40: 偏移 160
    var hslSatB: SIMD4<Float>       // 44: 偏移 176
    var hslLumA: SIMD4<Float>       // 48: 偏移 192
    var hslLumB: SIMD4<Float>       // 52: 偏移 208
    var useSoftGlow: Int32 = 0      // 56: 偏移 224
    var useGrain: Int32 = 0         // 57: 偏移 228
    var useVignette: Int32 = 0      // 58: 偏移 232
    var _padI: Int32 = 0            // 59: 偏移 236
    // 总大小: 240 字节
}
```

### 4.2 Metal 侧对应（ShaderShared.h:76）

```metal
struct AdjustUniforms {
    // 完全相同的字段顺序和类型
    float exposure;
    float contrast;
    float saturation;
    float highlights;
    float shadows;
    float whites;
    float blacks;
    float temperature;
    float tint;
    float clarity;
    float sharpness;
    float softGlow;
    float vignette;
    float grainIntensity;
    float grainSoftness;
    float grainSize;
    float grainRoughness;
    float grainColor;
    float opacity;
    float time;
    float halation;
    float bloom;
    float fade;
    float fadeWarmth;
    float splitShadowHue;
    float splitShadowSaturation;
    float splitHighlightHue;
    float splitHighlightSaturation;
    float splitBalance;
    float _pad0;
    float _pad1;
    float _pad2;
    float4 hslHueA;
    float4 hslHueB;
    float4 hslSatA;
    float4 hslSatB;
    float4 hslLumA;
    float4 hslLumB;
    int useSoftGlow;
    int useGrain;
    int useVignette;
    int _padI;
};
```

> **关键**：Swift 和 Metal 的 struct 必须**完全字节对齐**。Swift 用 `MemoryLayout<AdjustUniforms>.size` 分配 buffer，Metal 直接读取。如果字段顺序或对齐不一致，GPU 会读到错位的数据。

---

## 五、管线时序与条件渲染

### 5.1 一次滑块拖动的事件序列

```
时间线
│
├─ 用户开始拖动滑块
│
├─ 0ms    adjustments.exposure = 12.5  （第 1 次变化）
│
├─ 12ms   adjustments.exposure = 18.7  （第 2 次变化，被 throttle 丢弃）
│
├─ 37ms   adjustments.exposure = 25.0  （第 3 次变化，被 throttle 丢弃）
│
├─ 50ms ─┤ throttle 发射最新值（25.0）
│        ├→ processImage()
│        │   → MetalFilmProcessor.processImage()
│        │   → applyAdjustEffect()
│        │   → 填充 AdjustUniforms
│        │   → 调度 GPU → fragmentAdjustShader
│        │   → processedTexture → UIImage
│        │   → MainActor.run { processedImage = result }
│
├─ 63ms   adjustments.exposure = 31.2  （继续拖动）
│
├─ 100ms ─┤ throttle 发射最新值
│        ├→ processImage() ...
│
├─ 用户停止拖动
│
└─ 最终值触发下一次 processImage()
```

### 5.2 GPU 条件渲染（跳过无效计算）

```
// AdjustShaders.metal 中的条件判断：
if (abs(exposure) > 0.0001)             → Exposure
if (abs(contrast - 1.0) > 0.0001)       → Contrast
if (abs(temp) > 0.001 || abs(tint) > 0.001) → Temp/Tint
if (abs(highlights) > 0.001 || abs(shadows) > 0.001) → H/S
if (abs(whites) > 0.001 || abs(blacks) > 0.001)     → W/B
if (abs(clarity) > 0.001)               → Clarity
if (abs(sharpness) > 0.001)             → Sharpness
if (abs(saturation - 1.0) > 0.0001)     → Saturation
if (useSoftGlow > 0)                    → Soft Glow
if (halation > 0.001)                   → Halation
if (useVignette > 0)                    → Vignette
if (useGrain > 0 && grainIntensity > 0.001) → Grain
if (opacity < 0.999)                    → Opacity blend
```

每个 `if` 保护一组操作，当滑块值为 0/默认时完全跳过，减少 GPU 运算。

### 5.3 双 Pass 架构（胶片 Pass + ADJUST Pass）

```
processImage()
  │
  ├─ Pass 1（胶片模拟）← 仅在切换预设时触发
  │   fragmentFilmShader（FilmShaders.metal）
  │   sourceTexture → filmSimulatedTexture（缓存结果）
  │   ⚡ 包含：白平衡、色彩矩阵、曲线、Bloom、Fade、颗粒等
  │
  └─ Pass 2（ADJUST）← 每次滑块变化都触发
      fragmentAdjustShader（AdjustShaders.metal）
      filmSimulatedTexture → processedTexture
      ⚡ 轻量化，仅处理滑块参数
```

---

## 六、Clamp 防护体系

| 防护层级 | 位置 | 作用 |
|---------|------|------|
| Swift clamp | `MetalFilmProcessor.swift:529-598` | 所有参数送 GPU 前 clamp 到有效范围 |
| GPU saturate | `AdjustShaders.metal:119` | `return float4(saturate(color), alpha)` 最终保护 |
| 函数内 saturate | 各 `apply*` 函数末尾 | 防止中间溢出传播到后续步骤 |
| 条件跳过 | 各 `if (abs(...) > threshold)` | 值无效时不执行操作 |

---

## 七、关键设计要点

1. **线性空间处理**：Exposure/Contrast/Temp/Tint/Highlights/Shadows/Whites/Blacks/Clarity/Saturation 都在 Linear 空间操作；HSL/SplitToning/SoftGlow/Fade/Vignette/Grain 在 sRGB 空间
2. **亮度保持**：Temperature/Tint 用 BT.709 luma 系数归一化，调整色温和色调时不改变整体亮度
3. **双 Pass 架构**：胶片模拟（重）缓存到 `filmSimulatedTexture`，ADJUST 滑块（轻）仅调 Adjust pass，保证滑块拖动流畅度
4. **50ms 节流**：Combine `.throttle(for: .milliseconds(50), latest: true)` 保证滑块拖动不超载
5. **条件渲染**：16 组 `if` 判断跳过值为 0/默认的参数，减少 GPU 空转
6. **内存安全**：所有参数送 GPU 前经过 `clamped(to:)` 校验，防止越界值导致 GPU 计算异常
7. **双纹理输入**：Adjust shader 同时接收 `filmSimulatedTex`（处理用）和 `originalTex`（opacity 混合用），避免额外回读
