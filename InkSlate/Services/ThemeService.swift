import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Theme Service
class ThemeService: ObservableObject {
    static let shared = ThemeService()
    
    @Published var isDarkMode: Bool = false
    @Published var accentTheme: AccentTheme = .graphite
    @Published var dynamicFonts: Bool = true
    @Published var fontSize: CGFloat = 16
    @Published private(set) var appearanceVersion: Int = 0
    
    private enum Keys {
        static let isDarkMode = "theme.isDarkMode"
        static let accentTheme = "theme.accentTheme"
        static let dynamicFonts = "theme.dynamicFonts"
        static let fontSize = "theme.fontSize"
    }

    enum AccentTheme: String, CaseIterable, Identifiable {
        case graphite
        case blue
        case green
        case purple
        case orange

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .graphite: return "Graphite"
            case .blue: return "Ocean"
            case .green: return "Forest"
            case .purple: return "Violet"
            case .orange: return "Sunset"
            }
        }

        var adaptiveAccentColor: Color {
            switch self {
            case .graphite:
                return Color(light: Color(red: 0.2, green: 0.2, blue: 0.2),
                               dark: Color(red: 0.85, green: 0.85, blue: 0.85))
            case .blue:
                return Color(light: Color(red: 0.14, green: 0.43, blue: 0.98),
                               dark: Color(red: 0.46, green: 0.72, blue: 1.00))
            case .green:
                return Color(light: Color(red: 0.15, green: 0.62, blue: 0.36),
                               dark: Color(red: 0.45, green: 0.86, blue: 0.63))
            case .purple:
                return Color(light: Color(red: 0.58, green: 0.29, blue: 0.94),
                               dark: Color(red: 0.77, green: 0.58, blue: 1.00))
            case .orange:
                return Color(light: Color(red: 0.95, green: 0.49, blue: 0.12),
                               dark: Color(red: 1.00, green: 0.70, blue: 0.38))
            }
        }
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
        if let raw = defaults.string(forKey: Keys.accentTheme),
           let parsed = AccentTheme(rawValue: raw) {
            accentTheme = parsed
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
        setDarkMode(!isDarkMode)
    }
    
    func setDarkMode(_ enabled: Bool) {
        guard isDarkMode != enabled else { return }
        isDarkMode = enabled
        persist()
    }
    
    func setDynamicFonts(_ enabled: Bool) {
        guard dynamicFonts != enabled else { return }
        dynamicFonts = enabled
        persist()
    }
    
    func setAccentTheme(_ theme: AccentTheme) {
        guard accentTheme != theme else { return }
        accentTheme = theme
        persist()
    }

    func setFontSize(_ size: CGFloat) {
        guard fontSize != size else { return }
        fontSize = size
        persist()
    }

    func applyFontSizeFromSlider(_ size: CGFloat) {
        let clamped = min(24, max(12, round(size)))
        fontSize = clamped
        UserDefaults.standard.set(Double(clamped), forKey: Keys.fontSize)
        applyTheme()
        appearanceVersion &+= 1
    }
    
    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(isDarkMode, forKey: Keys.isDarkMode)
        defaults.set(accentTheme.rawValue, forKey: Keys.accentTheme)
        defaults.set(dynamicFonts, forKey: Keys.dynamicFonts)
        defaults.set(Double(fontSize), forKey: Keys.fontSize)
        applyTheme()
        appearanceVersion &+= 1
    }
    
    private func applyTheme() {
        #if canImport(UIKit)
        #endif
    }
}

// MARK: - Accent Palette
extension ThemeService {
    var accentColor: Color {
        accentTheme.adaptiveAccentColor
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
        ThemeService.shared.accentColor
    }
}

// MARK: - Theme Settings View
struct ThemeSettingsView: View {
    @EnvironmentObject private var themeService: ThemeService
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Appearance") {
                    Toggle("Dark Mode", isOn: Binding(
                        get: { themeService.isDarkMode },
                        set: { themeService.setDarkMode($0) }
                    ))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Accent Color")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            ForEach(ThemeService.AccentTheme.allCases) { theme in
                                let isCurrent = themeService.accentTheme == theme
                                Button {
                                    themeService.setAccentTheme(theme)
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(theme.adaptiveAccentColor)
                                            .frame(width: 34, height: 34)
                                        if isCurrent {
                                            Circle()
                                                .strokeBorder(Color.primary, lineWidth: 2.5)
                                                .frame(width: 42, height: 42)
                                        } else {
                                            Circle()
                                                .strokeBorder(theme.adaptiveAccentColor.opacity(0.35), lineWidth: 1)
                                                .frame(width: 38, height: 38)
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                                    .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(theme.displayName))
                                .accessibilityAddTraits(isCurrent ? .isSelected : [])
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    
                    Toggle("Dynamic Fonts", isOn: Binding(
                        get: { themeService.dynamicFonts },
                        set: { themeService.setDynamicFonts($0) }
                    ))
                }
                
                Section("Font Size") {
                    HStack {
                        Text("Size")
                        Spacer()
                        Slider(
                            value: Binding(
                                get: { themeService.fontSize },
                                set: { themeService.applyFontSizeFromSlider($0) }
                            ),
                            in: 12...24,
                            step: 1
                        )
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .tint(themeService.accentColor)
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
