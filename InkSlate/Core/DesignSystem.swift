//
//  DesignSystem.swift
//  InkSlate
//
//  Created by UI Overhaul on 9/29/25.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Color Extension for Light/Dark Mode
extension Color {
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .light, .unspecified:
                return UIColor(light)
            case .dark:
                return UIColor(dark)
            @unknown default:
                return UIColor(light)
            }
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(dark)
            }
            return NSColor(light)
        })
        #else
        self = light
        #endif
    }
}

// MARK: - Minimalist Design System
struct DesignSystem {
    
    // MARK: - Colors
    struct Colors {
        // Primary Colors - Minimalist (Dark Mode Adaptive)
        static let accent = Color(light: Color(red: 0.2, green: 0.2, blue: 0.2), 
                                 dark: Color(red: 0.85, green: 0.85, blue: 0.85))
        static let accentLight = Color(light: Color(red: 0.4, green: 0.4, blue: 0.4),
                                      dark: Color(red: 0.65, green: 0.65, blue: 0.65))
        static let accentDark = Color(light: Color(red: 0.1, green: 0.1, blue: 0.1),
                                     dark: Color(red: 0.95, green: 0.95, blue: 0.95))
        
        
        static let background = Color(light: Color(red: 0.98, green: 0.98, blue: 0.98),
                                     dark: Color(red: 0.1, green: 0.1, blue: 0.1))
        static let backgroundSecondary = Color(light: Color(red: 0.96, green: 0.96, blue: 0.96),
                                              dark: Color(red: 0.15, green: 0.15, blue: 0.15))
        static let backgroundTertiary = Color(light: Color(red: 0.94, green: 0.94, blue: 0.94),
                                             dark: Color(red: 0.2, green: 0.2, blue: 0.2))
        static let surface = Color(light: .white,
                                  dark: Color(red: 0.12, green: 0.12, blue: 0.12))
        
        // Text Colors - Minimalist (Dark Mode Adaptive)
        static let textPrimary = Color(light: Color(red: 0.15, green: 0.15, blue: 0.15),
                                      dark: Color(red: 0.95, green: 0.95, blue: 0.95))
        static let textSecondary = Color(light: Color(red: 0.45, green: 0.45, blue: 0.45),
                                        dark: Color(red: 0.65, green: 0.65, blue: 0.65))
        static let textTertiary = Color(light: Color(red: 0.65, green: 0.65, blue: 0.65),
                                       dark: Color(red: 0.45, green: 0.45, blue: 0.45))
        static let textInverse = Color(light: .white,
                                      dark: Color(red: 0.1, green: 0.1, blue: 0.1))
        
        // Status Colors - Muted (Dark Mode Adaptive)
        static let success = Color(light: Color(red: 0.3, green: 0.5, blue: 0.3),
                                  dark: Color(red: 0.4, green: 0.7, blue: 0.4))
        static let warning = Color(light: Color(red: 0.6, green: 0.5, blue: 0.3),
                                  dark: Color(red: 0.8, green: 0.7, blue: 0.4))
        static let error = Color(light: Color(red: 0.6, green: 0.4, blue: 0.4),
                                dark: Color(red: 0.8, green: 0.5, blue: 0.5))
        static let info = Color(light: Color(red: 0.3, green: 0.4, blue: 0.5),
                               dark: Color(red: 0.4, green: 0.5, blue: 0.7))
        
        // Border Colors - Subtle (Dark Mode Adaptive)
        static let border = Color(light: Color(red: 0.88, green: 0.88, blue: 0.88),
                                 dark: Color(red: 0.25, green: 0.25, blue: 0.25))
        static let borderLight = Color(light: Color(red: 0.92, green: 0.92, blue: 0.92),
                                      dark: Color(red: 0.2, green: 0.2, blue: 0.2))
    }
    
    // MARK: - Typography - Minimalist
    struct Typography {
        // Headers - Smaller, lighter
        static let largeTitle = Font.system(size: 24, weight: .light, design: .default)
        static let title1 = Font.system(size: 20, weight: .light, design: .default)
        static let title2 = Font.system(size: 18, weight: .light, design: .default)
        static let title3 = Font.system(size: 16, weight: .regular, design: .default)
        
