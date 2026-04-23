//
//  ContentView.swift
//  InkSlate
//
//  Created by Lucas Waldron on 9/29/25.
//

import SwiftUI

// MARK: - Main Content View
struct ContentView: View {
    @State private var selectedView: MenuViewType = .items
    @AppStorage("lastSelectedMenuView") private var lastSelectedMenuViewRawValue = MenuViewType.items.rawValue
    @EnvironmentObject var sharedStateManager: SharedStateManager
    @State private var hasAppliedInitialMainSection = false

    var body: some View {
        ZStack {
            // Main app content
            NavigationStack {
                MainContentView(selectedView: selectedView)
            }
            .opacity(sharedStateManager.showSplashScreen ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: sharedStateManager.showSplashScreen)
            
            // Splash screen
            if sharedStateManager.showSplashScreen {
                SplashScreenView {
                    sharedStateManager.hideSplashScreen()
                }
                .transition(.opacity)
            }
            
            // Floating launcher (always available)
            FloatingRadialLauncher(
                isMenuOpen: $sharedStateManager.isMenuOpen,
                selectedView: $selectedView
            )
        }
        .onAppear {
            // Cold start: restore the last feature only if the previous run had entered
            // the background (user left the app normally). If the app was force-terminated
            // before iOS delivered a background event, the flag is false and we start at home.
            guard !hasAppliedInitialMainSection else { return }
            hasAppliedInitialMainSection = true
            if AppLaunchPreferences.takeShouldRestoreLastMenuAfterColdStart(),
               let restored = MenuViewType(rawValue: lastSelectedMenuViewRawValue) {
                selectedView = restored
            } else {
                selectedView = .items
                lastSelectedMenuViewRawValue = MenuViewType.items.rawValue
            }
        }
        .onChange(of: selectedView) { _, newValue in
            lastSelectedMenuViewRawValue = newValue.rawValue
        }
        .withErrorHandling()
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

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        .environmentObject(SharedStateManager.shared)
}
