import Foundation

// MARK: - Film Preset Library

extension FilmPreset {
    static let allPresets: [FilmPreset] = [
        // Kodak Portra 400 - Portrait film (based on webgl.js)
        FilmPreset(
            id: "portra400",
            name: "Portra 400",
            description: "人像首选，肤色保护",
            category: .kodak,
            thumbnail: "portra_thumb",
            scene: "人像 / 婚礼 / 户外",
            feature: "奶油色肤色 / 柔和对比 / 宽容度高",
            detail: "Portra 400 是专业人像摄影的首选胶片。它采用 T-grain 技术，提供细腻的颗粒和出色的曝光宽容度。其特点是温暖柔和的色调，特别是肤色呈现出奶油般的质感。高光部分柔和不刺眼，阴影细节丰富。适合各种光线条件，从户外自然光到室内闪光灯都能表现出色。许多摄影师习惯过曝 1 档以获得更梦幻的效果。",
            whiteBalance: WhiteBalance(temperature: 0.08, tint: 0.015),
            colorMatrix: .portra400,
            curve: .portra,
            curveR: nil,
            curveG: nil,
            curveB: nil,
            saturation: 0.96,
            contrast: 0.96,
            halation: nil,
            bloom: nil,
            grain: .portra,
            vignette: 0.06,
            fade: 0.04
        ),

        // Kodak Gold 200
        FilmPreset(
            id: "gold200",
            name: "Gold 200",
            description: "暖色调，怀旧感",
            category: .kodak,
            thumbnail: "gold_thumb",
            scene: "日常 / 旅行 / 复古",
            feature: "温暖金调 / 高饱和 / 怀旧感",
            detail: "Gold 200 是 Kodak 经典的民用胶片，以其标志性的暖色调而闻名。画面呈现出阳光明媚的金色质感，特别适合户外 daylight 拍摄。色彩饱和度高，对比度适中，能营造出 90 年代家庭相册的怀旧氛围。适合旅行记录、日常生活和复古风格摄影。在黄昏和黄金时段拍摄效果最佳。",
            whiteBalance: WhiteBalance(temperature: 0.10, tint: 0.015),
            colorMatrix: .gold200,
            curve: .portra,
            curveR: nil,
            curveG: nil,
            curveB: nil,
            saturation: 1.08,
            contrast: 1.02,
            halation: nil,
            bloom: nil,
            grain: .portra,
            vignette: 0.10,
            fade: 0.07
        ),

        // Fuji Pro 400H (based on webgl.js)
        FilmPreset(
            id: "fuji400h",
            name: "Pro 400H",
            description: "日系清新，亮部通透",
            category: .fuji,
            thumbnail: "fuji_thumb",
            scene: "日系人像 / 婚礼 / 时尚",
            feature: "通透亮部 / 柔和色调 / 阴影偏青",
            detail: "Pro 400H 是 Fuji 的专业人像胶片，以其独特的日系美学著称。亮部呈现梦幻的通透感，不会生硬过曝；阴影带有轻微的青绿色调，营造出清新的氛围。肤色呈现粉嫩质感，整体色彩柔和不张扬。非常适合日式写真、婚礼摄影和时尚人像。建议在充足光线或轻微过曝时使用。",
            whiteBalance: WhiteBalance(temperature: -0.06, tint: -0.02),
            colorMatrix: .fuji400H,
            curve: .fuji,
            curveR: .fujiR,  // Red curve: compress highlights
            curveG: nil,
            // Fuji Blue 曲线加强 shadow 蓝提升（Pro 400H 阴影冷调）
            curveB: .fujiB,
            saturation: 0.94,
            contrast: 0.92,
            halation: nil,
            bloom: .fuji,  // bloom: sigma=13, strength=0.25
            grain: .fuji,
            vignette: 0.04,
            fade: 0.04
        ),

        // Fuji Velvia 50 (simulated)
        FilmPreset(
            id: "velvia50",
            name: "Velvia 50",
            description: "高饱和，风景胶片",
            category: .fuji,
            thumbnail: "velvia_thumb",
            scene: "风景 / 自然 / 日落",
            feature: "超高饱和 / 鲜艳色彩 / 细腻颗粒",
            detail: "Velvia 50 是 Fuji 最著名的反转片，以极高的色彩饱和度著称。色彩鲜艳夺目，特别是绿色和蓝色的表现令人印象深刻。对比度高，画面锐利，非常适合风景摄影和自然摄影。50 的低感光度带来极细的颗粒。建议用于光线充足的户外场景，如山脉、森林、日落和自然风光。",
            whiteBalance: WhiteBalance(temperature: 0.0, tint: 0.0),
            colorMatrix: ColorMatrix(values: [
                1.15, -0.06, -0.06,
                -0.05, 1.08, -0.05,
                -0.06, -0.06, 1.15
            ]),
            curve: .velvia,
            curveR: nil,
            curveG: nil,
            curveB: nil,
            saturation: 1.38,
            contrast: 1.15,
            halation: nil,
            bloom: nil,
            grain: GrainConfig(
                intensity: 0.03, softness: 0.7, fineSoftness: 0.22,
                fineWeight: 0.45, coarseWeight: 0.2, highlightReduction: 0.6,
                colorVariance: 0, mode: .spectral
            ),
            vignette: 0.05,
            fade: 0.0
        ),

        // CineStill 800T (based on webgl.js)
        FilmPreset(
            id: "cinestill800t",
            name: "800T",
            description: "电影感，红色光晕",
            category: .cinestill,
            thumbnail: "cinestill_thumb",
            scene: "夜景 / 钨丝灯 / 电影",
            feature: "钨丝灯平衡 / 红色光晕 / 电影质感",
            detail: "CineStill 800T 是将电影胶片 5219 去除碳层后制成的民用版本。专为钨丝灯照明设计，在夜景和室内人工光源下呈现独特的电影感。高光亮部会产生标志性的红色光晕（Halation）效果，极具氛围感。适合夜间街头摄影、霓虹灯场景、室内人像和电影感视频截图风格。",
            whiteBalance: WhiteBalance(temperature: -0.18, tint: -0.02),  // colder tungsten balance with a slight green/cyan pull
            colorMatrix: .cineStill800T,
            curve: ToneCurve(points: [
                [0, 0], [52, 42], [135, 148], [205, 228], [255, 245]
            ]),
            curveR: nil,
            curveG: nil,
            curveB: nil,
            saturation: 1.0,
            contrast: 1.05,
            halation: .cineStill,
            bloom: nil,
            grain: .cineStill,
            vignette: 0.14,
            fade: 0.03
        ),

        // CineStill 50D (Daylight)
        FilmPreset(
            id: "cinestill50d",
            name: "50D",
            description: "日光电影胶片",
            category: .cinestill,
            thumbnail: "cinestill50d_thumb",
            scene: "日光户外 / 电影 / 视频",
            feature: "日光平衡 / 电影色调 / 低感光度",
            detail: "CineStill 50D 源自电影胶片 5203，是日光平衡的低感光度胶片。呈现中性的电影色调，色彩真实自然，不会过于饱和。50 的低感光度提供极细颗粒和丰富细节。适合在充足日光下拍摄，可获得电影级别的画面质感。适合人像、风景和视频截图风格的摄影。",
            whiteBalance: WhiteBalance(temperature: 0.02, tint: -0.015),
            colorMatrix: ColorMatrix(values: [
                0.95, 0.03, 0.02,
                0.02, 0.96, 0.02,
                0.02, 0.04, 0.93
            ]),
            curve: .cineStill,
            curveR: nil,
            curveG: nil,
            curveB: nil,
            saturation: 0.95,
            contrast: 1.0,
            halation: HalationConfig(
                threshold: 0.90, strength: 0.3,
                colorShift: [1.15, 0.85, 0.75],
                sigmaSmall: 4.0, sigmaLarge: 12.0
            ),
            bloom: nil,
            grain: .portra,
            vignette: 0.1,
            fade: 0.03
        ),

        // Ilford HP5 Plus (based on webgl.js)
        FilmPreset(
            id: "hp5",
            name: "HP5 Plus",
            description: "经典黑白，高对比",
            category: .blackWhite,
            thumbnail: "hp5_thumb",
            scene: "纪实 / 街头 / 人像",
            feature: "经典黑白 / 丰富层次 / 推片友好",
            detail: "HP5 Plus 是 Ilford 最经典的黑白胶片之一，有着悠久的历史。颗粒结构经典，影调层次丰富，从深黑到纯白过渡自然。400 的感光度适合大多数拍摄场景，并且可以推片到 1600 或 3200 使用。适合纪实摄影、街头摄影和人像摄影，是黑白胶片入门的绝佳选择。",
            whiteBalance: WhiteBalance.neutral,
            colorMatrix: ColorMatrix(values: [
                0.2126, 0.7152, 0.0722,
                0.2126, 0.7152, 0.0722,
                0.2126, 0.7152, 0.0722
            ]),
            curve: .ilford,
            curveR: nil,
            curveG: nil,
            curveB: nil,
            saturation: 0.0,
            contrast: 1.08,
            halation: nil,
            bloom: nil,
            grain: GrainConfig(
                intensity: 0.12, softness: 0.5, fineSoftness: 0.20,
                fineWeight: 0.5, coarseWeight: 0.25, highlightReduction: 0.5,
                colorVariance: 0, mode: .spectral
            ),
            vignette: 0.08,
            fade: 0.0
        ),

        // Ilford Delta 3200
        FilmPreset(
            id: "delta3200",
            name: "Delta 3200",
            description: "高速黑白，粗颗粒",
            category: .blackWhite,
            thumbnail: "delta_thumb",
            scene: "弱光 / 夜景 / 运动",
            feature: "超高感光度 / 粗颗粒 / 独特质感",
            detail: "Delta 3200 是 Ilford 的高感光度黑白胶片，适合极端低光环境。颗粒粗大但质感独特，呈现出强烈的复古氛围。Delta 晶体技术让颗粒更锐利，不像传统高感光度胶片那样模糊。适合夜间摄影、室内运动、舞台演出等弱光场景。推片使用时颗粒更加夸张，是很多纪实摄影师的创意选择。",
            whiteBalance: WhiteBalance.neutral,
            colorMatrix: ColorMatrix(values: [
                0.3, 0.59, 0.11,
                0.3, 0.59, 0.11,
                0.3, 0.59, 0.11
            ]),
            curve: ToneCurve(points: [
                [0, 0],
                [50, 40],
                [128, 135],
                [200, 225],
                [255, 250]
            ]),
            curveR: nil,
            curveG: nil,
            curveB: nil,
            saturation: 0.0,
            contrast: 1.15,
            halation: nil,
            bloom: nil,
            grain: GrainConfig(
                intensity: 0.25, softness: 0.3, fineSoftness: 0.26,
                fineWeight: 0.50, coarseWeight: 0.15, highlightReduction: 0.4,
                colorVariance: 0, mode: .spectral
            ),
            vignette: 0.2,
            fade: 0.0
        ),

        // Polaroid Originals (based on webgl.js)
        FilmPreset(
            id: "polaroid",
            name: "Polaroid",
            description: "复古，柔光",
            category: .vintage,
            thumbnail: "polaroid_thumb",
            scene: "日常 / 复古 / 创意",
            feature: "即影即有 / 暖调柔和 / 边框感",
            detail: "Polaroid 即影即有胶片，独特的成像风格让无数人着迷。画面柔和，对比度低，带有温暖的色调和轻微的褪色效果。成像过程的不确定性带来惊喜感，每张照片都独一无二。适合日常记录、派对聚会、创意摄影。复古的质感能瞬间带你回到 70-80 年代。",
            whiteBalance: WhiteBalance(temperature: 0.12, tint: 0.04),
            colorMatrix: .polaroid,
            curve: ToneCurve(points: [
                [0, 28], [55, 72], [128, 140], [255, 232]
            ]),
            curveR: nil,
            curveG: nil,
            curveB: .polaroidB,  // Blue curve: reduce blue overall for warm tone
            saturation: 0.88,
            contrast: 0.92,
            halation: nil,
            bloom: .polaroid,  // bloom: sigma=28, strength=0.55
            grain: .polaroid,
            vignette: 0.0,
            fade: 0.16
        ),

        // Kodachrome (simulated)
        FilmPreset(
            id: "kodachrome",
            name: "Kodachrome",
            description: "传奇胶片，鲜艳色彩",
            category: .vintage,
            thumbnail: "kodachrome_thumb",
            scene: "旅行 / 纪实 / 幻灯片",
            feature: "传奇色彩 / 高饱和 / 长保存",
            detail: "Kodachrome 是 Kodak 最著名的反转片，也是历史上最成功的彩色胶片之一。以极其鲜艳的色彩、细腻的颗粒和出色的档案稳定性著称。2009 年停产，成为一代人的记忆。Steve McCurry 的《阿富汗少女》就是使用 Kodachrome 拍摄。适合旅行、纪实和任何追求色彩冲击力的场景。",
            whiteBalance: WhiteBalance(temperature: 0.05, tint: 0.0),
            colorMatrix: ColorMatrix(values: [
                1.10, -0.04, -0.04,
                -0.05, 1.08, -0.03,
                -0.02, 0.06, 0.95
            ]),
            curve: ToneCurve(points: [
                [0, 0],
                [64, 52],
                [128, 132],
                [200, 225],
                [255, 248]
            ]),
            curveR: nil,
            curveG: nil,
            curveB: nil,
            saturation: 1.15,
            contrast: 1.12,
            halation: nil,
            bloom: nil,
            grain: GrainConfig(
                intensity: 0.04, softness: 0.5, fineSoftness: 0.22,
                fineWeight: 0.45, coarseWeight: 0.2, highlightReduction: 0.6,
                colorVariance: 0, mode: .spectral
            ),
            vignette: 0.1,
            fade: 0.02
        ),

        // Ricoh GR (based on webgl.js)
        FilmPreset(
            id: "ricohgr",
            name: "Ricoh GR",
            description: "正片模式，高对比",
            category: .ricoh,
            thumbnail: "ricoh_thumb",
            scene: "街拍 / 日常 / 快拍",
            feature: "正片色彩 / 高对比 / 锐利",
            detail: "模拟 Ricoh GR 数码相机的正片模式，深受街拍摄影师喜爱。色彩饱和度高，对比度强烈，画面锐利。略带青色调，呈现出现代都市的冷峻美感。适合街头摄影、日常随拍和需要强烈视觉风格的场景。GR 的 28mm 视角和正片色彩的组合，创造出独特的影像语言。",
            whiteBalance: WhiteBalance(temperature: -0.04, tint: -0.03),
            colorMatrix: ColorMatrix(values: [
                1.04, -0.02, -0.02,
                -0.01, 1.02, -0.01,
                -0.03, 0.02, 1.01
            ]),
            curve: .ricoh,
            curveR: nil,
            curveG: nil,
            curveB: nil,
            saturation: 1.22,
            contrast: 1.08,
            halation: nil,
            bloom: nil,
            grain: .ricoh,
            vignette: 0.24,
            fade: 0.0
        ),

        // Lomography (experimental look)
        FilmPreset(
            id: "lomo",
            name: "Lomography",
            description: "实验性，色彩漂移",
            category: .vintage,
            thumbnail: "lomo_thumb",
            scene: "创意 / 实验 / 派对",
            feature: "色彩漂移 / 暗角 / 高饱和",
            detail: "Lomography 代表一种充满实验性和玩乐精神的摄影文化。强烈的色彩漂移、夸张的暗角、不可预测的光漏效果，都是 Lomography 的标志。高饱和度和高对比度让照片充满活力和个性。这种风格鼓励摄影师抛开规则，享受摄影的乐趣。适合创意摄影、派对记录、街头摄影，任何你想打破常规的场景。",
            whiteBalance: WhiteBalance(temperature: 0.1, tint: 0.15),
            colorMatrix: ColorMatrix(values: [
                1.06,  0.02, -0.04,
                0.03,  0.98,  0.02,
                -0.03,  0.08,  0.96
            ]),
            curve: .lomo,
            curveR: nil,
            curveG: nil,
            curveB: nil,
            saturation: 1.28,
            contrast: 1.2,
            halation: HalationConfig(
                threshold: 0.85, strength: 0.45,
                colorShift: [1.2, 0.9, 0.7],
                sigmaSmall: 4.0, sigmaLarge: 12.0
            ),
            bloom: nil,
            grain: GrainConfig(
                intensity: 0.15, softness: 0.4, fineSoftness: 0.22,
                fineWeight: 0.45, coarseWeight: 0.2, highlightReduction: 0.5,
                colorVariance: 0.2, mode: .chromatic
            ),
            vignette: 0.35,
            fade: 0.1
        ),

        // Kodak Ektar 100
        FilmPreset(
            id: "ektar100",
            name: "Ektar 100",
            description: "色彩爆炸，风景神片",
            category: .kodak,
            thumbnail: "ektar_thumb",
            scene: "风景 / 旅行 / 街拍",
            feature: "极高饱和 / 锐利颗粒 / 强对比",
            detail: "Kodak 最鲜艳的彩色负片，颜色像爆炸一样浓烈。适合光线充足的风景和旅行摄影。",
            whiteBalance: WhiteBalance(temperature: 0.08, tint: 0.0),
            colorMatrix: ColorMatrix(values: [1.15, -0.07, -0.07, -0.07, 1.20, -0.07, -0.07, -0.05, 1.20]),
            curve: .ektar,
            curveR: nil, curveG: nil, curveB: nil,
            saturation: 1.32,
            contrast: 1.22,
            halation: nil,
            bloom: nil,
            grain: GrainConfig(intensity: 0.03, softness: 0.75, fineSoftness: 0.20, fineWeight: 0.52, coarseWeight: 0.18, highlightReduction: 0.75, colorVariance: 0, mode: .spectral),
            vignette: 0.12,
            fade: 0.03
        ),

        // Fuji Astia 100F
        FilmPreset(
            id: "astia100f",
            name: "Astia 100F",
            description: "柔和人像，日系自然",
            category: .fuji,
            thumbnail: "astia_thumb",
            scene: "人像 / 婚礼 / 时尚",
            feature: "自然肤色 / 柔和过渡 / 低对比",
            detail: "Fuji 经典人像反转片，肤色极自然，过渡柔和。",
            whiteBalance: WhiteBalance(temperature: 0.03, tint: 0.04),
            colorMatrix: ColorMatrix(values: [0.97, 0.03, 0.0, 0.01, 0.98, 0.01, 0.0, 0.05, 0.94]),
            curve: .astia,
            curveR: nil, curveG: nil, curveB: nil,
            saturation: 0.92,
            contrast: 0.88,
            halation: nil,
            bloom: BloomConfig.subtle,
            grain: .fuji,
            vignette: 0.06,
            fade: 0.04
        ),

        // Fuji Classic Chrome（Fuji X 数字机型）
        FilmPreset(
            id: "classicChrome",
            name: "Classic Chrome",
            description: "Fuji X 复古胶片",
            category: .fujiDigital,
            thumbnail: "classicchrome_thumb",
            scene: "街拍 / 旅行 / 纪实",
            feature: "压暗高光 / 青橙调 / 胶片质感",
            detail: "富士 X 系列最受欢迎的胶片模拟，高光压得漂亮，阴影带青调。",
            whiteBalance: WhiteBalance(temperature: -0.04, tint: 0.03),
            colorMatrix: ColorMatrix(values: [0.95, 0.03, 0.02, 0.02, 0.92, 0.06, 0.08, 0.10, 0.82]),
            curve: .classicChrome,
            curveR: nil, curveG: nil, curveB: nil,
            saturation: 0.85,
            contrast: 1.15,
            halation: nil,
            bloom: BloomConfig.subtle,
            grain: GrainConfig(intensity: 0.07, softness: 0.6, fineSoftness: 0.22, fineWeight: 0.48, coarseWeight: 0.22, highlightReduction: 0.65, colorVariance: 0, mode: .spectral),
            vignette: 0.15,
            fade: 0.0
        ),

        // Panasonic LUMIX Natural
        FilmPreset(
            id: "panasonicNatural",
            name: "LUMIX Natural",
            description: "松下自然真实",
            category: .panasonic,
            thumbnail: "panasonic_natural_thumb",
            scene: "日常 / 人像 / 视频",
            feature: "干净自然 / 高动态 / 真实",
            detail: "模拟 Panasonic LUMIX Natural Film Mode，色彩最接近人眼。",
            whiteBalance: WhiteBalance.neutral,
            colorMatrix: ColorMatrix(values: [1.03, 0.0, -0.03, 0.0, 1.02, 0.0, -0.03, 0.0, 1.03]),
            curve: .linear,
            curveR: nil, curveG: nil, curveB: nil,
            saturation: 1.02,
            contrast: 1.02,
            halation: nil,
            bloom: nil,
            grain: GrainConfig(intensity: 0.03, softness: 0.7, fineSoftness: 0.25, fineWeight: 0.5, coarseWeight: 0.15, highlightReduction: 0.8, colorVariance: 0, mode: .spectral),
            vignette: 0.0,
            fade: 0.0
        ),

        // Panasonic LUMIX Vivid
        FilmPreset(
            id: "panasonicVivid",
            name: "LUMIX Vivid",
            description: "松下鲜艳模式",
            category: .panasonic,
            thumbnail: "panasonic_vivid_thumb",
            scene: "风景 / 旅行 / 街拍",
            feature: "高饱和 / 强对比 / 跳跃",
            detail: "LUMIX Vivid Film Mode，颜色鲜艳跳跃。",
            whiteBalance: WhiteBalance(temperature: 0.05, tint: 0.0),
            colorMatrix: ColorMatrix(values: [1.12, -0.04, -0.04, -0.04, 1.12, -0.04, -0.04, -0.04, 1.12]),
            curve: .ektar,
            curveR: nil, curveG: nil, curveB: nil,
            saturation: 1.28,
            contrast: 1.22,
            halation: nil,
            bloom: nil,
            grain: GrainConfig(intensity: 0.04, softness: 0.65, fineSoftness: 0.22, fineWeight: 0.5, coarseWeight: 0.18, highlightReduction: 0.75, colorVariance: 0, mode: .spectral),
            vignette: 0.0,
            fade: 0.0
        ),

        // Hasselblad Natural
        FilmPreset(
            id: "hasselbladNatural",
            name: "Hasselblad Natural",
            description: "中画幅自然色",
            category: .hasselblad,
            thumbnail: "hasselblad_thumb",
            scene: "人像 / 商业 / 风景",
            feature: "极致自然 / 丰富层次 / 真实",
            detail: "模拟 Hasselblad 数字中画幅的自然色彩科学。",
            whiteBalance: WhiteBalance.neutral,
            colorMatrix: ColorMatrix(values: [1.0, 0.01, -0.02, -0.01, 1.0, 0.01, -0.02, 0.01, 1.0]),
            curve: .hasselblad,
            curveR: nil, curveG: nil, curveB: nil,
            saturation: 1.04,
            contrast: 1.0,
            halation: nil,
            bloom: nil,
            grain: GrainConfig(intensity: 0.02, softness: 0.8, fineSoftness: 0.28, fineWeight: 0.6, coarseWeight: 0.1, highlightReduction: 0.9, colorVariance: 0, mode: .spectral),
            vignette: 0.0,
            fade: 0.0
        ),

        // Ricoh Positive Film（强化版）
        FilmPreset(
            id: "ricohPositive",
            name: "Ricoh Positive Film",
            description: "理光正片模式",
            category: .ricoh,
            thumbnail: "ricoh_positive_thumb",
            scene: "街拍 / 日常 / 快拍",
            feature: "高对比 / 正片色彩 / 锐利",
            detail: "模拟 Ricoh GR 系列经典 Positive Film 模式。",
            whiteBalance: WhiteBalance(temperature: -0.06, tint: -0.08),
            colorMatrix: ColorMatrix(values: [
                1.03, -0.01, -0.02,
                -0.01, 1.02, -0.01,
                -0.02, 0.01, 1.01
            ]),
            curve: .ricoh,
            curveR: nil, curveG: nil, curveB: nil,
            saturation: 1.42,
            contrast: 1.18,
            halation: nil,
            bloom: nil,
            grain: .ricoh,
            vignette: 0.55,
            fade: 0.0
        )
    ]

    static func preset(withId id: String) -> FilmPreset? {
        allPresets.first { $0.id == id }
    }
}
