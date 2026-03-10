//
//  PersistenceController.swift
//  InkSlate
//
//  Created by Lucas Waldron on 1/2/25.
//

import CoreData
import CloudKit
import Combine
import os.log
import UIKit

// MARK: - PersistenceController

final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer
    private let logger = Logger(subsystem: "com.lucas.InkSlateNew", category: "CloudKit")
    private var cancellables = Set<AnyCancellable>()
    
    @Published private(set) var syncStatus: CloudKitStatus = .unknown
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date? {
        didSet {
            if let date = lastSyncDate {
                UserDefaults.standard.set(date, forKey: "lastSyncDate")
            }
        }
    }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "InkSlate")

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            guard let description = container.persistentStoreDescriptions.first else {
                fatalError("Failed to retrieve a persistent store description.")
            }

            // Enable CloudKit syncing
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            // Configure CloudKit container
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.lucas.InkSlateNew"
            )
            
            // Optimize for lazy loading - Core Data will fetch in batches
            // This reduces memory usage for large datasets
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            
            // Note: fetchBatchSize is configured on NSFetchRequest objects, not on store descriptions

            logger.info("CloudKit configured: iCloud.com.lucas.InkSlateNew")
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                self.logger.error("❌ Failed to load store: \(error.localizedDescription)")
                if error.domain == CKErrorDomain {
                    self.logger.error("CloudKit error details: \(error.userInfo)")
                }
                return
            }
            self.logger.info("✅ Persistent store loaded successfully")
            
            // Delay migration to allow CloudKit to initialize schema first
            // Run on background thread to avoid blocking CloudKit sync
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.migrateWantToWatchItemsIfNeeded()
            }
        }

        // Context setup for optimal CloudKit sync
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        try? container.viewContext.setQueryGenerationFrom(.current)
        
        // Restore persisted last sync date
        lastSyncDate = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date

        // Register for CloudKit push notifications
        UIApplication.shared.registerForRemoteNotifications()

        // Start monitoring
        setupCloudKitMonitoring()
        checkInitialCloudKitStatus()
    }

    // MARK: - CloudKit Monitoring

    private func setupCloudKitMonitoring() {
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .compactMap { $0.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event }
            .sink { [weak self] event in
                self?.handleCloudKitEvent(event)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .sink { [weak self] _ in
                self?.handleRemoteChange()
            }
            .store(in: &cancellables)
        
        // Respond immediately when the iCloud account status changes (e.g., user signs in/out)
        NotificationCenter.default.publisher(for: Notification.Name.CKAccountChanged)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.logger.info("🔄 iCloud account status changed – rechecking CloudKit status")
                Task { @MainActor in
                    await self.checkCloudKitStatus()
                }
            }
            .store(in: &cancellables)
        
        // Removed periodic timer polling - rely on push notifications and account change events
        // This reduces battery usage and unnecessary network requests
    }

    private func handleCloudKitEvent(_ event: NSPersistentCloudKitContainer.Event) {
        let emoji: String
        switch event.type {
        case .setup:
            emoji = "⚙️"
            logger.info("\(emoji) CloudKit setup")
            // After setup completes, ensure schema is ready
            if event.endDate != nil {
                logger.info("📋 CloudKit setup complete - schema should be initialized")
            }
        case .import:
            emoji = "⬇️"
            logger.info("\(emoji) Importing from cloud (\(event.succeeded ? "succeeded" : "in progress"))")
            isSyncing = event.endDate == nil
        case .export:
            emoji = "⬆️"
            logger.info("\(emoji) Exporting to cloud (\(event.succeeded ? "succeeded" : "in progress"))")
            isSyncing = event.endDate == nil
        @unknown default:
            emoji = "❓"
            logger.warning("\(emoji) Unknown CloudKit event")
        }

        if let error = event.error {
            logger.error("❌ CloudKit \(String(describing: event.type)) error: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                if nsError.domain == NSURLErrorDomain {
                    logger.warning("🌐 Network error - sync will retry when online")
                } else if nsError.domain == CKErrorDomain {
                    let ckError = error as? CKError
                    if ckError?.code == .serverRecordChanged || ckError?.code == .notAuthenticated {
                        logger.warning("⚠️ CloudKit authentication or schema issue - may need to sign in to iCloud")
                    } else if ckError?.code == .batchRequestFailed {
                        logger.warning("⚠️ CloudKit batch request failed - schema may still be initializing")
                    }
                    logger.error("CloudKit error details: \(nsError.userInfo)")
                }
            }
        } else if event.endDate != nil {
            logger.info("✅ CloudKit \(String(describing: event.type)) completed")
            lastSyncDate = event.endDate
            isSyncing = false
        }
    }

    private func handleRemoteChange() {
        logger.info("☁️ Remote changes detected")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .cloudKitDataRefreshed, object: nil)
        }
    }

    // MARK: - CloudKit Status

    private func checkInitialCloudKitStatus() {
        Task { await checkCloudKitStatus() }
    }

    @MainActor
    func checkCloudKitStatus() async {
        let container = CKContainer(identifier: "iCloud.com.lucas.InkSlateNew")
        do {
            let status = try await container.accountStatus()
            let newStatus = CloudKitStatus.from(accountStatus: status)
            if self.syncStatus != newStatus {
                logger.info("📊 CloudKit status changed: \(newStatus.description)")
                self.syncStatus = newStatus
            }
        } catch {
            logger.error("❌ Failed to check status: \(error.localizedDescription)")
            self.syncStatus = .error
        }
    }

    // MARK: - Core Data Operations

    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        
        do {
            try context.save()
            logger.info("💾 Context saved")
        } catch {
            logger.error("❌ Save failed: \(error.localizedDescription)")
        }
    }
    
    /// Enhanced save that ensures CloudKit metadata is set and triggers sync
    func saveWithSync() {
        let context = container.viewContext
        
        // Ensure all new objects have proper metadata
        for object in context.insertedObjects {
            object.ensureCloudKitMetadata()
        }
        
        // Update modifiedDate for changed objects
        for object in context.updatedObjects {
            if object.responds(to: Selector(("modifiedDate"))) {
                object.setValue(Date(), forKey: "modifiedDate")
            }
        }
        
        guard context.hasChanges else { return }
        
        do {
            try context.save()
            logger.info("💾 Context saved with CloudKit sync metadata")
            
            // Post notification that data changed - helps trigger sync
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .dataSaved, object: nil)
            }
        } catch {
            logger.error("❌ Save failed: \(error.localizedDescription)")
        }
    }
    
    /// Force a refresh from CloudKit by resetting query generation
    func refreshFromCloud() {
        let context = container.viewContext
        context.refreshAllObjects()
        try? context.setQueryGenerationFrom(.current)
        logger.info("🔄 Forced refresh from CloudKit")
    }

    func backgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }
    
    /// Migrate existing WantToWatchItem records to set mediaCategory based on isMovie
    /// Runs on background context to avoid interfering with CloudKit sync
    private func migrateWantToWatchItemsIfNeeded() {
        let context = backgroundContext()
        context.perform {
            let fetchRequest: NSFetchRequest<WantToWatchItem> = WantToWatchItem.fetchRequest()
            
            // Only fetch items that don't have mediaCategory set or have empty string
            fetchRequest.predicate = NSPredicate(format: "mediaCategory == nil OR mediaCategory == ''")
            
            do {
                let itemsToMigrate = try context.fetch(fetchRequest)
                
                if !itemsToMigrate.isEmpty {
                    self.logger.info("🔄 Migrating \(itemsToMigrate.count) WantToWatchItem records to set mediaCategory")
                    
                    for item in itemsToMigrate {
                        // Set category based on isMovie flag
                        item.mediaCategory = item.isMovie ? "movie" : "tv"
                        item.modifiedDate = Date()
                    }
                    
                    if context.hasChanges {
                        try context.save()
                        self.logger.info("✅ Successfully migrated WantToWatchItem records")
                    }
                } else {
                    self.logger.info("✓ No items need migration - all have mediaCategory set")
                }
            } catch {
                self.logger.error("❌ Failed to migrate WantToWatchItem records: \(error.localizedDescription)")
                // Don't crash if migration fails - CloudKit will handle schema updates
                if let nsError = error as NSError? {
                    if nsError.domain == CKErrorDomain {
                        self.logger.warning("⚠️ CloudKit error during migration - this may be normal during schema initialization")
                    }
                }
            }
        }
    }
    
    /// Save on background context to avoid blocking main thread
    func saveInBackground() {
        let context = backgroundContext()
        context.perform {
            do {
                if context.hasChanges {
                    try context.save()
                    self.logger.info("💾 Background context saved")
                }
            } catch {
                self.logger.error("❌ Background save failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// Batch save multiple changes with debouncing
    func batchSave(debounceTime: TimeInterval = 2.0) {
        // Cancel any pending batch save
        batchSaveWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.saveInBackground()
        }
        batchSaveWorkItem = workItem
        
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + debounceTime, execute: workItem)
    }
    
    private var batchSaveWorkItem: DispatchWorkItem?

    // MARK: - Preview

    static var preview: PersistenceController = {
        PersistenceController(inMemory: true)
    }()
}

// MARK: - CloudKitStatus

enum CloudKitStatus: Equatable {
    case available
    case noAccount
    case temporarilyUnavailable
    case restricted
    case couldNotDetermine
    case unknown
    case error

    var description: String {
        switch self {
        case .available: return "✅ Syncing with iCloud"
        case .noAccount: return "⚠️ No iCloud account"
        case .temporarilyUnavailable: return "⏸️ iCloud temporarily unavailable"
        case .restricted: return "🚫 iCloud account restricted"
        case .couldNotDetermine: return "❓ Cannot determine iCloud status"
        case .unknown: return "🔍 Checking iCloud status..."
        case .error: return "❌ iCloud error"
        }
    }

    var isAvailable: Bool { self == .available }
    
    var systemImage: String {
        switch self {
        case .available: return "icloud.fill"
        case .noAccount: return "icloud.slash"
        case .temporarilyUnavailable: return "icloud.and.arrow.down"
        case .restricted: return "exclamationmark.icloud"
        case .couldNotDetermine, .unknown: return "icloud"
        case .error: return "xmark.icloud"
        }
    }

    static func from(accountStatus: CKAccountStatus) -> CloudKitStatus {
        switch accountStatus {
        case .available: return .available
        case .noAccount: return .noAccount
        case .temporarilyUnavailable: return .temporarilyUnavailable
        case .restricted: return .restricted
        case .couldNotDetermine: return .couldNotDetermine
        @unknown default: return .unknown
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let cloudKitDataRefreshed = Notification.Name("cloudKitDataRefreshed")
    static let dataSaved = Notification.Name("dataSaved")
}
