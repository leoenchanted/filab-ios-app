import SwiftUI

// MARK: - Film Presets View (Expanded)

struct FilmPresetsView: View {
    @ObservedObject var viewModel: FilmEditorViewModel
    @State private var selectedCategory: FilmCategory? = nil
    @State private var showingDetail: FilmPreset? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryButton(
                        title: "ALL",
                        isSelected: selectedCategory == nil,
                        color: .orange
                    ) {
                        selectedCategory = nil
                    }

                    ForEach(FilmCategory.allCases, id: \.self) { category in
                        CategoryButton(
                            title: category.displayName.uppercased(),
                            isSelected: selectedCategory == category,
                            color: categoryColor(category)
                        ) {
                            selectedCategory = category
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Preset grid - horizontal scrolling cards with info
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(filteredPresets) { preset in
                        FilmPresetInfoCard(
                            preset: preset,
                            isSelected: viewModel.selectedPreset?.id == preset.id
                        ) {
                            viewModel.selectPreset(preset)
                        } onDetailTap: {
                            showingDetail = preset
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 164)
        }
        .sheet(item: $showingDetail) { preset in
            FilmDetailView(preset: preset)
        }
    }

    private var filteredPresets: [FilmPreset] {
        if let category = selectedCategory {
            return FilmPreset.allPresets.filter { $0.category == category }
        }
        return FilmPreset.allPresets
    }

private func categoryColor(_ category: FilmCategory) -> Color {
    category.accentColor
}
}

// MARK: - Category Button

struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? color : .gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(
                    Rectangle()
                        .frame(height: 2)
                        .foregroundStyle(isSelected ? color : .clear)
                        .padding(.horizontal, 8),
                    alignment: .bottom
                )
        }
    }
}

// MARK: - Film Preset Info Card

struct FilmPresetInfoCard: View {
    let preset: FilmPreset
    let isSelected: Bool
    let onTap: () -> Void
    let onDetailTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Button(action: onTap) {
                    FilmCanisterArtwork(
                        imageName: preset.icon,
                        accentColor: filmColor,
                        isSelected: isSelected,
                        size: CGSize(width: 82, height: 112)
                    )
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: onDetailTap) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.orange)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(6)
            }
            .frame(width: 82, height: 112)

            // Film name
            Text(preset.name)
                .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? .orange : .white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: 15)

            // Scene tag
            Text(preset.scene)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: 12)

            // Feature tag
            Text(preset.feature)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: 11)
        }
        .frame(width: 82)
        .frame(height: 162, alignment: .top)
    }

private var filmColor: Color {
    preset.category.accentColor
}
}

// MARK: - Film Detail View

struct FilmDetailView: View {
    let preset: FilmPreset
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        FilmCanisterArtwork(
                            imageName: preset.icon,
                            accentColor: filmColor,
                            isSelected: true,
                            size: CGSize(width: 92, height: 122)
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(preset.name)
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(preset.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            CategoryBadge(category: preset.category)
                        }
                    }
                    .padding(.bottom, 10)

                    Divider()

                    // Scene section
                    InfoSection(title: "适用场景", content: preset.scene, icon: "camera.fill")

                    // Feature section
                    InfoSection(title: "主要特色", content: preset.feature, icon: "sparkles")

                    Divider()

                    // Detail description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("详细介绍")
                            .font(.headline)

                        Text(preset.detail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                }
                .padding()
            }
            .navigationTitle("胶片详情")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

private var filmColor: Color {
    preset.category.accentColor
}
}

struct FilmCanisterArtwork: View {
    let imageName: String
    let accentColor: Color
    let isSelected: Bool
    let size: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            accentColor.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    isSelected ? Color.orange : accentColor.opacity(0.35),
                    lineWidth: isSelected ? 2.5 : 1
                )

            Image(imageName)
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Category Badge

struct CategoryBadge: View {
    let category: FilmCategory

    var body: some View {
        Text(category.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch category {
        case .kodak: return .orange
        case .fuji: return .green
        case .fujiDigital: return .mint
        case .panasonic: return .blue
        case .hasselblad: return .purple
        case .ricoh: return .cyan
        case .cinestill: return .red
        case .blackWhite: return .gray
        case .vintage: return .brown
        }
    }
}

// MARK: - Info Section

struct InfoSection: View {
    let title: String
    let content: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            Text(content)
                .font(.subheadline)
        }
    }
}

// MARK: - Preview

#Preview {
    FilmPresetsView(viewModel: FilmEditorViewModel())
}
