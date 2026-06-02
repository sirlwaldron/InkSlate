import Foundation
import CoreData
import os.log


// MARK: - Notes Extensions
extension Notes {
    var isMarkedAsDeleted: Bool {
        return isMarkedDeleted
    }
    
    var displayTitle: String {
        return title?.isEmpty == false ? title! : "Untitled Note"
    }
    
    var contentPreview: String {
        if let preview = preview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
            return preview.count > 100 ? String(preview.prefix(100)) + "..." : preview
        }
        guard let content = content, !content.isEmpty else {
            return "No content"
        }
        return String(content.prefix(100)) + (content.count > 100 ? "..." : "")
    }
    
    var formattedCreatedDate: String {
        guard let date = createdDate else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
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
    var displayText: String {
        return text?.isEmpty == false ? text! : "No quote text"
    }
    
    var displayAuthor: String {
        return author?.isEmpty == false ? author! : "Unknown"
    }
    
    var displayCategory: String {
        return category?.isEmpty == false ? category! : "Uncategorized"
    }
}

// MARK: - WantToWatchItem Extensions
extension WantToWatchItem {
    var displayTitle: String {
        return title?.isEmpty == false ? title! : "Unknown Title"
    }
    
    var mediaTypeDisplay: String {
        if let category = mediaCategory {
            switch category {
            case "anime": return "Anime"
            case "cartoon": return "TV Show"
            case "tv": return "TV Show"
            case "movie": return "Movie"
            default: return isMovie ? "Movie" : "TV Show"
            }
        }
        return isMovie ? "Movie" : "TV Show"
    }
    
    var category: String {
        if let category = mediaCategory, !category.isEmpty {
            return category
        }
        return isMovie ? "movie" : "tv"
    }

    var watchShelfCategory: String {
        let raw = category
        return raw == "cartoon" ? "tv" : raw
    }
    
    var posterURL: URL? {
        guard let posterPath = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }
    
    var backdropURL: URL? {
        guard let backdropPath = backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w1280\(backdropPath)")
    }
    
