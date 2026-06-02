import Foundation

struct BudgetDefaultSubcategories {
    static let defaults: [String: [String]] = [
        "🏠 Housing": [
            "Rent / Mortgage",
            "Utilities"
        ],
        "🍽️ Food": [
            "Groceries",
            "Dining Out"
        ],
        "🚗 Transportation": [
            "Fuel / Gas",
            "Car / Transit"
        ],
        "🧾 Bills": [
            "Phone",
            "Internet",
            "Insurance"
        ],
        "🛍️ Shopping": [
            "Household",
            "Personal"
        ],
        "💰 Savings": [
            "Emergency Fund",
            "Goals"
        ],
        "🎉 Fun": [
            "Entertainment",
            "Hobbies"
        ],
        "📺 Subscriptions": [
            "Netflix",
            "Hulu",
            "Disney+",
            "Max",
            "Prime Video",
            "Apple TV+",
            "Paramount+",
            "Peacock",
            "YouTube Premium",
            "Spotify",
            "Crunchyroll",
            "ESPN+"
        ],
        "📝 Misc": [
            "General"
        ]
    ]
    
    static func subcategories(for categoryName: String) -> [String] {
        return defaults[categoryName] ?? []
    }
}

