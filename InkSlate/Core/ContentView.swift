//
//  ContentView.swift
//  InkSlate
//
//  Created by Lucas Waldron on 9/29/25.
//

import SwiftUI

// MARK: - Main Content View
struct ContentView: View {
    @State private var isHovering = false
    @State private var selectedView: MenuViewType = .items
    @EnvironmentObject var sharedStateManager: SharedStateManager

    var body: some View {
        ZStack {
            // Main app content
            NavigationStack {
                MainContentView(selectedView: selectedView)
                    .toolbar(content: {
                        ToolbarItem(placement: .navigationBarLeading) {
                            HamburgerMenuButton(
                                isMenuOpen: $sharedStateManager.isMenuOpen,
                                isHovering: $isHovering
                            )
                        }
                        
                    })
            }
            .overlay(
                MenuOverlay(isMenuOpen: $sharedStateManager.isMenuOpen)
            )
            .overlay(
                SideMenu(
                    isMenuOpen: $sharedStateManager.isMenuOpen,
                    selectedView: $selectedView
                )
            )
            .opacity(sharedStateManager.showSplashScreen ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: sharedStateManager.showSplashScreen)
            
            // Splash screen
            if sharedStateManager.showSplashScreen {
                SplashScreenView {
                    sharedStateManager.hideSplashScreen()
                }
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Main Content Container
struct MainContentView: View {
    let selectedView: MenuViewType
    
    var body: some View {
        switch selectedView {
            case .items:
                ItemsListView()
            case .notes:
                NotesListView()
            case .mindMaps:
                MindMapListView()
            case .journal:
                BookshelfView()
            case .todo:
                TodoMainView()
            case .budget:
                BudgetMainView()
            case .recipes:
            RecipeTabView()
            case .places:
                PlacesMainView()
            case .quotes:
                ModernQuotesMainView()
            case .calendar:
                CalendarMainView()
            case .wantToWatch:
                WantToWatchMainView()
            case .settings:
                SettingsView()
            case .profile:
                ProfileMainView()
        }
    }
}

// MARK: - Menu Overlay
struct MenuOverlay: View {
    @Binding var isMenuOpen: Bool
    
    var body: some View {
        Group {
            if isMenuOpen {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isMenuOpen = false
                        }
                    }
            }
        }
    }
}



#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        .environmentObject(SharedStateManager.shared)
}