        // Body Text - Minimalist
        static let headline = Font.system(size: 14, weight: .medium, design: .default)
        static let body = Font.system(size: 15, weight: .regular, design: .default)
        static let callout = Font.system(size: 12, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 11, weight: .regular, design: .default)
        static let footnote = Font.system(size: 10, weight: .regular, design: .default)
        static let caption = Font.system(size: 9, weight: .regular, design: .default)
        
        // Special - Minimalist
        static let button = Font.system(size: 12, weight: .medium, design: .default)
        static let tabBar = Font.system(size: 8, weight: .regular, design: .default)
    }
    
    // MARK: - Spacing - Minimalist
    struct Spacing {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 24
    }
    
    // MARK: - Corner Radius - Minimalist
    struct CornerRadius {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
        static let xl: CGFloat = 10
        static let xxl: CGFloat = 12
    }
    
    // MARK: - Shadows - Minimalist (Dark Mode Adaptive)
    struct Shadows {
        static let small = Color(light: Color.black.opacity(0.05), 
                                dark: Color.black.opacity(0.3))
        static let medium = Color(light: Color.black.opacity(0.08), 
                                 dark: Color.black.opacity(0.4))
        static let large = Color(light: Color.black.opacity(0.12), 
                                dark: Color.black.opacity(0.5))
    }
}

// MARK: - Minimalist Button Styles
struct MinimalistButtonStyle: ButtonStyle {
    let variant: ButtonVariant
    let size: ButtonSize
    
    enum ButtonVariant {
        case primary
        case secondary
        case tertiary
        case destructive
        case ghost
    }
    
    enum ButtonSize {
        case small
        case medium
        case large
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(buttonFont)
            .foregroundColor(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundColor)
            .cornerRadius(DesignSystem.CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
    
    private var buttonFont: Font {
        switch size {
        case .small: return DesignSystem.Typography.caption
        case .medium: return DesignSystem.Typography.button
        case .large: return DesignSystem.Typography.callout
        }
    }
    
    private var horizontalPadding: CGFloat {
        switch size {
        case .small: return DesignSystem.Spacing.sm
        case .medium: return DesignSystem.Spacing.md
        case .large: return DesignSystem.Spacing.lg
        }
    }
    
    private var verticalPadding: CGFloat {
        switch size {
        case .small: return DesignSystem.Spacing.xs
        case .medium: return DesignSystem.Spacing.sm
        case .large: return DesignSystem.Spacing.md
        }
    }
    
    private var foregroundColor: Color {
        switch variant {
        case .primary: return DesignSystem.Colors.textInverse
        case .secondary: return DesignSystem.Colors.accent
        case .tertiary: return DesignSystem.Colors.textPrimary
        case .destructive: return DesignSystem.Colors.textInverse
        case .ghost: return DesignSystem.Colors.accent
        }
    }
    
    private var backgroundColor: Color {
        switch variant {
        case .primary: return DesignSystem.Colors.accent
        case .secondary: return DesignSystem.Colors.surface
        case .tertiary: return DesignSystem.Colors.backgroundSecondary
        case .destructive: return DesignSystem.Colors.error
        case .ghost: return Color.clear
        }
    }
    
    private var borderColor: Color {
        switch variant {
        case .primary: return Color.clear
        case .secondary: return DesignSystem.Colors.border
        case .tertiary: return Color.clear
        case .destructive: return Color.clear
        case .ghost: return DesignSystem.Colors.border
        }
    }
    
    private var borderWidth: CGFloat {
        switch variant {
        case .primary: return 0
        case .secondary: return 0.5
        case .tertiary: return 0
        case .destructive: return 0
        case .ghost: return 0.5
        }
    }
}

// MARK: - Minimalist Card Style
struct MinimalistCardStyle: ViewModifier {
    let variant: CardVariant
    
    enum CardVariant {
        case elevated
        case outlined
        case filled
    }
    
