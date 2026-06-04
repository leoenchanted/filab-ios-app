import CoreLocation
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

enum CameraPhotoLibrarySaver {
    static func saveRawDNG(_ data: Data, format: CameraCaptureFormat, location: CLLocation?) async throws {
        try await requestAddOnlyAccess()
        let fileURL = try writeTemporaryFile(data: data, extension: "dng")

        try await performPhotoLibraryChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.location = location
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = "Filab_\(format.rawValue)_\(timestamp()).dng"
            options.shouldMoveFile = true
            request.addResource(with: .photo, fileURL: fileURL, options: options)
        }
    }

    static func saveImage(
        _ image: UIImage,
        format: CameraCaptureFormat,
        metadata: [String: Any],
        location: CLLocation?,
        capturedAt: Date
    ) async throws {
        try await requestAddOnlyAccess()

        let output: (data: Data, fileExtension: String, filename: String)

        switch format {
        case .heif:
            guard let data = image.encodedData(
                typeIdentifier: UTType.heic.identifier,
                quality: 0.95,
                metadata: metadata,
                location: location,
                capturedAt: capturedAt
            ) else {
                throw CameraPhotoLibraryError.encodingFailed
            }
            output = (data, "heic", "Filab_\(timestamp()).heic")
        case .jpeg, .proRaw, .bayerRaw:
            guard let data = image.encodedData(
                typeIdentifier: UTType.jpeg.identifier,
                quality: 0.96,
                metadata: metadata,
                location: location,
                capturedAt: capturedAt
            ) else {
                throw CameraPhotoLibraryError.encodingFailed
            }
            output = (data, "jpg", "Filab_\(timestamp()).jpg")
        }

        let fileURL = try writeTemporaryFile(data: output.data, extension: output.fileExtension)

        try await performPhotoLibraryChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.location = location
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
    func encodedData(
        typeIdentifier: String,
        quality: CGFloat,
        metadata: [String: Any],
        location: CLLocation?,
        capturedAt: Date
    ) -> Data? {
        let imageForEncoding = normalizedOrientation()
        guard let cgImage = imageForEncoding.cgImage else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            typeIdentifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let properties = Self.metadataProperties(
            sourceMetadata: metadata,
            location: location,
            capturedAt: capturedAt,
            quality: quality
        )

        CGImageDestinationAddImage(
            destination,
            cgImage,
            properties as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }

    private static func metadataProperties(
        sourceMetadata: [String: Any],
        location: CLLocation?,
        capturedAt: Date,
        quality: CGFloat
    ) -> [String: Any] {
        var properties = sourceMetadata
        properties[kCGImageDestinationLossyCompressionQuality as String] = quality
        properties[kCGImagePropertyOrientation as String] = 1

        var exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let exifDate = exifDateString(for: capturedAt)
        exif[kCGImagePropertyExifDateTimeOriginal as String] = exif[kCGImagePropertyExifDateTimeOriginal as String] ?? exifDate
        exif[kCGImagePropertyExifDateTimeDigitized as String] = exif[kCGImagePropertyExifDateTimeDigitized as String] ?? exifDate
        properties[kCGImagePropertyExifDictionary as String] = exif

        var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        tiff[kCGImagePropertyTIFFMake as String] = tiff[kCGImagePropertyTIFFMake as String] ?? "Apple"
        tiff[kCGImagePropertyTIFFModel as String] = tiff[kCGImagePropertyTIFFModel as String] ?? UIDevice.current.localizedModel
        tiff[kCGImagePropertyTIFFSoftware as String] = "Filab"
        properties[kCGImagePropertyTIFFDictionary as String] = tiff

        if let location {
            properties[kCGImagePropertyGPSDictionary as String] = gpsMetadata(for: location)
        }

        return properties
    }

    private static func gpsMetadata(for location: CLLocation) -> [String: Any] {
        let coordinate = location.coordinate
        var gps: [String: Any] = [
            kCGImagePropertyGPSLatitudeRef as String: coordinate.latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLatitude as String: abs(coordinate.latitude),
            kCGImagePropertyGPSLongitudeRef as String: coordinate.longitude >= 0 ? "E" : "W",
            kCGImagePropertyGPSLongitude as String: abs(coordinate.longitude),
            kCGImagePropertyGPSDateStamp as String: gpsDateString(for: location.timestamp),
            kCGImagePropertyGPSTimeStamp as String: gpsTimeString(for: location.timestamp),
            kCGImagePropertyGPSMapDatum as String: "WGS-84"
        ]

        if location.verticalAccuracy >= 0 {
            gps[kCGImagePropertyGPSAltitudeRef as String] = location.altitude >= 0 ? 0 : 1
            gps[kCGImagePropertyGPSAltitude as String] = abs(location.altitude)
        }

        return gps
    }

    private static func exifDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func gpsDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd"
        return formatter.string(from: date)
    }

    private static func gpsTimeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
