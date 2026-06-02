import Foundation
import SwiftUI
import CoreData
import Combine

// MARK: - Enums
enum SortBy: String, CaseIterable {
    case title = "title"
    case creationDate = "creationDate"
    case modificationDate = "modificationDate"
    case pin = "pin"

    static func fromProjectSettings(_ raw: String?) -> SortBy {
        switch raw {
        case "creationDate": return .creationDate
        case "title": return .title
        case "pin": return .pin
        default: return .modificationDate
        }
    }
}

enum SortDirection: String, CaseIterable {
    case ascending = "ascending"
    case descending = "descending"
}

// MARK: - Notes Service
class NotesService: ObservableObject {
    static let shared = NotesService()
    
    private let errorService = ErrorHandlingService.shared
    
    private init() {}
    
    
    deinit {
        
    }
    
    // MARK: - Note Operations
    
    func createNote(title: String, content: String, in context: NSManagedObjectContext) -> Notes? {
        return errorService.safeSave({
            let newNote = Notes(context: context)
            newNote.title = title
            newNote.content = content
            newNote.createdDate = Date()
            newNote.modifiedDate = Date()
            newNote.id = UUID()
            newNote.isMarkedDeleted = false
            newNote.isPinned = false
            newNote.isEncrypted = false
            newNote.noteType = "markdown"
            newNote.containerType = "none"
            context.insert(newNote)
            try context.save()
            return newNote
        }, context: "Create note")
    }
    
    func updateNote(_ note: Notes, in context: NSManagedObjectContext) -> Bool {
        return errorService.safeSave({
            note.modifiedDate = Date()
            if let content = note.content, !content.isEmpty {
                let plain = MarkdownSerialization.plainText(from: content)
                note.preview = plain.isEmpty ? nil : String(plain.prefix(100))
            } else {
                note.preview = nil
            }
            try context.save()
            return true
        }, context: "Update note") ?? false
    }
    
    func deleteNote(_ note: Notes, in context: NSManagedObjectContext) -> Bool {
        return errorService.safeDelete({
            context.delete(note)
            try context.save()
            return true
        }, context: "Delete note") ?? false
    }
    
    func moveToTrash(_ note: Notes, in context: NSManagedObjectContext) -> Bool {
        return errorService.safeSave({
            note.isMarkedDeleted = true
            note.deletedDate = Date()
            note.modifiedDate = Date()
            try context.save()
            return true
        }, context: "Move to trash") ?? false
    }
    
    func restoreNote(_ note: Notes, in context: NSManagedObjectContext) -> Bool {
        return errorService.safeSave({
            note.isMarkedDeleted = false
            note.deletedDate = nil
            note.modifiedDate = Date()
            try context.save()
            return true
        }, context: "Restore note") ?? false
    }
    
    func togglePin(_ note: Notes, in context: NSManagedObjectContext) -> Bool {
        return errorService.safeSave({
            note.isPinned.toggle()
            note.modifiedDate = Date()
            try context.save()
            return true
        }, context: "Toggle pin") ?? false
    }
    
    func emptyTrash(notes: [Notes], in context: NSManagedObjectContext) -> Bool {
        return errorService.safeDelete({
            for note in notes where note.isMarkedDeleted {
                context.delete(note)
            }
            try context.save()
            return true
        }, context: "Empty trash") ?? false
    }
    
    func purgeOldDeletedNotes(notes: [Notes], in context: NSManagedObjectContext) -> Bool {
        return errorService.safeDelete({
            guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else {
                return true
            }
            for note in notes where note.isMarkedDeleted {
                let marker = note.deletedDate ?? note.modifiedDate ?? Date()
                if marker < cutoffDate {
                    context.delete(note)
                }
            }
            try context.save()
            return true
        }, context: "Purge old notes") ?? false
    }
    
    // MARK: - Search and Filter Operations
    
    func searchNotes(_ notes: [Notes], searchText: String) -> [Notes] {
        guard !searchText.isEmpty else { return notes }
        
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return notes }
        
        return notes.filter { note in
            let titleMatch = note.title?.localizedCaseInsensitiveContains(trimmed) ?? false
            return titleMatch ||
                (note.content?.localizedCaseInsensitiveContains(trimmed) ?? false) ||
                (note.preview?.localizedCaseInsensitiveContains(trimmed) ?? false) ||
                (note.tags?.components(separatedBy: ",").contains { $0.localizedCaseInsensitiveContains(trimmed) } ?? false)
        }
    }
    
    func filterNotes(_ notes: [Notes], showDeleted: Bool, showPinnedOnly: Bool) -> [Notes] {
        var filtered = notes
        
        if showDeleted {
            filtered = filtered.filter { $0.isMarkedDeleted }
        } else {
            filtered = filtered.filter { !$0.isMarkedDeleted }
        }
        
        if showPinnedOnly && !showDeleted {
            filtered = filtered.filter { $0.isPinned }
        }
        
        return filtered
    }
    
    func sortNotes(_ notes: [Notes], by sortBy: SortBy, direction: SortDirection) -> [Notes] {
        var sortedNotes = notes
        
        switch sortBy {
        case .title:
            sortedNotes.sort { ($0.title ?? "") < ($1.title ?? "") }
        case .creationDate:
            sortedNotes.sort { ($0.createdDate ?? Date.distantPast) < ($1.createdDate ?? Date.distantPast) }
        case .modificationDate:
            sortedNotes.sort { ($0.modifiedDate ?? Date.distantPast) < ($1.modifiedDate ?? Date.distantPast) }
        case .pin:
            sortedNotes.sort { $0.isPinned && !$1.isPinned }
        }
        
        if direction == .descending {
            sortedNotes.reverse()
        }
        
        return sortedNotes
    }
    
    // MARK: - Tag Operations

    private func normalizedTags(from raw: String?) -> [String] {
        (raw ?? "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    func addTag(_ tag: String, to note: Notes, in context: NSManagedObjectContext) -> Bool {
        return errorService.safeSave({
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return true }
            
            var currentTags = normalizedTags(from: note.tags)
            let exists = currentTags.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
            if !exists {
                currentTags.append(trimmed)
                note.tags = currentTags.joined(separator: ",")
                note.modifiedDate = Date()
            }
            try context.save()
            return true
        }, context: "Add tag") ?? false
    }
    
    func removeTag(_ tag: String, from note: Notes, in context: NSManagedObjectContext) -> Bool {
        return errorService.safeSave({
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return true }
            
            var currentTags = normalizedTags(from: note.tags)
            currentTags.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
            note.tags = currentTags.joined(separator: ",")
            note.modifiedDate = Date()
            try context.save()
            return true
        }, context: "Remove tag") ?? false
    }
    
}

