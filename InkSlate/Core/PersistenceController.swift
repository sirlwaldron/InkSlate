import CoreData
import CloudKit
import Combine
import os.log
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - PersistenceController

final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer
    private let logger = Logger(subsystem: "com.lucas.InkSlateNew", category: "CloudKit")
    private var cancellables = Set<AnyCancellable>()
    private var dailyJournalEnsureWorkItem: DispatchWorkItem?
    private var isRunningDailyJournalEnsure = false
    private var lastRemoteDailyEnsureDay: Date?
    
    @Published private(set) var syncStatus: CloudKitStatus = .unknown
    @Published private(set) var isSyncing = false
    /// When true, the SQLite store failed to load; the app should show a blocking error instead of normal UI
    @Published private(set) var persistentStoreLoadFailed = false
    @Published private(set) var lastSyncDate: Date? {
        didSet {
            if let date = lastSyncDate {
                UserDefaults.standard.set(date, forKey: "lastSyncDate")
            }
        }
    }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "InkSlate")

        let description: NSPersistentStoreDescription
        if let existing = container.persistentStoreDescriptions.first {
            description = existing
        } else {
            logger.error("InkSlate: Missing persistent store description; creating a default description.")
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let storeURL = (appSupport ?? FileManager.default.temporaryDirectory)
                .appendingPathComponent("InkSlate.sqlite", isDirectory: false)
            description = NSPersistentStoreDescription(url: storeURL)
            container.persistentStoreDescriptions = [description]
            DispatchQueue.main.async {
                self.persistentStoreLoadFailed = true
            }
        }

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            
            description.setOption(FileProtectionType.complete as NSObject, forKey: NSPersistentStoreFileProtectionKey)

            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.lucas.InkSlateNew"
            )
            
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                self.logger.error("Failed to load store: \(error.localizedDescription)")
                if error.domain == CKErrorDomain {
                    self.logger.error("CloudKit error details: \(error.userInfo)")
                }
                DispatchQueue.main.async {
                    self.persistentStoreLoadFailed = true
                }
                return
            }
            DispatchQueue.main.async {
                self.persistentStoreLoadFailed = false
            }

            DispatchQueue.main.async {
                self.ensureDailyJournalBooksConfiguredAfterPersistentStoreLoad()
            }
            
            // Defer migrations ~2s so CloudKit schema init is not blocked.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.migrateWantToWatchItemsIfNeeded()
                self.migrateInkSlateSchemaFixupsIfNeeded()
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        // Property-level merge: local edits win; notes editor adds explicit save-time conflict handling.
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        // Unpinned viewContext so CloudKit imports appear in fetches (pinning hides remote rows).
        
        lastSyncDate = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date

        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #endif

        setupCloudKitMonitoring()
        checkInitialCloudKitStatus()
    }

    // MARK: - CloudKit Monitoring

    private func setupCloudKitMonitoring() {
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .compactMap { $0.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleCloudKitEvent(event)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleRemoteChange()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: Notification.Name.CKAccountChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.checkCloudKitStatus()
                }
            }
            .store(in: &cancellables)
        
    }

    private func handleCloudKitEvent(_ event: NSPersistentCloudKitContainer.Event) {
        switch event.type {
        case .import, .export:
            isSyncing = event.endDate == nil
        case .setup:
            break
        @unknown default:
            break
        }

        if let error = event.error {
            logger.error("CloudKit \(String(describing: event.type)) error: \(error.localizedDescription)")
            if let nsError = error as NSError?, nsError.domain == CKErrorDomain {
                logger.error("CloudKit error details: \(nsError.userInfo)")
            }
            // Ignore transient CloudKit errors (offline, throttling, token refresh) for sync banner state.
            if Self.isPersistentCloudKitError(error) {
                syncStatus = .error
            }
            isSyncing = false
        } else if event.endDate != nil {
            lastSyncDate = event.endDate
            isSyncing = false
            if syncStatus == .error {
                syncStatus = .available
            }
        }
    }

    /// True for CloudKit errors that indicate a real, persistent sync problem worth surfacing to the user as `.error`
    private static func isPersistentCloudKitError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == CKErrorDomain, let code = CKError.Code(rawValue: nsError.code) else {
            return true
        }
        switch code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
             .zoneBusy, .partialFailure, .batchRequestFailed, .changeTokenExpired,
             .serverRecordChanged, .unknownItem, .operationCancelled:
            return false
        default:
            return true
        }
    }

    private func handleRemoteChange() {
        // Advance query generation so newly imported CloudKit rows are visible in fetches.
        try? container.viewContext.setQueryGenerationFrom(.current)
        NotificationCenter.default.post(name: .cloudKitDataRefreshed, object: nil)
        // Throttle daily-journal ensure to once per day on this path (launch/bookshelf still run it).
        let now = Date()
        if let last = lastRemoteDailyEnsureDay, Calendar.current.isDate(last, inSameDayAs: now) {
            return
        }
        lastRemoteDailyEnsureDay = now
        runDailyJournalEnsure()
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
                self.syncStatus = newStatus
            }
        } catch {
            logger.error("Failed to check status: \(error.localizedDescription)")
            self.syncStatus = .error
        }
    }

    // MARK: - Core Data Operations

    func purgeTrashedNotesOlderThan30Days(in context: NSManagedObjectContext) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Notes")
        let deletedPred = NSPredicate(format: "isMarkedDeleted == YES AND deletedDate != nil AND deletedDate < %@", cutoff as NSDate)
        let legacyPred = NSPredicate(format: "isMarkedDeleted == YES AND deletedDate == nil AND modifiedDate < %@", cutoff as NSDate)
        fetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [deletedPred, legacyPred])

        // Collect note IDs before batch delete so CloudKit photo/attachment cleanup can still run.
        let idFetch = NSFetchRequest<Notes>(entityName: "Notes")
        idFetch.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [deletedPred, legacyPred])
        idFetch.propertiesToFetch = ["id"]
        let doomedIDs: [UUID] = ((try? context.fetch(idFetch)) ?? []).compactMap { $0.id }

        let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        batchDelete.resultType = .resultTypeObjectIDs
        do {
            let result = try context.execute(batchDelete) as? NSBatchDeleteResult
            let objectIDArray = result?.result as? [NSManagedObjectID]
            let changes = [NSDeletedObjectsKey: objectIDArray ?? []]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])

