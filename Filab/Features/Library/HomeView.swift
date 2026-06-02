import SwiftUI
import PhotosUI

// MARK: - Home View

struct HomeView: View {
    @ObservedObject var viewModel: FilmEditorViewModel
    @Binding var selectedTab: Int
    @Binding var showingCamera: Bool
    @Binding var showingImagePicker: Bool
    @Binding var showingEditor: Bool
    @ObservedObject private var colorSchemeManager = ColorSchemeManager.shared
    @ObservedObject private var historyStore = PhotoHistoryStore.shared
    @State private var searchText = ""
    @State private var selectedPresetFilter: String?
    @State private var isSelectionMode = false
    @State private var selectedRecordIds: Set<String> = []
    @State private var showingDeleteSelectedAlert = false

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                // Main Content
                if historyStore.records.isEmpty {
                    emptyStateView
                } else {
                    photoAlbumView
                }
            }

            floatingActionButtons
                .padding(.trailing, 20)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .alert("删除选中的照片", isPresented: $showingDeleteSelectedAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                deleteSelectedRecords()
            }
        } message: {
            Text("将删除 \(selectedRecordIds.count) 张照片，此操作无法撤销。")
        }
    }

    // MARK: - Theme Colors

    private var backgroundColor: Color {
        colorSchemeManager.isDarkMode ? .black : Color(.systemBackground)
    }

    private var textColor: Color {
        colorSchemeManager.isDarkMode ? .white : .primary
    }

    private var secondaryColor: Color {
        colorSchemeManager.isDarkMode ? .gray : .secondary
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("FILM LAB")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(textColor)

                Text("\(historyStore.records.count) 张照片")
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryColor)
            }

            Spacer()

            if isSelectionMode {
                Button("取消") {
                    exitSelectionMode()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(secondaryColor)

                Button(role: .destructive) {
                    showingDeleteSelectedAlert = true
                } label: {
                    Label("删除", systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 18, weight: .semibold))
                }
                .disabled(selectedRecordIds.isEmpty)
            } else if !historyStore.records.isEmpty {
                Menu {
                    Button {
                        isSelectionMode = true
                        selectedRecordIds.removeAll()
                    } label: {
                        Label("选择照片", systemImage: "checkmark.circle")
                    }

                    Button(role: .destructive) {
                        historyStore.clearAllRecords()
                        exitSelectionMode()
                    } label: {
                        Label("清空相册", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(secondaryColor)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 40) {
            Spacer()

            // Film illustration
            ZStack {
                Circle()
                    .fill(textColor.opacity(0.05))
                    .frame(width: 200, height: 200)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(textColor.opacity(0.3))
            }

            VStack(spacing: 12) {
                Text("导入照片开始编辑")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(textColor)

                Text("选择照片，应用胶片模拟效果")
                    .font(.system(size: 14))
                    .foregroundStyle(secondaryColor)
            }

            // Main Add Button
            Button(action: {
                newPhotoTapped()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 20))
                    Text("选择照片")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.black)
                .frame(width: 160, height: 52)
                .background(
                    Capsule()
                        .fill(Color.orange)
                )
            }
            .padding(.top, 20)

            Spacer()
        }
    }

    // MARK: - Photo Album View (Grouped by Date)

    private var photoAlbumView: some View {
        VStack(spacing: 12) {
            albumFilterBar
                .padding(.horizontal, 16)
                .padding(.top, 8)

            if filteredRecords.isEmpty {
                emptyFilterState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 24, pinnedViews: [.sectionHeaders]) {
                // Add new photo button at top
                        Button(action: {
                            newPhotoTapped()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))
                                Text("添加新照片")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 16)
                        .padding(.top, 2)

                        // Group by date
                        ForEach(filteredGroupedByDate, id: \.date) { group in
                            Section {
                                photoGrid(records: group.records)
                            } header: {
                                dateHeader(date: group.date)
                            }
                        }
                    }
                    .padding(.bottom, 100) // Space for floating button
                }
            }
        }
    }

    private var albumFilterBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(secondaryColor)

                TextField("搜索胶片、日期或尺寸", text: $searchText)
                    .font(.system(size: 14))
                    .foregroundStyle(textColor)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(secondaryColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(colorSchemeManager.isDarkMode ? Color.white.opacity(0.08) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(title: "全部", isSelected: selectedPresetFilter == nil) {
                        selectedPresetFilter = nil
                    }

                    ForEach(presetFilterOptions) { option in
                        filterChip(title: option.name, isSelected: selectedPresetFilter == option.id) {
                            selectedPresetFilter = option.id
                        }
                    }
                }
            }
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? .black : textColor)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(isSelected ? Color.orange : Color.white.opacity(colorSchemeManager.isDarkMode ? 0.10 : 0.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(isSelected ? Color.clear : secondaryColor.opacity(0.25), lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var emptyFilterState: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(secondaryColor)

            Text("没有匹配的照片")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(textColor)

            Button("清除筛选") {
                searchText = ""
                selectedPresetFilter = nil
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.orange)
        }
    }

    private var filteredRecords: [PhotoEditRecord] {
        historyStore.records.filter { record in
            let matchesPreset = selectedPresetFilter == nil || record.presetId == selectedPresetFilter
            let matchesSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || recordMatchesSearch(record)
            return matchesPreset && matchesSearch
        }
    }

    private var filteredGroupedByDate: [(date: String, records: [PhotoEditRecord])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"

        let groups = Dictionary(grouping: filteredRecords) { record in
            formatter.string(from: record.createdAt)
        }

        return groups.keys.sorted { left, right in
            guard let leftDate = formatter.date(from: left),
                  let rightDate = formatter.date(from: right) else {
                return left > right
            }
            return leftDate > rightDate
        }.map { key in
            (date: key, records: groups[key] ?? [])
        }
    }

    private var presetFilterOptions: [FilmPreset] {
        let ids = Array(Set(historyStore.records.map(\.presetId))).sorted()
        return ids.compactMap { FilmPreset.preset(withId: $0) }
    }

    private func recordMatchesSearch(_ record: PhotoEditRecord) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let presetName = FilmPreset.preset(withId: record.presetId)?.name ?? record.presetId
        let searchableText = [
            presetName,
            record.displayDate,
            record.displayTime,
            "\(record.imageWidth)×\(record.imageHeight)",
            "\(record.imageWidth)x\(record.imageHeight)"
        ].joined(separator: " ")

        return searchableText.localizedCaseInsensitiveContains(query)
    }

    // MARK: - Date Header

    private func dateHeader(date: String) -> some View {
        HStack {
            Text(date)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(textColor)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(backgroundColor.opacity(0.95))
    }

    // MARK: - Photo Grid

    private func photoGrid(records: [PhotoEditRecord]) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(records) { record in
                PhotoCell(
                    record: record,
                    isEditing: viewModel.editingRecordId == record.id,
                    isSelectionMode: isSelectionMode,
                    isSelected: selectedRecordIds.contains(record.id)
                ) {
                    if isSelectionMode {
                        toggleSelection(record)
                    } else {
                        openRecord(record)
                    }
                } onLongPress: {
                    isSelectionMode = true
                    toggleSelection(record)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Photo Cell

    struct PhotoCell: View {
        let record: PhotoEditRecord
        let isEditing: Bool
        let isSelectionMode: Bool
        let isSelected: Bool
        let onTap: () -> Void
        let onLongPress: () -> Void

        @ObservedObject private var historyStore = PhotoHistoryStore.shared

        var body: some View {
            Button(action: onTap) {
                ZStack(alignment: .bottomTrailing) {
                    // Thumbnail - 固定高度容器，图片居中显示
                    Group {
                        if let thumbnail = historyStore.loadImage(named: record.thumbnailName) {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFit()  // 保持比例，不裁剪
                        } else if let processed = historyStore.loadImage(named: record.processedImageName) {
                            Image(uiImage: processed)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundStyle(.gray)
                                )
                        }
                    }
                    .frame(height: 120)  // 固定高度，确保所有格子上下对齐
                    .frame(maxWidth: .infinity)  // 宽度填满
                    .background(Color.gray.opacity(0.1))

                    // Editing indicator
                    if isEditing {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange, lineWidth: 3)
                            .frame(height: 120)
                    }

                    if isSelectionMode {
                        selectionIndicator
                            .padding(6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }

                    // Preset badge
                    if !isSelectionMode, let preset = FilmPreset.preset(withId: record.presetId) {
                        Text(preset.name)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .padding(6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .onLongPressGesture(minimumDuration: 0.35) {
                onLongPress()
            }
            .contextMenu {
                Button(role: .destructive) {
                    historyStore.deleteRecord(id: record.id)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }

        private var selectionIndicator: some View {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isSelected ? .orange : .white)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
    }

    // MARK: - Floating Add Button

    private var floatingActionButtons: some View {
        VStack(spacing: 12) {
            floatingCameraButton
            floatingAddButton
        }
    }

    private var floatingCameraButton: some View {
        Button(action: {
            openCameraTapped()
        }) {
            ZStack {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 58, height: 58)
                    .shadow(color: Color.purple.opacity(0.3), radius: 12, x: 0, y: 4)

                Image(systemName: "camera.aperture")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel("打开相机")
    }

    private var floatingAddButton: some View {
        Button(action: {
            newPhotoTapped()
        }) {
            ZStack {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.orange.opacity(0.3), radius: 12, x: 0, y: 4)

                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.black)
            }
        }
    }

    // MARK: - Actions

    private func openCameraTapped() {
        exitSelectionMode()
        showingCamera = true
    }

    private func newPhotoTapped() {
        exitSelectionMode()
        viewModel.editingRecordId = nil
        viewModel.reset()
        showingImagePicker = true
    }

    private func openRecord(_ record: PhotoEditRecord) {
        exitSelectionMode()
        viewModel.editingRecordId = record.id

        // 加载原图到 viewModel
        if let originalImage = historyStore.loadImage(named: record.originalImageName) {
            viewModel.loadImage(originalImage)

            // 恢复之前的编辑状态
            if let preset = FilmPreset.preset(withId: record.presetId) {
                viewModel.selectedPreset = preset
                viewModel.adjustments = record.adjustments

                // 如果有处理后的图片，设置为当前处理结果
                if let processed = historyStore.loadImage(named: record.processedImageName) {
                    viewModel.processedImage = processed
                }

                // 触发重新处理以应用当前参数
                viewModel.triggerProcessing()
            }
        }

        showingEditor = true
    }

    private func toggleSelection(_ record: PhotoEditRecord) {
        if selectedRecordIds.contains(record.id) {
            selectedRecordIds.remove(record.id)
        } else {
            selectedRecordIds.insert(record.id)
        }
    }

    private func deleteSelectedRecords() {
        let ids = selectedRecordIds
        ids.forEach { historyStore.deleteRecord(id: $0) }
        exitSelectionMode()
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedRecordIds.removeAll()
    }
}

// MARK: - FilmEditorViewModel Extension

extension FilmEditorViewModel {
    func reset() {
        clearProcessingState()
        originalImage = nil
        processedImage = nil
        selectedPreset = nil
        adjustments = AdjustmentParams()
        editingRecordId = nil
    }
}

// MARK: - Preview

#Preview {
    HomeView(
        viewModel: FilmEditorViewModel(),
        selectedTab: .constant(0),
        showingCamera: .constant(false),
        showingImagePicker: .constant(false),
        showingEditor: .constant(false)
    )
}
