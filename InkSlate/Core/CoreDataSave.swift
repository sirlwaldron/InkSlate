import CoreData
import Foundation

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
