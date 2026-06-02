# Filab 胶片预设 — 底层逻辑与完整数据

## 一、渲染管线总览

```
                       原图输入
                          │
               ┌──────────┴──────────┐
               │                     │
          Metal 路径            Core Image 路径（后备）
               │                     │
     ┌─────────┴────────┐            │
     │ Pass 1: Film     │            │
     │ 胶片模拟          │            │
     │ 只在预设切换时运行 │            │
     └─────────┬────────┘            │
               │                     │
     ┌─────────┴────────┐            │
     │ Pass 2: Adjust   │            │
     │ ADJUST 滑块参数   │            │
     │ 每次都运行        │            │
     └─────────┬────────┘            │
               │                     │
     ┌─────────┴────────┐            │
     │ 最终输出          │            │
     └──────────────────┘            │
               │                     │
               └──────────┬──────────┘
                          │
                       结果图像
```

### 关键设计原则
- **双通道分离**：Film pass（重）和 Adjust pass（轻）解耦
- **缓存机制**：`filmSimulatedTexture` 缓存胶片结果，滑块拖动只跑 Adjust pass
- **needsFilmUpdate 标志**：切换预设→true，触发 Film pass；调滑块→false，跳过 Film pass

---

## 二、胶片 Pass 处理步骤（按顺序）

```
sRGB 输入
  │
  1. sRGB → Linear
  2. WhiteBalance — RGB 乘数（色温/色调转 RGB scale）
  3. ColorMatrix — 3×3 矩阵乘法（模拟胶片色彩响应）
  4. Linear → sRGB（曲线在 sRGB 空间操作）
  5. Master Tone Curve — 主色调曲线（线性插值）
  6. RGB Curves — 分通道曲线（可选，R/G/B 独立）
  7. sRGB → Linear
  8. Exposure — exp2 乘法
  9. Contrast — S-curve
  10. Temperature/Tint — 亮度保持算法
  11. Highlights/Shadows — 按亮度区域调整
  12. Clarity — 局部对比度增强
  13. Saturation — 饱和度
  14. Monochrome — 黑白转换
  15. Linear → sRGB
  16. Soft Glow — 柔光/bloom
  17. Vignette — 暗角
  18. Fade — 褪色（胶片底片雾）
  19. Grain — 颗粒
  20. Bloom（预设 bloom 配置）
  21. Opacity 混合回原图
```

### Adjust Pass 处理步骤

```
从 filmSimulatedTexture 读取
  │
  sRGB → Linear
  → Exposure → Contrast → Temperature/Tint
  → Highlights/Shadows → Whites/Blacks
  → Clarity → Sharpness → Saturation
  → sRGB
  → HSL（8 色带）
  → Split Toning
  → Soft Glow / Halation / Fade / Vignette / Grain
  → Opacity 混合回原图
```

---

## 三、核心算法细节

### 3.1 Tone Curve（色调曲线）

线性插值，`[0-255]` 空间操作：

```
输入 x（0-1）→ x * 255 → 找到所在线段 → 线性插值 → / 255 输出
```

关键：输入输出都在 sRGB 空间。曲线产生胶片的 "toe"（暗部抬起）和 "shoulder"（高光压缩）。

### 3.2 ColorMatrix（色彩矩阵）

Row-major 存储，传给 GPU 时转置为 column-major：

```
// Portra 400 矩阵（row-major）
[0.95, 0.035, 0.015,  ← R 输出 = 0.95R + 0.035G + 0.015B
 0.015, 0.975, 0.01,  ← G 输出 = 0.015R + 0.975G + 0.01B
 0.035, 0.055, 0.91]  ← B 输出 = 0.035R + 0.055G + 0.91B

// 转置后传给 Metal（column-major）
[0.95, 0.015, 0.035,  ← 第一列
 0.035, 0.975, 0.055, ← 第二列
 0.015, 0.01, 0.91]   ← 第三列
```

### 3.3 WhiteBalance（白平衡）

```
temperature > 0（暖）：R *= 1+temp*0.3, B *= 1-temp*0.3
temperature < 0（冷）：R *= 1+temp*0.3, B *= 1-temp*0.3  // temp 负值
tint > 0（洋红）：R += tint*0.15, B += tint*0.15, G -= tint*0.1
tint < 0（绿）：G += |tint|*0.15, R -= |tint|*0.1, B -= |tint|*0.1
```

