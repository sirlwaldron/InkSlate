//
//  RecipeExtensions.swift
//  InkSlate
//
//  CoreData Recipe entity extensions
//

import Foundation
import CoreData

// MARK: - Recipe Extensions

extension Recipe {
    var isFavorite: Bool {
        return rating >= Int16(RecipeConstants.favoriteRatingThreshold)
    }
    
    var totalTime: Int {
        return Int(prepTime) + Int(cookTime)
    }
    
    var ingredientsArray: [RecipeIngredient] {
        (ingredients?.allObjects as? [RecipeIngredient]) ?? []
    }
    
    fileprivate var recipeDetails: StoredRecipeDetails {
        if let instructions = instructions,
           let data = instructions.data(using: .utf8),
           let details = try? recipeDetailsDecoder.decode(StoredRecipeDetails.self, from: data) {
            return details
        }
        
        if let instructions = instructions, !instructions.isEmpty {
            return StoredRecipeDetails(
                steps: [StoredRecipeStep(id: UUID(), instruction: instructions, timerMinutes: nil)],
                notes: nil
            )
        }
        
        return StoredRecipeDetails(steps: [], notes: nil)
    }
    
    var recipeSteps: [RecipeStep] {
        recipeDetails.steps.map {
            RecipeStep(id: $0.id, instruction: $0.instruction, timerMinutes: $0.timerMinutes)
        }
    }
    
    var recipeNotes: String {
        recipeDetails.notes ?? ""
    }
    
    var dietaryTagsSet: Set<DietaryTag> {
        guard
            let source = source,
            let data = source.data(using: .utf8),
            let rawValues = try? dietaryTagsDecoder.decode([String].self, from: data)
        else { return [] }
        
        return Set(rawValues.compactMap { DietaryTag(rawValue: $0) })
    }
    
    func updateDetails(steps: [RecipeStep], notes: String) {
        let storedSteps = steps.map { step in
            StoredRecipeStep(id: step.id, instruction: step.instruction, timerMinutes: step.timerMinutes)
        }
        
        let storedDetails = StoredRecipeDetails(
            steps: storedSteps,
            notes: notes.isEmpty ? nil : notes
        )
        
        if let data = try? recipeDetailsEncoder.encode(storedDetails),
           let json = String(data: data, encoding: .utf8) {
            instructions = json
        } else {
            instructions = notes
        }
    }
    
    func updateDietaryTags(_ tags: Set<DietaryTag>) {
        let rawValues = tags.map { $0.rawValue }
        if let data = try? dietaryTagsEncoder.encode(rawValues),
           let json = String(data: data, encoding: .utf8) {
            source = json
        } else {
            source = nil
        }
    }
}

extension RecipeIngredient {
    var rawAmountString: String {
        (notes?.isEmpty == false) ? notes! : formattedAmount
    }
    
    var formattedAmount: String {
        if amount == 0 { return "" }
        if amount.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(amount))
        }
        return String(format: "%.2f", amount)
    }
}

// MARK: - Shopping Item Extensions

extension ShoppingItemEntity {
    var itemID: UUID { id ?? UUID() }
    var wrappedName: String { name ?? "" }
    var wrappedAmount: String { amount ?? "" }
    var wrappedUnit: String { unit ?? "" }
    var wrappedCategory: String { category ?? "Other" }
    var recipeSource: String? {
        guard let fromRecipe, !fromRecipe.isEmpty else { return nil }
        return fromRecipe
    }
    var createdAt: Date { createdDate ?? Date() }
}

// MARK: - Pantry Item Extensions

extension PantryItemEntity {
    var itemID: UUID { id ?? UUID() }
    var wrappedName: String { name ?? "" }
    var wrappedQuantity: String { quantity ?? "" }
    var wrappedUnit: String { unit ?? "" }
    var wrappedNotes: String { notes ?? "" }
    var wrappedCategory: PantryCategory {
        PantryCategory(rawValue: category ?? PantryCategory.pantry.rawValue) ?? .pantry
    }
    var createdAt: Date { createdDate ?? Date() }
}

// MARK: - Persistence Helpers

fileprivate struct StoredRecipeStep: Codable {
    let id: UUID
    let instruction: String
    let timerMinutes: Int?
}

fileprivate struct StoredRecipeDetails: Codable {
    var steps: [StoredRecipeStep]
    var notes: String?
}

private let recipeDetailsDecoder = JSONDecoder()
private let recipeDetailsEncoder = JSONEncoder()
private let dietaryTagsDecoder = JSONDecoder()
private let dietaryTagsEncoder = JSONEncoder()

