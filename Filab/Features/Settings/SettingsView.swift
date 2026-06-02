import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var viewModel: FilmEditorViewModel
    @ObservedObject private var colorSchemeManager = ColorSchemeManager.shared
    @AppStorage("exportQuality") private var exportQuality: ExportQuality = .high
    @AppStorage("exportFormat") private var exportFormat: ExportFormat = .jpeg
    @AppStorage("autoSave") private var autoSave: Bool = true
    @AppStorage("preserveMetadata") private var preserveMetadata: Bool = true
    @State private var showingClearCacheAlert = false
    @State private var cacheSize: String = "0 MB"

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                List {
                    // Appearance Section
                    Section {
                        appearanceRow
                    } header: {
                        Text("外观")
                            .font(.caption)
                            .textCase(.none)
                            .foregroundStyle(headerColor)
                    }
                    .listRowBackground(rowBackgroundColor)

                    // Export Quality Section
                    Section {
                        exportFormatRow
                        exportQualityRow
                    } header: {
                        Text("导出设置")
                            .font(.caption)
                            .textCase(.none)
                            .foregroundStyle(headerColor)
                    }
                    .listRowBackground(rowBackgroundColor)

                    // Auto Save Section
                    Section {
                        Toggle(isOn: $autoSave) {
                            Label {
                                Text("自动保存")
                                    .font(.body)
                                    .foregroundStyle(textColor)
                            } icon: {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .tint(.orange)

                        Toggle(isOn: $preserveMetadata) {
                            Label {
                                Text("保留元数据 (EXIF)")
                                    .font(.body)
                                    .foregroundStyle(textColor)
                            } icon: {
                                Image(systemName: "doc.text.fill")
                                    .foregroundStyle(.gray)
                            }
                        }
                        .tint(.orange)
                    } header: {
                        Text("保存选项")
                            .font(.caption)
                            .textCase(.none)
                            .foregroundStyle(headerColor)
                    }
                    .listRowBackground(rowBackgroundColor)

                    // Cache Section
                    Section {
                        HStack {
                            Label {
                                Text("缓存大小")
                                    .font(.body)
                                    .foregroundStyle(textColor)
                            } icon: {
                                Image(systemName: "externaldrive.fill")
                                    .foregroundStyle(.orange)
                            }

                            Spacer()

                            Text(cacheSize)
                                .font(.subheadline)
                                .foregroundStyle(secondaryColor)
                        }

                        Button(action: {
                            showingClearCacheAlert = true
                        }) {
                            Label {
                                Text("清除缓存")
                                    .font(.body)
                                    .foregroundStyle(.red)
                            } icon: {
                                Image(systemName: "trash.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    } header: {
                        Text("存储管理")
                            .font(.caption)
                            .textCase(.none)
                            .foregroundStyle(headerColor)
                    }
                    .listRowBackground(rowBackgroundColor)

                    // About Section
                    Section {
                        HStack {
                            Label {
                                Text("版本")
                                    .font(.body)
                                    .foregroundStyle(textColor)
                            } icon: {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.gray)
                            }

                            Spacer()

                            Text("1.0.0")
                                .font(.subheadline)
                                .foregroundStyle(secondaryColor)
                        }

                        Link(destination: URL(string: "https://apps.apple.com")!) {
                            Label {
                                Text("评价应用")
                                    .font(.body)
                                    .foregroundStyle(textColor)
                            } icon: {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                            }
                        }

                        Link(destination: URL(string: "https://apps.apple.com")!) {
                            Label {
                                Text("分享应用")
                                    .font(.body)
                                    .foregroundStyle(textColor)
                            } icon: {
                                Image(systemName: "square.and.arrow.up.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    } header: {
                        Text("关于")
                            .font(.caption)
                            .textCase(.none)
                            .foregroundStyle(headerColor)
                    }
                    .listRowBackground(rowBackgroundColor)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("设置")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(textColor)
                }
            }
            .onAppear {
                calculateCacheSize()
            }
            .alert("清除缓存", isPresented: $showingClearCacheAlert) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive) {
                    clearCache()
                }
            } message: {
                Text("这将删除所有临时文件和编辑历史。此操作无法撤销。")
            }
        }
    }

    // MARK: - Theme Colors

    private var backgroundColor: Color {
        colorSchemeManager.isDarkMode ? .black : Color(.systemGroupedBackground)
    }

    private var rowBackgroundColor: Color {
        colorSchemeManager.isDarkMode ? Color.white.opacity(0.08) : Color(.secondarySystemGroupedBackground)
    }

    private var textColor: Color {
        colorSchemeManager.isDarkMode ? .white : .primary
    }

    private var secondaryColor: Color {
        colorSchemeManager.isDarkMode ? .gray : .secondary
    }

    private var headerColor: Color {
        colorSchemeManager.isDarkMode ? .gray : .secondary
    }

    // MARK: - Appearance Row

    private var appearanceRow: some View {
        HStack {
            Label {
                Text("深色模式")
                    .font(.body)
                    .foregroundStyle(textColor)
            } icon: {
                Image(systemName: colorSchemeManager.isDarkMode ? "moon.fill" : "sun.max.fill")
                    .foregroundStyle(colorSchemeManager.isDarkMode ? .purple : .orange)
            }

            Spacer()

            Toggle("", isOn: $colorSchemeManager.isDarkMode)
                .tint(.orange)
                .labelsHidden()
        }
    }

// MARK: - Export Quality Row

    private var exportFormatRow: some View {
        NavigationLink {
            ExportFormatView(selectedFormat: $exportFormat)
        } label: {
            HStack {
                Label {
                    Text("导出格式")
                        .font(.body)
                        .foregroundStyle(textColor)
                } icon: {
                    Image(systemName: "doc.richtext.fill")
                        .foregroundStyle(.orange)
                }

                Spacer()

                Text(exportFormat.displayName)
                    .font(.subheadline)
                    .foregroundStyle(secondaryColor)
            }
        }
    }

    private var exportQualityRow: some View {
        NavigationLink {
            ExportQualityView(selectedQuality: $exportQuality)
        } label: {
            HStack {
                Label {
                    Text("导出质量")
                        .font(.body)
                        .foregroundStyle(textColor)
                } icon: {
                    Image(systemName: "photo.badge.gear")
                        .foregroundStyle(.green)
                }

                Spacer()

                Text(exportQuality.displayName)
                    .font(.subheadline)
                    .foregroundStyle(secondaryColor)
            }
        }
    }

    // MARK: - Cache Management

    private func calculateCacheSize() {
        let historyStore = PhotoHistoryStore.shared
        let recordsCount = historyStore.records.count

        // Estimate: each record has 3 images (original, processed, thumbnail)
        // Average size: original ~3MB, processed ~2MB, thumbnail ~0.1MB = ~5MB per record
        let estimatedSizeMB = Double(recordsCount) * 5.0

        if estimatedSizeMB < 1.0 {
            cacheSize = "0 MB"
        } else if estimatedSizeMB < 1000.0 {
            cacheSize = String(format: "%.1f MB", estimatedSizeMB)
        } else {
            cacheSize = String(format: "%.2f GB", estimatedSizeMB / 1000.0)
        }
    }

    private func clearCache() {
        // Clear temporary files
        let tempDir = FileManager.default.temporaryDirectory
        do {
            let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        } catch {
            print("Error clearing temp cache: \(error)")
        }

        // Clear photo edit history
        PhotoHistoryStore.shared.clearAllRecords()

        cacheSize = "0 MB"
    }
}
