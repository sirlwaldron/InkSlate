//
//  RecipeModels.swift
//  InkSlate
//
//  Recipe data models and enums
//

import Foundation
import SwiftUI

// MARK: - Recipe Category

enum RecipeCategory: String, CaseIterable {
    case appetizer = "Appetizer"
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case dessert = "Dessert"
    case snack = "Snack"
    case beverage = "Beverage"
    case side = "Side Dish"
    
    var icon: String {
        switch self {
        case .appetizer: return "fork.knife.circle.fill"
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.fill"
        case .dessert: return "birthday.cake.fill"
        case .snack: return "popcorn.fill"
        case .beverage: return "cup.and.saucer.fill"
        case .side: return "square.split.2x2.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .appetizer: return .mint
        case .breakfast: return .orange
        case .lunch: return .yellow
        case .dinner: return .blue
        case .dessert: return .pink
        case .snack: return .green
        case .beverage: return .purple
        case .side: return .brown
        }
    }
}

// MARK: - Dietary Tags

enum DietaryTag: String, CaseIterable {
    case vegetarian = "Vegetarian"
    case vegan = "Vegan"
    case glutenFree = "Gluten-Free"
    case dairyFree = "Dairy-Free"
    case keto = "Keto"
    case paleo = "Paleo"
    case lowCarb = "Low-Carb"
    case highProtein = "High-Protein"
    
    var icon: String {
        switch self {
        case .vegetarian: return "leaf.fill"
        case .vegan: return "leaf.circle.fill"
        case .glutenFree: return "g.circle.fill"
        case .dairyFree: return "drop.circle.fill"
        case .keto: return "k.circle.fill"
        case .paleo: return "p.circle.fill"
        case .lowCarb: return "chart.line.downtrend.xyaxis"
        case .highProtein: return "figure.strengthtraining.traditional"
        }
    }
}

// MARK: - Sort Options

enum SortOption: String, CaseIterable {
    case dateNewest = "Newest First"
    case dateOldest = "Oldest First"
    case nameAZ = "Name (A-Z)"
    case nameZA = "Name (Z-A)"
    case ratingHigh = "Highest Rated"
    case ratingLow = "Lowest Rated"
    case quickest = "Quickest to Make"
}

// MARK: - Recipe Ingredient Data

struct RecipeIngredientData: Codable, Identifiable {
    let id: UUID
    var name: String
    var amount: String
    var unit: String
    var isChecked: Bool = false
    
    init(id: UUID = UUID(), name: String, amount: String, unit: String) {
        self.id = id
        self.name = name
        self.amount = amount
        self.unit = unit
    }
}

// MARK: - Recipe Step

struct RecipeStep: Codable, Identifiable {
    let id: UUID
    var instruction: String
    var timerMinutes: Int?
    var isCompleted: Bool = false
    
    init(id: UUID = UUID(), instruction: String, timerMinutes: Int? = nil) {
        self.id = id
        self.instruction = instruction
        self.timerMinutes = timerMinutes
    }
}

// MARK: - Constants

enum RecipeConstants {
    static let favoriteRatingThreshold = 4
    static let maxImageSize: Int64 = 10 * 1024 * 1024 // 10MB
}

