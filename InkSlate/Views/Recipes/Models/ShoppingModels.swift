//
//  ShoppingModels.swift
//  InkSlate
//
//  Shopping list data models
//

import Foundation
import SwiftUI

enum ShoppingCategory: String, CaseIterable {
    case general = "General"
    case produce = "Produce"
    case meat = "Meat & Seafood"
    case dairy = "Dairy"
    case bakery = "Bakery"
    case pantry = "Pantry Staples"
    case beverages = "Beverages"
    case frozen = "Frozen"
    case snacks = "Snacks"
    case household = "Household"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .general: return "square.grid.2x2"
        case .produce: return "leaf.fill"
        case .meat: return "fork.knife"
        case .dairy: return "drop.fill"
        case .bakery: return "birthday.cake.fill"
        case .pantry: return "shippingbox"
        case .beverages: return "cup.and.saucer.fill"
        case .frozen: return "snowflake"
        case .snacks: return "popcorn.fill"
        case .household: return "sparkles"
        case .other: return "ellipsis"
        }
    }
}

