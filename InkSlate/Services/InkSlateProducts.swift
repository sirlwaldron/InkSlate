import Foundation

// MARK: - App Store product identifiers (must match App Store Connect + InkSlate.storekit)

enum InkSlateProducts {
    static let monthly = "com.lucas.InkSlateNew.pro.sub.monthly"
    static let yearly = "com.lucas.InkSlateNew.pro.sub.yearly"
    static let lifetime = "com.lucas.InkSlateNew.pro.lifetime"

    static let subscriptionIDs: Set<String> = [monthly, yearly]
    static let allProductIDs: Set<String> = [monthly, yearly, lifetime]

    static let loadOrder: [String] = [yearly, monthly, lifetime]
}

// MARK: - Free vs Pro modules

extension MenuViewType {
    var requiresPro: Bool {
        switch self {
        case .notes, .budget, .calendar, .items, .settings, .profile:
            return false
        case .mindMaps, .journal, .todo, .recipes, .places, .quotes, .wantToWatch:
            return true
        }
    }

    var proFeatureTitle: String {
        switch self {
        case .mindMaps: return "Mind Maps"
        case .journal: return "Journal"
        case .todo: return "To-Do"
        case .recipes: return "Recipes"
        case .places: return "Places"
        case .quotes: return "Quotes"
        case .wantToWatch: return "Watchlist"
        default: return menuTitle
        }
    }

    static var proModules: [MenuViewType] {
        allCases.filter(\.requiresPro)
    }

    static var freeModules: [MenuViewType] {
        allCases.filter { !$0.requiresPro && $0 != .settings && $0 != .profile }
    }
}

enum InkSlateLegal {
    static let privacyPolicy = URL(string: "https://sirlwaldron.github.io/InkSlate/privacy.html")!
    static let termsOfUse = URL(string: "https://sirlwaldron.github.io/InkSlate/terms.html")!
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
}
