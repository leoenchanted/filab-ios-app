# Filab Agent 指南

## 项目用途

Filab 是一个 iOS SwiftUI 照片胶片模拟应用。它把照片导入、胶片预设、精细调整、本地编辑历史和导出质量控制放在同一个工作流里。

项目主要组成：

- SwiftUI 界面。
- Metal shader 图像处理。
- Core Image fallback 图像处理。
- 本地编辑历史 / 相册层。
- 导出质量设置。
- 导出格式设置。

核心用户流程：

1. 从相册导入照片。
2. 或从底部相机专属入口启动全屏系统相机拍摄照片，直接保存到系统相册。
3. 选择胶片预设。
4. 在 Adjust 页面微调。
5. 对比原图和处理后效果。
6. 导出或自动保存编辑记录。

主入口分类：

- `相机`：页面层使用系统原生 `TabView(selection:)` 管理相册 / 设置两个页面，但不要给页面添加 `.tabItem`，否则 iOS 26 会生成第二条系统浮动 tabbar。这个 `TabView` 应使用 `.tabViewStyle(.page(indexDisplayMode: .never))`，只保留页面容器和 selection 能力。底部唯一可见入口是覆盖在 `TabView` 上方的 `MainBottomDock`，视觉参考 iOS 26 电话 App：左侧一个胶囊 tab group，当前 tab 在内部显示灰色选中 pill，右侧是独立圆形相机主按钮。这个 dock 里的左侧 tab bar 和右侧相机按钮必须放在同一个 SwiftUI `GlassEffectContainer` 内，分别使用系统原生 `glassEffect(.regular, ...)` / `glassEffect(.regular.interactive(true), ...)` 和稳定的 `glassEffectID`，这样相机按钮按压靠近时才能获得系统原生 Liquid Glass metaball / morphing 融合；不要用自绘毛玻璃或长期相连的形状模拟。相机使用 AVFoundation 接入系统相机，支持权限请求、前后摄切换、系统级变焦、点按对焦/测光、EV、WB、格式/画幅入口、胶片实时轻量预览。相机横竖屏方向必须使用 `AVCaptureDevice.RotationCoordinator` 分别驱动预览层 and 照片输出的 `videoRotationAngle`，不要手动读取陀螺仪或固定 portrait；JPEG / HEIF 拍照后会把当前胶片烘焙进照片并直接写入系统相册；RAW 拍照会保存真正的 DNG 原始文件，不应用胶片效果。未来完整逐帧 Metal 胶片预览从这里继续扩展。
- `相册`：照片导入、本地编辑历史、搜索筛选和批量管理。
- `设置`：外观、导出、保存和缓存等全局设置。

## 重要文件

