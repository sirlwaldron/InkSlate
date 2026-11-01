import CoreData
import Foundation

// MARK: - Sync ping (throttled)

/// Tells the user's other devices "something changed" through iCloud key-value storage. Every save used
/// to write the key and force a `synchronize()`; the store throttles/queues rapid writes anyway, so
/// bursts (typing autosaves, bulk edits) are collapsed: the first ping goes out immediately and later
/// ones within `minInterval` are merged into one trailing ping, so the final change is always announced.
enum SyncPing {
    private static let key = "lastSyncPing"
    private static let minInterval: TimeInterval = 3
    private static let lock = NSLock()
    private static var lastSent: Date = .distantPast
    private static var trailing: DispatchWorkItem?

    static func send() {
        lock.lock()
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSent)
        if elapsed >= minInterval {
            lastSent = now
            trailing?.cancel()
            trailing = nil
            lock.unlock()
            write()
            return
        }
        if trailing == nil {
            let work = DispatchWorkItem {
                lock.lock()
                lastSent = Date()
                trailing = nil
                lock.unlock()
                write()
            }
            trailing = work
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + (minInterval - elapsed), execute: work)
        }
        lock.unlock()
    }

    private static func write() {
        NSUbiquitousKeyValueStore.default.set(Date().timeIntervalSince1970, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }
}

// MARK: - Consistent Core Data save + user-visible errors

enum CoreDataSave {
    @MainActor
    @discardableResult
    static func save(_ context: NSManagedObjectContext, module: String, retry: (() -> Void)? = nil) -> Bool {
        guard context.hasChanges else { return true }
        
// Ensure required metadata exists for CloudKit sync + asset linking (e.g. Notes.id for NotePhoto).
        for object in context.insertedObjects {
            object.ensureCloudKitMetadata()
        }
        for object in context.updatedObjects {
            if object.responds(to: Selector(("modifiedDate"))) {
                object.setValue(Date(), forKey: "modifiedDate")
            }
        }
        do {
            try context.save()
            SyncPing.send()
            return true
        } catch {
            ErrorHandlingService.shared.reportSaveFailure(error, module: module, retry: retry)
            return false
        }
    }
}

extension NSManagedObjectContext {
    @MainActor
    @discardableResult
    func inkSlateSave(module: String, retry: (() -> Void)? = nil) -> Bool {
        CoreDataSave.save(self, module: module, retry: retry)
    }
}
