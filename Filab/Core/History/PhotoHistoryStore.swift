import Foundation
import SwiftUI
import Combine

// MARK: - Photo Edit Record

struct PhotoEditRecord: Identifiable, Codable, Equatable {
    let id: String
    var originalImageName: String      // 原始图片文件名
    var processedImageName: String     // 处理后图片文件名
    var thumbnailName: String          // 缩略图文件名
    var presetId: String               // 胶片预设ID
    var adjustments: AdjustmentParams  // 调整参数
    let createdAt: Date                // 创建时间
    var updatedAt: Date                // 最后更新时间
    let imageWidth: Int                // 图片宽度
    let imageHeight: Int               // 图片高度

    // FIX 5: 用静态缓存的 DateFormatter，避免每次访问属性都新建
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()

    var displayDate: String {
        Self.dateFormatter.string(from: createdAt)
    }

    var displayTime: String {
        Self.timeFormatter.string(from: createdAt)
    }

    // 是否为同一天
    func isSameDay(as other: PhotoEditRecord) -> Bool {
        Calendar.current.isDate(createdAt, inSameDayAs: other.createdAt)
    }
}

// MARK: - Photo History Store

@MainActor
final class PhotoHistoryStore: ObservableObject {
    static let shared = PhotoHistoryStore()

    @Published var records: [PhotoEditRecord] = []

    private let documentsDirectory: URL
    private let recordsKey = "photoEditRecords"

    // FIX 1: 专用后台队列处理所有磁盘 IO，不阻塞主线程
    private let ioQueue = DispatchQueue(label: "filab.history.io", qos: .userInitiated)

    // FIX 4: saveRecords 防抖 — 避免连续多次操作时重复序列化
    nonisolated(unsafe) private var saveWorkItem: DispatchWorkItem?

    init() {
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        loadRecords()
    }

