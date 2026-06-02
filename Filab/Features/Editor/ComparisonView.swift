import SwiftUI

// MARK: - Comparison View

struct ComparisonView: View {
    @ObservedObject var viewModel: FilmEditorViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    if let original = viewModel.originalImage,
                       let processed = viewModel.processedImage {
                        HStack(spacing: 0) {
                            VStack {
                                Text("原图")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                Spacer()
                            }
                            .frame(width: geometry.size.width / 2)
                            .background(
                                Image(uiImage: original)
                                    .resizable()
                                    .scaledToFit()
                            )

                            VStack {
                                Text("效果")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .padding(.top, 8)
                                Spacer()
                            }
                            .frame(width: geometry.size.width / 2)
                            .background(
                                Image(uiImage: processed)
                                    .resizable()
                                    .scaledToFit()
                            )
                        }
                        .overlay(
                            Rectangle()
                                .fill(Color.orange)
                                .frame(width: 2)
                                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        )
                    }
                }
            }
            .navigationTitle("对比")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}
