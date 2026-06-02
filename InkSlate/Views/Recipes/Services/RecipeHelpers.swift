import Foundation
import SwiftUI

// MARK: - Helper Functions

func parseAmountString(_ text: String) -> Double? {
    return RecipeService.parseAmountString(text)
}

// MARK: - Error Handling Helper

func handleRecipeError(_: Error, context _: String = "") {}

// MARK: - Validation Helpers

struct RecipeValidation {
    static func validateAmount(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        return RecipeService.parseAmountString(text) != nil
    }
    
    static func validateImageData(_ data: Data?) -> Bool {
        guard let data = data else { return true }
        guard data.count > 0 else { return false }
        guard data.count < Int(RecipeConstants.maxImageSize) else { return false }
        return platformImage(from: data) != nil
    }
}

