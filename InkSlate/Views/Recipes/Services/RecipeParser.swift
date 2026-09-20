import Foundation
import NaturalLanguage

struct RecipeParser {
    
    /// Parses a block of text into individual recipe ingredients.
    /// It handles common formats like "1 1/2 cups all-purpose flour"
    static func parseIngredients(from text: String) -> [RecipeIngredientData] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            
        return lines.map { parseSingleIngredient($0) }
    }
    
    /// Parses a block of text into steps.
    static func parseSteps(from text: String) -> [RecipeStep] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // Remove leading numbers or bullets (e.g. "1. ", "- ")
        let cleanLines = lines.map { line -> String in
            var cleaned = line
            if let match = cleaned.range(of: #"^(\d+[\.\)]\s*|- \s*|\* \s*)"#, options: .regularExpression) {
                cleaned.removeSubrange(match)
            }
            return cleaned.trimmingCharacters(in: .whitespaces)
        }
        
        return cleanLines.map { RecipeStep(instruction: $0) }
    }
    
    static func parseSingleIngredient(_ line: String) -> RecipeIngredientData {
        // Known units
        let units = [
            "cup", "cups", "c", "c.", 
            "tablespoon", "tablespoons", "tbsp", "tbsps", "tbs", "T",
            "teaspoon", "teaspoons", "tsp", "tsps", "t",
            "ounce", "ounces", "oz",
            "pound", "pounds", "lb", "lbs",
            "gram", "grams", "g",
            "kilogram", "kilograms", "kg",
            "milliliter", "milliliters", "ml",
            "liter", "liters", "l",
            "pint", "pints", "pt",
            "quart", "quarts", "qt",
            "gallon", "gallons", "gal",
            "pinch", "pinches", "dash", "dashes",
            "clove", "cloves", "slice", "slices", "piece", "pieces",
            "whole"
        ]
        
        var name = line
        var amount = ""
        var unit = ""
        
        // 1. Extract amount at the beginning
        // Pattern matches optional leading text, then numbers like "1", "1/2", "1 1/2", "1.5"
        let amountPattern = #"^(\d+\s+\d+/\d+|\d+/\d+|\d*\.?\d+)"#
        if let range = name.range(of: amountPattern, options: .regularExpression) {
            amount = String(name[range]).trimmingCharacters(in: .whitespaces)
            name.removeSubrange(range)
            name = name.trimmingCharacters(in: .whitespaces)
        }
        
        // 2. Extract unit if it exists right after the amount
        let firstWord = name.components(separatedBy: .whitespaces).first?.lowercased() ?? ""
        // Check if the first word (ignoring punctuation like plural 's' or '.') is a known unit
        let cleanFirstWord = firstWord.trimmingCharacters(in: .punctuationCharacters)
        
        if units.contains(cleanFirstWord) {
            unit = cleanFirstWord
            
            // Remove the unit from the name
            if let unitRange = name.range(of: firstWord, options: [.caseInsensitive]) {
                name.removeSubrange(unitRange)
                name = name.trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Remove trailing or leading punctuation/connecting words like "of"
        if name.lowercased().hasPrefix("of ") {
            name.removeFirst(3)
            name = name.trimmingCharacters(in: .whitespaces)
        }
        
        return RecipeIngredientData(
            id: UUID(),
            name: name.isEmpty ? line : name,
            amount: amount,
            unit: unit
        )
    }
}