### 3.4 Temperature/Tint（色温/色调）

亮度保持算法（BT.709 luma 系数归一化）：

```
tempStrength = temperature / 50     // -1 ~ 1
tintStrength = tint / 50            // -1 ~ 1

R = (1 + temp*0.25) * (1 + tint*0.20)
G = (1 + temp*0.05) * (1 - tint*0.15)
B = (1 - temp*0.30) * (1 + tint*0.20)

lumaScale = R*0.2126 + G*0.7152 + B*0.0722
normFactor = 1 / lumaScale

result = color * (R/G/B * normFactor)
```

### 3.5 Grain（颗粒）

双层噪声 + 亮度衰减：

```
细颗粒：texCoord * sizeScale * 0.8（高频）
粗颗粒：texCoord * sizeScale * 0.4（低频）

highlightFactor = 1 - smoothstep(0, highlightReduction, luma)
grain *= highlightFactor

mode=1（单色）：luminance grain
mode=2（彩色）：RGB 各通道独立噪声
```

### 3.6 Halation（红色光晕 — CineStill 特有）

```
两步高斯模糊（横向+纵向）
→ 提取高光（threshold=0.85）
→ 红色染色（1.8, 0.4, 0.1）
→ Screen 混合回原图
```

### 3.7 Soft Glow（柔光 — DeepGlow 算法）

```
16 方向 × 4 采样 = 64 点径向采样
亮度权重：weight = 1.0 + luma * 1.5
Blur 层提饱和：mix(gray, blurColor, 1.3)
Screen 混合 → 压暗 -0.02 → 微对比 1.05
```

### 3.8 sRGB <-> Linear 转换

```c
// sRGB → Linear
c ≤ 0.04045 : c / 12.92
c > 0.04045 : ((c + 0.055) / 1.055)^2.4

// Linear → sRGB
c ≤ 0.0031308 : c * 12.92
c > 0.0031308 : 1.055 * c^(1/2.4) - 0.055
```

### 3.9 Luminance（亮度 — 线性空间）

```
luma = R*0.2126 + G*0.7152 + B*0.0722
```

---

## 四、完整预设数据

### 4.1 Kodak Portra 400

| 参数 | 值 |
|---|---|
| ID | portra400 |
| 类别 | Kodak |
| WhiteBalance | temp=0.08, tint=0.015（暖调） |
| ColorMatrix（row-major） | 0.95, 0.035, 0.015 / 0.015, 0.975, 0.01 / 0.035, 0.055, 0.91 |
| Tone Curve | [0,8], [48,55], [128,132], [210,225], [255,242] |
| Saturation | 0.96 |
| Contrast | 0.96 |
| Grain | intensity=0.04, softness=1.0, mode=spectral(1) |
| Vignette | 0.06 |
| Fade | 0.04 |
| Halation | 无 |
| Bloom | 无 |

### 4.2 Kodak Gold 200

| 参数 | 值 |
|---|---|
| ID | gold200 |
| 类别 | Kodak |
| WhiteBalance | temp=0.14, tint=0.02（暖） |
| ColorMatrix（row-major） | 1.035, 0.025, -0.06 / 0.055, 0.94, 0.005 / 0.015, 0.065, 0.92 |
| Tone Curve | 同 Portra [0,8], [48,55], [128,132], [210,225], [255,242] |
| Saturation | 1.08 |
| Contrast | 1.02 |
| Grain | 同 Portra |
| Vignette | 0.10 |
| Fade | 0.07 |

### 4.3 Fuji Pro 400H

| 参数 | 值 |
|---|---|
| ID | fuji400h |
| 类别 | Fuji |
| WhiteBalance | temp=-0.06, tint=-0.02（偏冷偏绿） |
| ColorMatrix（row-major） | 0.90, 0.065, 0.035 / 0.015, 0.965, 0.02 / 0.015, 0.085, 0.90 |
| Tone Curve | [0,5], [55,52], [128,138], [205,235], [255,248] |
| Red Curve | [0,0], [128,122], [255,235]（压缩高光红） |
| Blue Curve | [0,22], [128,130], [255,245]（提亮阴影蓝） |
| Saturation | 0.94 |
| Contrast | 0.92 |
| Bloom | sigma=13, strength=0.25 |
| Grain | intensity=0.06, softness=0.8, mode=spectral(1) |
| Vignette | 0.04 |
| Fade | 0.04 |

