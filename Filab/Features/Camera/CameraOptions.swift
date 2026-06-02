import SwiftUI

enum CameraAspectRatio: String, CaseIterable, Identifiable {
    case full
    case threeFour
    case oneOne
    case sixteenNine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "FULL"
        case .threeFour: return "3:4"
        case .oneOne: return "1:1"
        case .sixteenNine: return "16:9"
        }
    }

    var frameRatio: CGFloat? {
        switch self {
        case .full:
            return nil
        case .threeFour:
            return 3.0 / 4.0
        case .oneOne:
            return 1.0
        case .sixteenNine:
            return 9.0 / 16.0
        }
    }
}

enum CameraCaptureFormat: String, CaseIterable, Identifiable {
    case jpeg
    case heif
    case proRaw
    case bayerRaw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jpeg: return "JPG"
        case .heif: return "HEIF"
        case .proRaw: return "ProRAW"
        case .bayerRaw: return "Bayer"
        }
    }

    var badgeTitle: String {
        switch self {
        case .jpeg: return "JPG 10-bit"
        case .heif: return "HEIF 10-bit"
        case .proRaw: return "ProRAW DNG"
        case .bayerRaw: return "Bayer DNG"
        }
    }

    var detail: String {
        switch self {
        case .jpeg:
            return "兼容"
        case .heif:
            return "高质量"
        case .proRaw:
            return "多帧融合 RAW"
        case .bayerRaw:
            return "传感器 RAW"
        }
    }

    var isRaw: Bool {
        switch self {
        case .proRaw, .bayerRaw:
            return true
        case .jpeg, .heif:
            return false
        }
    }

    var rawUnavailableMessage: String {
        switch self {
        case .proRaw:
            return "当前设备不支持 Apple ProRAW"
        case .bayerRaw:
            return "当前设备不支持 Bayer RAW"
        case .jpeg, .heif:
            return ""
        }
    }
}

enum CameraControlPanel: String, CaseIterable, Identifiable {
    case iso
    case shutter
    case exposure
    case whiteBalance
    case film

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iso: return "ISO"
        case .shutter: return "快门"
        case .exposure: return "EV"
        case .whiteBalance: return "WB"
        case .film: return "FILM"
        }
    }

    var icon: String {
        switch self {
        case .iso: return "camera.aperture"
        case .shutter: return "timer"
        case .exposure: return "plusminus.circle"
        case .whiteBalance: return "thermometer.medium"
        case .film: return "film"
        }
    }
}

extension FilmPreset {
    var cameraPreviewSaturation: Double {
        max(0, min(1.55, saturation))
    }

    var cameraPreviewContrast: Double {
        max(0.78, min(1.28, contrast))
    }

    var cameraPreviewOverlayColors: [Color] {
        let warmColor = Color(red: 1.0, green: 0.68, blue: 0.36)
        let coolColor = Color(red: 0.26, green: 0.48, blue: 0.86)
        let tintColor = whiteBalance.tint >= 0
            ? Color(red: 0.95, green: 0.34, blue: 0.78)
            : Color(red: 0.20, green: 0.78, blue: 0.56)

        return [
            whiteBalance.temperature >= 0 ? warmColor : coolColor,
            tintColor,
            category.accentColor
        ]
    }

    var cameraPreviewOverlayOpacity: Double {
        let whiteBalanceWeight = abs(whiteBalance.temperature) * 0.08 + abs(whiteBalance.tint) * 0.05
        let fadeWeight = fade * 0.24
        return max(0.05, min(0.24, 0.08 + whiteBalanceWeight + fadeWeight))
    }

    var cameraPreviewVignetteOpacity: Double {
        max(0.08, min(0.28, 0.08 + vignette * 1.25))
    }

    var cameraShortName: String {
        if name.count <= 12 {
            return name
        }

        return String(name.prefix(11)) + "..."
    }
}
