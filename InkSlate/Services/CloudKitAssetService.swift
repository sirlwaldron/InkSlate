//
//  CloudKitAssetService.swift
//  InkSlate
//
//  Service for managing CloudKit assets for Place photos
//

import CloudKit
import UIKit
import os.log

final class CloudKitAssetService {
    static let shared = CloudKitAssetService()
    
    private let container: CKContainer
    private let logger = Logger(subsystem: "com.lucas.InkSlateNew", category: "CloudKitAssets")
    
    private init() {
        container = CKContainer(identifier: "iCloud.com.lucas.InkSlateNew")
    }
    
    /// Uploads an image to CloudKit as an asset and returns the asset URL
    func uploadPhoto(_ image: UIImage, for placeID: UUID) async throws -> String {
        // Compress image to reasonable size for CloudKit (max ~5MB recommended)
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw CloudKitAssetError.imageConversionFailed
        }
        
        // CloudKit has a 15MB limit for assets, but we'll keep it smaller
        let maxSize = 5 * 1024 * 1024 // 5MB
        guard imageData.count <= maxSize else {
            throw CloudKitAssetError.imageTooLarge
        }
        
        // Create a temporary file for the asset
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        
        do {
            try imageData.write(to: tempURL)
            let asset = CKAsset(fileURL: tempURL)
            
            // Upload to CloudKit
            let recordID = CKRecord.ID(recordName: "PlacePhoto-\(placeID.uuidString)")
            let record = CKRecord(recordType: "PlacePhoto", recordID: recordID)
            record["photo"] = asset
            record["placeID"] = placeID.uuidString
            
            let database = container.privateCloudDatabase
            let savedRecord = try await database.save(record)
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            
            // Store the record ID as the URL (we'll use this to retrieve the asset)
            if let photoAsset = savedRecord["photo"] as? CKAsset,
               let fileURL = photoAsset.fileURL {
                let assetURL = fileURL.absoluteString
                logger.info("✅ Photo uploaded successfully: \(assetURL)")
                return recordID.recordName // Store record name to retrieve later
            }
            
            return recordID.recordName
        } catch {
            // Clean up temp file on error
            try? FileManager.default.removeItem(at: tempURL)
            logger.error("❌ Failed to upload photo: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Downloads an image from CloudKit using the stored record name
    func downloadPhoto(recordName: String) async throws -> UIImage? {
        let recordID = CKRecord.ID(recordName: recordName)
        let database = container.privateCloudDatabase
        
        do {
            let record = try await database.record(for: recordID)
            
            guard let photoAsset = record["photo"] as? CKAsset,
                  let fileURL = photoAsset.fileURL,
                  let imageData = try? Data(contentsOf: fileURL),
                  let image = UIImage(data: imageData) else {
                throw CloudKitAssetError.imageLoadFailed
            }
            
            logger.info("✅ Photo downloaded successfully")
            return image
        } catch {
            logger.error("❌ Failed to download photo: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Deletes a photo from CloudKit
    func deletePhoto(recordName: String) async throws {
        let recordID = CKRecord.ID(recordName: recordName)
        let database = container.privateCloudDatabase
        
        do {
            try await database.deleteRecord(withID: recordID)
            logger.info("✅ Photo deleted successfully")
        } catch {
            logger.error("❌ Failed to delete photo: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Deletes all PlacePhoto records from CloudKit (for factory reset)
    func deleteAllPlacePhotos() async throws {
        let database = container.privateCloudDatabase
        let query = CKQuery(recordType: "PlacePhoto", predicate: NSPredicate(value: true))
        
        do {
            let (matchResults, _) = try await database.records(matching: query)
            var recordIDsToDelete: [CKRecord.ID] = []
            
            for (_, result) in matchResults {
                switch result {
                case .success(let record):
                    recordIDsToDelete.append(record.recordID)
                case .failure(let error):
                    logger.error("❌ Failed to fetch photo record: \(error.localizedDescription)")
                }
            }
            
            // Delete all records in batches
            if !recordIDsToDelete.isEmpty {
                for recordID in recordIDsToDelete {
                    try? await database.deleteRecord(withID: recordID)
                }
                logger.info("✅ Deleted \(recordIDsToDelete.count) PlacePhoto records")
            }
        } catch {
            logger.error("❌ Failed to delete all place photos: \(error.localizedDescription)")
            // Don't throw - factory reset should continue even if photo deletion fails
        }
    }
}

enum CloudKitAssetError: LocalizedError {
    case imageConversionFailed
    case imageTooLarge
    case imageLoadFailed
    
    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image to data"
        case .imageTooLarge:
            return "Image is too large (maximum 5MB)"
        case .imageLoadFailed:
            return "Failed to load image from CloudKit"
        }
    }
}


