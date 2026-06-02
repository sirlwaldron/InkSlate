import CloudKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif
import os.log

// MARK: - Dedicated zones for large binary CK assets (places, notes)

private actor PrivatePhotoZoneGate {
    private var ensuredZoneNames = Set<String>()

    func reset() {
        ensuredZoneNames.removeAll()
    }

    func ensureExists(database: CKDatabase, zoneName: String, logger: Logger) async throws {
        if ensuredZoneNames.contains(zoneName) { return }
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        do {
            _ = try await database.recordZone(for: zoneID)
        } catch let error as CKError where error.code == .zoneNotFound {
            let zone = CKRecordZone(zoneName: zoneName)
            do {
                try await Self.saveRecordZones(database: database, zonesToSave: [zone])
            } catch {
                do {
                    _ = try await database.recordZone(for: zoneID)
                } catch {
                    logger.error("CloudKit: failed to create or verify zone \(zoneName): \(error.localizedDescription)")
                    throw error
                }
            }
        }
        ensuredZoneNames.insert(zoneName)
    }

    private static func saveRecordZones(database: CKDatabase, zonesToSave: [CKRecordZone]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordZonesOperation(recordZonesToSave: zonesToSave, recordZoneIDsToDelete: nil)
            operation.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }
}

/// Manages CloudKit assets for Place photos and inline Note photos
final class CloudKitAssetService {
    static let shared = CloudKitAssetService()

    private let container: CKContainer
    private let logger = Logger(subsystem: "com.lucas.InkSlateNew", category: "CloudKitAssets")
    private let zoneGate = PrivatePhotoZoneGate()
    private var accountChangeToken: NSObjectProtocol?

    private static let placePhotosZoneName = "InkSlatePlacePhotos"