- `App/FilabApp.swift`：App 入口。
- `App/ContentView.swift`：App 外壳、底部 Liquid Glass dock、右侧圆形相机主按钮、全屏相机和编辑器展示。编辑器 `onDismiss` 必须遵守固定顺序：①快照取出数据 → ②立即清空 ViewModel 全部 `@Published` 状态 → ③调用 `PhotoHistoryStore` 异步存盘接口；禁止在 `onDismiss` 内做任何同步磁盘 IO（详见线程与性能约定）。
- `Features/Camera/CameraView.swift`：全屏相机页 SwiftUI 界面、权限状态展示、专业相机风格读数条、左侧每页 5 个工具的分页工具栏、直方图、1x/2x 快捷变焦、捏合变焦、点按对焦反馈、ISO / 快门 / EV / WB / 胶片两层选择调节区、格式和画幅当前值显示、快门和自拍入口。
- `Features/Camera/CameraController.swift`：AVFoundation 系统相机权限、Session 配置、前后摄切换、设备级变焦、点按对焦/测光、EV、WB、照片格式 and 拍照回调。内部维护专用 `sessionQueue = DispatchQueue(label: "filab.camera.session")`，所有 `session.startRunning` / `stopRunning` / `beginConfiguration` / `commitConfiguration` 均在此队列执行，不可在 `@MainActor` 主线程直接调用。拍摄 JPEG / HEIF 时必须通过当前 active format 的 `supportedMaxPhotoDimensions` 选择最高照片尺寸，并同时设置 `AVCapturePhotoOutput.maxPhotoDimensions` 和每次 `AVCapturePhotoSettings.maxPhotoDimensions`；不要恢复到默认 settings，否则系统会倾向使用较小尺寸。纯 RAW 格式不设置 `photoQualityPrioritization`（详见线程与性能约定）。
- `Features/Camera/CameraOptions.swift`：相机页专用枚举和预览 helper，包含画幅、拍摄格式、专业控制面板分类，以及基于 `FilmPreset` 的轻量实时预览参数。
- `Features/Camera/CameraPhotoLibrarySaver.swift`：相机拍摄后的系统相册写入，负责 JPEG / HEIF 编码、RAW DNG 临时文件导入 and Photos add-only 权限请求。
- `Features/Camera/CameraPreviewView.swift`：`AVCaptureVideoPreviewLayer` 的 SwiftUI 桥接，负责真实取景器预览和自拍镜像。
- `Features/Library/HomeView.swift`：相册 / 历史记录 / 搜索筛选 / 批量管理界面。
- `Features/Library/PhotoPicker.swift`：相册导入桥接，供相册入口 and 相机入口复用。
- `Features/Editor/EditorView.swift`：照片编辑器，包含 FILM / ADJUST 两个 tab。
- `Features/Editor/AdjustmentControlsView.swift`：Adjust 页面滑块、HSL 面板和调节分组 UI。
- `Features/Editor/FilmPresetsView.swift`：胶片预设选择和胶片详情。
- `Features/Editor/ExportSheet.swift`：全分辨率导出和保存到系统相册。
- `Features/Editor/ComparisonView.swift`：原图 / 效果对比视图。
- `Features/Editor/FilmEditorViewModel.swift`：编辑状态、预览处理、Core Image fallback、全分辨率导出渲染。
- `Features/Settings/SettingsView.swift`：外观、导出质量、导出格式、保存和缓存设置。
- `Features/Settings/SettingsExportOptions.swift`：导出质量 / 导出格式模型和选择界面。
- `Core/Film/FilmPreset.swift`：胶片、曲线、颗粒、调节参数等核心模型。
- `Core/Film/FilmPresetCatalog.swift`：内置胶片预设目录。
- `Core/History/PhotoHistoryStore.swift`：本地编辑记录和图片文件存储。`addRecord` / `updateRecord` 为异步接口，接受可选 `completion` 回调；所有磁盘 IO 在内部 `ioQueue`（`DispatchQueue(label: "filab.history.io", qos: .userInitiated)`）执行，完成后回到主线程更新 `records`。缩略图生成使用 `UIGraphicsImageRenderer`，已废弃的 `UIGraphicsBeginImageContextWithOptions` 不可使用。`DateFormatter` 用 `static let` 缓存，不要在 computed property 里每次新建（详见线程与性能约定）。
- `Core/Rendering/MetalFilmProcessor.swift`：Metal 纹理创建和图像处理管线。
- `Core/Rendering/Shaders/`：Metal shader，包含 Film pass、Adjust pass、颗粒、bloom、halation and 共享 helper。
- `Core/Appearance/ColorSchemeManager.swift`：手动深色 / 浅色模式管理。

## 渲染模型

请保持这个架构：

- 预览使用降采样后的图片纹理，以保证滑块交互顺畅。
- 导出使用原始全分辨率图片。
- 胶片模拟和用户调整是两个概念层。
- Film pass 负责计算选中胶片的基础效果。
- Adjust pass 负责把用户滑块参数叠加到胶片基础效果之上。
- 当前暂时不做独立预设数据文件或完整数据驱动胶片系统；如果用户没有重新要求，不要把内置预设迁移出 `Core/Film/FilmPreset.swift`。

除非源图或选中预设变化，否则普通用户调整参数不要重新塞回 Film pass。

当前 Adjust 参数包括：

