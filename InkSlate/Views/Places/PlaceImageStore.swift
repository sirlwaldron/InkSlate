#if canImport(UIKit)
import UIKit
#endif
import Foundation
import CoreData

/// Local disk cache + CloudKit display helper for place cover photos.
enum PlaceImageStore {
    private static let folderName = "PlaceImages"
    private static var imageCache: [String: PlatformImage] = [:]
    private static let cacheQueue = DispatchQueue(label: "com.inkslate.placeImageCache", attributes: .concurrent)

    static func isCloudRecordName(_ path: String) -> Bool {
        path.hasPrefix("PlacePhoto-")
    }

    static func normalizedJPEGData(from image: PlatformImage, maxBytes: Int = 5 * 1024 * 1024) -> Data? {
        if let fitted = image.inkSlateJPEGDataFitting(maxBytes: maxBytes) {
            return fitted
        }
        return image.jpegData(compressionQuality: 0.7)
    }

    static func saveImage(_ image: PlatformImage, for placeID: UUID, replacing existingPath: String?) throws -> String {
        guard let data = normalizedJPEGData(from: image), !data.isEmpty else {
            throw PlaceImageStoreError.invalidData
        }

        if let path = existingPath, !path.isEmpty, !isCloudRecordName(path), !path.hasPrefix("http") {
            deleteImage(at: path)
        }

        let directoryURL = try imagesDirectoryURL()
        let fileName = "\(placeID.uuidString).jpg"
        let fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: fileURL, options: .atomic)
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [FileAttributeKey.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
        #endif
        cacheQueue.async(flags: .barrier) {
            imageCache[fileName] = image
        }
        return fileName
    }

    static func cachedImage(path: String?) -> PlatformImage? {
        guard let path, !path.isEmpty else { return nil }
        return cacheQueue.sync { imageCache[path] }
    }

    static func loadImage(path: String?) async -> PlatformImage? {
        guard let path, !path.isEmpty else { return nil }
        if let cached = cachedImage(path: path) {
            return cached
        }
        guard let directoryURL = try? imagesDirectoryURL() else { return nil }
        let fileURL = directoryURL.appendingPathComponent(path)
        return await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: fileURL),
                  let image = platformImage(from: data) else { return nil }
            cacheQueue.async(flags: .barrier) { imageCache[path] = image }
            return image
        }.value
    }

    static func loadDisplayImage(path: String?) async -> PlatformImage? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return nil }

        if let cached = cachedImage(path: path) {
            return cached
        }

        if let disk = await loadImageFromDisk(path: path) {
            return disk
        }

        if isCloudRecordName(path) {
            guard let image = try? await CloudKitAssetService.shared.downloadPhoto(recordName: path) else {
                return nil
            }
            persistDownloadedCloudImage(image, recordName: path)
            return image
        }

        return await loadImage(path: path)
    }

    /// Writes a CloudKit photo into Documents/PlaceImages so reopen does not hit the network.
    static func cacheSyncedImage(_ image: PlatformImage, recordName: String) {
        persistDownloadedCloudImage(image, recordName: recordName)
    }

    private static func persistDownloadedCloudImage(_ image: PlatformImage, recordName: String) {
        cacheQueue.async(flags: .barrier) {
            imageCache[recordName] = image
        }
        guard let data = normalizedJPEGData(from: image),
              let directoryURL = try? imagesDirectoryURL() else { return }
        let fileURL = diskFileURL(for: recordName, in: directoryURL)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func diskFileURL(for path: String, in directoryURL: URL) -> URL {
        if path.lowercased().hasSuffix(".jpg") || path.lowercased().hasSuffix(".jpeg") || path.lowercased().hasSuffix(".png") {
            return directoryURL.appendingPathComponent(path, isDirectory: false)
        }
        return directoryURL.appendingPathComponent(path + ".jpg", isDirectory: false)
    }

    private static func loadImageFromDisk(path: String) async -> PlatformImage? {
        guard let directoryURL = try? imagesDirectoryURL() else { return nil }
        let candidates = [
            diskFileURL(for: path, in: directoryURL),
            directoryURL.appendingPathComponent(path, isDirectory: false)
        ]
        return await Task.detached(priority: .userInitiated) {
            for fileURL in candidates {
                guard let data = try? Data(contentsOf: fileURL),
                      let image = platformImage(from: data) else { continue }
                cacheQueue.async(flags: .barrier) { imageCache[path] = image }
                return image
            }
            return nil
        }.value
    }

    static func deleteImage(at path: String?) {
        guard let path, !path.isEmpty else { return }
        cacheQueue.async(flags: .barrier) {
            imageCache.removeValue(forKey: path)
        }
        guard let directoryURL = try? imagesDirectoryURL() else { return }
        let candidates = [
            diskFileURL(for: path, in: directoryURL),
            directoryURL.appendingPathComponent(path, isDirectory: false)
        ]
        for fileURL in candidates {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Uploads place covers that are still local-only so they sync across devices.
    @MainActor
    static func migrateLocalPhotosToCloudKit(in context: NSManagedObjectContext) async {
        let request = Place.fetchRequest()
        request.predicate = NSPredicate(
            format: "photoURL != nil AND photoURL != '' AND NOT (photoURL BEGINSWITH %@) AND NOT (photoURL BEGINSWITH %@)",
            "PlacePhoto-",
            "http"
        )
        guard let places = try? context.fetch(request), !places.isEmpty else { return }

        var didChange = false
        var localPathsToDelete: [String] = []
        for place in places {
            guard let placeID = place.id,
                  let path = place.photoURL,
                  !path.isEmpty,
                  let image = await loadImage(path: path)
            else { continue }

            do {
                let recordName = try await CloudKitAssetService.shared.uploadPhoto(image, for: placeID)
                place.photoURL = recordName
                cacheSyncedImage(image, recordName: recordName)
                localPathsToDelete.append(path)
                didChange = true
            } catch {
                // Keep local file; retry later.
            }
        }

        if didChange {
            if context.inkSlateSave(module: "Places") {
                for path in localPathsToDelete {
                    deleteImage(at: path)
                }
            }
        }
    }

    private static func imagesDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directoryURL = baseURL.appendingPathComponent(folderName, isDirectory: true)
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL
    }
}

enum PlaceImageStoreError: LocalizedError {
    case invalidData

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Invalid image data"
        }
    }
}