    var formattedReleaseDate: String {
        guard let date = releaseDate else { return "TBA" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    var formattedWatchedDate: String {
        guard let date = watchedDate else { return "Not watched" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Recipe Extensions
extension Recipe {
    var displayName: String {
        return name?.isEmpty == false ? name! : "Untitled Recipe"
    }
    
    var totalTimeInMinutes: Int {
        return Int(prepTime) + Int(cookTime)
    }
    
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
    
    var difficultyDisplay: String {
        return difficulty?.capitalized ?? "Easy"
    }
}

// MARK: - Place Extensions
extension Place {
    var displayName: String {
        return name?.isEmpty == false ? name! : "Unnamed Place"
    }
    
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
    
    var ratingDisplay: String {
        return "\(rating)/5"
    }
    
    var visitStatus: String {
        return isVisited ? "Visited" : "Not Visited"
    }
}

// MARK: - JournalEntry Extensions
extension JournalEntry {
    var displayTitle: String {
        return title?.isEmpty == false ? title! : "Untitled Entry"
    }
    
    var wordCount: Int {
        guard let content = content else { return 0 }
        return content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
    
    var formattedDate: String {
        guard let date = createdDate else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
}

// MARK: - JournalBook Extensions
extension JournalBook {
    var displayTitle: String {
        return title?.isEmpty == false ? title! : "Untitled Journal"
    }
    
    var entryCount: Int {
        return entries?.count ?? 0
    }
}

// MARK: - TodoTask Extensions
extension TodoTask {
    var displayTitle: String {
        return title?.isEmpty == false ? title! : "Untitled Task"
    }
    
    var priorityDisplay: String {
        return priority?.capitalized ?? "Medium"
    }
    
    var formattedDueDate: String {
        guard let date = dueDate else { return "No due date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    var formattedCompletedDate: String {
        guard let date = completedDate else { return "Not completed" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - TodoTab Extensions
extension TodoTab {
    var displayName: String {
        return name?.isEmpty == false ? name! : "Untitled Tab"
    }
    
    var taskCount: Int {
        return tasks?.count ?? 0
    }
    
    var completedTaskCount: Int {
        return tasks?.filter { ($0 as? TodoTask)?.isCompleted == true }.count ?? 0
    }
}

// MARK: - BudgetItem Extensions
extension BudgetItem {
    var displayName: String {
        return name?.isEmpty == false ? name! : "Untitled Item"
    }
    
    var formattedAmount: String {
        let safeAmount = amount.isFinite ? amount : 0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: safeAmount)) ?? "$0.00"
    }
    
    var formattedDate: String {
        guard let date = date else { return "No date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - BudgetSubcategory Extensions
extension BudgetSubcategory {
    var displayName: String {
        return name?.isEmpty == false ? name! : "Untitled Subcategory"
    }
    
    var formattedBudgetAmount: String {
        let safeAmount = budgetAmount.isFinite ? budgetAmount : 0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: safeAmount)) ?? "$0.00"
    }
    
    var itemCount: Int {
        return items?.count ?? 0
    }
}

// MARK: - BudgetCategory Extensions
extension BudgetCategory {
    var displayName: String {
        return name?.isEmpty == false ? name! : "Untitled Category"
    }
    
    var subcategoryCount: Int {
        return subcategories?.count ?? 0
    }
}

// MARK: - MindMap Extensions
extension MindMap {
    var displayTitle: String {
        return title?.isEmpty == false ? title! : "Untitled Mind Map"
    }
    
    var nodeCount: Int {
        let roots = rootNodes?.allObjects as? [MindMapNode] ?? []
        return roots.reduce(0) { $0 + MindMap.countSubtree(root: $1) }
    }

    private static func countSubtree(root: MindMapNode) -> Int {
        let children = root.children?.allObjects as? [MindMapNode] ?? []
        return 1 + children.reduce(0) { $0 + countSubtree(root: $1) }
    }
}

// MARK: - MindMapNode Extensions
extension MindMapNode {
    var displayTitle: String {
        return title?.isEmpty == false ? title! : "New Node"
    }
    
    var childCount: Int {
        return children?.count ?? 0
    }
    
    var depthLevel: Int {
        return Int(ring)
    }
}

// MARK: - CloudKit Sync Helpers
protocol CloudKitSyncable {
    var id: UUID? { get set }
    var createdDate: Date? { get set }
    var modifiedDate: Date? { get set }
}

extension NSManagedObject {
    func ensureCloudKitMetadata() {
        if responds(to: Selector(("id"))) {
            if value(forKey: "id") == nil {
                setValue(UUID(), forKey: "id")
            }
        }
        
        if responds(to: Selector(("createdDate"))) {
            if value(forKey: "createdDate") == nil {
                setValue(Date(), forKey: "createdDate")
            }
        }
        
        if responds(to: Selector(("modifiedDate"))) {
            setValue(Date(), forKey: "modifiedDate")
        }
    }
}

// MARK: - MindMap CloudKit Helpers
extension MindMap {
    func initializeForCloudKit() {
        if id == nil { id = UUID() }
        if createdDate == nil { createdDate = Date() }
        modifiedDate = Date()
    }
}

extension MindMapNode {
    func initializeForCloudKit() {
        if id == nil { id = UUID() }
        if createdDate == nil { createdDate = Date() }
        modifiedDate = Date()
    }
}

// MARK: - Context Save Helper
extension NSManagedObjectContext {
    func saveWithCloudKitSync() throws {
        for object in insertedObjects {
            object.ensureCloudKitMetadata()
        }
        
        for object in updatedObjects {
            if object.responds(to: Selector(("modifiedDate"))) {
                object.setValue(Date(), forKey: "modifiedDate")
            }
        }
        
        guard hasChanges else { return }
        try save()
    }
    
    func saveQuietly(module: String = "InkSlate") {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            Logger(subsystem: "com.lucas.InkSlateNew", category: "CoreData")
                .error("saveQuietly failed in \(module, privacy: .public): \(error.localizedDescription, privacy: .public)")
            ErrorHandlingService.shared.reportSaveFailure(error, module: module)
        }
    }
}