- 调光：曝光、对比、高光、阴影、白色色阶、黑色色阶。
- 颜色：色温、色调、饱和度、清晰度、锐化。
- HSL：红、橙、黄、绿、青、蓝、紫、洋红的色相、饱和、明度。
- HSL UI 采用“先选颜色通道，再调色相、饱和、明度”的结构，不要恢复成 24 个滑块平铺。
- 色调：阴影色相、阴影强度、高光色相、高光强度、色调平衡。
- 效果：胶片强度、暗角、柔光、Halation、Fade、Fade 冷暖。`bloom` 字段仍可兼容旧记录，但当前不作为独立用户滑块展示。
- 颗粒：颗粒强度、颗粒大小、颗粒粗糙、彩色颗粒。

调光算法约定：

- 高光、阴影、白色色阶、黑色色阶不要直接对 RGB 做硬加法或硬乘法。
- 这四个滑块的 UI 范围是 `-100...100`，但 Swift 送入 shader / Core Image fallback 前要除以 100 映射到 `-1...1`；不要因为 UI 范围扩大而放大实际渲染极限。
- Metal 主路径在 `ShaderHelpers.metal` 中先计算线性亮度，再用 `smoothstep` 遮罩和 `pow` 曲线生成目标亮度，最后通过亮度回灌保留色度。
- 亮部需要 soft shoulder 保护，避免死白；暗部需要软遮罩和幂曲线，避免死黑、断层和直方图尖峰。
- 阴影和黑色色阶要比亮部更保守：使用感知型内部力度映射，并在接近纯黑的区域设置软保护区，防止极值滑块把黑场、噪点或背景大面积抬起/压死。
- Core Image fallback 在 `FilmEditorViewModel` 中用 `CIColorCube` 近似同一套亮度重映射逻辑，避免 Metal 不可用时调光手感明显变硬。
- 如果以后继续改这四个滑块，要同时检查 Metal 主路径 and Core Image fallback，避免预览、导出或低端设备路径不一致。

## Metal 管线说明

`MetalFilmProcessor` 主要持有：

- `sourceTexture`：当前源图纹理。
- `filmSimulatedTexture`：缓存的胶片基础效果。
- `processedTexture`：最终预览 / 导出输出。
- `intermediateTexture` 和 `bloomTexture`：blur、halation 等效果的临时纹理。

`needsFilmUpdate` 控制是否需要重新跑较重的 Film pass。

重要坑位：

- `ColorMatrix.values` 按 row-major 存储。
- Swift 的 `float3x3` 是 column-major。
- `ColorMatrix.toSIMD()` 会故意转置矩阵后再传给 Metal。
- 不要随便删除这个转置，除非你同时改掉所有预设矩阵的数据存储方式。

## 线程与性能约定

这是本项目最容易出现卡死 / Watchdog 超时的区域，后续 Agent 修改时必须严格遵守。

### AVFoundation Session（CameraController）

- `session.startRunning()` 和 `session.stopRunning()` 是同步阻塞调用，Apple 文档明确要求放到后台线程。Bayer RAW / ProRAW 的 session 配置比普通 JPEG 更重，在主线程调用极易触发明显卡顿或 Watchdog 超时杀死进程。
- `CameraController` 内部维护专用 `sessionQueue = DispatchQueue(label: "filab.camera.session")`，所有 session 操作（`startRunning` / `stopRunning` / `beginConfiguration` / `commitConfiguration` / `applyCamera`）必须在此队列执行，`@Published` 属性更新通过 `DispatchQueue.main.async` 回写主线程。
- `switchCamera()` 的 session 配置同样在 `sessionQueue` 执行，不要在 `@MainActor` 方法里直接调用。

### RAW 拍照设置（CameraController）

- `AVCapturePhotoSettings` 的 `photoQualityPrioritization` 只对 processed 格式有效，对纯 RAW settings 设置此属性会导致 capture pipeline 卡住或抛 `Unsupported when capturing RAW` 异常。
- `capturePhoto()` 内通过 `if !captureFormat.isRaw` 判断，只对 JPEG / HEIF 设置 `photoQualityPrioritization = .quality`，RAW 格式跳过，不要移除这个判断。
- Bayer RAW 使用 RAW-only 捕获：`AVCapturePhotoSettings(rawPixelFormatType:rawFileType:processedFormat:processedFileType:)` 后两个参数传 `nil`，不附加 processed 双路输出。

