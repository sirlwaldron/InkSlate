//
//  NotesService.swift
//  InkSlate
//
//  Created by Lucas Waldron on 10/18/25.
//  Business logic service for notes operations
//

import Foundation
import SwiftUI
import CoreData

// MARK: - Enums
enum SortBy: String, CaseIterable {
    case title = "title"
    case creationDate = "creationDate"
    case modificationDate = "modificationDate"
    case pin = "pin"
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
            // Update preview if content changed
            if let content = note.content, !content.isEmpty {
                note.preview = String(content.prefix(100))
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
            note.modifiedDate = Date()
            try context.save()
            return true
        }, context: "Move to trash") ?? false
    }
    
    func restoreNote(_ note: Notes, in context: NSManagedObjectContext) -> Bool {
        return errorService.safeSave({
            note.isMarkedDeleted = false
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
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            for note in notes where note.isMarkedDeleted && (note.modifiedDate ?? Date()) < cutoffDate {
                context.delete(note)
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
            (note.title?.localizedCaseInsensitiveContains(trimmed) ?? false) ||
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
    
    func addTag(_ tag: String, to note: Notes, in context: NSManagedObjectContext) -> Bool {
        return errorService.safeSave({
            var currentTags = note.tags?.components(separatedBy: ",") ?? []
            if !currentTags.contains(tag) {
                currentTags.append(tag)
                note.tags = currentTags.joined(separator: ",")
                note.modifiedDate = Date()
            }
            try context.save()
            return true
        }, context: "Add tag") ?? false
    }
    
    func removeTag(_ tag: String, from note: Notes, in context: NSManagedObjectContext) -> Bool {
        return errorService.safeSave({
            var currentTags = note.tags?.components(separatedBy: ",") ?? []
            currentTags.removeAll { $0 == tag }
            note.tags = currentTags.joined(separator: ",")
            note.modifiedDate = Date()
            try context.save()
            return true
        }, context: "Remove tag") ?? false
    }
    
    // MARK: - Encryption Operations
    
    func encryptNote(_ note: Notes, password: String, in context: NSManagedObjectContext) -> Bool {
        return errorService.safeSave({
            // For now, just mark as encrypted - actual encryption would need to be implemented
            note.isEncrypted = true
            note.modifiedDate = Date()
            try context.save()
            return true
        }, context: "Encrypt note") ?? false
    }
    
    func decryptNote(_ note: Notes, password: String, in context: NSManagedObjectContext) -> Bool {
        return errorService.safeSave({
            // For now, just mark as not encrypted - actual decryption would need to be implemented
            note.isEncrypted = false
            note.modifiedDate = Date()
            try context.save()
            return true
        }, context: "Decrypt note") ?? false
    }
}

// MARK: - Notes View Model
class NotesViewModel: ObservableObject {
    @Published var notes: [Notes] = []
    @Published var searchText: String = ""
    @Published var debouncedSearchText: String = ""
    @Published var sortBy: SortBy = .modificationDate
    @Published var sortDirection: SortDirection = .descending
    @Published var showPinnedOnly: Bool = false
    @Published var showDeleted: Bool = false
    @Published var isLoading: Bool = false
    
    private let notesService = NotesService.shared
    private var searchTimer: Timer?
    
    var filteredNotes: [Notes] {
        let filtered = notesService.filterNotes(notes, showDeleted: showDeleted, showPinnedOnly: showPinnedOnly)
        let searched = notesService.searchNotes(filtered, searchText: debouncedSearchText)
        return notesService.sortNotes(searched, by: sortBy, direction: sortDirection)
    }
    
    func updateNotes(_ newNotes: [Notes]) {
        notes = newNotes
    }
    
    func updateSearchText(_ text: String) {
        searchText = text
        searchTimer?.invalidate()
        
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.debouncedSearchText = text
        }
    }
    
    func toggleSort() {
        sortDirection = sortDirection == .ascending ? .descending : .ascending
    }
    
    func setSortBy(_ newSortBy: SortBy) {
        sortBy = newSortBy
    }
    
    
    deinit {
        searchTimer?.invalidate()
        searchTimer = nil
        
    }
}
