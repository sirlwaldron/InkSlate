//
//  ColorExtensions.swift
//  InkSlate
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Color Extension
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String {
        #if canImport(UIKit)
        let components = UIColor(self).cgColor.components
        #elseif canImport(AppKit)
        let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components
        #else
        let components: [CGFloat]? = nil
        #endif
        let r = components?[0] ?? 0
        let g = components?[1] ?? 0
        let b = components?[2] ?? 0
        return String(format: "#%02lX%02lX%02lX", lroundf(Float(r * 255)), lroundf(Float(g * 255)), lroundf(Float(b * 255)))
    }
    
    /// Cross-platform list/card background (systemBackground on iOS, windowBackgroundColor on macOS).
    static var adaptiveSystemBackground: Color {
        #if canImport(UIKit)
        return Color(.systemBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color.white
        #endif
    }
    
    /// Cross-platform gray (systemGray5 on iOS, light gray on macOS).
    static var adaptiveSystemGray: Color {
        #if canImport(UIKit)
        return Color(.systemGray5)
        #elseif canImport(AppKit)
        return Color(nsColor: .systemGray)
        #else
        return Color.gray
        #endif
    }
    /// System blue CGColor (for calendar/event colors).
    static var platformSystemBlueCGColor: CGColor {
        #if canImport(UIKit)
        return UIColor.systemBlue.cgColor
        #elseif canImport(AppKit)
        return NSColor.systemBlue.cgColor
        #else
        return CGColor(red: 0, green: 0.478, blue: 1, alpha: 1)
        #endif
    }
    /// Cross-platform separator (divider) color.
    static var adaptiveSeparator: Color {
        #if canImport(UIKit)
        return Color(.separator)
        #elseif canImport(AppKit)
        return Color(nsColor: .separatorColor)
        #else
        return Color.gray.opacity(0.3)
        #endif
    }
}