### 4.4 Fuji Velvia 50

| 参数 | 值 |
|---|---|
| ID | velvia50 |
| 类别 | Fuji |
| WhiteBalance | temp=0, tint=0（中性） |
| ColorMatrix（row-major） | 1.1, -0.05, -0.05 / -0.05, 1.1, -0.05 / -0.05, -0.05, 1.1 |
| Tone Curve | linear [0,0], [64,64], [128,128], [192,192], [255,255] |
| Saturation | 1.38 |
| Contrast | 1.1 |
| Grain | intensity=0.08, softness=0.6, mode=spectral(1) |
| Vignette | 0.05 |
| Fade | 0.0 |

### 4.5 CineStill 800T

| 参数 | 值 |
|---|---|
| ID | cinestill800t |
| 类别 | CineStill |
| WhiteBalance | temp=-0.18, tint=-0.02（冷，钨丝灯平衡） |
| ColorMatrix（row-major） | 0.95, 0.03, 0.02 / 0.02, 0.92, 0.06 / 0.08, 0.12, 0.80 |
| Tone Curve | [0,0], [52,38], [135,148], [205,228], [255,245] |
| Saturation | 0.95 |
| Contrast | 1.05 |
| Halation | threshold=0.85, strength=0.6, colorShift=[1.8,0.4,0.1], sigmaSmall=8, sigmaLarge=20 |
| Grain | intensity=0.08, softness=0.5, mode=chromatic(2), colorVariance=0.3 |
| Vignette | 0.14 |
| Fade | 0.03 |

### 4.6 CineStill 50D

| 参数 | 值 |
|---|---|
| ID | cinestill50d |
| 类别 | CineStill |
| WhiteBalance | temp=0, tint=0（中性） |
| ColorMatrix（row-major） | 0.95, 0.03, 0.02 / 0.02, 0.96, 0.02 / 0.03, 0.08, 0.89 |
| Tone Curve | 同 CineStill [0,0], [52,38], [135,148], [205,228], [255,245] |
| Saturation | 0.95 |
| Contrast | 1.0 |
| Halation | threshold=0.9, strength=0.3, colorShift=[1.2,0.9,0.7], sigmaSmall=4, sigmaLarge=12 |
| Grain | 同 Portra |
| Vignette | 0.1 |
| Fade | 0.03 |

### 4.7 Ilford HP5 Plus（黑白）

| 参数 | 值 |
|---|---|
| ID | hp5 |
| 类别 | B&W |
| WhiteBalance | temp=0, tint=0（中性） |
| ColorMatrix（row-major） | 0.3, 0.59, 0.11 / 0.3, 0.59, 0.11 / 0.3, 0.59, 0.11（亮度矩阵，三行相同） |
| Tone Curve | [0,0], [50,35], [128,138], [195,230], [255,255] |
| Saturation | 0.0（黑白） |
| Contrast | 1.08 |
| Grain | intensity=0.15, softness=0.45, mode=spectral(1) |
| Vignette | 0.08 |
| Fade | 0.0 |

### 4.8 Ilford Delta 3200（黑白）

| 参数 | 值 |
|---|---|
| ID | delta3200 |
| 类别 | B&W |
| WhiteBalance | temp=0, tint=0（中性） |
| ColorMatrix（row-major） | 0.3, 0.59, 0.11 / 0.3, 0.59, 0.11 / 0.3, 0.59, 0.11（同 HP5） |
| Tone Curve | [0,5], [50,40], [128,135], [200,225], [255,250] |
| Saturation | 0.0（黑白） |
| Contrast | 1.15 |
| Grain | intensity=0.25, softness=0.3, mode=spectral(1) |
| Vignette | 0.2 |
| Fade | 0.05 |

### 4.9 Polaroid

| 参数 | 值 |
|---|---|
| ID | polaroid |
| 类别 | Vintage |
| WhiteBalance | temp=0.15, tint=0.1（暖调） |
| ColorMatrix（row-major） | 1.05, 0.05, 0.00 / 0.00, 0.95, 0.05 / 0.05, 0.10, 0.85 |
| Tone Curve | [0,38], [55,72], [128,140], [255,232] |
| Blue Curve | [0,0], [255,215]（整体压低蓝色） |
| Saturation | 0.88 |
| Contrast | 0.92 |
| Bloom | sigma=28, strength=0.55 |
| Grain | intensity=0.10, softness=0.5, mode=chromatic(2), colorVariance=0.35 |
| Vignette | 0.0 |
| Fade | 0.16 |

