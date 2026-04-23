//
//  BudgetManager.swift
//  InkSlate
//
//  Created by Lucas Waldron on 1/2/25.
//

import Foundation
import CoreData
import SwiftUI
import Combine

class BudgetManager: ObservableObject {
    static let shared = BudgetManager()
    
    private init() {}
    
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
        category.id = UUID()  // Required for CloudKit sync
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
        subcategory.id = UUID()  // Required for CloudKit sync
        subcategory.name = name
        subcategory.category = category
        subcategory.budgetAmount = budgetAmount
        subcategory.createdDate = Date()
        subcategory.modifiedDate = Date()
        subcategory.sortOrder = Int16((category.subcategories?.count ?? 0))
        
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
        item.id = UUID()  // Required for CloudKit sync
        item.name = name
        item.amount = amount
        item.date = Date()
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
        guard let items = subcategory.items else { return 0.0 }
        
        let calendar = Calendar.current
        let startOfMonth = calendar.dateInterval(of: .month, for: period)?.start ?? period
        let endOfMonth = calendar.dateInterval(of: .month, for: period)?.end ?? period
        
        return items.reduce(0.0) { total, item in
            guard let budgetItem = item as? BudgetItem,
                  let itemDate = budgetItem.date,
                  itemDate >= startOfMonth && itemDate < endOfMonth else {
                return total
            }
            return total + budgetItem.amount
        }
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
            ("🚗 Transportation", "car.fill", "#8B4513"),
            ("🏠 Housing & Utilities", "house.fill", "#2196F3"),
            ("🛍️ Daily Living & Household", "cart.fill", "#FF9800"),
            ("🍽️ Food & Leisure", "fork.knife", "#4CAF50"),
            ("💵 Financial Obligations", "banknote.fill", "#E91E63"),
            ("🧠 Education & Personal Growth", "graduationcap.fill", "#9C27B0"),
            ("🩺 Health & Wellness", "cross.fill", "#3F51B5"),
            ("🎁 Gifts & Giving", "gift.fill", "#F44336"),
            ("📝 Miscellaneous", "ellipsis.circle.fill", "#607D8B")
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
        // This could be used to clean up old budget items if needed
        // For now, we'll keep all items
    }
    
    func clearAllBudgetData(with context: NSManagedObjectContext) {
        // Clear all budget items
        let budgetItemRequest: NSFetchRequest<BudgetItem> = BudgetItem.fetchRequest()
        let budgetItems = (try? context.fetch(budgetItemRequest)) ?? []
        for item in budgetItems {
            context.delete(item)
        }
        
        // Clear all subcategories
        let subcategoryRequest: NSFetchRequest<BudgetSubcategory> = BudgetSubcategory.fetchRequest()
        let subcategories = (try? context.fetch(subcategoryRequest)) ?? []
        for subcategory in subcategories {
            context.delete(subcategory)
        }
        
        // Clear all categories
        let categoryRequest: NSFetchRequest<BudgetCategory> = BudgetCategory.fetchRequest()
        let categories = (try? context.fetch(categoryRequest)) ?? []
        for category in categories {
            context.delete(category)
        }
        
        saveContext(context)
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
            // Log error but don't crash - let calling code handle UI feedback
            print("Failed to save context: \(error.localizedDescription)")
        }
    }
}