//
//  ThemeService.swift
//  InkSlate
//
//  Created by Lucas Waldron on 10/18/25.
//  Based on FSNotes theme implementation
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Theme Service (FSNotes-inspired)
class ThemeService: ObservableObject {
    static let shared = ThemeService()
    
    @Published var isDarkMode: Bool = false
    @Published var dynamicFonts: Bool = true
    @Published var fontSize: CGFloat = 16
    
    private enum Keys {
        static let isDarkMode = "theme.isDarkMode"
        static let dynamicFonts = "theme.dynamicFonts"
        static let fontSize = "theme.fontSize"
    }
    
    private init() {
        loadFromDefaults()
        applyTheme()
    }
    
    private func loadFromDefaults() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.isDarkMode) != nil {
            isDarkMode = defaults.bool(forKey: Keys.isDarkMode)
        }
        if defaults.object(forKey: Keys.dynamicFonts) != nil {
            dynamicFonts = defaults.bool(forKey: Keys.dynamicFonts)
        }
        if defaults.object(forKey: Keys.fontSize) != nil {
            let v = defaults.double(forKey: Keys.fontSize)
            if v > 0 { fontSize = CGFloat(v) }
        }
    }
    
    func toggleDarkMode() {
        isDarkMode.toggle()
        persist()
    }
    
    func setDarkMode(_ enabled: Bool) {
        isDarkMode = enabled
        persist()
    }
    
    func setDynamicFonts(_ enabled: Bool) {
        dynamicFonts = enabled
        persist()
    }
    
    func setFontSize(_ size: CGFloat) {
        fontSize = size
        persist()
    }
    
    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(isDarkMode, forKey: Keys.isDarkMode)
        defaults.set(dynamicFonts, forKey: Keys.dynamicFonts)
        defaults.set(Double(fontSize), forKey: Keys.fontSize)
        applyTheme()
    }
    
    private func applyTheme() {
        #if canImport(UIKit)
        UINavigationBar.appearance().barTintColor = UIColor.systemBackground
        UINavigationBar.appearance().tintColor = UIColor.label
        UITextView.appearance().backgroundColor = UIColor.systemBackground
        UITextView.appearance().textColor = UIColor.label
        #endif
        // macOS uses system appearance; no need to set NSAppearance here
    }
}

// MARK: - Dynamic Font Support
extension Font {
    static func dynamicFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if ThemeService.shared.dynamicFonts {
            return .system(size: size, weight: weight, design: .default)
        } else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
    }
}

// MARK: - Theme-Aware Colors
extension Color {
    static var themeBackground: Color {
        ThemeService.shared.isDarkMode ? Color.black : Color.white
    }
    
    static var themeSecondary: Color {
        ThemeService.shared.isDarkMode ? Color.gray : Color.secondary
    }
    
    static var themeAccent: Color {
        ThemeService.shared.isDarkMode ? Color.blue : Color.blue
    }
}

// MARK: - Theme Settings View
struct ThemeSettingsView: View {
    @StateObject private var themeService = ThemeService.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Appearance") {
                    Toggle("Dark Mode", isOn: $themeService.isDarkMode)
                        .onChange(of: themeService.isDarkMode) { _, newValue in
                            themeService.setDarkMode(newValue)
                        }
                    
                    Toggle("Dynamic Fonts", isOn: $themeService.dynamicFonts)
                        .onChange(of: themeService.dynamicFonts) { _, newValue in
                            themeService.setDynamicFonts(newValue)
                        }
                }
                
                Section("Font Size") {
                    HStack {
                        Text("Size")
                        Spacer()
                        Slider(value: $themeService.fontSize, in: 12...24, step: 1)
                            .frame(width: 150)
                        Text("\(Int(themeService.fontSize))")
                            .foregroundColor(.secondary)
                    }
                    .onChange(of: themeService.fontSize) { _, newValue in
                        themeService.setFontSize(newValue)
                    }
                }
                
                Section("Preview") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sample Text")
                            .font(.dynamicFont(size: themeService.fontSize, weight: .bold))
                        
                        Text("This is how your notes will look with the current settings.")
                            .font(.dynamicFont(size: themeService.fontSize))
                            .foregroundColor(.themeSecondary)
                    }
                    .padding()
                    .background(Color.themeBackground)
                    .cornerRadius(8)
                }
            }
            .navigationTitle("Theme Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
