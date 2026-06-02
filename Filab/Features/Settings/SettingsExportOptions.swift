import SwiftUI

// MARK: - Export Quality

enum ExportQuality: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case original = "original"

    var displayName: String {
        switch self {
        case .low: return "小文件 (JPEG 60%)"
        case .medium: return "均衡 (JPEG 80%)"
        case .high: return "高质量 (JPEG 95%)"
        case .original: return "最大质量 (JPEG 100%)"
        }
    }

    var compression: Double {
        switch self {
        case .low: return 0.6
        case .medium: return 0.8
        case .high: return 0.95
        case .original: return 1.0
        }
    }
}

enum ExportFormat: String, CaseIterable, Codable {
    case jpeg = "jpeg"
    case heif = "heif"
    case png = "png"

    var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .heif: return "HEIF"
        case .png: return "PNG"
        }
    }

    var description: String {
        switch self {
        case .jpeg: return "兼容性最好，质量受导出质量控制"
        case .heif: return "体积更小，质量受导出质量控制"
        case .png: return "无损格式，文件较大，不使用质量压缩"
        }
    }
}

// MARK: - Export Quality Selection View

struct ExportQualityView: View {
    @Binding var selectedQuality: ExportQuality
    @ObservedObject private var colorSchemeManager = ColorSchemeManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                List {
                    ForEach(ExportQuality.allCases, id: \.self) { quality in
                        Button(action: {
                            selectedQuality = quality
                            dismiss()
                        }) {
                            HStack {
                                Text(quality.displayName)
                                    .font(.body)
                                    .foregroundStyle(textColor)

                                Spacer()

                                if selectedQuality == quality {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("导出质量")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("导出质量")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(textColor)
                }
            }
        }
    }

    private var backgroundColor: Color {
        colorSchemeManager.isDarkMode ? .black : Color(.systemGroupedBackground)
    }

    private var textColor: Color {
        colorSchemeManager.isDarkMode ? .white : .primary
    }
}

struct ExportFormatView: View {
    @Binding var selectedFormat: ExportFormat
    @ObservedObject private var colorSchemeManager = ColorSchemeManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                List {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Button(action: {
                            selectedFormat = format
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(format.displayName)
                                        .font(.body)
                                        .foregroundStyle(textColor)

                                    Text(format.description)
                                        .font(.caption)
                                        .foregroundStyle(secondaryColor)
                                }

                                Spacer()

                                if selectedFormat == format {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("导出格式")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("导出格式")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(textColor)
                }
            }
        }
    }

    private var backgroundColor: Color {
        colorSchemeManager.isDarkMode ? .black : Color(.systemGroupedBackground)
    }

    private var textColor: Color {
        colorSchemeManager.isDarkMode ? .white : .primary
    }

    private var secondaryColor: Color {
        colorSchemeManager.isDarkMode ? .gray : .secondary
    }
}

// MARK: - Preview

#Preview {
    SettingsView(viewModel: FilmEditorViewModel())
}
