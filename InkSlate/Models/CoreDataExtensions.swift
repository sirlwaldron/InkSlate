//
//  CoreDataExtensions.swift
//  InkSlate
//
//  Core Data entity extensions for computed properties
//

import Foundation
import CoreData

// MARK: - Notes Extensions
extension Notes {
    /// Computed property to check if note is marked as deleted (soft delete)
    var isMarkedAsDeleted: Bool {
        return isMarkedDeleted
    }
    
    /// Computed property for display title
    var displayTitle: String {
        return title?.isEmpty == false ? title! : "Untitled Note"
    }
    
    /// Computed property for display content preview
    var contentPreview: String {
        guard let content = content, !content.isEmpty else {
            return "No content"
        }
        return String(content.prefix(100)) + (content.count > 100 ? "..." : "")
    }
    
    /// Computed property for formatted creation date
    var formattedCreatedDate: String {
        guard let date = createdDate else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    /// Computed property for formatted modified date
    var formattedModifiedDate: String {
        guard let date = modifiedDate else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Quote Extensions
extension Quote {
    /// Computed property for display text
    var displayText: String {
        return text?.isEmpty == false ? text! : "No quote text"
    }
    
    /// Computed property for display author
    var displayAuthor: String {
        return author?.isEmpty == false ? author! : "Unknown"
    }
    
    /// Computed property for display category
    var displayCategory: String {
        return category?.isEmpty == false ? category! : "Uncategorized"
    }
}

// MARK: - WantToWatchItem Extensions
extension WantToWatchItem {
    /// Computed property for display title
    var displayTitle: String {
        return title?.isEmpty == false ? title! : "Unknown Title"
    }
    
    /// Computed property for media type display
    var mediaTypeDisplay: String {
        if let category = mediaCategory {
            switch category {
            case "anime": return "Anime"
            case "tv": return "TV Show"
            case "movie": return "Movie"
            default: return isMovie ? "Movie" : "TV Show"
            }
        }
        return isMovie ? "Movie" : "TV Show"
    }
    
    /// Computed property for category (with fallback)
    var category: String {
        if let category = mediaCategory, !category.isEmpty {
            return category
        }
        // Fallback for existing items without category
        return isMovie ? "movie" : "tv"
    }
    
    /// Computed property for poster URL
    var posterURL: URL? {
        guard let posterPath = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }
    
    /// Computed property for backdrop URL
    var backdropURL: URL? {
        guard let backdropPath = backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w1280\(backdropPath)")
    }
    
    /// Computed property for formatted release date
    var formattedReleaseDate: String {
        guard let date = releaseDate else { return "TBA" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    /// Computed property for formatted watched date
    var formattedWatchedDate: String {
        guard let date = watchedDate else { return "Not watched" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Recipe Extensions
extension Recipe {
    /// Computed property for display name
    var displayName: String {
        return name?.isEmpty == false ? name! : "Untitled Recipe"
    }
    
    /// Computed property for total time in minutes
    var totalTimeInMinutes: Int {
        return Int(prepTime) + Int(cookTime)
    }
    
    /// Computed property for formatted total time
    var formattedTotalTime: String {
        let total = totalTimeInMinutes
        if total < 60 {
            return "\(total) min"
        } else {
            let hours = total / 60
            let minutes = total % 60
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
    }
    
    /// Computed property for difficulty display
    var difficultyDisplay: String {
        return difficulty?.capitalized ?? "Easy"
    }
}

// MARK: - Place Extensions
extension Place {
    /// Computed property for display name
    var displayName: String {
        return name?.isEmpty == false ? name! : "Unnamed Place"
    }
    
    /// Computed property for full address
    var fullAddress: String {
        var components: [String] = []
        
        if let address = address, !address.isEmpty {
            components.append(address)
        }
        if let city = city, !city.isEmpty {
            components.append(city)
        }
        if let state = state, !state.isEmpty {
            components.append(state)
        }
        if let postalCode = postalCode, !postalCode.isEmpty {
            components.append(postalCode)
        }
        if let country = country, !country.isEmpty {
            components.append(country)
        }
        
        return components.joined(separator: ", ")
    }
    
    /// Computed property for rating display
    var ratingDisplay: String {
        return "\(rating)/5"
    }
    
    /// Computed property for visit status
    var visitStatus: String {
        return isVisited ? "Visited" : "Not Visited"
    }
}

// MARK: - JournalEntry Extensions
extension JournalEntry {
    /// Computed property for display title
    var displayTitle: String {
        return title?.isEmpty == false ? title! : "Untitled Entry"
    }
    
    /// Computed property for word count
    var wordCount: Int {
        guard let content = content else { return 0 }
        return content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
    
    /// Computed property for formatted date
    var formattedDate: String {
        guard let date = createdDate else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
}

// MARK: - JournalBook Extensions
extension JournalBook {
    /// Computed property for display title
    var displayTitle: String {
        return title?.isEmpty == false ? title! : "Untitled Journal"
    }
    
    /// Computed property for entry count
    var entryCount: Int {
        return entries?.count ?? 0
    }
}

// MARK: - TodoTask Extensions
extension TodoTask {
    /// Computed property for display title
    var displayTitle: String {
        return title?.isEmpty == false ? title! : "Untitled Task"
    }
    
    /// Computed property for priority display
    var priorityDisplay: String {
        return priority?.capitalized ?? "Medium"
    }
    
    /// Computed property for formatted due date
    var formattedDueDate: String {
        guard let date = dueDate else { return "No due date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    /// Computed property for formatted completed date
    var formattedCompletedDate: String {
        guard let date = completedDate else { return "Not completed" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - TodoTab Extensions
extension TodoTab {
    /// Computed property for display name
    var displayName: String {
        return name?.isEmpty == false ? name! : "Untitled Tab"
    }
    
    /// Computed property for task count
    var taskCount: Int {
        return tasks?.count ?? 0
    }
    
    /// Computed property for completed task count
    var completedTaskCount: Int {
        return tasks?.filter { ($0 as? TodoTask)?.isCompleted == true }.count ?? 0
    }
}

// MARK: - BudgetItem Extensions
extension BudgetItem {
    /// Computed property for display name
    var displayName: String {
        return name?.isEmpty == false ? name! : "Untitled Item"
    }
    
    /// Computed property for formatted amount
    var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
    
    /// Computed property for formatted date
    var formattedDate: String {
        guard let date = date else { return "No date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - BudgetSubcategory Extensions
extension BudgetSubcategory {
    /// Computed property for display name
    var displayName: String {
        return name?.isEmpty == false ? name! : "Untitled Subcategory"
    }
    
    /// Computed property for formatted budget amount
    var formattedBudgetAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: budgetAmount)) ?? "$0.00"
    }
    
    /// Computed property for item count
    var itemCount: Int {
        return items?.count ?? 0
    }
}

// MARK: - BudgetCategory Extensions
extension BudgetCategory {
    /// Computed property for display name
    var displayName: String {
        return name?.isEmpty == false ? name! : "Untitled Category"
    }
    
    /// Computed property for subcategory count
    var subcategoryCount: Int {
        return subcategories?.count ?? 0
    }
}

// MARK: - MindMap Extensions
extension MindMap {
    /// Computed property for display title
    var displayTitle: String {
        return title?.isEmpty == false ? title! : "Untitled Mind Map"
    }
    
    /// Computed property for node count
    var nodeCount: Int {
        return rootNodes?.count ?? 0
    }
}

// MARK: - MindMapNode Extensions
extension MindMapNode {
    /// Computed property for display title
    var displayTitle: String {
        return title?.isEmpty == false ? title! : "New Node"
    }
    
    /// Computed property for child count
    var childCount: Int {
        return children?.count ?? 0
    }
    
    /// Computed property for depth level
    var depthLevel: Int {
        return Int(ring)
    }
}

// MARK: - CloudKit Sync Helpers
/// Protocol for entities that need CloudKit sync metadata
protocol CloudKitSyncable {
    var id: UUID? { get set }
    var createdDate: Date? { get set }
    var modifiedDate: Date? { get set }
}

/// Extension to ensure entities have proper sync metadata before saving
extension NSManagedObject {
    /// Ensures the entity has proper CloudKit sync metadata
    func ensureCloudKitMetadata() {
        // Check and set id if available
        if responds(to: Selector(("id"))) {
            if value(forKey: "id") == nil {
                setValue(UUID(), forKey: "id")
            }
        }
        
        // Check and set createdDate if available
        if responds(to: Selector(("createdDate"))) {
            if value(forKey: "createdDate") == nil {
                setValue(Date(), forKey: "createdDate")
            }
        }
        
        // Update modifiedDate if available
        if responds(to: Selector(("modifiedDate"))) {
            setValue(Date(), forKey: "modifiedDate")
        }
    }
}

// MARK: - MindMap CloudKit Helpers
extension MindMap {
    /// Initializes with proper CloudKit metadata
    func initializeForCloudKit() {
        if id == nil { id = UUID() }
        if createdDate == nil { createdDate = Date() }
        modifiedDate = Date()
    }
}

extension MindMapNode {
    /// Initializes with proper CloudKit metadata
    func initializeForCloudKit() {
        if id == nil { id = UUID() }
        if createdDate == nil { createdDate = Date() }
        modifiedDate = Date()
    }
}

// MARK: - Context Save Helper
extension NSManagedObjectContext {
    /// Saves the context with proper error handling and CloudKit metadata validation
    func saveWithCloudKitSync() throws {
        // Ensure all inserted objects have proper metadata
        for object in insertedObjects {
            object.ensureCloudKitMetadata()
        }
        
        // Ensure all updated objects have updated modifiedDate
        for object in updatedObjects {
            if object.responds(to: Selector(("modifiedDate"))) {
                object.setValue(Date(), forKey: "modifiedDate")
            }
        }
        
        guard hasChanges else { return }
        try save()
    }
    
    /// Saves silently without throwing, logs errors
    func saveQuietly() {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            print("❌ Core Data save error: \(error)")
        }
    }
}