### 4.10 Kodachrome

| 参数 | 值 |
|---|---|
| ID | kodachrome |
| 类别 | Vintage |
| WhiteBalance | temp=0.05, tint=0.0 |
| ColorMatrix（row-major） | 1.05, -0.02, -0.03 / -0.05, 1.08, -0.03 / 0.02, -0.05, 1.03 |
| Tone Curve | [0,2], [64,58], [128,132], [200,225], [255,248] |
| Saturation | 1.15 |
| Contrast | 1.05 |
| Grain | intensity=0.04, softness=0.5, mode=spectral(1) |
| Vignette | 0.1 |
| Fade | 0.02 |

### 4.11 Ricoh GR

| 参数 | 值 |
|---|---|
| ID | ricohgr |
| 类别 | Ricoh |
| WhiteBalance | temp=-0.04, tint=-0.03（偏冷偏绿） |
| ColorMatrix | identity（无矩阵变换） |
| Tone Curve | [0,0], [40,18], [128,148], [200,245], [255,255] |
| Saturation | 1.22 |
| Contrast | 1.08 |
| Grain | intensity=0.12, softness=0.2, mode=spectral(1) |
| Vignette | 0.32 |
| Fade | 0.0 |

### 4.12 Lomography

| 参数 | 值 |
|---|---|
| ID | lomo |
| 类别 | Vintage |
| WhiteBalance | temp=0.1, tint=0.15（暖调） |
| ColorMatrix（row-major） | 1.1, 0.0, -0.1 / 0.05, 0.95, 0.0 / -0.05, 0.1, 0.95 |
| Tone Curve | 同 Polaroid [0,38], [55,72], [128,140], [255,232] |
| Saturation | 1.2 |
| Contrast | 1.2 |
| Halation | threshold=0.9, strength=0.3, colorShift=[1.2,0.9,0.7]（subtle） |
| Grain | intensity=0.15, softness=0.4, mode=chromatic(2), colorVariance=0.2 |
| Vignette | 0.35 |
| Fade | 0.1 |

### 4.13 Kodak Ektar 100

| 参数 | 值 |
|---|---|
| ID | ektar100 |
| 类别 | Kodak |
| WhiteBalance | temp=0.08, tint=0.0 |
| ColorMatrix（row-major） | 1.18, -0.06, -0.06 / -0.06, 1.18, -0.06 / -0.06, -0.06, 1.18 |
| Tone Curve | [0,0], [45,32], [120,125], [190,235], [255,255] |
| Saturation | 1.32 |
| Contrast | 1.18 |
| Grain | intensity=0.06, softness=0.55, mode=spectral(1) |
| Vignette | 0.12 |
| Fade | 0.03 |

### 4.14 Fuji Astia 100F

| 参数 | 值 |
|---|---|
| ID | astia100f |
| 类别 | Fuji |
| WhiteBalance | temp=-0.06, tint=0.08 |
| ColorMatrix（row-major） | 0.96, 0.04, 0.0 / 0.01, 0.97, 0.02 / 0.0, 0.04, 0.96 |
| Tone Curve | [0,12], [64,75], [128,132], [192,188], [255,242] |
| Saturation | 0.92 |
| Contrast | 0.88 |
| Bloom | sigma=8, strength=0.15（subtle） |
| Grain | 同 Fuji |
| Vignette | 0.06 |
| Fade | 0.02 |

### 4.15 Fuji Classic Chrome

| 参数 | 值 |
|---|---|
| ID | classicChrome |
| 类别 | Fuji X |
| WhiteBalance | temp=-0.08, tint=0.05 |
| ColorMatrix（row-major） | 0.95, 0.03, 0.02 / 0.02, 0.92, 0.06 / 0.08, 0.10, 0.82 |
| Tone Curve | [0,12], [60,48], [128,122], [200,205], [255,235] |
| Saturation | 0.85 |
| Contrast | 1.15 |
| Bloom | sigma=8, strength=0.15（subtle） |
| Grain | intensity=0.07, softness=0.6, mode=spectral(1) |
| Vignette | 0.15 |
| Fade | 0.05 |

### 4.16 Panasonic LUMIX Natural

