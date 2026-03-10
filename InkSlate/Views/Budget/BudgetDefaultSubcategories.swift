//
//  BudgetDefaultSubcategories.swift
//  InkSlate
//
//  Created by Lucas Waldron on 1/2/25.
//

import Foundation

struct BudgetDefaultSubcategories {
    static let defaults: [String: [String]] = [
        "🚗 Transportation": [
            "Car Payment",
            "Car Insurance",
            "Fuel / Gas",
            "Public Transit / Rideshare",
            "Parking / Tolls",
            "Maintenance & Repairs",
            "Vehicle Registration / Licensing"
        ],
        "🏠 Housing & Utilities": [
            "Rent / Mortgage",
            "Property Taxes / HOA",
            "Home Insurance",
            "Electricity",
            "Water & Sewer",
            "Gas / Heating",
            "Internet",
            "Phone / Mobile",
            "Trash / Recycling",
            "Home Maintenance / Repairs"
        ],
        "🛍️ Daily Living & Household": [
            "Groceries",
            "Household Supplies",
            "Personal Care",
            "Clothing & Shoes",
            "Childcare / Babysitting",
            "Pet Care",
            "Laundry / Dry Cleaning"
        ],
        "🍽️ Food & Leisure": [
            "Dining Out / Takeout",
            "Coffee / Snacks",
            "Entertainment",
            "Hobbies",
            "Subscriptions / Memberships",
            "Vacations & Travel"
        ],
        "💵 Financial Obligations": [
            "Income Taxes",
            "Debt Payments",
            "Insurance",
            "Investments",
            "Retirement Contributions",
            "Emergency Fund",
            "Savings Goals"
        ],
        "🧠 Education & Personal Growth": [
            "School Tuition / Fees",
            "Books & Supplies",
            "Courses / Training",
            "Kids' Activities"
        ],
        "🩺 Health & Wellness": [
            "Health Insurance Premiums",
            "Doctor / Dentist Visits",
            "Prescriptions / Medications",
            "Therapy / Counseling",
            "Fitness"
        ],
        "🎁 Gifts & Giving": [
            "Charitable Donations",
            "Birthday / Holiday Gifts",
            "Special Occasions"
        ],
        "📝 Miscellaneous": [
            "Miscellaneous Expenses",
            "Buffer / Unplanned",
            "Allowances"
        ]
    ]
    
    static func subcategories(for categoryName: String) -> [String] {
        return defaults[categoryName] ?? []
    }
}

