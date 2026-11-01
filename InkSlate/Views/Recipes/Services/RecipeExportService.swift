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
        if let videoURL = recipe.videoURL, !videoURL.isEmpty {
            text += "Video: \(videoURL)\n"
        }
        text += "\n"
        
        let ingredients = recipe.ingredientsArray
        if !ingredients.isEmpty {
            text += "INGREDIENTS:\n"
            text += "\(String(repeating: "-", count: 40))\n"
            for ingredient in ingredients {
                // `.trimmingCharacters(in: .whitespaces)` doesn't strip "\n", so the old code added a blank
                // line after every ingredient, and empty amount/unit left double spaces.
                let parts = [ingredient.rawAmountString, ingredient.unit ?? "", ingredient.name ?? ""]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                text += "• " + parts.joined(separator: " ") + "\n"
            }
            text += "\n"
        }
        
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
        
        if !recipe.recipeNotes.isEmpty {
            text += "NOTES:\n"
            text += "\(String(repeating: "-", count: 40))\n"
            text += "\(recipe.recipeNotes)\n"
        }
        
        return text
    }
    
    static func shareRecipe(_ recipe: Recipe) -> [Any] {
        var items: [Any] = []
        
        items.append(exportRecipe(recipe))
        
        if let imagePath = recipe.imageUrl {
            if let url = RecipeImageStore.existingFileURL(path: imagePath) {
                items.append(url)
            } else if let image = RecipeImageStore.cachedImage(path: imagePath) {
                items.append(image)
            }
        }
        
        return items
    }
}