| 参数 | 值 |
|---|---|
| ID | panasonicNatural |
| 类别 | Panasonic |
| WhiteBalance | temp=0, tint=0（中性） |
| ColorMatrix（row-major） | 1.03, 0.0, -0.03 / 0.0, 1.02, 0.0 / -0.03, 0.0, 1.03 |
| Tone Curve | linear |
| Saturation | 1.02 |
| Contrast | 1.06 |
| Bloom | subtle |
| Grain | intensity=0.03, softness=0.7, mode=spectral(1) |
| Vignette | 0.0 |
| Fade | 0.0 |

### 4.17 Panasonic LUMIX Vivid

| 参数 | 值 |
|---|---|
| ID | panasonicVivid |
| 类别 | Panasonic |
| WhiteBalance | temp=0.05, tint=0.0 |
| ColorMatrix（row-major） | 1.12, -0.04, -0.04 / -0.04, 1.12, -0.04 / -0.04, -0.04, 1.12 |
| Tone Curve | 同 Ektar |
| Saturation | 1.28 |
| Contrast | 1.22 |
| Bloom | subtle |
| Grain | intensity=0.04, softness=0.65, mode=spectral(1) |
| Vignette | 0.08 |
| Fade | 0.0 |

### 4.18 Hasselblad Natural

| 参数 | 值 |
|---|---|
| ID | hasselbladNatural |
| 类别 | Hasselblad |
| WhiteBalance | temp=0, tint=0（中性） |
| ColorMatrix（row-major） | 1.0, 0.02, -0.02 / -0.01, 1.0, 0.01 / -0.02, 0.01, 1.0 |
| Tone Curve | [0,5], [64,68], [128,135], [200,208], [255,250] |
| Saturation | 1.06 |
| Contrast | 1.0 |
| Grain | intensity=0.02, softness=0.8, mode=spectral(1) |
| Vignette | 0.0 |
| Fade | 0.0 |

### 4.19 Ricoh Positive Film（强化版）

| 参数 | 值 |
|---|---|
| ID | ricohPositive |
| 类别 | Ricoh |
| WhiteBalance | temp=-0.06, tint=-0.08 |
| ColorMatrix | identity |
| Tone Curve | 同 Ricoh GR [0,0], [40,18], [128,148], [200,245], [255,255] |
| Saturation | 1.42 |
| Contrast | 1.18 |
| Grain | 同 Ricoh |
| Vignette | 0.88 |
| Fade | 0.0 |

---

## 五、共享曲线数据

### ToneCurve 预定义

| 名称 | 控制点 |
|---|---|
| linear | [0,0], [64,64], [128,128], [192,192], [255,255] |
| portra | [0,8], [48,55], [128,132], [210,225], [255,242] |
| ektar | [0,0], [45,32], [120,125], [190,235], [255,255] |
| fuji | [0,5], [55,52], [128,138], [205,235], [255,248] |
| fujiR | [0,0], [128,122], [255,235] |
| fujiB | [0,22], [128,130], [255,245] |
| classicChrome | [0,12], [60,48], [128,122], [200,205], [255,235] |
| cineStill | [0,0], [52,38], [135,148], [205,228], [255,245] |
| astia | [0,12], [64,75], [128,132], [192,188], [255,242] |
| ilford | [0,0], [50,35], [128,138], [195,230], [255,255] |
| polaroid | [0,38], [55,72], [128,140], [255,232] |
| polaroidB | [0,0], [255,215] |
| ricoh | [0,0], [40,18], [128,148], [200,245], [255,255] |
| hasselblad | [0,5], [64,68], [128,135], [200,208], [255,250] |

### GrainConfig 预定义

| 名称 | intensity | softness | mode | colorVariance | fineSoftness | fineWeight | coarseWeight | highlightReduction |
|---|---|---|---|---|---|---|---|---|
| none | 0 | 0.5 | none(0) | 0 | 0.22 | 0.45 | 0.2 | 0.5 |
| portra | 0.04 | 1.0 | spectral(1) | 0 | 0.24 | 0.45 | 0.2 | 0.6 |
| fuji | 0.06 | 0.8 | spectral(1) | 0 | 0.22 | 0.45 | 0.2 | 0.6 |
| cineStill | 0.08 | 0.5 | chromatic(2) | 0.3 | 0.22 | 0.42 | 0.2 | 0.5 |
| polaroid | 0.10 | 0.5 | chromatic(2) | 0.35 | 0.26 | 0.42 | 0.22 | 0.5 |
| ilford | 0.15 | 0.45 | spectral(1) | 0 | 0.20 | 0.5 | 0.25 | 0.5 |
| ricoh | 0.12 | 0.2 | spectral(1) | 0 | 0.18 | 0.45 | 0.22 | 0.5 |

