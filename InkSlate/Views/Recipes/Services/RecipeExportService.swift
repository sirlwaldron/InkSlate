//
//  RecipeExportService.swift
//  InkSlate
//
//  Recipe export and sharing functionality
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

struct RecipeExportService {
    static func exportRecipe(_ recipe: Recipe) -> String {
        var text = "\(recipe.name ?? "Untitled Recipe")\n"
        text += "\(String(repeating: "=", count: 40))\n\n"
        
        if let description = recipe.recipeDescription, !description.isEmpty {
            text += "\(description)\n\n"
        }
        
        text += "Category: \(recipe.cuisine ?? "Uncategorized")\n"
        text += "Rating: \(recipe.rating)/5\n"
        text += "Prep Time: \(recipe.prepTime) minutes\n"
        text += "Cook Time: \(recipe.cookTime) minutes\n"
        if let servings = recipe.servings {
            text += "Servings: \(servings)\n"
        }
        text += "\n"
        
        // Ingredients
        let ingredients = recipe.ingredientsArray
        if !ingredients.isEmpty {
            text += "INGREDIENTS:\n"
            text += "\(String(repeating: "-", count: 40))\n"
            for ingredient in ingredients {
                let amount = ingredient.rawAmountString
                let unit = ingredient.unit ?? ""
                let name = ingredient.name ?? ""
                text += "• \(amount) \(unit) \(name)\n".trimmingCharacters(in: .whitespaces) + "\n"
            }
            text += "\n"
        }
        
        // Instructions
        let steps = recipe.recipeSteps
        if !steps.isEmpty {
            text += "INSTRUCTIONS:\n"
            text += "\(String(repeating: "-", count: 40))\n"
            for (index, step) in steps.enumerated() {
                text += "\(index + 1). \(step.instruction)\n"
                if let timer = step.timerMinutes {
                    text += "   (Timer: \(timer) minutes)\n"
                }
                text += "\n"
            }
        }
        
        // Notes
        if !recipe.recipeNotes.isEmpty {
            text += "NOTES:\n"
            text += "\(String(repeating: "-", count: 40))\n"
            text += "\(recipe.recipeNotes)\n"
        }
        
        return text
    }
    
    static func shareRecipe(_ recipe: Recipe) -> [Any] {
        var items: [Any] = []
        
        // Add text
        items.append(exportRecipe(recipe))
        
        // Add image if available (prefer file URL so it always attaches).
        if let imagePath = recipe.imageUrl {
            if let url = RecipeImageStore.fileURL(path: imagePath) {
                items.append(url)
            } else if let image = RecipeImageStore.cachedImage(path: imagePath) {
                items.append(image)
            }
        }
        
        return items
    }
}

