import CoreData
import Foundation
import Security
import os

final class FactoryResetService {
    static let shared = FactoryResetService()

    private let log = Logger(subsystem: "com.lucas.InkSlateNew", category: "FactoryReset")

    private init() {}

    private enum Keys {
        static let resetToken = "factoryReset.resetToken"
        static let resetRequestedAt = "factoryReset.requestedAt"
        static let lastHandledToken = "factoryReset.lastHandledToken"
    }

    @MainActor
    func requestRemoteReset() -> String {
        let token = UUID().uuidString
        let cloud = NSUbiquitousKeyValueStore.default
        cloud.set(token, forKey: Keys.resetToken)
        cloud.set(Date().timeIntervalSince1970, forKey: Keys.resetRequestedAt)
        cloud.synchronize()
        UserDefaults.standard.set(token, forKey: Keys.lastHandledToken)
        return token
    }

    // MARK: - Remote (cross-device) reset — USER-CONFIRMED OPT-IN

    struct RemoteResetRequest: Equatable {
        let token: String
        let requestedAt: Date
    }

    private static let remoteResetValidityWindow: TimeInterval = 7 * 24 * 60 * 60

    @MainActor
    func pendingRemoteReset() -> RemoteResetRequest? {
        let cloud = NSUbiquitousKeyValueStore.default
        cloud.synchronize()
        let defaults = UserDefaults.standard

        guard let token = cloud.string(forKey: Keys.resetToken), !token.isEmpty else { return nil }
        guard defaults.string(forKey: Keys.lastHandledToken) != token else { return nil }

        let requestedAtRaw = cloud.double(forKey: Keys.resetRequestedAt)
        guard requestedAtRaw > 0 else { return nil }
        let requestedAt = Date(timeIntervalSince1970: requestedAtRaw)
        guard Date().timeIntervalSince(requestedAt) <= Self.remoteResetValidityWindow else { return nil }

        return RemoteResetRequest(token: token, requestedAt: requestedAt)
    }

    @MainActor
    func confirmRemoteReset(token: String, viewContext: NSManagedObjectContext, shared: SharedStateManager) throws {
        log.warning("User confirmed remote factory reset; token=\(token)")
        UserDefaults.standard.set(token, forKey: Keys.lastHandledToken)
        try performLocalReset(viewContext: viewContext, shared: shared, preserveResetToken: true)
    }

    @MainActor
    func dismissRemoteReset(token: String) {
        UserDefaults.standard.set(token, forKey: Keys.lastHandledToken)
    }

    @MainActor
    func performLocalReset(
        viewContext: NSManagedObjectContext,
        shared: SharedStateManager,
        preserveResetToken: Bool
    ) throws {
        for entity in Self.entitiesToWipe {
            try batchDelete(entityName: entity, viewContext: viewContext)
        }

        viewContext.reset()

        let defaults = UserDefaults.standard
        for key in InkSlateUserDefaultsKeys.all {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()

        InkSlateNotificationService.shared.removeAllPendingNotifications()

        clearICloudKeyValueStore(preservingResetToken: preserveResetToken)
        clearKeychainData()
        clearLocalFileStorage()

        ProfileService.shared.resetToDefaults()
        shared.resetToDefaults()
    }

    // MARK: - Core Data

    private static let entitiesToWipe: [String] = [
        "Notes", "FSProject", "ProjectSettings", "FSTag",
        "JournalBook", "JournalEntry",
        "TodoTab", "TodoTask",
        "MindMap", "MindMapNode",
        "PlaceCategory", "Place",
        "Quote", "WantToWatchItem",
        "BudgetCategory", "BudgetSubcategory", "BudgetItem",
        "Recipe", "RecipeIngredient",
        "ShoppingItemEntity", "PantryItemEntity"
    ]

    private func batchDelete(entityName: String, viewContext: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetchRequest.includesPropertyValues = false
        fetchRequest.includesSubentities = true

        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs

        let result = try viewContext.execute(deleteRequest) as? NSBatchDeleteResult
        let objectIDs = (result?.result as? [NSManagedObjectID]) ?? []
        if !objectIDs.isEmpty {
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                into: [viewContext]
            )
        }
    }

    // MARK: - iCloud KV / Keychain / Files

    private func clearICloudKeyValueStore(preservingResetToken: Bool) {
        let cloud = NSUbiquitousKeyValueStore.default
        let keys = cloud.dictionaryRepresentation.keys
        for key in keys {
            if preservingResetToken, key == Keys.resetToken || key == Keys.resetRequestedAt { continue }
            cloud.removeObject(forKey: key)
        }
        cloud.synchronize()
    }

    private func clearKeychainData() {
        let keychainService = "co.inkslate.encryption"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            log.error("Keychain clear failed: OSStatus \(status)")
        }
    }

    private func clearLocalFileStorage() {
        let fm = FileManager.default

        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let docPaths: [(String, Bool)] = [
                ("profile-user-image.jpg", false),
                ("RecipeImages", true)
            ]
            for (relative, isDir) in docPaths {
                let url = docs.appendingPathComponent(relative, isDirectory: isDir)
                if fm.fileExists(atPath: url.path) { try? fm.removeItem(at: url) }
            }
        }

        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let notePhotosCache = appSupport
                .appendingPathComponent("InkSlate", isDirectory: true)
                .appendingPathComponent("NotePhotos", isDirectory: true)
            removeIfNotPersistentStore(notePhotosCache, fm: fm)
        }

        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let legacy = caches.appendingPathComponent("InkSlateNotePhotoCache", isDirectory: true)
            if fm.fileExists(atPath: legacy.path) { try? fm.removeItem(at: legacy) }
        }

// App Group share-import payload + downloaded attachments. These are written by the share
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: SharedImportManager.appGroupID) {
            let pending = group.appendingPathComponent("pending-share-import.json", isDirectory: false)
            if fm.fileExists(atPath: pending.path) { try? fm.removeItem(at: pending) }
            let attachments = group.appendingPathComponent("share-import-attachments", isDirectory: true)
            if fm.fileExists(atPath: attachments.path) { try? fm.removeItem(at: attachments) }
        }
    }

    /// Removes `url` only if it is not (and does not contain) an active Core Data store file
    private func removeIfNotPersistentStore(_ url: URL, fm: FileManager) {
        guard fm.fileExists(atPath: url.path) else { return }
        let storePaths = Set(
            PersistenceController.shared.container.persistentStoreCoordinator.persistentStores
                .compactMap { $0.url?.standardizedFileURL.path }
        )
        let target = url.standardizedFileURL.path
        if storePaths.contains(target) { return }
        if storePaths.contains(where: { $0.hasPrefix(target + "/") }) { return }
        try? fm.removeItem(at: url)
    }
}

