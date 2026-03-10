//
//  NavigationComponents.swift
//  InkSlate
//
//  Created by Lucas Waldron on 9/29/25.
//

import SwiftUI
import Foundation

// MARK: - Navigation Types
enum MenuViewType: String, CaseIterable {
    case items = "Home"
    case notes = "Notes"
    case mindMaps = "Mind Maps"
    case journal = "Journal"
    case todo = "To-Do"
    case budget = "Budget"
    case recipes = "Recipes"
    case places = "Places"
    case quotes = "Quotes"
    case calendar = "Calendar"
    case wantToWatch = "Want to Watch"
    case settings = "Settings"
    case profile = "Profile"
    
    var icon: String {
        switch self {
        case .items: return "house.fill"
        case .notes: return "note.text"
        case .mindMaps: return "brain.head.profile"
        case .journal: return "book.closed"
            case .todo: return "checklist"
            case .budget: return "chart.pie.fill"
            case .recipes: return "fork.knife"
            case .places: return "mappin.and.ellipse"
            case .quotes: return "quote.bubble"
            case .calendar: return "calendar"
        case .wantToWatch: return "tv"
        case .settings: return "gear"
        case .profile: return "person.fill"
        }
    }
}

// MARK: - Hamburger Menu Components
struct HamburgerMenuButton: View {
    @Binding var isMenuOpen: Bool
    @Binding var isHovering: Bool
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                isMenuOpen.toggle()
            }
        }) {
            VStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 18, height: 2)
                        .cornerRadius(1)
                        .scaleEffect(isMenuOpen ? (index == 0 ? 0.8 : index == 1 ? 1.2 : 0.8) : 1.0)
                        .rotationEffect(.degrees(isMenuOpen ? (index == 0 ? 45 : index == 1 ? 0 : -45) : 0))
                        .offset(x: isMenuOpen ? (index == 0 ? 6 : index == 1 ? 0 : -6) : 0)
                }
            }
            .frame(width: 20, height: 18)
            .frame(width: 44, height: 44)  // Minimum tap target size
            .contentShape(Rectangle())  // Make entire frame tappable
        }
        .scaleEffect(isHovering ? 1.1 : 1.0)
        .opacity(isHovering ? 0.7 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Menu Item Component
struct MenuItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 20)
                .foregroundColor(isSelected ? .white : DesignSystem.Colors.textPrimary)
                .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isSelected ? .white : DesignSystem.Colors.textPrimary)
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : (isHovering ? Color.accentColor.opacity(0.1) : Color.clear))
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            action()
        }
    }
}

// MARK: - Side Menu Component
struct SideMenu: View {
    @Binding var isMenuOpen: Bool
    @Binding var selectedView: MenuViewType
    @State private var visibleMenuItems: [MenuViewType] = []
    @State private var hiddenItems: Set<MenuViewType> = []
    
    var body: some View {
        HStack {
            if isMenuOpen {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Navigation")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.top, 20)
                    
                    // Home at top
                    VStack(alignment: .leading, spacing: 15) {
                        // Home
                        if !hiddenItems.contains(.items) {
                            MenuItem(
                                title: MenuViewType.items.rawValue,
                                icon: MenuViewType.items.icon,
                                isSelected: selectedView == .items
                            ) {
                                selectedView = .items
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isMenuOpen = false
                                }
                            }
                        }
                    }
                    
                    // Separator
                    Divider()
                        .padding(.vertical, 10)
                    
                    // Main menu items (excluding Home and Settings)
                    VStack(alignment: .leading, spacing: 15) {
                        ForEach(visibleMenuItems.filter { $0 != .items && $0 != .settings }, id: \.self) { viewType in
                            MenuItem(
                                title: viewType.rawValue,
                                icon: viewType.icon,
                                isSelected: selectedView == viewType
                            ) {
                                selectedView = viewType
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isMenuOpen = false
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Separator
                    Divider()
                        .padding(.vertical, 10)
                    
                    // Settings at bottom
                    VStack(alignment: .leading, spacing: 15) {
                        // Settings
                        if !hiddenItems.contains(.settings) {
                            MenuItem(
                                title: MenuViewType.settings.rawValue,
                                icon: MenuViewType.settings.icon,
                                isSelected: selectedView == .settings
                            ) {
                                selectedView = .settings
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isMenuOpen = false
                                }
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .frame(width: 250)
                .background(DesignSystem.Colors.surface)
                .shadow(radius: 10)
                .transition(.move(edge: .leading))
                .onAppear {
                    loadMenuConfiguration()
                }
            }
            Spacer()
        }
    }
    
    private func loadMenuConfiguration() {
        // Load saved menu order
        if let savedOrder = UserDefaults.standard.array(forKey: "MenuOrder") as? [String] {
            let orderedItems = savedOrder.compactMap { MenuViewType(rawValue: $0) }
            if !orderedItems.isEmpty {
                visibleMenuItems = orderedItems.filter { !hiddenItems.contains($0) }
            } else {
                visibleMenuItems = MenuViewType.allCases.filter { !hiddenItems.contains($0) }
            }
        } else {
            visibleMenuItems = MenuViewType.allCases.filter { !hiddenItems.contains($0) }
        }
        
        // Load hidden items
        if let hiddenItemsData = UserDefaults.standard.array(forKey: "HiddenMenuItems") as? [String] {
            hiddenItems = Set(hiddenItemsData.compactMap { MenuViewType(rawValue: $0) })
            visibleMenuItems = visibleMenuItems.filter { !hiddenItems.contains($0) }
        }
        
    }
}
