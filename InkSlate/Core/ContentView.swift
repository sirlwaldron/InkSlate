import SwiftUI

// MARK: - Main Content View
struct ContentView: View {
    @State private var selectedView: MenuViewType = .items
    @EnvironmentObject var sharedStateManager: SharedStateManager
    @EnvironmentObject var subscription: SubscriptionService
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var persistence = PersistenceController.shared
    @State private var hasAppliedInitialMainSection = false

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var isShowingOnboarding = false
    @State private var isShowingPaywall = false
    @State private var paywallHighlight: MenuViewType?

    var body: some View {
        ZStack {
            NavigationStack {
                VStack(spacing: 0) {
                    SyncBackupWarningBanner(persistence: persistence)
                    MainContentView(
                        selectedView: selectedView,
                        onRequestUpgrade: { feature in
                            presentPaywall(for: feature)
                        }
                    )
                }
                .id(selectedView)
            }
            .opacity(sharedStateManager.showSplashScreen ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: sharedStateManager.showSplashScreen)
            
            if sharedStateManager.showSplashScreen {
                SplashScreenView {
                    sharedStateManager.hideSplashScreen()
                    presentOnboardingIfNeeded()
                }
                .transition(.opacity)
            }
            
            FloatingRadialLauncher(
                isMenuOpen: $sharedStateManager.isMenuOpen,
                selectedView: $selectedView,
                onSelectMenu: { menu in
                    selectMenu(menu)
                }
            )
        }
        .onAppear {
            if !hasAppliedInitialMainSection {
                hasAppliedInitialMainSection = true
                selectedView = .items
            }
            if let menu = sharedStateManager.pendingMenuSelection {
                applyMenuSelection(menu)
                sharedStateManager.pendingMenuSelection = nil
            }
        }
        .fullScreenCoverIfAvailable(isPresented: $isShowingOnboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
                isShowingOnboarding = false
            }
            .interactiveDismissDisabled(true)
        }
        .fullScreenCoverIfAvailable(isPresented: $isShowingPaywall) {
            PaywallView(highlightFeature: paywallHighlight)
                .environmentObject(subscription)
                .environmentObject(ThemeService.shared)
        }
        .onChange(of: sharedStateManager.pendingMenuSelection) { _, newValue in
            guard let menu = newValue else { return }
            applyMenuSelection(menu)
            sharedStateManager.pendingMenuSelection = nil
        }
        .onChange(of: subscription.isPro) { _, isPro in
            if isPro {
                isShowingPaywall = false
            }
        }
        .alert("Erase this device?", isPresented: Binding(
            get: { sharedStateManager.pendingRemoteResetToken != nil },
            set: { if !$0 { sharedStateManager.pendingRemoteResetToken = nil } }
        )) {
            Button("Erase This Device", role: .destructive) { confirmRemoteReset() }
            Button("Not Now", role: .cancel) { dismissRemoteReset() }
        } message: {
            Text("InkSlate was factory reset on another one of your devices. Do you also want to permanently erase all InkSlate data on this device? This cannot be undone.")
        }
        .withErrorHandling()
    }

    private func selectMenu(_ menu: MenuViewType) {
        if subscription.canAccess(menu) {
            selectedView = menu
        } else {
            presentPaywall(for: menu)
        }
    }

    private func applyMenuSelection(_ menu: MenuViewType) {
        if subscription.canAccess(menu) {
            selectedView = menu
        } else {
            presentPaywall(for: menu)
        }
    }

    private func presentPaywall(for feature: MenuViewType) {
        paywallHighlight = feature
        isShowingPaywall = true
    }

    private func confirmRemoteReset() {
        guard let token = sharedStateManager.pendingRemoteResetToken else { return }
        do {
            try FactoryResetService.shared.confirmRemoteReset(
                token: token,
                viewContext: viewContext,
                shared: sharedStateManager
            )
        } catch {
            ErrorHandlingService.shared.handleError(error, context: "Factory reset on this device")
        }
        sharedStateManager.pendingRemoteResetToken = nil
    }

    private func dismissRemoteReset() {
        if let token = sharedStateManager.pendingRemoteResetToken {
            FactoryResetService.shared.dismissRemoteReset(token: token)
        }
        sharedStateManager.pendingRemoteResetToken = nil
    }

    private func presentOnboardingIfNeeded() {
        guard !hasCompletedOnboarding else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isShowingOnboarding = true
        }
    }
}

// MARK: - Main Content Container
struct MainContentView: View {
    let selectedView: MenuViewType
    var onRequestUpgrade: (MenuViewType) -> Void = { _ in }

    @EnvironmentObject private var subscription: SubscriptionService

    var body: some View {
        if selectedView.requiresPro && !subscription.isPro {
            ProLockedFeatureView(feature: selectedView) {
                onRequestUpgrade(selectedView)
            }
        } else {
            moduleContent
        }
    }

    @ViewBuilder
    private var moduleContent: some View {
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
        .environmentObject(ThemeService.shared)
        .environmentObject(SubscriptionService.shared)
}
