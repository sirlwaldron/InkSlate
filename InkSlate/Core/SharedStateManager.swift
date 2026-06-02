import SwiftUI
import Combine

// MARK: - Shared State Manager
@MainActor
class SharedStateManager: ObservableObject {
    static let shared = SharedStateManager()
    
    
    let loadingManager = LoadingStateManager()
    let autoSaveManager = AutoSaveManager()
    
    
    @Published var showSplashScreen = true
    @Published var isMenuOpen = false

    @Published var pendingMenuSelection: MenuViewType?

    @Published var pendingRemoteResetToken: String?

    private init() {
    }

    func requestOpenMenu(_ menu: MenuViewType) {
        pendingMenuSelection = menu
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
        showSplashScreen = true
        pendingMenuSelection = nil
        pendingRemoteResetToken = nil
        
        loadingManager.stopLoading()
        
        autoSaveManager.lastSaveStatus = "Ready"
        autoSaveManager.isSaving = false
    }
    
    
    deinit {
        
    }
    
}

// MARK: - Environment Key for Shared State
private struct SharedStateManagerKey: EnvironmentKey {
    @MainActor
    static var defaultValue: SharedStateManager { SharedStateManager.shared }
}

extension EnvironmentValues {
    var sharedStateManager: SharedStateManager {
        get { self[SharedStateManagerKey.self] }
        set { self[SharedStateManagerKey.self] = newValue }
    }
}

