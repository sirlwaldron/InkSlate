import SwiftUI
import Combine
import CoreData

// MARK: - Shared State Manager
@MainActor
class SharedStateManager: ObservableObject {
    static let shared = SharedStateManager()
    
    
    let loadingManager = LoadingStateManager()
    let autoSaveManager = AutoSaveManager()
    
    
    @Published var showSplashScreen: Bool
    @Published var isMenuOpen = false

    private let menuStyleKey = "NavigationMenuStyle"
    @Published var navigationMenuStyle: NavigationMenuStyle {
        didSet {
            UserDefaults.standard.set(navigationMenuStyle.rawValue, forKey: menuStyleKey)
            NSUbiquitousKeyValueStore.default.set(navigationMenuStyle.rawValue, forKey: menuStyleKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    @Published var pendingMenuSelection: MenuViewType?

    /// Note imported from the share extension that should be opened in the editor.
    @Published var pendingOpenNoteID: NSManagedObjectID?

    @Published var pendingRemoteResetToken: String?

    private init() {
        self.showSplashScreen = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        let savedStyle = NSUbiquitousKeyValueStore.default.string(forKey: menuStyleKey)
            ?? UserDefaults.standard.string(forKey: menuStyleKey)
        if let raw = savedStyle, let style = NavigationMenuStyle(rawValue: raw) {
            self.navigationMenuStyle = style
        } else {
            self.navigationMenuStyle = .radial
        }

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if let cloudStyle = NSUbiquitousKeyValueStore.default.string(forKey: self.menuStyleKey),
                   let style = NavigationMenuStyle(rawValue: cloudStyle),
                   self.navigationMenuStyle != style {
                    self.navigationMenuStyle = style
                }
            }
        }
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
        navigationMenuStyle = .radial
        pendingMenuSelection = nil
        pendingOpenNoteID = nil
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