    private var placePhotosZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.placePhotosZoneName, ownerName: CKCurrentUserDefaultName)
    }

    private static let notePhotosZoneName = "InkSlateNotePhotos"

    private var notePhotosZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.notePhotosZoneName, ownerName: CKCurrentUserDefaultName)
    }
    
    private static let noteAttachmentsZoneName = "InkSlateNoteAttachments"
    
    private var noteAttachmentsZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.noteAttachmentsZoneName, ownerName: CKCurrentUserDefaultName)
    }

    private static let recipePhotosZoneName = "InkSlateRecipePhotos"

    private var recipePhotosZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.recipePhotosZoneName, ownerName: CKCurrentUserDefaultName)
    }

    private init() {
        container = CKContainer(identifier: "iCloud.com.lucas.InkSlateNew")
        accountChangeToken = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.zoneGate.reset() }
        }
    }

    deinit {
        if let accountChangeToken {
            NotificationCenter.default.removeObserver(accountChangeToken)
        }
    }

    /// Uploads an image to CloudKit as an asset and returns the asset URL
    func uploadPhoto(_ image: PlatformImage, for placeID: UUID) async throws -> String {
        let tempURL: URL = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let maxSize = 5 * 1024 * 1024
                #if canImport(UIKit)
                guard let imageData = image.inkSlateJPEGDataFitting(maxBytes: maxSize) else {
                    continuation.resume(throwing: CloudKitAssetError.imageTooLarge)
                    return
                }
                #else
                guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                    continuation.resume(throwing: CloudKitAssetError.imageConversionFailed)
                    return
                }
                guard imageData.count <= maxSize else {
                    continuation.resume(throwing: CloudKitAssetError.imageTooLarge)
                    return
                }
                #endif
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("jpg")
                do {
                    try imageData.write(to: url)
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        do {
            let asset = CKAsset(fileURL: tempURL)

            let database = container.privateCloudDatabase
            try await zoneGate.ensureExists(database: database, zoneName: Self.placePhotosZoneName, logger: logger)

            let recordID = CKRecord.ID(recordName: "PlacePhoto-\(placeID.uuidString)", zoneID: placePhotosZoneID)
            let record = CKRecord(recordType: "PlacePhoto", recordID: recordID)
            record["photo"] = asset
            record["placeID"] = placeID.uuidString

            let savedRecord = try await database.save(record)

            try? FileManager.default.removeItem(at: tempURL)

            if let photoAsset = savedRecord["photo"] as? CKAsset,
               photoAsset.fileURL != nil {
                return recordID.recordName
            }

            return recordID.recordName
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            logger.error("Failed to upload photo: \(error.localizedDescription)")
            throw error
        }
    }

    /// Downloads an image from CloudKit using the stored record name
    func downloadPhoto(recordName: String) async throws -> PlatformImage? {
        let database = container.privateCloudDatabase

        do {
            try await zoneGate.ensureExists(database: database, zoneName: Self.placePhotosZoneName, logger: logger)

            let dedicatedID = CKRecord.ID(recordName: recordName, zoneID: placePhotosZoneID)
            do {
                let record = try await database.record(for: dedicatedID)
                let image = try imageFromRecord(record)
                return image
            } catch let err as CKError where err.code == .unknownItem {
                let legacyID = CKRecord.ID(recordName: recordName)
                let record = try await database.record(for: legacyID)
                let image = try imageFromRecord(record)
                return image
            }
        } catch {
            logger.error("Failed to download photo: \(error.localizedDescription)")
            throw error
        }
    }

    /// Deletes a photo from CloudKit
    func deletePhoto(recordName: String) async throws {
        let database = container.privateCloudDatabase

        do {
            try await zoneGate.ensureExists(database: database, zoneName: Self.placePhotosZoneName, logger: logger)

            let dedicatedID = CKRecord.ID(recordName: recordName, zoneID: placePhotosZoneID)
            do {
                try await database.deleteRecord(withID: dedicatedID)
                return
            } catch let err as CKError where err.code == .unknownItem {
                let legacyID = CKRecord.ID(recordName: recordName)
                do {
                    try await database.deleteRecord(withID: legacyID)
                } catch let legacyErr as CKError where legacyErr.code == .unknownItem {
                } catch let legacyFailure {
                    throw legacyFailure
                }
                return
            }
        } catch {
            logger.error("Failed to delete photo: \(error.localizedDescription)")
            throw error
        }
    }

    /// Deletes all PlacePhoto records from CloudKit (for factory reset) by removing the dedicated custom zone
    func deleteAllPlacePhotos() async throws {
        try await deleteZone(zoneName: Self.placePhotosZoneName)
    }

    // MARK: - Recipe photos

    /// Uploads a recipe cover image to CloudKit; returns the record name (`RecipePhoto-{recipeID}`)
    func uploadRecipePhoto(_ image: PlatformImage, for recipeID: UUID) async throws -> String {
        let tempURL: URL = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let maxSize = 5 * 1024 * 1024
                #if canImport(UIKit)
                guard let imageData = image.inkSlateJPEGDataFitting(maxBytes: maxSize) else {
                    continuation.resume(throwing: CloudKitAssetError.imageTooLarge)
                    return
                }
                #else
                guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                    continuation.resume(throwing: CloudKitAssetError.imageConversionFailed)
                    return
                }
                guard imageData.count <= maxSize else {
                    continuation.resume(throwing: CloudKitAssetError.imageTooLarge)
                    return
                }
                #endif
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("jpg")
                do {
                    try imageData.write(to: url)
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        do {
            let asset = CKAsset(fileURL: tempURL)
            let database = container.privateCloudDatabase
            try await zoneGate.ensureExists(database: database, zoneName: Self.recipePhotosZoneName, logger: logger)

            let recordID = CKRecord.ID(recordName: "RecipePhoto-\(recipeID.uuidString)", zoneID: recipePhotosZoneID)
            let record = CKRecord(recordType: "RecipePhoto", recordID: recordID)
            record["photo"] = asset
            record["recipeID"] = recipeID.uuidString

            _ = try await database.save(record)
            try? FileManager.default.removeItem(at: tempURL)
            return recordID.recordName
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            logger.error("Failed to upload recipe photo: \(error.localizedDescription)")
            throw error
        }
    }

    /// Downloads a recipe cover image from CloudKit using the stored record name
    func downloadRecipePhoto(recordName: String) async throws -> PlatformImage? {
        let database = container.privateCloudDatabase
        do {
            try await zoneGate.ensureExists(database: database, zoneName: Self.recipePhotosZoneName, logger: logger)
            let dedicatedID = CKRecord.ID(recordName: recordName, zoneID: recipePhotosZoneID)
            do {
                let record = try await database.record(for: dedicatedID)
                return try imageFromRecord(record)
            } catch let err as CKError where err.code == .unknownItem {
                let legacyID = CKRecord.ID(recordName: recordName)
                let record = try await database.record(for: legacyID)
                return try imageFromRecord(record)
            }
        } catch {
            logger.error("Failed to download recipe photo: \(error.localizedDescription)")
            throw error
        }
    }

    /// Deletes a recipe cover photo from CloudKit
    func deleteRecipePhoto(recordName: String) async throws {
        let database = container.privateCloudDatabase
        do {
            try await zoneGate.ensureExists(database: database, zoneName: Self.recipePhotosZoneName, logger: logger)
            let dedicatedID = CKRecord.ID(recordName: recordName, zoneID: recipePhotosZoneID)
            do {
                try await database.deleteRecord(withID: dedicatedID)
                return
            } catch let err as CKError where err.code == .unknownItem {
                let legacyID = CKRecord.ID(recordName: recordName)
                do {
                    try await database.deleteRecord(withID: legacyID)
                } catch let legacyErr as CKError where legacyErr.code == .unknownItem {
                } catch let legacyFailure {
                    throw legacyFailure
                }
                return
            }
        } catch {
            logger.error("Failed to delete recipe photo: \(error.localizedDescription)")
            throw error
        }
    }

    /// Deletes all RecipePhoto records from CloudKit (factory reset)
    func deleteAllRecipePhotos() async throws {
        try await deleteZone(zoneName: Self.recipePhotosZoneName)
    }

    private func deleteZone(zoneName: String) async throws {
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let operation = CKModifyRecordZonesOperation(recordZonesToSave: nil, recordZoneIDsToDelete: [zoneID])
                operation.modifyRecordZonesResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                database.add(operation)
            }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
        } catch {
            logger.error("Failed to delete zone \(zoneName): \(error.localizedDescription)")
            throw error
        }
        await zoneGate.reset()
    }

    /// Deletes all CloudKit photo assets (places + notes)
    func deleteAllCloudAssetsForFactoryReset() async throws {
        var failures: [String] = []
        do {
            try await deleteAllPlacePhotos()
        } catch {
            failures.append("place photos: \(error.localizedDescription)")
        }
        do {
            try await deleteAllRecipePhotos()
        } catch {
            failures.append("recipe photos: \(error.localizedDescription)")
        }
        #if canImport(UIKit)
        do {
            try await deleteAllNotePhotos()
        } catch {
            failures.append("note photos: \(error.localizedDescription)")
        }
        #endif
        do {
            try await deleteAllNoteAttachments()
        } catch {
            failures.append("note attachments: \(error.localizedDescription)")
        }
        if !failures.isEmpty {
            throw NSError(
                domain: "InkSlate.CloudKitAssets",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: "; ")]
            )
        }
    }

    // MARK: - Note inline photos

    #if canImport(UIKit)
    /// Uploads a JPEG for an inline note image; returns the CloudKit record name (`NotePhoto-{uuid}`)
    func uploadNotePhoto(_ image: PlatformImage, noteID: UUID, attachmentID: UUID) async throws -> String {
        let tempURL: URL = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let maxSize = 5 * 1024 * 1024
                guard let imageData = image.inkSlateJPEGDataFitting(maxBytes: maxSize) else {
                    continuation.resume(throwing: CloudKitAssetError.imageTooLarge)
                    return
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("jpg")
                do {
                    try imageData.write(to: url)
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        let recordName = "NotePhoto-\(attachmentID.uuidString)"

        do {
            let asset = CKAsset(fileURL: tempURL)
            let database = container.privateCloudDatabase
            try await zoneGate.ensureExists(database: database, zoneName: Self.notePhotosZoneName, logger: logger)

            let recordID = CKRecord.ID(recordName: recordName, zoneID: notePhotosZoneID)
            let record = CKRecord(recordType: "NotePhoto", recordID: recordID)
            record["photo"] = asset
            record["noteID"] = noteID.uuidString

            _ = try await database.save(record)
            try? FileManager.default.removeItem(at: tempURL)
            return recordName
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            logger.error("Failed to upload note photo: \(error.localizedDescription)")
            throw error
        }
    }

    func downloadNotePhoto(recordName: String) async throws -> PlatformImage? {
        let database = container.privateCloudDatabase
        do {
            try await zoneGate.ensureExists(database: database, zoneName: Self.notePhotosZoneName, logger: logger)

            let dedicatedID = CKRecord.ID(recordName: recordName, zoneID: notePhotosZoneID)
            do {
                let record = try await database.record(for: dedicatedID)
                return try imageFromRecord(record)
            } catch let err as CKError where err.code == .unknownItem {
                let legacyID = CKRecord.ID(recordName: recordName)
                let record = try await database.record(for: legacyID)
                return try imageFromRecord(record)
            }
        } catch {
            logger.error("Failed to download note photo: \(error.localizedDescription)")
            throw error
        }
    }

    func deleteNotePhoto(recordName: String) async throws {
        let database = container.privateCloudDatabase
        do {
            try await zoneGate.ensureExists(database: database, zoneName: Self.notePhotosZoneName, logger: logger)

            let dedicatedID = CKRecord.ID(recordName: recordName, zoneID: notePhotosZoneID)
            do {
                try await database.deleteRecord(withID: dedicatedID)
                return
            } catch let err as CKError where err.code == .unknownItem {
                let legacyID = CKRecord.ID(recordName: recordName)
                do {
                    try await database.deleteRecord(withID: legacyID)
                } catch let legacyErr as CKError where legacyErr.code == .unknownItem {
                } catch let legacyFailure {
                    throw legacyFailure
                }
                return
            }
        } catch {
            logger.error("Failed to delete note photo: \(error.localizedDescription)")
            throw error
        }
    }

    func deleteNotePhotosForNote(noteID: UUID) async throws {
        let database = container.privateCloudDatabase
        try await zoneGate.ensureExists(database: database, zoneName: Self.notePhotosZoneName, logger: logger)

        let predicate = NSPredicate(format: "noteID == %@", noteID.uuidString as NSString)
        let query = CKQuery(recordType: "NotePhoto", predicate: predicate)
        var recordIDs: [CKRecord.ID] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let operation: CKQueryOperation
            if let cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else {
                operation = CKQueryOperation(query: query)
                operation.zoneID = notePhotosZoneID
            }
            operation.resultsLimit = 200
            let nextCursor: CKQueryOperation.Cursor? = try await withCheckedThrowingContinuation { continuation in
                operation.recordMatchedBlock = { _, result in
                    if case .success(let record) = result {
                        recordIDs.append(record.recordID)
                    }
                }
                operation.queryResultBlock = { result in
                    switch result {
                    case .success(let newCursor):
                        continuation.resume(returning: newCursor)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                database.add(operation)
            }
            cursor = nextCursor
        } while cursor != nil

        guard !recordIDs.isEmpty else { return }
        let batchSize = 200
        for batchStart in stride(from: 0, to: recordIDs.count, by: batchSize) {
            let batch = Array(recordIDs[batchStart..<min(batchStart + batchSize, recordIDs.count)])
            try await deleteRecords(database: database, recordIDs: batch)
        }
    }

    /// Deletes all `NotePhoto` records (factory reset) by removing the dedicated custom zone (see `deleteZone` / `deleteAllPlacePhotos` for why...
    func deleteAllNotePhotos() async throws {
        try await deleteZone(zoneName: Self.notePhotosZoneName)
    }
    #endif
    
    // MARK: - Note attachments (share import)
    
    /// Uploads a file as a CloudKit asset tied to a note; returns the record name (`NoteAttachment-{uuid}`)
    func uploadNoteAttachment(
        fileURL: URL,
        noteID: UUID,
        attachmentID: UUID,
        filename: String,
        uti: String?,
        kind: String
    ) async throws -> String {
        let maxSize = 20 * 1024 * 1024
        if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
           let fileSize = values.fileSize,
           fileSize > maxSize {
            throw CloudKitAssetError.fileTooLarge
        }
        
        let recordName = "NoteAttachment-\(attachmentID.uuidString)"
        let asset = CKAsset(fileURL: fileURL)
        
        let database = container.privateCloudDatabase
        try await zoneGate.ensureExists(database: database, zoneName: Self.noteAttachmentsZoneName, logger: logger)
        
        let recordID = CKRecord.ID(recordName: recordName, zoneID: noteAttachmentsZoneID)
        let record = CKRecord(recordType: "NoteAttachment", recordID: recordID)
        record["file"] = asset
        record["noteID"] = noteID.uuidString
        record["filename"] = filename
        record["uti"] = uti
        record["kind"] = kind
        
        _ = try await database.save(record)
        return recordName
    }
    
    static func noteAttachmentsCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("InkSlateNoteAttachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cachedNoteAttachmentURL(recordName: String, filename: String) -> URL {
        let safeName = filename.isEmpty ? "Attachment" : filename
        let dir = noteAttachmentsCacheDirectory().appendingPathComponent(recordName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(safeName, isDirectory: false)
    }

    private static func persistDownloadedAttachment(from assetURL: URL, recordName: String, filename: String) -> URL? {
        let dest = cachedNoteAttachmentURL(recordName: recordName, filename: filename)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: assetURL, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    /// Downloads a previously uploaded note attachment and copies it into durable on-device storage
    func downloadNoteAttachment(recordName: String) async throws -> URL? {
        let database = container.privateCloudDatabase
        try await zoneGate.ensureExists(database: database, zoneName: Self.noteAttachmentsZoneName, logger: logger)
        
        let dedicatedID = CKRecord.ID(recordName: recordName, zoneID: noteAttachmentsZoneID)
        let record: CKRecord
        do {
            record = try await database.record(for: dedicatedID)
        } catch let err as CKError where err.code == .unknownItem {
            let legacyID = CKRecord.ID(recordName: recordName)
            record = try await database.record(for: legacyID)
        }
        guard let assetURL = (record["file"] as? CKAsset)?.fileURL else { return nil }
        let filename = (record["filename"] as? String) ?? "Attachment"
        return Self.persistDownloadedAttachment(from: assetURL, recordName: recordName, filename: filename)
    }
    
    func deleteNoteAttachment(recordName: String) async throws {
        let database = container.privateCloudDatabase
        try await zoneGate.ensureExists(database: database, zoneName: Self.noteAttachmentsZoneName, logger: logger)
        
        let dedicatedID = CKRecord.ID(recordName: recordName, zoneID: noteAttachmentsZoneID)
        do {
            try await database.deleteRecord(withID: dedicatedID)
            return
        } catch let err as CKError where err.code == .unknownItem {
            let legacyID = CKRecord.ID(recordName: recordName)
            do {
                try await database.deleteRecord(withID: legacyID)
            } catch let legacyErr as CKError where legacyErr.code == .unknownItem {
            } catch let legacyFailure {
                throw legacyFailure
            }
        }
    }
    
    func deleteNoteAttachmentsForNote(noteID: UUID) async throws {
        let database = container.privateCloudDatabase
        try await zoneGate.ensureExists(database: database, zoneName: Self.noteAttachmentsZoneName, logger: logger)
        
        let predicate = NSPredicate(format: "noteID == %@", noteID.uuidString as NSString)
        let query = CKQuery(recordType: "NoteAttachment", predicate: predicate)
        var recordIDs: [CKRecord.ID] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let operation: CKQueryOperation
            if let cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else {
                operation = CKQueryOperation(query: query)
                operation.zoneID = noteAttachmentsZoneID
            }
            operation.desiredKeys = []
            operation.resultsLimit = 200
            let nextCursor: CKQueryOperation.Cursor? = try await withCheckedThrowingContinuation { continuation in
                operation.recordMatchedBlock = { _, result in
                    if case .success(let record) = result {
                        recordIDs.append(record.recordID)
                    }
                }
                operation.queryResultBlock = { result in
                    switch result {
                    case .success(let newCursor):
                        continuation.resume(returning: newCursor)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                database.add(operation)
            }
            cursor = nextCursor
        } while cursor != nil
        
        guard !recordIDs.isEmpty else { return }
        let batchSize = 200
        for batchStart in stride(from: 0, to: recordIDs.count, by: batchSize) {
            let batch = Array(recordIDs[batchStart..<min(batchStart + batchSize, recordIDs.count)])
            try await deleteRecords(database: database, recordIDs: batch)
        }
    }
    
    /// Deletes all `NoteAttachment` records (factory reset) by removing the dedicated custom zone (see `deleteZone` / `deleteAllPlacePhotos` for...
    func deleteAllNoteAttachments() async throws {
        try await deleteZone(zoneName: Self.noteAttachmentsZoneName)
    }

    private func deleteRecords(database: CKDatabase, recordIDs: [CKRecord.ID]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
            operation.isAtomic = false
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func imageFromRecord(_ record: CKRecord) throws -> PlatformImage {
        guard let photoAsset = record["photo"] as? CKAsset,
              let fileURL = photoAsset.fileURL,
              let imageData = try? Data(contentsOf: fileURL),
              let image = platformImage(from: imageData) else {
            throw CloudKitAssetError.imageLoadFailed
        }
        return image
    }

}

enum CloudKitAssetError: LocalizedError {
    case imageConversionFailed
    case imageTooLarge
    case imageLoadFailed
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image to data"
        case .imageTooLarge:
            return "Image is too large (maximum 5MB)"
        case .imageLoadFailed:
            return "Failed to load image from CloudKit"
        case .fileTooLarge:
            return "File is too large (maximum 20MB)"
        }
    }
}
