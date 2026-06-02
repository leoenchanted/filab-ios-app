import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

enum CameraPhotoLibrarySaver {
    static func saveRawDNG(_ data: Data, format: CameraCaptureFormat) async throws {
        try await requestAddOnlyAccess()
        let fileURL = try writeTemporaryFile(data: data, extension: "dng")

        try await performPhotoLibraryChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = "Filab_\(format.rawValue)_\(timestamp()).dng"
            options.shouldMoveFile = true
            request.addResource(with: .photo, fileURL: fileURL, options: options)
        }
    }

    static func saveImage(_ image: UIImage, format: CameraCaptureFormat) async throws {
        try await requestAddOnlyAccess()

        let output: (data: Data, fileExtension: String, filename: String)

        switch format {
        case .heif:
            guard let data = image.heifData(quality: 0.95) else {
                throw CameraPhotoLibraryError.encodingFailed
            }
            output = (data, "heic", "Filab_\(timestamp()).heic")
        case .jpeg, .proRaw, .bayerRaw:
            guard let data = image.jpegData(compressionQuality: 0.96) else {
                throw CameraPhotoLibraryError.encodingFailed
            }
            output = (data, "jpg", "Filab_\(timestamp()).jpg")
        }

        let fileURL = try writeTemporaryFile(data: output.data, extension: output.fileExtension)

        try await performPhotoLibraryChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = output.filename
            options.shouldMoveFile = true
            request.addResource(with: .photo, fileURL: fileURL, options: options)
        }
    }

    private static func requestAddOnlyAccess() async throws {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        if currentStatus == .authorized || currentStatus == .limited {
            return
        }

        let nextStatus = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }

        guard nextStatus == .authorized || nextStatus == .limited else {
            throw CameraPhotoLibraryError.photoLibraryAccessDenied
        }
    }

    private static func performPhotoLibraryChanges(_ changes: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CameraPhotoLibraryError.saveFailed)
                }
            }
        }
    }

    private static func writeTemporaryFile(data: Data, extension fileExtension: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}

enum CameraPhotoLibraryError: LocalizedError {
    case photoLibraryAccessDenied
    case encodingFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .photoLibraryAccessDenied:
            return "没有相册写入权限"
        case .encodingFailed:
            return "照片编码失败"
        case .saveFailed:
            return "保存到系统相册失败"
        }
    }
}

private extension UIImage {
    func heifData(quality: CGFloat) -> Data? {
        guard let cgImage else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(
            destination,
            cgImage,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }
}