// Clean up orphaned CloudKit assets for the purged notes (photos + share-import
            for uid in doomedIDs {
                Task {
                    #if canImport(UIKit)
                    try? await CloudKitAssetService.shared.deleteNotePhotosForNote(noteID: uid)
                    #endif
                    try? await CloudKitAssetService.shared.deleteNoteAttachmentsForNote(noteID: uid)
                }
            }
            let viewContext = container.viewContext
            if context !== viewContext {
                viewContext.perform {
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
                }
            }
        } catch {
            logger.error("Purge trashed notes failed: \(error.localizedDescription)")
        }
    }

    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        
        do {
            try context.save()
        } catch {
            logger.error("Save failed: \(error.localizedDescription)")
            ErrorHandlingService.shared.handleError(error, context: "Could not save your changes")
        }
    }
    
    /// Enhanced save that ensures CloudKit metadata is set and triggers sync
    func saveWithSync() {
        let context = container.viewContext
        
        for object in context.insertedObjects {
            object.ensureCloudKitMetadata()
        }
        
        for object in context.updatedObjects {
            if object.responds(to: Selector(("modifiedDate"))) {
                object.setValue(Date(), forKey: "modifiedDate")
            }
        }
        
        guard context.hasChanges else { return }
        
        do {
            try context.save()

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .dataSaved, object: nil)
            }
        } catch {
            logger.error("Save failed: \(error.localizedDescription)")
            ErrorHandlingService.shared.handleError(error, context: "Could not save your changes (sync)")
        }
    }

    func refreshFromCloud() {
        let context = container.viewContext
        context.refreshAllObjects()
        try? context.setQueryGenerationFrom(.current)
    }

    func backgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }
    
    /// After the store loads: sync daily flags when data is already present; if the store is empty, defer creation briefly so CloudKit can impor...
    func ensureDailyJournalBooksConfiguredAfterPersistentStoreLoad() {
        scheduleDailyJournalEnsure(deferEmptyStoreCreate: true)
    }
    
    func ensureDailyJournalBooksConfiguredFromBookshelf() {
        scheduleDailyJournalEnsure(deferEmptyStoreCreate: false)
    }
    
    private func scheduleDailyJournalEnsure(deferEmptyStoreCreate: Bool) {
        let context = container.viewContext
        var bookCount = 0
        context.performAndWait {
            bookCount = (try? context.count(for: JournalBook.fetchRequest())) ?? 0
        }
        dailyJournalEnsureWorkItem?.cancel()

        let delay: TimeInterval = (deferEmptyStoreCreate && bookCount == 0) ? 1.5 : 0.0
        let item = DispatchWorkItem { [weak self] in
            self?.runDailyJournalEnsure()
        }
        dailyJournalEnsureWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
    
    private func runDailyJournalEnsure() {
// Prevent concurrent ensures from racing and creating duplicates.
        guard !isRunningDailyJournalEnsure else { return }
        isRunningDailyJournalEnsure = true
        defer { isRunningDailyJournalEnsure = false }

        let context = container.viewContext
        let key = JournalDailyDefaults.bookIDUserDefaultsKey
        
        context.performAndWait {
            let fetchRequest: NSFetchRequest<JournalBook> = JournalBook.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \JournalBook.createdDate, ascending: true)]
            let books = (try? context.fetch(fetchRequest)) ?? []
            
            var dailyBook: JournalBook?
            if let stored = UserDefaults.standard.string(forKey: key),
               let uuid = UUID(uuidString: stored) {
                dailyBook = books.first { $0.id == uuid }
            }
            if dailyBook == nil {
                let titled = books.filter { $0.title?.localizedCaseInsensitiveCompare("Daily Journal") == .orderedSame }
                dailyBook = titled.first
            }
            
            if dailyBook == nil {
                let j = JournalBook(context: context)
                j.title = "Daily Journal"
                j.color = "#2E7D32"
                j.id = UUID()
                j.createdDate = Date()
                j.modifiedDate = Date()
                j.isDailyJournal = true
                for b in books {
                    b.isDailyJournal = false
                }
                if context.hasChanges {
                    do {
                        try context.save()
                        if let id = j.id?.uuidString {
                            UserDefaults.standard.set(id, forKey: key)
                        }
                    } catch {
                        self.logger.error("runDailyJournalEnsure: save failed for new daily journal: \(error.localizedDescription)")
                        context.rollback()
                    }
                }
                return
            }
            
            guard let chosen = dailyBook else { return }
            
            for b in books {
                let isDaily = (b.objectID == chosen.objectID)
                if b.isDailyJournal != isDaily {
                    b.isDailyJournal = isDaily
                    b.modifiedDate = Date()
                }
            }

            let chosenID = chosen.id?.uuidString
            if context.hasChanges {
                do {
                    try context.save()
                    if let chosenID {
                        UserDefaults.standard.set(chosenID, forKey: key)
                    }
                } catch {
                    self.logger.error("runDailyJournalEnsure: save failed: \(error.localizedDescription)")
                    context.rollback()
                }
            } else if let chosenID {
                UserDefaults.standard.set(chosenID, forKey: key)
            }
        }
    }
    
    /// Migrate existing WantToWatchItem records to set mediaCategory based on isMovie Runs on background context to avoid interfering with Cloud...
    private func migrateWantToWatchItemsIfNeeded() {
        let context = backgroundContext()
        context.perform {
            let fetchRequest: NSFetchRequest<WantToWatchItem> = WantToWatchItem.fetchRequest()
            
            fetchRequest.predicate = NSPredicate(format: "mediaCategory == nil OR mediaCategory == ''")
            
            do {
                let itemsToMigrate = try context.fetch(fetchRequest)
                
                if !itemsToMigrate.isEmpty {
                    for item in itemsToMigrate {
                        item.mediaCategory = item.isMovie ? "movie" : "tv"
                        item.modifiedDate = Date()
                    }
                    
                    if context.hasChanges {
                        try context.save()
                    }
                }
            } catch {
                self.logger.error("Failed to migrate WantToWatchItem records: \(error.localizedDescription)")
            }
        }
    }

    private static let schemaFixupsVersion = 1

    private func migrateInkSlateSchemaFixupsIfNeeded() {
        let guardKey = "migration.schemaFixups.version"
        let currentVersion = Self.schemaFixupsVersion
        if UserDefaults.standard.integer(forKey: guardKey) == currentVersion {
            return
        }

        let context = backgroundContext()
        context.perform {
            do {
// Recipe: set isFavorite for legacy high ratings (threshold matches this migration).
                let favoriteThreshold: Int16 = 4
                let recipes: [Recipe] = try context.fetch(Recipe.fetchRequest())
                for recipe in recipes where recipe.isFavorite == false && recipe.rating >= favoriteThreshold {
                    recipe.isFavorite = true
                }

                let incomeName = "Monthly Income"
                let incomeFetch: NSFetchRequest<BudgetItem> = BudgetItem.fetchRequest()
                incomeFetch.predicate = NSPredicate(format: "name == %@ AND subcategory == nil", incomeName)
                for item in try context.fetch(incomeFetch) {
                    item.isIncome = true
                }

// Mind map: attach orphan nodes to their owning map for search.
                let orphanRequest: NSFetchRequest<MindMapNode> = MindMapNode.fetchRequest()
                orphanRequest.predicate = NSPredicate(format: "mindMap == nil")
                let orphanNodes = try context.fetch(orphanRequest)
                for node in orphanNodes {
                    var walk: MindMapNode? = node.parent
                    var owning: MindMap?
                    while let cur = walk {
                        if let m = cur.mindMap {
                            owning = m
                            break
                        }
                        walk = cur.parent
                    }
                    if let owning {
                        node.mindMap = owning
                    }
                }

                let trashedFetch: NSFetchRequest<Notes> = Notes.fetchRequest()
                trashedFetch.predicate = NSPredicate(format: "isMarkedDeleted == YES AND deletedDate == nil")
                for note in try context.fetch(trashedFetch) {
                    note.deletedDate = note.modifiedDate ?? note.createdDate ?? Date()
                }

// Notes: stable IDs for CloudKit NotePhoto and hydrator metadata.
                let notesMissingID: NSFetchRequest<Notes> = Notes.fetchRequest()
                notesMissingID.predicate = NSPredicate(format: "id == nil")
                for note in try context.fetch(notesMissingID) {
                    note.id = UUID()
                    if note.modifiedDate == nil { note.modifiedDate = Date() }
                }

                if context.hasChanges {
                    try context.save()
                }
                UserDefaults.standard.set(currentVersion, forKey: guardKey)
            } catch {
                self.logger.error("migrateInkSlateSchemaFixupsIfNeeded failed: \(error.localizedDescription)")
            }
        }
    }

    func saveInBackground() {
        let context = backgroundContext()
        context.perform {
            do {
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                self.logger.error("Background save failed: \(error.localizedDescription)")
            }
        }
    }
    
    func batchSave(debounceTime: TimeInterval = 2.0) {
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

    /// True only when iCloud backup is *known* to be unavailable
    var isDefinitivelyUnavailable: Bool {
        switch self {
        case .noAccount, .temporarilyUnavailable, .restricted, .error:
            return true
        case .available, .unknown, .couldNotDetermine:
            return false
        }
    }
    
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

