import SwiftUI
import PhotosUI

// MARK: - Editor View

struct EditorView: View {
    @ObservedObject var viewModel: FilmEditorViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedTab = 0
    @State private var showingExportSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top Bar - Minimal
                    topBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // Image Display - Takes most space
                    imageDisplayArea
                        .frame(maxHeight: .infinity)

                    // Bottom Controls - Compact
                    bottomControls
                        .background(
                            Color.black
                                .overlay(
                                    LinearGradient(
                                        colors: [Color.black.opacity(0), Color.black],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .frame(height: 20)
                                    .offset(y: -20),
                                    alignment: .top
                                )
                        )
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingExportSheet = true }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    .disabled(viewModel.processedImage == nil)
                }
            }
            .sheet(isPresented: $showingExportSheet) {
                ExportSheet(viewModel: viewModel)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Resolution badge
            HStack(spacing: 4) {
                if let image = viewModel.originalImage {
                    Text("\(Int(image.size.width))×\(Int(image.size.height))")
                        .font(.system(size: 11, weight: .medium))
                } else {
                    Text("--×--")
                        .font(.system(size: 11, weight: .medium))
                }

                Image(systemName: "arrow.right")
                    .font(.system(size: 9))

                Text("原图")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
            .foregroundStyle(.gray)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.08)))

            Spacer()

            // Compare button (only show when has processed image)
            if viewModel.processedImage != nil {
                compareButton
            }
        }
    }

    private var compareButton: some View {
        Button(action: {}) {
            Image(systemName: "eye")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(viewModel.isComparing ? .orange : .white)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(viewModel.isComparing ? Color.orange.opacity(0.2) : Color.white.opacity(0.1))
                )
                .overlay(
                    Circle()
                        .stroke(viewModel.isComparing ? Color.orange : Color.white.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .pressAndHold {
            viewModel.isComparing = true
        } onRelease: {
            viewModel.isComparing = false
        }
    }

    // MARK: - Image Display Area

    private var imageDisplayArea: some View {
        GeometryReader { geometry in
            ZStack {
                if let originalImage = viewModel.originalImage {
                    Image(uiImage: viewModel.isComparing ? originalImage : (viewModel.processedImage ?? originalImage))
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: max(0, geometry.size.width - 24))
                        .frame(maxHeight: max(0, geometry.size.height - 24))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        let panelHeight: CGFloat = 260

        return VStack(spacing: 0) {
            // Content area - same height for both FILM and ADJUST
            Group {
                switch selectedTab {
                case 0:
                    FilmPresetsView(viewModel: viewModel)
                case 1:
                    AdjustView(viewModel: viewModel)
                default:
                    EmptyView()
                }
            }
            .frame(height: panelHeight)

            // Tab selector at bottom
            HStack(spacing: 0) {
                TabButton(title: "FILM", isSelected: selectedTab == 0) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = 0
                    }
                }

                TabButton(title: "ADJUST", isSelected: selectedTab == 1) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = 1
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 2)
            .padding(.bottom, 2)
        }
    }
}

// MARK: - Press and Hold Button Style

struct PressAndHoldButtonStyle: ViewModifier {
    var onPress: () -> Void
    var onRelease: () -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress() }
                    .onEnded { _ in onRelease() }
            )
    }
}

extension View {
    func pressAndHold(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        self.modifier(PressAndHoldButtonStyle(onPress: onPress, onRelease: onRelease))
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : .gray)
                    .frame(maxWidth: .infinity)

                // Underline indicator
                Rectangle()
                    .fill(isSelected ? Color.orange : Color.clear)
                    .frame(width: 40, height: 2)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