    func body(content: Content) -> some View {
        content
            .background(backgroundColor)
            .cornerRadius(DesignSystem.CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: 0,
                y: shadowOffset
            )
    }
    
    private var backgroundColor: Color {
        switch variant {
        case .elevated: return DesignSystem.Colors.surface
        case .outlined: return DesignSystem.Colors.surface
        case .filled: return DesignSystem.Colors.backgroundSecondary
        }
    }
    
    private var borderColor: Color {
        switch variant {
        case .elevated: return Color.clear
        case .outlined: return DesignSystem.Colors.border
        case .filled: return Color.clear
        }
    }
    
    private var borderWidth: CGFloat {
        switch variant {
        case .elevated: return 0
        case .outlined: return 0.5
        case .filled: return 0
        }
    }
    
    private var shadowColor: Color {
        switch variant {
        case .elevated: return DesignSystem.Shadows.medium
        case .outlined: return Color.clear
        case .filled: return Color.clear
        }
    }
    
    private var shadowRadius: CGFloat {
        switch variant {
        case .elevated: return 4
        case .outlined: return 0
        case .filled: return 0
        }
    }
    
    private var shadowOffset: CGFloat {
        switch variant {
        case .elevated: return 2
        case .outlined: return 0
        case .filled: return 0
        }
    }
}

// MARK: - Minimalist Input Field Style
struct MinimalistInputFieldStyle: TextFieldStyle {
    let state: InputState
    
    enum InputState {
        case normal
        case focused
        case error
        case disabled
    }
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(backgroundColor)
            .cornerRadius(DesignSystem.CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
    }
    
    private var backgroundColor: Color {
        switch state {
        case .normal: return DesignSystem.Colors.surface
        case .focused: return DesignSystem.Colors.surface
        case .error: return DesignSystem.Colors.surface
        case .disabled: return DesignSystem.Colors.backgroundSecondary
        }
    }
    
    private var borderColor: Color {
        switch state {
        case .normal: return DesignSystem.Colors.border
        case .focused: return DesignSystem.Colors.accent
        case .error: return DesignSystem.Colors.error
        case .disabled: return DesignSystem.Colors.border
        }
    }
    
    private var borderWidth: CGFloat {
        switch state {
        case .normal: return 0.5
        case .focused: return 1
        case .error: return 1
        case .disabled: return 0.5
        }
    }
}

// MARK: - View Extensions
extension View {
    func minimalistCard(_ variant: MinimalistCardStyle.CardVariant = .outlined) -> some View {
        modifier(MinimalistCardStyle(variant: variant))
    }
    
    func minimalistButton(
        variant: MinimalistButtonStyle.ButtonVariant = .primary,
        size: MinimalistButtonStyle.ButtonSize = .medium
    ) -> some View {
        buttonStyle(MinimalistButtonStyle(variant: variant, size: size))
    }
}

// MARK: - Refresh Control
struct RefreshControl: View {
    @Binding var isRefreshing: Bool
    let onRefresh: () -> Void
    
    var body: some View {
        if isRefreshing {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Refreshing...")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding()
        }
    }
}

// MARK: - Cross-platform navigation (iOS-only modifiers no-op on macOS)
extension View {
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    @ViewBuilder
    func navigationBarHiddenIfPossible(_ hidden: Bool) -> some View {
        #if os(iOS)
        self.navigationBarHidden(hidden)
        #else
        self
        #endif
    }
    @ViewBuilder
    func fullScreenCoverIfAvailable<Content: View>(isPresented: Binding<Bool>, content: @escaping () -> Content) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }
}

// MARK: - Haptic Feedback
func lightHaptic() {
    #if canImport(UIKit)
    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    impactFeedback.impactOccurred()
    #elseif canImport(AppKit)
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    #endif
}

func mediumHaptic() {
    #if canImport(UIKit)
    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    impactFeedback.impactOccurred()
    #elseif canImport(AppKit)
    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    #endif
}

func heavyHaptic() {
    #if canImport(UIKit)
    let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
    impactFeedback.impactOccurred()
    #elseif canImport(AppKit)
    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    #endif
}