### 最高照片尺寸（CameraController）

- 1x 只代表焦段 / 当前镜头，不代表 AVFoundation 会默认输出传感器最高像素。
- `AVCapturePhotoSettings.maxPhotoDimensions` 默认会使用当前 active format 支持列表里的较小尺寸；JPEG / HEIF 高像素拍摄必须显式设置。
- 配置相机时优先选择 `supportedMaxPhotoDimensions` 面积最大的设备和 active format，并在 `startRunning()` 前设置 `photoOutput.maxPhotoDimensions`。
- 每次 JPEG / HEIF 拍照创建 `AVCapturePhotoSettings` 后，也要把 `settings.maxPhotoDimensions` 设置为同一个最大尺寸。
- 取景器右上角显示当前 pipeline 的最大 MP，并在真机日志打印配置尺寸和实际回调照片像素，用于确认 48MP / 24MP / 20MP 等实际输出。

### PhotoCaptureDelegate 错误处理（CameraController）

- `didFinishCaptureFor` 里顶层 `error` 参数优先级最高，表示整个 capture 会话失败，直接 `completion(.failure(error))` 返回，不要和内部 `captureError` 混在同一条 fallback 里。
- `didFinishProcessingPhoto` 阶段的错误存入内部 `captureError`，只在顶层 `error == nil` 且数据也为空时作为 fallback 使用。

### 磁盘 IO（PhotoHistoryStore）

- `addRecord` / `updateRecord` 的 JPEG 编码 + 文件写入 + 缩略图生成都是同步阻塞 IO，全画质图片单次写入可达数百毫秒，绝对不能在主线程执行。
- 所有磁盘 IO 在 `ioQueue = DispatchQueue(label: "filab.history.io", qos: .userInitiated)` 里执行，完成后通过 `DispatchQueue.main.async` 回到主线程更新 `records` 并触发 `saveRecords()`。
- `saveRecords()` 使用防抖（50 ms），避免连续操作重复序列化；JSON 序列化在 `ioQueue` 完成，只把最终 `UserDefaults.set` 回到主线程。
- `deleteRecord` / `clearAllRecords` 先在主线程更新数组和 `saveRecords()`，文件删除异步在 `ioQueue` 执行，不等待删除完成再返回。

### 编辑器关闭（ContentView.onDismiss）

- `fullScreenCover` 的 `onDismiss` 在主线程同步执行，任何阻塞都会冻住 dismiss 动画，严重时触发 Watchdog 杀进程。
- 正确顺序：①用 O(1) 引用复制把图片和参数快照取出 → ②立即清空 ViewModel 所有 `@Published` 状态（释放大图内存，让 dismiss 动画流畅完成）→ ③调用 `PhotoHistoryStore` 的异步存盘接口（在 `ioQueue` 后台静默完成）。
- 不要在 `onDismiss` 里加任何同步磁盘写入、JPEG 编码或大数据序列化操作。
- 连续多次赋值 `@Published` 属性会触发多次 SwiftUI diff；如能合并到一个状态对象，优先合并，减少重绘次数。

### 其他主线程保护

- 避免在 `@MainActor` 上做图像处理、大数据 JSON 编解码或文件操作。
- 缩略图生成使用 `UIGraphicsImageRenderer`；已废弃的 `UIGraphicsBeginImageContextWithOptions` 不要使用。
- `DateFormatter` 创建成本高，使用 `static let` 缓存，不要在 computed property 或循环里每次新建。

## 当前已知限制

