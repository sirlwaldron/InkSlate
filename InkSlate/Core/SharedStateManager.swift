//
//  SharedStateManager.swift
//  InkSlate
//
//  Created by Performance Optimization on 9/30/25.
//

import SwiftUI
import Combine

// MARK: - Shared State Manager
class SharedStateManager: ObservableObject {
    static let shared = SharedStateManager()
    
    
    // These don't need to trigger view updates at the SharedStateManager level
    let loadingManager = LoadingStateManager()
    let autoSaveManager = AutoSaveManager()
    
    
    @Published var showSplashScreen = true
    @Published var isMenuOpen = false
    
    
    private init() {
        // No authentication or onboarding needed - app starts directly
    }
    
    func hideSplashScreen() {
        showSplashScreen = false
    }
    
    func toggleMenu() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isMenuOpen.toggle()
        }
    }
    
    func resetToDefaults() {
        // Reset splash screen
        showSplashScreen = true
        
        // Reset loading state
        loadingManager.stopLoading()
        
        // Reset auto save state
        autoSaveManager.lastSaveStatus = "Ready"
        autoSaveManager.isSaving = false
    }
    
    
    deinit {
        
    }
    
}

// MARK: - Environment Key for Shared State
private struct SharedStateManagerKey: EnvironmentKey {
    static let defaultValue = SharedStateManager.shared
}

extension EnvironmentValues {
    var sharedStateManager: SharedStateManager {
        get { self[SharedStateManagerKey.self] }
        set { self[SharedStateManagerKey.self] = newValue }
    }
}