    // MARK: - Load/Save Records

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: recordsKey),
              let savedRecords = try? JSONDecoder().decode([PhotoEditRecord].self, from: data) else {
            return
        }
        records = savedRecords.sorted(by: { $0.createdAt > $1.createdAt })
    }

    // FIX 4: 防抖写入，50ms 内的多次调用只执行最后一次
    private func saveRecords() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // 在 ioQueue 序列化，序列化完再切回主线程写 UserDefaults
            let snapshot = self.records
            self.ioQueue.async {
                if let data = try? JSONEncoder().encode(snapshot) {
                    DispatchQueue.main.async {
                        UserDefaults.standard.set(data, forKey: self.recordsKey)
                    }
                }
            }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    // MARK: - Image Storage

    // FIX 1: 同步版本仅供内部 ioQueue 调用（nonisolated 使其可从 Sendable 闭包调用）
    nonisolated private func saveImageSync(_ image: UIImage, withName name: String) -> Bool {
        let fileURL = documentsDirectory.appendingPathComponent(name)
        guard let data = image.jpegData(compressionQuality: 0.9) else { return false }
        do {
            try data.write(to: fileURL)
            return true
        } catch {
            print("Failed to save image: \(error)")
            return false
        }
    }

    // 供外部调用的异步版本（不阻塞调用方）
    func saveImage(_ image: UIImage, withName name: String, completion: ((Bool) -> Void)? = nil) {
        ioQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            let result = self.saveImageSync(image, withName: name)
            DispatchQueue.main.async { completion?(result) }
        }
    }

    func loadImage(named name: String) -> UIImage? {
        let fileURL = documentsDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return UIImage(data: data)
        } catch {
            print("Failed to load image: \(error)")
            return nil
        }
    }

    // MARK: - CRUD Operations

    /// 异步添加记录，完成后在主线程回调。不阻塞调用方。
    func addRecord(
        originalImage: UIImage,
        processedImage: UIImage,
        preset: FilmPreset,
        adjustments: AdjustmentParams,
        completion: ((PhotoEditRecord?) -> Void)? = nil
    ) {
        let id = UUID().uuidString
        let timestamp = Date()
        let dateString = Self.fileDateString(from: timestamp)

        let originalName  = "original_\(id)_\(dateString).jpg"
        let processedName = "processed_\(id)_\(dateString).jpg"
        let thumbnailName = "thumb_\(id)_\(dateString).jpg"

        let width  = Int(originalImage.size.width)
        let height = Int(originalImage.size.height)

        // FIX 1: 所有磁盘 IO 移到 ioQueue，不在主线程执行
        ioQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            guard self.saveImageSync(originalImage, withName: originalName) else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            guard self.saveImageSync(processedImage, withName: processedName) else {
                self.deleteImageSync(named: originalName)
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            let thumbnail = self.generateThumbnailSync(from: processedImage)
            _ = self.saveImageSync(thumbnail, withName: thumbnailName)

            let record = PhotoEditRecord(
                id: id,
                originalImageName: originalName,
                processedImageName: processedName,
                thumbnailName: thumbnailName,
                presetId: preset.id,
                adjustments: adjustments,
                createdAt: timestamp,
                updatedAt: timestamp,
                imageWidth: width,
                imageHeight: height
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.records.insert(record, at: 0)
                self.saveRecords()
                completion?(record)
            }
        }
    }

    /// 异步更新记录，完成后在主线程回调。不阻塞调用方。
    func updateRecord(
        id: String,
        processedImage: UIImage,
        preset: FilmPreset,
        adjustments: AdjustmentParams,
        completion: ((PhotoEditRecord?) -> Void)? = nil
    ) {
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            completion?(nil)
            return
        }

        let oldRecord = records[index]
        let timestamp = Date()
        let dateString = Self.fileDateString(from: timestamp)
        let processedName = "processed_\(id)_\(dateString).jpg"
        let thumbnailName = "thumb_\(id)_\(dateString).jpg"

        ioQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            // 删除旧文件
            self.deleteImageSync(named: oldRecord.processedImageName)
            self.deleteImageSync(named: oldRecord.thumbnailName)

            guard self.saveImageSync(processedImage, withName: processedName) else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            let thumbnail = self.generateThumbnailSync(from: processedImage)
            _ = self.saveImageSync(thumbnail, withName: thumbnailName)

            var newRecord = oldRecord
            newRecord.processedImageName = processedName
            newRecord.thumbnailName = thumbnailName
            newRecord.presetId = preset.id
            newRecord.adjustments = adjustments
            newRecord.updatedAt = timestamp

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // 再次确认 index（中途可能被删除）
                if let currentIndex = self.records.firstIndex(where: { $0.id == id }) {
                    self.records[currentIndex] = newRecord
                    self.saveRecords()
                    completion?(newRecord)
                } else {
                    completion?(nil)
                }
            }
        }
    }

    func deleteRecord(id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }

        let record = records[index]
        records.remove(at: index)
        saveRecords()

        // 删文件放后台，不影响 UI
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.deleteImageSync(named: record.originalImageName)
            self.deleteImageSync(named: record.processedImageName)
            self.deleteImageSync(named: record.thumbnailName)
        }
    }

    func clearAllRecords() {
        let snapshot = records
        records.removeAll()
        saveRecords()

        ioQueue.async { [weak self] in
            guard let self else { return }
            for record in snapshot {
                self.deleteImageSync(named: record.originalImageName)
                self.deleteImageSync(named: record.processedImageName)
                self.deleteImageSync(named: record.thumbnailName)
            }
        }
    }

    // MARK: - Group by Date

    var groupedByDate: [(date: String, records: [PhotoEditRecord])] {
        // FIX 5: 复用静态 DateFormatter
        var groups: [String: [PhotoEditRecord]] = [:]

        for record in records {
            let dateKey = record.displayDate
            if groups[dateKey] == nil {
                groups[dateKey] = []
            }
            groups[dateKey]?.append(record)
        }

        // 按日期排序（最新的在前），直接比较 createdAt 避免重新解析字符串
        let sortedKeys = groups.keys.sorted { key1, key2 in
            let d1 = groups[key1]?.first?.createdAt ?? .distantPast
            let d2 = groups[key2]?.first?.createdAt ?? .distantPast
            return d1 > d2
        }

        return sortedKeys.map { (date: $0, records: groups[$0]!) }
    }

    // MARK: - Private Helpers (ioQueue 内调用，nonisolated 使其可从 Sendable 闭包调用)

    nonisolated private func deleteImageSync(named name: String) {
        let fileURL = documentsDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // FIX 3: 用 UIGraphicsImageRenderer 替换废弃的 UIGraphicsBeginImageContextWithOptions
    nonisolated private func generateThumbnailSync(from image: UIImage, size: CGFloat = 300) -> UIImage {
        let scale = min(size / image.size.width, size / image.size.height)
        let newSize = CGSize(
            width:  (image.size.width  * scale).rounded(),
            height: (image.size.height * scale).rounded()
        )
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func fileDateString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: date)
    }
}