- 现在的胶片预设是手工近似值，不是严格校准的胶片 profile。
- 如果未来追求更准确的胶片系统，应该支持 3D LUT 和固定参考图校准。
- 当前重点是继续精修现有内置预设，不做独立预设数据迁移。
- Metal shader 编译依赖 Xcode Metal Toolchain。如果构建报 `cannot execute tool 'metal'`，需要按 Xcode 提示下载 Metal Toolchain。
- 当前编辑记录通过 `UserDefaults` 加 Documents 里的 JPEG 文件保存。早期可以用，但如果相册系统继续扩大，建议迁移到 SwiftData 或其他数据库。
- `PhotoHistoryStore.saveRecords()` 把整个记录数组序列化进 `UserDefaults`；记录数量较大时单次序列化体积会增长，未来应考虑分页存储或迁移到数据库。
- Bayer RAW / ProRAW 拍照时 session 配置比 JPEG 明显更重，启动耗时更长；若未来出现 RAW 模式切换卡顿，应优先检查 `sessionQueue` 里是否有阻塞操作或配置冲突。

## 构建和验证

常用构建命令：

```sh
xcodebuild -project ../Filab.xcodeproj -scheme Filab -configuration Debug -sdk iphonesimulator -derivedDataPath /private/tmp/FilabDerivedData CODE_SIGNING_ALLOWED=NO build
```

如果单独 Swift typecheck 被 `#Preview` 宏卡住，可以临时复制源码到 `/private/tmp`，去掉 `#Preview` 块后再 typecheck。这个只是本地验证技巧，不应该改项目源码。

## UI 约定

- 用户拖动滑块时，编辑器图片区域不要显示阻塞式 loading 浮层。
- 滑块交互要保持顺畅、非模态。
- 单个 Adjust 滑块支持双击或长按重置。
- 内容页面使用 `TabView(selection:)`，但不要添加 `.tabItem`；底部可见导航完全交给自定义 `MainBottomDock`，避免第二条系统 tabbar。底部相册 / 设置入口不要手写模糊材质，也不要用 `.ultraThinMaterial` 仿玻璃；只能使用 SwiftUI iOS 26 原生 `GlassEffectContainer`、`glassEffect`、`glassEffectID`。相机不是普通 tab，而是同一容器里的右侧独立圆形主入口，使用 regular interactive glass，不固定染成蓝色。常态下左侧 bar 和右侧按钮要保持分开；按压相机按钮时临时缩小间距，让系统在同一容器内做 Liquid Glass metaball / morphing 融合。左侧 tab 选中态参考电话 App 的内嵌灰色 pill，不要再显示第二条系统 tabbar。
- 相机页视觉参考专业胶片相机界面：顶部格式和画幅按钮必须直接显示当前值（例如 JPG、RAW、3:4），左侧取景器工具栏每页固定 5 个工具并保持等距，底部功能调节区用于切换 ISO、快门、EV、WB 和胶片。胶片调节区必须分两层：上面是全部 / 品牌分类，下面是具体 `FilmPreset` 胶片，不要把品牌 and 胶片混在同一条横向列表里。
- 相机拍照后不要进入编辑器。JPEG / HEIF 会用临时 `FilmEditorViewModel` 调用现有胶片渲染能力，把当前 `FilmPreset` 烘焙到照片里，再用 `PHAssetCreationRequest` 保存到系统相册。
- RAW 模式必须走 `AVCapturePhotoSettings(rawPixelFormatType:rawFileType:processedFormat:processedFileType:)` 的 RAW-only DNG 捕获；不要把 RAW 转成 `UIImage`，也不要应用胶片预设。RAW settings 不要设置 `photoQualityPrioritization`，AVFoundation 会因此抛 `Unsupported when capturing RAW` 异常。RAW 模式 UI 需要提示“保存 DNG 原始文件，不应用胶片效果”。
- 相机实时胶片预览直接使用 `FilmPreset.allPresets` 和 `FilmCategory` 分类，不再维护单独的相机胶片列表。当前预览是 SwiftUI/GPU 合成的轻量预览层，用 saturation、contrast、soft-light overlay 和暗角模拟大方向，保持取景流畅；它不是最终照片编辑器的完整 Metal shader 管线。下一阶段如果要做严肃所见即所得，应按 Apple `AVCamFilter` 思路使用 `AVCaptureVideoDataOutput` 获取帧，再用 Core Image / Metal 复用现有胶片参数，且预览帧率应节流到 24-30fps、降分辨率处理，拍照仍走 `AVCapturePhotoOutput` 高质量静态图。
- 首页相册支持按胶片预设筛选、按胶片名/日期/尺寸搜索、选择模式 and 批量删除。
- 深色 / 浅色模式都要检查文字对比度。
- 编辑器主体视觉上是深色，所以深色面板里不要随便用 `.primary`，除非背景也会跟随主题变化。
- 导出 sheet 可以显示进度，因为导出是用户明确触发的耗时动作。

