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
        
        for ingredientData in ingredients where ingredientData.hasName {
            let ingredient = RecipeIngredient(context: context)
            ingredient.id = UUID()
            ingredient.createdDate = Date()
            ingredient.modifiedDate = Date()
            ingredient.name = ingredientData.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawAmount = ingredientData.amount.trimmingCharacters(in: .whitespacesAndNewlines)
            ingredient.amount = parseAmountString(rawAmount) ?? 0.0
            ingredient.notes = rawAmount
            ingredient.unit = ingredientData.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            ingredient.recipe = recipe
        }
        
        return recipe
    }
    
    // MARK: - Shopping List Helpers
    
    /// Adds recipe ingredients to the shopping list.
    /// - Parameter ingredients: When non-nil, only these ingredients are added; otherwise all recipe ingredients.
    @discardableResult
    static func addRecipeIngredientsToShoppingList(
        recipe: Recipe,
        in context: NSManagedObjectContext,
        ingredients selectedIngredients: [RecipeIngredient]? = nil
    ) throws -> Int {
        let ingredients = selectedIngredients ?? recipe.ingredientsArray
        let now = Date()

        // Dedupe against any existing item (checked or not). Re-adding a checked
        // "Milk" unchecks/updates it instead of creating a second row.
        let existingByName: [String: ShoppingItemEntity] = {
            let fetchRequest: NSFetchRequest<ShoppingItemEntity> = ShoppingItemEntity.fetchRequest()
            fetchRequest.includesPendingChanges = true
            let results = (try? context.fetch(fetchRequest)) ?? []
            var map: [String: ShoppingItemEntity] = [:]
            for item in results {
                let key = (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !key.isEmpty else { continue }
                // Prefer an unchecked row if both somehow exist.
                if let prior = map[key], prior.isChecked == false { continue }
                map[key] = item
            }
            return map
        }()

        var seenNames = Set(existingByName.keys)
        var addedCount = 0
        
        for ingredient in ingredients {
            let normalized = (ingredient.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { continue }

            if let existing = existingByName[normalized] {
                if existing.isChecked {
                    existing.isChecked = false
                    existing.amount = ingredient.rawAmountString
                    existing.unit = ingredient.unit ?? existing.unit
                    existing.fromRecipe = recipe.name
                    existing.modifiedDate = now
                    addedCount += 1
                }
                continue
            }
            if seenNames.contains(normalized) {
                continue
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
            addedCount += 1
        }
        
        try context.saveWithCloudKitSync()
        return addedCount
    }
    
    /// Adds a single recipe ingredient to the shopping list.
    @discardableResult
    static func addIngredientToShoppingList(
        _ ingredient: RecipeIngredient,
        recipe: Recipe,
        in context: NSManagedObjectContext
    ) throws -> Int {
        try addRecipeIngredientsToShoppingList(
            recipe: recipe,
            in: context,
            ingredients: [ingredient]
        )
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

