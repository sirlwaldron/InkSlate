//
//  PantryModels.swift
//  InkSlate
//
//  Pantry data models
//

import Foundation
import SwiftUI

enum PantryCategory: String, CaseIterable, Codable {
    case fridge = "Fridge"
    case spices = "Spice Cabinet"
    case pantry = "Pantry"
    case freezer = "Freezer"
    
    var icon: String {
        switch self {
        case .fridge: return "refrigerator.fill"
        case .spices: return "sparkles"
        case .pantry: return "cabinet.fill"
        case .freezer: return "snowflake"
        }
    }

    var navigationTitle: String {
        switch self {
        case .fridge: return "What's in My Fridge"
        case .spices: return "Spice Cabinet"
        case .pantry: return "Pantry Staples"
        case .freezer: return "Freezer"
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .fridge: return "Nothing in the fridge yet"
        case .spices: return "No spices recorded"
        case .pantry: return "Pantry is empty"
        case .freezer: return "Freezer inventory is empty"
        }
    }
}

