import SwiftUI

// MARK: - Main Content View

private enum MainTab: Int {
    case library
    case settings
}

struct ContentView: View {
    @StateObject private var viewModel = FilmEditorViewModel()
    @ObservedObject private var colorSchemeManager = ColorSchemeManager.shared

    // Tab selection
    @State private var selectedTab = MainTab.library

    // Navigation states
    @State private var showingCamera = false
    @State private var showingImagePicker = false
    @State private var showingEditor = false
    @AppStorage("autoSave") private var autoSave: Bool = true

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("相册", systemImage: "photo.on.rectangle.angled", value: MainTab.library) {
                HomeView(
                    viewModel: viewModel,
                    selectedTab: Binding(
                        get: { selectedTab.rawValue },
                        set: { if let tab = MainTab(rawValue: $0) { selectedTab = tab } }
                    ),
                    showingCamera: $showingCamera,
                    showingImagePicker: $showingImagePicker,
                    showingEditor: $showingEditor
                )
            }

            Tab("设置", systemImage: "gearshape.fill", value: MainTab.settings) {
                SettingsView(viewModel: viewModel)
            }
        }
        .preferredColorScheme(colorSchemeManager.colorScheme)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .fullScreenCover(isPresented: $showingCamera) {
            CameraView(
                showingImagePicker: $showingImagePicker,
                onPhotoCaptured: handleCameraCapture(result:cameraPreset:)
            )
        }
        .sheet(isPresented: $showingImagePicker) {
            PhotoPicker(viewModel: viewModel, onImageSelected: {
                showingImagePicker = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingEditor = true
                }
            })
        }
        .fullScreenCover(isPresented: $showingEditor, onDismiss: {
            handleEditorDismiss()
        }) {
            EditorView(viewModel: viewModel)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // FIX 1+2: 先把图片和状态从 ViewModel 取出来，立即清空 ViewModel（解除大图内存引用、
    // 停止 SwiftUI 连锁刷新），然后再异步存盘，整个过程不阻塞主线程。
    private func handleEditorDismiss() {
        // 1. 先把需要保存的数据快照取出
        let originalImage   = viewModel.originalImage
        let processedImage  = viewModel.processedImage
        let preset          = viewModel.selectedPreset
        let adjustments     = viewModel.adjustments
        let editingRecordId = viewModel.editingRecordId

        // 2. 立即清空 ViewModel 状态，让 dismiss 动画流畅完成
        //    用一次赋值批量触发，减少 SwiftUI diff 次数
        viewModel.clearProcessingState()
        viewModel.originalImage    = nil
        viewModel.processedImage   = nil
        viewModel.selectedPreset   = nil
        viewModel.adjustments      = AdjustmentParams()
        viewModel.editingRecordId  = nil

        // 3. 不需要保存则直接返回
        guard autoSave,
              let original   = originalImage,
              let processed  = processedImage,
              let filmPreset = preset else { return }

        // 4. 异步存盘（PhotoHistoryStore 内部在 ioQueue 执行，不卡主线程）
        let store = PhotoHistoryStore.shared

        if let existingId = editingRecordId {
            store.updateRecord(
                id: existingId,
                processedImage: processed,
                preset: filmPreset,
                adjustments: adjustments
            )
        } else {
            store.addRecord(
                originalImage: original,
                processedImage: processed,
                preset: filmPreset,
                adjustments: adjustments
            )
        }
    }

    private func handleCameraCapture(result: CameraCaptureResult, cameraPreset: FilmPreset?) async throws {
        if result.isRaw {
            guard let rawData = result.rawData else {
                throw CameraPhotoLibraryError.saveFailed
            }

            try await CameraPhotoLibrarySaver.saveRawDNG(
                rawData,
                format: result.format,
                location: result.location
            )
            return
        }

        guard let image = result.processedImage else {
            throw CameraPhotoLibraryError.saveFailed
        }

        guard let cameraPreset else {
            try await CameraPhotoLibrarySaver.saveImage(
                image,
                format: result.format,
                metadata: result.metadata,
                location: result.location,
                capturedAt: result.capturedAt
            )
            return
        }

        let renderViewModel = FilmEditorViewModel()
        renderViewModel.selectedPreset = cameraPreset
        renderViewModel.adjustments = AdjustmentParams(opacity: 100)
        renderViewModel.loadImage(image)

        let outputImage = await renderViewModel.renderFullResolutionImage() ?? image
        try await CameraPhotoLibrarySaver.saveImage(
            outputImage,
            format: result.format,
            metadata: result.metadata,
            location: result.location,
            capturedAt: result.capturedAt
        )
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
