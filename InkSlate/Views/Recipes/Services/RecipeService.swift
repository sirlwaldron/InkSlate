import Foundation
import CoreData
import os

private let recipeServiceLog = Logger(subsystem: "com.lucas.InkSlateNew", category: "RecipeService")


enum RecipeServiceError: LocalizedError {
    case invalidAmount
    case parseError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "Invalid amount format"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}

struct RecipeService {
    // MARK: - Amount Parsing
    
    static func parseAmountString(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        if let value = Double(trimmed) {
            return value
        }
        
        let components = trimmed.split(separator: " ")
        if components.count == 2,
           let whole = Double(components[0]),
           let fraction = parseFraction(String(components[1])) {
            return whole + fraction
        }
        
        return parseFraction(trimmed)
    }
    
    private static func parseFraction(_ text: String) -> Double? {
        let parts = text.split(separator: "/")
        guard parts.count == 2,
              let numerator = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let denominator = Double(parts[1].trimmingCharacters(in: .whitespaces)),
              denominator != 0 else {
            return nil
        }
        return numerator / denominator
    }
    
    // MARK: - Recipe Creation Helpers
    
    static func createRecipe(
        in context: NSManagedObjectContext,
        name: String,
        description: String?,
        category: RecipeCategory,
        rating: Int16,
        prepTime: Int16,
        cookTime: Int16,
        servings: Int,
        imageData: Data?,
        imagePath: String?,
        ingredients: [RecipeIngredientData],
        steps: [RecipeStep],
        notes: String,
        dietaryTags: Set<DietaryTag>
    ) throws -> Recipe {
        let recipe = Recipe(context: context)
        recipe.id = UUID()
        recipe.createdDate = Date()
        recipe.isFavorite = false
        recipe.modifiedDate = Date()
        recipe.name = name
        recipe.recipeDescription = description
        recipe.cuisine = category.rawValue
        recipe.rating = rating
        recipe.prepTime = prepTime
        recipe.cookTime = cookTime
        recipe.servings = String(servings)
        
        if let data = imageData, let recipeID = recipe.id {
            do {
                let path = try RecipeImageStore.saveImage(
                    data: data,
                    for: recipeID,
                    replacing: nil
                )
                recipe.imageUrl = path
            } catch {
                recipeServiceLog.error("Recipe image save failed: \(error.localizedDescription)")
            }
        } else if let existingPath = imagePath {
            recipe.imageUrl = existingPath
        }
        
        recipe.updateDetails(steps: steps, notes: notes)
        recipe.updateDietaryTags(dietaryTags)
        
        for ingredientData in ingredients {
            let ingredient = RecipeIngredient(context: context)
            ingredient.id = UUID()
            ingredient.createdDate = Date()
            ingredient.modifiedDate = Date()
            ingredient.name = ingredientData.name
            let rawAmount = ingredientData.amount.trimmingCharacters(in: .whitespacesAndNewlines)
            ingredient.amount = parseAmountString(rawAmount) ?? 0.0
            ingredient.notes = rawAmount
            ingredient.unit = ingredientData.unit
            ingredient.recipe = recipe
        }
        
        return recipe
    }
    
    // MARK: - Shopping List Helpers
    
    static func addRecipeIngredientsToShoppingList(
        recipe: Recipe,
        in context: NSManagedObjectContext
    ) throws {
        let ingredients = recipe.ingredientsArray
        let now = Date()

// Use case-insensitive normalization so "Milk" and "milk" are treated as duplicates.
        let existingNames: Set<String> = {
            let fetchRequest: NSFetchRequest<ShoppingItemEntity> = ShoppingItemEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "isChecked == NO")
            fetchRequest.includesPendingChanges = true
            fetchRequest.propertiesToFetch = ["name"]
            fetchRequest.returnsObjectsAsFaults = true

            let results = (try? context.fetch(fetchRequest)) ?? []
            return Set(results.compactMap { ($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        }()

        var seenNames = existingNames
        
        for ingredient in ingredients {
            let normalized = (ingredient.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { continue }

            if seenNames.contains(normalized) {
                continue  // Skip duplicate
            }
            seenNames.insert(normalized)
            
            let item = ShoppingItemEntity(context: context)
            item.id = UUID()
            item.createdDate = now
            item.modifiedDate = now  // Critical for CloudKit sync
            item.name = ingredient.name ?? ""
            item.amount = ingredient.rawAmountString
            item.unit = ingredient.unit ?? ""
            item.category = "Groceries"
            item.fromRecipe = recipe.name
            item.isChecked = false
        }
        
        try context.saveWithCloudKitSync()
    }
    
    // MARK: - Search Helpers
    
    static func searchRecipes(
        _ recipes: [Recipe],
        searchText: String,
        category: RecipeCategory?,
        favoritesOnly: Bool
    ) -> [Recipe] {
        var filtered = recipes
        
        if !searchText.isEmpty {
            let lowercased = searchText.lowercased()
            filtered = filtered.filter { recipe in
                recipe.name?.localizedCaseInsensitiveContains(lowercased) == true ||
                recipe.recipeDescription?.localizedCaseInsensitiveContains(lowercased) == true ||
                recipe.instructions?.localizedCaseInsensitiveContains(lowercased) == true ||
                recipe.ingredientsArray.contains { ingredient in
                    ingredient.name?.localizedCaseInsensitiveContains(lowercased) == true
                }
            }
        }
        
        if let category = category {
            filtered = filtered.filter { $0.cuisine == category.rawValue }
        }
        
        if favoritesOnly {
            filtered = filtered.filter { $0.isFavorite }
        }
        
        return filtered
    }
    
    static func sortRecipes(_ recipes: [Recipe], by option: SortOption) -> [Recipe] {
        var sorted = recipes
        
        switch option {
        case .dateNewest:
            sorted.sort { ($0.createdDate ?? Date.distantPast) > ($1.createdDate ?? Date.distantPast) }
        case .dateOldest:
            sorted.sort { ($0.createdDate ?? Date.distantPast) < ($1.createdDate ?? Date.distantPast) }
        case .nameAZ:
            sorted.sort { ($0.name ?? "") < ($1.name ?? "") }
        case .nameZA:
            sorted.sort { ($0.name ?? "") > ($1.name ?? "") }
        case .ratingHigh:
            sorted.sort { $0.rating > $1.rating }
        case .ratingLow:
            sorted.sort { $0.rating < $1.rating }
        case .quickest:
            sorted.sort { ($0.prepTime + $0.cookTime) < ($1.prepTime + $1.cookTime) }
        }
        
        return sorted
    }
}