## 导出说明

导出质量由 `Features/Settings/SettingsExportOptions.swift` 里的 `ExportQuality` 控制。

当前行为：

- 低质量：JPEG 60%。
- 中等质量：JPEG 80%。
- 高质量：JPEG 95%。
- 最大质量：JPEG 100%。
- 导出格式由 `ExportFormat` 控制：JPEG、HEIF、PNG。
- JPEG and HEIF 使用 `ExportQuality.compression`；PNG 是无损格式，不使用质量压缩。
- `autoSave` 开关会控制编辑器关闭时是否写入本地历史记录。

导出必须通过 `FilmEditorViewModel.renderFullResolutionImage()` 从原图重新渲染，不要直接保存预览图。

## 未来功能方向

优先考虑：

- 更准确的胶片预设。
- 用户自定义胶片配方。
- HSL 控制。
- 分离色调。
- 曲线编辑器。
- 更完整的相册管理。
- EXIF 保留。
- HEIF 导出。
- 批量编辑。
- 用 Instruments 做真机性能分析。

## 给后续 Agent 的编辑规则

- 修改渲染行为前，先读 `Core/Film/FilmPreset.swift`、`Features/Editor/FilmEditorViewModel.swift`、`Core/Rendering/MetalFilmProcessor.swift` 和 `Core/Rendering/Shaders/FilmShaders.metal`。
- 保持改动范围清晰，能跑 Swift typecheck 或 Xcode build 时一定要跑。
- 不要无说明地修改胶片预设视觉效果。
- 保留“预览降采样、导出全分辨率”的区别。
- 避免在 `@MainActor` / 主线程上阻塞图像处理、磁盘 IO 或 AVFoundation session 操作；详见「线程与性能约定」章节。
- 修改 `CameraController` 时，`session.startRunning` / `stopRunning` / `beginConfiguration` / `commitConfiguration` 必须保留在 `sessionQueue` 里执行。
- 修改 `PhotoHistoryStore` 时，`addRecord` / `updateRecord` 的磁盘 IO 必须保留在 `ioQueue` 里；接口是异步的，调用方通过 `completion` 回调获取结果，不要改回同步返回值。
- 修改 `ContentView` 编辑器 `onDismiss` 时，必须保持「先清状态、再异步存盘」的顺序，不可在 `onDismiss` 里加任何同步 IO。
- 不要给纯 RAW `AVCapturePhotoSettings` 设置 `photoQualityPrioritization`，会导致 pipeline 卡住或异常。
- 不要回滚用户已有改动，除非用户明确要求。

## AGENT.md 维护规则

如果后续 agent 做了以下类型的大改，必须同步补充或更新本文件：

- 改了渲染架构，例如 Film pass、Adjust pass、导出 pass 的职责变化。
- 改了 Metal 纹理生命周期、缓存策略或 shader 参数结构。
- 新增或迁移数据存储，例如从 `UserDefaults` 迁移到 SwiftData。
- 改了导出格式、导出质量、EXIF 或色彩空间策略。
- 新增重要功能模块，例如配方系统、相册系统、批量编辑、LUT 管线。
- 新增重要构建步骤、依赖、脚本或本地环境要求。
- 修复了会影响后续判断的关键 bug，特别是线程安全类的 bug。
- 新增或改动了任何涉及 `@MainActor`、后台队列、`async/await` 的并发模型。

维护方式：

- 在相关章节补充新的事实，不要只写在聊天记录里。
- 如果新增文件或模块，要把它加到“重要文件”里。
- 如果改了处理管线，要更新“渲染模型”和“Metal 管线说明”。
- 如果修改了线程模型或新增阻塞点保护，要更新“线程与性能约定”。
- 如果新增已知限制或验证方法，要更新“当前已知限制”或“构建和验证”。
