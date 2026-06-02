import Foundation
import SwiftUI
import Photos
import UniformTypeIdentifiers
import ImageIO

// MARK: - Export Sheet

struct ExportSheet: View {
    @ObservedObject var viewModel: FilmEditorViewModel
    @Environment(\.dismiss) var dismiss
    @AppStorage("exportQuality") private var exportQuality: ExportQuality = .high
    @AppStorage("exportFormat") private var exportFormat: ExportFormat = .jpeg

    @State private var isSaving = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 20) {
                    Spacer()

                    // Preview
                    if let processedImage = viewModel.processedImage {
                        Image(uiImage: processedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                    }

                    // Export button
                    Button(action: saveImage) {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 20))
                            }
                            Text(isSaving ? "保存中..." : "保存到相册")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(isSaving ? Color.orange.opacity(0.6) : Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 32)
                    }
                    .disabled(isSaving)

                    // Cancel button
                    Button(action: { dismiss() }) {
                        Text("取消")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal, 32)
                    }
                    .disabled(isSaving)

                    Spacer()
                }
                .navigationTitle("导出")
                .navigationBarTitleDisplayMode(.large)

                // Success overlay
                if showSuccess {
                    successOverlay
                }
            }
        }
        .alert("保存失败", isPresented: $showError) {
            Button("确定") { }
        } message: {
            Text(errorMessage)
        }
    }

    private var successOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("保存成功")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .frame(width: 200, height: 200)
        .background(Color.black.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .transition(.scale.combined(with: .opacity))
    }

    private func saveImage() {
        guard viewModel.processedImage != nil else {
            errorMessage = "图片处理中，请稍后再试"
            showError = true
            return
        }

        isSaving = true

        Task {
            do {
                guard let image = await viewModel.renderFullResolutionImage() else {
                    throw ExportError.renderFailed
                }
                let encoded = try encodeExportImage(image)

                try await saveImageDataToPhotoLibrary(encoded.data, type: encoded.type)

                await MainActor.run {
                    isSaving = false
                    withAnimation {
                        showSuccess = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func encodeExportImage(_ image: UIImage) throws -> (data: Data, type: UTType) {
        switch exportFormat {
        case .jpeg:
            guard let data = image.jpegData(compressionQuality: exportQuality.compression) else {
                throw ExportError.encodingFailed
            }
            return (data, .jpeg)
        case .heif:
            guard let cgImage = image.cgImage else {
                throw ExportError.encodingFailed
            }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil) else {
                throw ExportError.encodingFailed
            }
            let options = [
                kCGImageDestinationLossyCompressionQuality: exportQuality.compression
            ] as CFDictionary
            CGImageDestinationAddImage(destination, cgImage, options)
            guard CGImageDestinationFinalize(destination) else {
                throw ExportError.encodingFailed
            }
            return (data as Data, .heic)
        case .png:
            guard let data = image.pngData() else {
                throw ExportError.encodingFailed
            }
            return (data, .png)
        }
    }

    private func saveImageDataToPhotoLibrary(_ data: Data, type: UTType) async throws {
        let status = await requestAddOnlyPhotoAuthorization()
        guard status == .authorized || status == .limited else {
            throw ExportError.photoPermissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = type.identifier
                request.addResource(with: .photo, data: data, options: options)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ExportError.saveFailed)
                }
            }
        }
    }

    private func requestAddOnlyPhotoAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}

private enum ExportError: LocalizedError {
    case renderFailed
    case encodingFailed
    case photoPermissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            return "全尺寸图片渲染失败，请稍后再试"
        case .encodingFailed:
            return "图片编码失败"
        case .photoPermissionDenied:
            return "没有相册写入权限"
        case .saveFailed:
            return "保存失败，请检查相册权限"
        }
    }
}
