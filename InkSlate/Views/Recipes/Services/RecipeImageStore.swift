//
//  RecipeImageStore.swift
//  InkSlate
//
//  Image storage service with error handling and caching
//

import UIKit
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
    private static var imageCache: [String: UIImage] = [:]
    private static let cacheQueue = DispatchQueue(label: "com.inkslate.recipeImageCache", attributes: .concurrent)
    private static let maxCacheSize = 50 // Maximum number of images to cache
    
    // MARK: - Save Image
    
    static func saveImage(data: Data, for recipeID: UUID, replacing existingPath: String?) throws -> String {
        // Validate data
        guard !data.isEmpty else {
            throw RecipeImageStoreError.invalidData
        }
        
        // Check disk space (rough estimate - need at least 2x the data size)
        let requiredSpace = Int64(data.count * 2)
        if let availableSpace = try? availableDiskSpace(), availableSpace < requiredSpace {
            throw RecipeImageStoreError.diskSpaceUnavailable
        }
        
        let directoryURL = try imagesDirectoryURL()
        
        // Remove previous image if requested
        if let path = existingPath, !path.isEmpty {
            deleteImage(at: path)
        }
        
        let fileName = "\(recipeID.uuidString).jpg"
        let fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        
        do {
            try data.write(to: fileURL, options: .atomic)
            
            // Update cache
            if let image = UIImage(data: data) {
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
    
    static func loadImage(path: String?) -> UIImage? {
        guard let path, !path.isEmpty else { return nil }
        
        // Check cache first
        if let cachedImage = getCachedImage(key: path) {
            return cachedImage
        }
        
        // Handle HTTP URLs
        if path.hasPrefix("http"), let url = URL(string: path) {
            return loadImageFromURL(url)
        }
        
        // Handle base64 data URLs
        if path.hasPrefix("data:image"),
           let base64 = path.components(separatedBy: ",").last,
           let data = Data(base64Encoded: base64),
           let image = UIImage(data: data) {
            cacheQueue.async(flags: .barrier) {
                updateCache(key: path, image: image)
            }
            return image
        }
        
        // Load from file system
        guard let directoryURL = try? imagesDirectoryURL() else { return nil }
        let fileURL = directoryURL.appendingPathComponent(path)
        
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        
        // Cache the loaded image
        cacheQueue.async(flags: .barrier) {
            updateCache(key: path, image: image)
        }
        
        return image
    }
    
    // MARK: - Delete Image
    
    static func deleteImage(at path: String?) {
        guard let path, !path.isEmpty else { return }
        
        // Remove from cache
        cacheQueue.async(flags: .barrier) {
            imageCache.removeValue(forKey: path)
        }
        
        // Delete from file system
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
            print("Error cleaning up orphaned images: \(error.localizedDescription)")
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
    
    private static func loadImageFromURL(_ url: URL) -> UIImage? {
        // For network images, we should use AsyncImage in views
        // This is a fallback for synchronous loading
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        
        cacheQueue.async(flags: .barrier) {
            updateCache(key: url.absoluteString, image: image)
        }
        
        return image
    }
    
    private static func getCachedImage(key: String) -> UIImage? {
        return cacheQueue.sync {
            imageCache[key]
        }
    }
    
    private static func updateCache(key: String, image: UIImage) {
        // Limit cache size
        if imageCache.count >= maxCacheSize {
            // Remove oldest entry (simple FIFO - in production, use LRU)
            if let firstKey = imageCache.keys.first {
                imageCache.removeValue(forKey: firstKey)
            }
        }
        
        imageCache[key] = image
    }
}