### BloomConfig 预定义

| 名称 | sigma | strength |
|---|---|---|
| fuji | 13.0 | 0.25 |
| polaroid | 28.0 | 0.55 |
| subtle | 8.0 | 0.15 |

### HalationConfig 预定义

| 名称 | threshold | strength | colorShift | sigmaSmall | sigmaLarge |
|---|---|---|---|---|---|
| cineStill | 0.85 | 0.6 | [1.8, 0.4, 0.1] | 8.0 | 20.0 |
| subtle | 0.90 | 0.3 | [1.2, 0.9, 0.7] | 4.0 | 12.0 |

---

## 六、ADJUST 参数模型

```swift
AdjustmentParams {
    // 调光
    opacity: Double = 100      // 0-100, 胶片强度
    exposure: Double = 0       // -50~50
    contrast: Double = 0       // -50~50
    highlights: Double = 0     // -50~50
    shadows: Double = 0        // -50~50
    whites: Double = 0         // -50~50
    blacks: Double = 0         // -50~50

    // 颜色
    temperature: Double = 0    // -50~50
    tint: Double = 0           // -50~50
    saturation: Double = 0     // -50~50
    sharpness: Double = 0      // -50~50
    clarity: Double = 0        // -50~50

    // HSL（8 色相带 × 3 参数）
    hsl[Hue/Sat/Lum]Red, Orange, Yellow, Green, Cyan, Blue, Purple, Magenta

    // 色调分离
    splitShadowHue: 220
    splitShadowSaturation: 0
    splitHighlightHue: 40
    splitHighlightSaturation: 0
    splitBalance: 0

    // 效果
    softGlow: Double = 0       // 0-100
    halation: Double = 0       // 0-100
    bloom: Double = 0          // 0-100
    vignette: Double = 0       // -100~100
    fade: Double = 0           // 0-100
    fadeWarmth: Double = 50    // 0-100

    // 颗粒
    grain: Double = 0          // 0-100
    grainSize: Double = 50     // 0-100
    grainRoughness: Double = 50 // 0-100
    grainColor: Double = 0     // 0-100
}
```

---

## 七、文件索引

| 文件 | 内容 |
|---|---|
| [Models/FilmPreset.swift](Models/FilmPreset.swift) | 所有预设数据定义、AdjustmentParams、ColorMatrix/WhiteBalance/GrainConfig/ToneCurve 等模型 |
| [Shaders/FilmShaders.metal](Shaders/FilmShaders.metal) | Metal 着色器：fragmentFilmShader（胶片 pass）、fragmentAdjustShader（adjust pass）、所有辅助函数 |
| [Utilities/MetalFilmProcessor.swift](Utilities/MetalFilmProcessor.swift) | Metal 管线调度：纹理管理、双通道渲染、uniform 传递 |
| [ViewModels/FilmEditorViewModel.swift](ViewModels/FilmEditorViewModel.swift) | 编辑状态管理、Core Image 后备路径、预设选择逻辑 |
| [AGENT.md](AGENT.md) | 项目架构文档、渲染模型说明、已知限制 |
| [ADVICE.md](ADVICE.md) | 后续优化建议 |

---

## 八、关于数据公式的说明

**ColorMatrix → Metal 传值**：
```swift
// Swift 定义（row-major）
values = [r1, g1, b1, r2, g2, b2, r3, g3, b3]

// toSIMD() 转置为 column-major
float3x3(
    SIMD3<Float>(Float(values[0]), Float(values[3]), Float(values[6])),  // 第一列 = r1, r2, r3
    SIMD3<Float>(Float(values[1]), Float(values[4]), Float(values[7])),  // 第二列 = g1, g2, g3
    SIMD3<Float>(Float(values[2]), Float(values[5]), Float(values[8]))   // 第三列 = b1, b2, b3
)
```

**ToneCurve → Metal 传值**：曲线点在 `[0-255]` 范围定义，shader 内 normalize 到 `[0-1]` 后线性插值。

**强度混合**：预设效果强度通过 `opacity` 控制，在 Core Image 路径中白平衡/矩阵/对比/饱和度均按 `opacity%` 混合到中性值。
