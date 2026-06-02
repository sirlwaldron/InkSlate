import Foundation
import CoreData
import SwiftUI
import Combine
import os

class BudgetManager: ObservableObject {
    static let shared = BudgetManager()

    private let logger = Logger(subsystem: "com.lucas.InkSlateNew", category: "Budget")

    private var totalSpentCache: [String: Double] = [:]
    private var totalSpentObserversInstalled = false

    private init() {
        installCacheInvalidationObservers()
    }

    private func installCacheInvalidationObservers() {
        guard !totalSpentObserversInstalled else { return }
        totalSpentObserversInstalled = true
        let center = NotificationCenter.default
        center.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.totalSpentCache.removeAll(keepingCapacity: true)
        }
        center.addObserver(
            forName: .cloudKitDataRefreshed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.totalSpentCache.removeAll(keepingCapacity: true)
        }
    }

    private static let cachePeriodFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()
    
    // MARK: - Category Management
    
    func createCategory(
        name: String,
        icon: String,
        color: String,
        initialBudget: Double = 0.0,
        createDefaultSubcategory: Bool = true,
        with context: NSManagedObjectContext
    ) -> BudgetCategory {
        let category = BudgetCategory(context: context)
        category.id = UUID()
        category.name = name
        category.icon = icon
        category.color = color
        category.sortOrder = Int16(getNextSortOrder(for: context))
        category.createdDate = Date()
        category.modifiedDate = Date()
        context.insert(category)
        
        if createDefaultSubcategory {
            _ = createSubcategory(
                name: "General",
                category: category,
                budgetAmount: initialBudget,
                with: context
            )
        }
        
        saveContext(context)
        return category
    }
    
    func createSubcategory(
        name: String,
        category: BudgetCategory,
        budgetAmount: Double = 0.0,
        with context: NSManagedObjectContext
    ) -> BudgetSubcategory {
        if let existing = category.subcategories?.first(where: {
            guard let subcategory = $0 as? BudgetSubcategory else { return false }
            return subcategory.name == name
        }) as? BudgetSubcategory {
            if existing.budgetAmount != budgetAmount {
                existing.budgetAmount = budgetAmount
                existing.modifiedDate = Date()
                saveContext(context)
            }
            return existing
        }
        
        let subcategory = BudgetSubcategory(context: context)
        subcategory.id = UUID()
        subcategory.name = name
        subcategory.category = category
        subcategory.budgetAmount = budgetAmount
        subcategory.createdDate = Date()
        subcategory.modifiedDate = Date()
        let siblings = (category.subcategories as? Set<BudgetSubcategory>) ?? []
        let next = (siblings.map(\.sortOrder).max() ?? -1) + 1
        subcategory.sortOrder = next
        
        context.insert(subcategory)
        saveContext(context)
        return subcategory
    }
    
    func deleteCategory(_ category: BudgetCategory, with context: NSManagedObjectContext) {
        context.delete(category)
        saveContext(context)
    }
    
    // MARK: - Budget Item Management
    
    func createBudgetItem(name: String, amount: Double, subcategory: BudgetSubcategory?, with context: NSManagedObjectContext) -> BudgetItem {
        let item = BudgetItem(context: context)
        item.id = UUID()
        item.name = name
        item.amount = amount
        item.date = Date()
        item.isIncome = false
        item.subcategory = subcategory
        item.createdDate = Date()
        item.modifiedDate = Date()
        
        context.insert(item)
        saveContext(context)
        return item
    }
    
    func saveBudgetItem(_ item: BudgetItem, with context: NSManagedObjectContext) {
        item.modifiedDate = Date()
        saveContext(context)
    }
    
    func deleteBudgetItem(_ item: BudgetItem, with context: NSManagedObjectContext) {
        context.delete(item)
        saveContext(context)
    }
    
    // MARK: - Calculations
    
    func calculateTotalSpent(for subcategory: BudgetSubcategory, in period: Date) -> Double {
        guard let context = subcategory.managedObjectContext else { return 0.0 }

        if (subcategory.items?.count ?? 0) == 0 { return 0.0 }

        let cacheKey = "\(subcategory.objectID.uriRepresentation().absoluteString)|\(BudgetManager.cachePeriodFormatter.string(from: period))"
        if let cached = totalSpentCache[cacheKey] {
            return cached
        }

        let calendar = Calendar.current
        let startOfMonth = calendar.dateInterval(of: .month, for: period)?.start ?? period
        let endOfMonth = calendar.dateInterval(of: .month, for: period)?.end ?? period

        var total: Double = 0.0
        context.performAndWait {
            let request = NSFetchRequest<NSDictionary>(entityName: "BudgetItem")
            request.resultType = .dictionaryResultType
            request.predicate = NSPredicate(
                format: "subcategory == %@ AND date >= %@ AND date < %@ AND (isIncome == NO OR isIncome == nil)",
                subcategory,
                startOfMonth as NSDate,
                endOfMonth as NSDate
            )

            let sumDescription = NSExpressionDescription()
            sumDescription.name = "total"
            sumDescription.expression = NSExpression(
                forFunction: "sum:",
                arguments: [NSExpression(forKeyPath: "amount")]
            )
            sumDescription.expressionResultType = .doubleAttributeType

            request.propertiesToFetch = [sumDescription]

            do {
                let results = try context.fetch(request)
                total = (results.first?["total"] as? Double) ?? 0.0
            } catch {
                total = 0.0
            }
        }

        totalSpentCache[cacheKey] = total
        return total
    }
    
    func calculateTotalBudget(for category: BudgetCategory, in period: Date) -> Double {
        guard let subcategories = category.subcategories else { return 0.0 }
        
        return subcategories.reduce(0.0) { total, subcategory in
            guard let sub = subcategory as? BudgetSubcategory else { return total }
            return total + calculateTotalBudget(for: sub, in: period)
        }
    }
    
    func calculateTotalBudget(for subcategory: BudgetSubcategory, in period: Date) -> Double {
        guard let items = subcategory.items else { return 0.0 }
        
        let calendar = Calendar.current
        let startOfMonth = calendar.dateInterval(of: .month, for: period)?.start ?? period
        let endOfMonth = calendar.dateInterval(of: .month, for: period)?.end ?? period
        
        return items.reduce(0.0) { total, item in
            guard let budgetItem = item as? BudgetItem,
                  !budgetItem.isIncome,
                  let itemDate = budgetItem.date,
                  itemDate >= startOfMonth && itemDate < endOfMonth else {
                return total
            }
            return total + budgetItem.amount
        }
    }
    
    // MARK: - Default Categories
    
    func initializeDefaultCategories(with context: NSManagedObjectContext) {
        let defaultCategories = [
            ("🏠 Housing", "house.fill", "#2196F3"),
            ("🍽️ Food", "fork.knife", "#4CAF50"),
            ("🚗 Transportation", "car.fill", "#8B4513"),
            ("🧾 Bills", "doc.plaintext.fill", "#FF9800"),
            ("🛍️ Shopping", "cart.fill", "#FF5722"),
            ("💰 Savings", "banknote.fill", "#E91E63"),
            ("🎉 Fun", "sparkles", "#9C27B0"),
            ("📺 Subscriptions", "tv.fill", "#00BCD4"),
            ("📝 Misc", "ellipsis.circle.fill", "#607D8B")
        ]
        
        for (index, (name, icon, color)) in defaultCategories.enumerated() {
            let category = createCategory(
                name: name,
                icon: icon,
                color: color,
                initialBudget: 0.0,
                createDefaultSubcategory: false,
                with: context
            )
            category.sortOrder = Int16(index)
        }
        
        saveContext(context)
    }
    
    // MARK: - Cleanup
    
    func cleanupExpiredItems(with context: NSManagedObjectContext) {
    }
    
    func repairOrphanBudgetSubcategories(with context: NSManagedObjectContext) {
        // Grace period before deleting orphan subcategories — CloudKit may deliver parent after child.
        let orphanGracePeriod: TimeInterval = 10 * 60
        let staleCutoff = Date().addingTimeInterval(-orphanGracePeriod)
        let orphanRequest: NSFetchRequest<BudgetSubcategory> = BudgetSubcategory.fetchRequest()
        orphanRequest.predicate = NSPredicate(format: "category == nil")
        if let orphans = try? context.fetch(orphanRequest) {
            for sub in orphans {
                let lastTouched = sub.modifiedDate ?? sub.createdDate
                guard let lastTouched, lastTouched < staleCutoff else { continue }
                context.delete(sub)
            }
        }
        
        if let categories = try? context.fetch(BudgetCategory.fetchRequest()) {
            for cat in categories where cat.id == nil {
                cat.id = UUID()
                cat.modifiedDate = Date()
            }
        }
        if let subs = try? context.fetch(BudgetSubcategory.fetchRequest()) {
            for sub in subs where sub.id == nil {
                sub.id = UUID()
                sub.modifiedDate = Date()
            }
        }
        if let items = try? context.fetch(BudgetItem.fetchRequest()) {
            for item in items where item.id == nil {
                item.id = UUID()
                item.modifiedDate = Date()
            }
        }
        
        saveContext(context)
    }
    
    func clearAllBudgetData(with context: NSManagedObjectContext) {
        context.performAndWait {
            do {
                try batchDelete(entityName: "BudgetItem", in: context)
                try batchDelete(entityName: "BudgetSubcategory", in: context)
                try batchDelete(entityName: "BudgetCategory", in: context)
            } catch {
            }
        }
    }

    func ensureAllDefaultSubcategoriesExist(
        categories: [BudgetCategory],
        with context: NSManagedObjectContext
    ) {
        context.performAndWait {
            var didChange = false

            for category in categories {
                let categoryName = category.name ?? ""
                let defaults = BudgetDefaultSubcategories.subcategories(for: categoryName)
                guard !defaults.isEmpty else { continue }

                let existing = (category.subcategories as? Set<BudgetSubcategory>) ?? []
                let existingNames = Set(existing.compactMap { $0.name })

                for name in defaults where !existingNames.contains(name) {
                    _ = createSubcategory(
                        name: name,
                        category: category,
                        budgetAmount: 0.0,
                        with: context
                    )
                    didChange = true
                }

// Re-index subcategory sort orders (especially after factory reset).
                if normalizeSubcategorySortOrdersIfNeeded(category: category, defaults: defaults) {
                    didChange = true
                }
            }

            if didChange {
                saveContext(context)
            }
        }
    }

    private func normalizeSubcategorySortOrdersIfNeeded(category: BudgetCategory, defaults: [String]) -> Bool {
        let subs = (category.subcategories as? Set<BudgetSubcategory>) ?? []
        guard !subs.isEmpty else { return false }

        let defaultIndex: [String: Int] = Dictionary(uniqueKeysWithValues: defaults.enumerated().map { ($0.element, $0.offset) })

        let ordered = subs.sorted { a, b in
            let aName = a.name ?? ""
            let bName = b.name ?? ""
            let aIsDefault = defaultIndex[aName] != nil
            let bIsDefault = defaultIndex[bName] != nil

            if aIsDefault && bIsDefault {
                return (defaultIndex[aName] ?? 0) < (defaultIndex[bName] ?? 0)
            }
            if aIsDefault != bIsDefault { return aIsDefault }

            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return aName.localizedCaseInsensitiveCompare(bName) == .orderedAscending
        }

        var changed = false
        for (idx, sub) in ordered.enumerated() {
            let desired = Int16(idx)
            if sub.sortOrder != desired {
                sub.sortOrder = desired
                sub.modifiedDate = Date()
                changed = true
            }
        }
        return changed
    }
    
    // MARK: - Helper Methods
    
    private func getNextSortOrder(for context: NSManagedObjectContext) -> Int {
        let request: NSFetchRequest<BudgetCategory> = BudgetCategory.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \BudgetCategory.sortOrder, ascending: false)]
        request.fetchLimit = 1
        
        do {
            let categories = try context.fetch(request)
            return Int(categories.first?.sortOrder ?? 0) + 1
        } catch {
            return 0
        }
    }
    
    private func saveContext(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        
        do {
            try context.save()
        } catch {
            logger.error("Budget save failed: \(error.localizedDescription)")
        }
    }

    private func batchDelete(entityName: String, in context: NSManagedObjectContext) throws {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetch)
        deleteRequest.resultType = .resultTypeObjectIDs

        let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
        let objectIDs = (result?.result as? [NSManagedObjectID]) ?? []

        guard !objectIDs.isEmpty else { return }

        NSManagedObjectContext.mergeChanges(
            fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
            into: [context]
        )
    }
}