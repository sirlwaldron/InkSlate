//
//  RecipeHelpers.swift
//  InkSlate
//
//  Helper functions and utilities for recipe views
//

import Foundation
import SwiftUI

// MARK: - Helper Functions

func parseAmountString(_ text: String) -> Double? {
    return RecipeService.parseAmountString(text)
}

// MARK: - Error Handling Helper

func handleRecipeError(_ error: Error, context: String = "") {
    let message = "\(context.isEmpty ? "" : context + ": ")\(error.localizedDescription)"
    print("Recipe Error: \(message)")
    
    // In production, you might want to show an alert to the user
    // For now, we'll just log it
}

// MARK: - Validation Helpers

struct RecipeValidation {
    static func validateAmount(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true // Empty is valid (optional)
        }
        return RecipeService.parseAmountString(text) != nil
    }
    
    static func validateImageData(_ data: Data?) -> Bool {
        guard let data = data else { return true } // Optional
        guard data.count > 0 else { return false }
        guard data.count < Int(RecipeConstants.maxImageSize) else { return false }
        return UIImage(data: data) != nil
    }
}

