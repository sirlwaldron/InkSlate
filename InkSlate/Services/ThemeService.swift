//
//  ThemeService.swift
//  InkSlate
//
//  Created by Lucas Waldron on 10/18/25.
//  Based on FSNotes theme implementation
//

import SwiftUI
import UIKit

// MARK: - Theme Service (FSNotes-inspired)
class ThemeService: ObservableObject {
    static let shared = ThemeService()
    
    @Published var isDarkMode: Bool = false
    @Published var dynamicFonts: Bool = true
    @Published var fontSize: CGFloat = 16
    
    private init() {
        // Initialize with system appearance
        updateAppearance()
    }
    
    
    deinit {
        
    }
    
    func updateAppearance() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            isDarkMode = windowScene.traitCollection.userInterfaceStyle == .dark
        }
    }
    
    func toggleDarkMode() {
        isDarkMode.toggle()
        // Apply theme changes
        applyTheme()
    }
    
    func setDynamicFonts(_ enabled: Bool) {
        dynamicFonts = enabled
        applyTheme()
    }
    
    func setFontSize(_ size: CGFloat) {
        fontSize = size
        applyTheme()
    }
    
    private func applyTheme() {
        // Update UI appearance based on theme
        if isDarkMode {
            // Dark mode colors
            UINavigationBar.appearance().barTintColor = UIColor.systemBackground
            UINavigationBar.appearance().tintColor = UIColor.label
            UITextView.appearance().backgroundColor = UIColor.systemBackground
            UITextView.appearance().textColor = UIColor.label
        } else {
            // Light mode colors
            UINavigationBar.appearance().barTintColor = UIColor.systemBackground
            UINavigationBar.appearance().tintColor = UIColor.label
            UITextView.appearance().backgroundColor = UIColor.systemBackground
            UITextView.appearance().textColor = UIColor.label
        }
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
                            themeService.toggleDarkMode()
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
