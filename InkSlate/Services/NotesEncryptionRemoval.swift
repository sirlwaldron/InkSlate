import CoreData
import os

/// One-time removal of note encryption (requested while iCloud + lock flow was unreliable)
enum NotesEncryptionRemoval {
    private static let migrationCompletedKey = "inkslate.notes.encryptionRemoved.v1"
    private static let encPrefix = "⟪ENC⟫"
    private static let enc2Prefix = "⟪ENC2⟫"
    private static let log = Logger(subsystem: "com.lucas.InkSlateNew", category: "NotesEncryptionRemoval")

    private static let recoveryBody = """
    Note locking was removed from InkSlate. This note was previously encrypted, so its contents could not be migrated automatically.

    If you need the original text, restore from an iCloud or device backup created before this update, or open an older version of the app that still had note encryption enabled.
    """

    static func migrateIfNeeded(in context: NSManagedObjectContext) {
        guard !UserDefaults.standard.bool(forKey: migrationCompletedKey) else { return }

        let request = NSFetchRequest<Notes>(entityName: "Notes")
        request.includesPropertyValues = true

        do {
            let notes = try context.fetch(request)
            var changed = 0
            for note in notes {
                guard needsMigration(note) else { continue }
                applyRemoval(to: note)
                changed += 1
            }
            if context.hasChanges {
                try context.save()
            }
            UserDefaults.standard.set(true, forKey: migrationCompletedKey)
            UserDefaults.standard.removeObject(forKey: "inkslate.encryption.failedAttempts")
            UserDefaults.standard.removeObject(forKey: "inkslate.encryption.lockoutUntil")
            let cloud = NSUbiquitousKeyValueStore.default
            cloud.removeObject(forKey: "inkslate.notesPasscode.salt")
            cloud.removeObject(forKey: "inkslate.notesPasscode.hash")
            cloud.removeObject(forKey: "inkslate.notesPasscode.iterations")
            cloud.synchronize()
            if changed > 0 {
                log.info("Cleared encryption from \(changed) note(s)")
            }
        } catch {
            log.error("Encryption removal migration failed: \(error.localizedDescription)")
        }
    }

    private static func needsMigration(_ note: Notes) -> Bool {
        if note.isEncrypted { return true }
        let content = note.content ?? ""
        return content.contains(encPrefix) || content.contains(enc2Prefix)
    }

    private static func applyRemoval(to note: Notes) {
        let content = note.content ?? ""
        let hadCiphertext = content.contains(encPrefix) || content.contains(enc2Prefix)

        note.isEncrypted = false
        note.containerType = "none"

        if hadCiphertext {
            note.content = recoveryBody
            note.preview = String(recoveryBody.prefix(100))
        } else if let content = note.content, !content.isEmpty {
            let plain = MarkdownSerialization.plainText(from: content)
            note.preview = plain.isEmpty ? nil : String(plain.prefix(100))
        } else {
            note.preview = nil
        }
        note.modifiedDate = Date()
    }
}
