//
//  DateFormatter+Extensions.swift
//  InkSlate
//
//  Performance Optimization - Cached DateFormatters
//  Created on 10/9/2025
//

import Foundation

extension DateFormatter {
    /// Short time format (e.g., "3:45 PM")
    /// Use for note timestamps in list rows
    static let noteTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    
    /// Medium date + short time (e.g., "Oct 9, 2025 at 3:45 PM")
    /// Use for detailed note views
    static let noteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    /// Short date only (e.g., "Oct 9, 2025")
    /// Use for trash/archive views
    static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    /// Compact date (e.g., "10/9/25")
    static let compactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}


