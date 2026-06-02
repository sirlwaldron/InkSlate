#if canImport(UIKit)
import UIKit
#endif
import Foundation


enum RecipeImageStoreError: LocalizedError {
    case invalidData
    case diskSpaceUnavailable
    case saveFailed(Error)
    case invalidURL
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Invalid image data"
        case .diskSpaceUnavailable:
            return "Not enough disk space available"
        case .saveFailed(let error):
            return "Failed to save image: \(error.localizedDescription)"
        case .invalidURL:
            return "Invalid image URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

final class RecipeImageStore {
    private static let folderName = "RecipeImages"
    private static var imageCache: [String: PlatformImage] = [:]
    private static let cacheQueue = DispatchQueue(label: "com.inkslate.recipeImageCache", attributes: .concurrent)
    private static let maxCacheSize = 50
    
    // MARK: - Save Image
    
    static func saveImage(data: Data, for recipeID: UUID, replacing existingPath: String?) throws -> String {
        guard !data.isEmpty else {
            throw RecipeImageStoreError.invalidData
        }
        
        let requiredSpace = Int64(data.count * 2)
        if let availableSpace = try? availableDiskSpace(), availableSpace < requiredSpace {
            throw RecipeImageStoreError.diskSpaceUnavailable
        }
        
        let directoryURL = try imagesDirectoryURL()
        
        if let path = existingPath, !path.isEmpty {
            deleteImage(at: path)
        }
        
        let fileName = "\(recipeID.uuidString).jpg"
        let fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        
        do {
            try data.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [FileAttributeKey.protectionKey: FileProtectionType.complete],
                ofItemAtPath: fileURL.path
            )
            
            if let image = platformImage(from: data) {
                cacheQueue.async(flags: .barrier) {
                    updateCache(key: fileName, image: image)
                }
            }
            
            return fileName
        } catch {
            throw RecipeImageStoreError.saveFailed(error)
        }
    }
    
    // MARK: - Load Image
    
    static func cachedImage(path: String?) -> PlatformImage? {
        guard let path, !path.isEmpty else { return nil }
        
        if let cachedImage = getCachedImage(key: path) {
            return cachedImage
        }
        return nil
    }
    
    static func loadImage(path: String?) async -> PlatformImage? {
        guard let path, !path.isEmpty else { return nil }
        
        if let cached = cachedImage(path: path) {
            return cached
        }
        
        if path.hasPrefix("data:image"),
           let base64 = path.components(separatedBy: ",").last,
           let data = Data(base64Encoded: base64),
           let image = platformImage(from: data) {
            cacheQueue.async(flags: .barrier) { updateCache(key: path, image: image) }
            return image
        }
        
        if path.hasPrefix("http"), let url = URL(string: path) {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let image = platformImage(from: data) else {
                    return nil
                }
                cacheQueue.async(flags: .barrier) { updateCache(key: url.absoluteString, image: image) }
                return image
            } catch {
                return nil
            }
        }
        
        guard let directoryURL = try? imagesDirectoryURL() else { return nil }
        let fileURL = directoryURL.appendingPathComponent(path)
        
        return await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: fileURL),
                  let image = platformImage(from: data) else {
                return nil
            }
            cacheQueue.async(flags: .barrier) { updateCache(key: path, image: image) }
            return image
        }.value
    }

    /// CloudKit record names for synced recipe cover images (`RecipePhoto-{uuid}`)
    static func isCloudRecordName(_ path: String) -> Bool {
        path.hasPrefix("RecipePhoto-")
    }

    /// Loads a recipe image from local disk or CloudKit (for cross-device sync)
    static func loadDisplayImage(path: String?) async -> PlatformImage? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return nil }
        if isCloudRecordName(path) {
            return try? await CloudKitAssetService.shared.downloadRecipePhoto(recordName: path)
        }
        return await loadImage(path: path)
    }
    
    static func fileURL(path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        guard !path.hasPrefix("http"), !path.hasPrefix("data:image") else { return nil }
        guard let directoryURL = try? imagesDirectoryURL() else { return nil }
        return directoryURL.appendingPathComponent(path)
    }
    
    // MARK: - Delete Image
    
    static func deleteImage(at path: String?) {
        guard let path, !path.isEmpty else { return }
        
        cacheQueue.async(flags: .barrier) {
            imageCache.removeValue(forKey: path)
        }
        
        guard let directoryURL = try? imagesDirectoryURL() else { return }
        let fileURL = directoryURL.appendingPathComponent(path)
        
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - Cleanup Orphaned Images
    
    static func cleanupOrphanedImages(validRecipeIDs: Set<UUID>) {
        guard let directoryURL = try? imagesDirectoryURL() else { return }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            
            for fileURL in files {
                let fileName = fileURL.lastPathComponent
                let fileIDString = fileName.replacingOccurrences(of: ".jpg", with: "")
                
                if let fileID = UUID(uuidString: fileIDString),
                   !validRecipeIDs.contains(fileID) {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        } catch {
        }
    }
    
    // MARK: - Clear Cache
    
    static func clearCache() {
        cacheQueue.async(flags: .barrier) {
            imageCache.removeAll()
        }
    }
    
    // MARK: - Private Helpers
    
    private static func imagesDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directoryURL = baseURL.appendingPathComponent(folderName, isDirectory: true)
        
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        
        return directoryURL
    }
    
    private static func availableDiskSpace() throws -> Int64 {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        let attributes = try fileManager.attributesOfFileSystem(forPath: baseURL.path)
        if let freeSize = attributes[.systemFreeSize] as? Int64 {
            return freeSize
        }
        
        throw RecipeImageStoreError.diskSpaceUnavailable
    }
    
    private static func getCachedImage(key: String) -> PlatformImage? {
        return cacheQueue.sync {
            imageCache[key]
        }
    }
    
    private static func updateCache(key: String, image: PlatformImage) {
        if imageCache.count >= maxCacheSize {
            if let firstKey = imageCache.keys.first {
                imageCache.removeValue(forKey: firstKey)
            }
        }
        
        imageCache[key] = image
    }
}

