import SwiftUI
import CoreData

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

    #if os(iOS)
    @State private var drawerDragOffset: CGFloat = 0
    @State private var isDraggingDrawer: Bool = false
    #endif

    #if os(macOS)
    @Binding var columnVisibility: NavigationSplitViewVisibility
  #endif

    #if os(macOS)
    init(columnVisibility: Binding<NavigationSplitViewVisibility> = .constant(.automatic)) {
        _columnVisibility = columnVisibility
    }
    #endif

    var body: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    #if os(macOS)
    private var macBody: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacSidebarView(
                selectedView: $selectedView,
                onSelectMenu: selectMenu
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            macDetailContent
        }
        .overlay {
            if sharedStateManager.showSplashScreen {
                SplashScreenView {
                    sharedStateManager.hideSplashScreen()
                    presentOnboardingIfNeeded()
                }
                .transition(.opacity)
            }
        }
        .modifier(SharedContentModifiers(
            sharedStateManager: sharedStateManager,
            subscription: subscription,
            hasCompletedOnboarding: $hasCompletedOnboarding,
            isShowingOnboarding: $isShowingOnboarding,
            isShowingPaywall: $isShowingPaywall,
            paywallHighlight: $paywallHighlight,
            viewContext: viewContext,
            onAppearSetup: onAppearSetup,
            onPendingMenuChange: { menu in
                applyMenuSelection(menu)
                sharedStateManager.pendingMenuSelection = nil
            },
            onProChange: { isPro in
                if isPro { isShowingPaywall = false }
            },
            confirmRemoteReset: confirmRemoteReset,
            dismissRemoteReset: dismissRemoteReset
        ))
    }

    private var macDetailContent: some View {
        // Keep the outer stack stable; remount only the feature so menu swaps stay fast
        // and features with their own stacks (Mind Maps, Places, Notes, …) drop pushed detail.
        NavigationStack {
            VStack(spacing: 0) {
                SyncBackupWarningBanner(persistence: persistence)
                MainContentView(
                    selectedView: selectedView,
                    onRequestUpgrade: { presentPaywall(for: $0) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(selectedView)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(sharedStateManager.showSplashScreen ? 0 : 1)
        .animation(.easeInOut(duration: 0.3), value: sharedStateManager.showSplashScreen)
    }
    #endif

    #if os(iOS)
    private var iosBody: some View {
        GeometryReader { proxy in
            let drawerWidth = min(320, proxy.size.width * 0.82)
            let safeBottom = proxy.safeAreaInsets.bottom

            ZStack(alignment: .leading) {
                // Keep the outer stack stable; remount only the feature so menu swaps stay fast
                // and features with their own stacks drop any pushed detail.
                NavigationStack {
                    VStack(spacing: 0) {
                        SyncBackupWarningBanner(persistence: persistence)
                        MainContentView(
                            selectedView: selectedView,
                            onRequestUpgrade: { presentPaywall(for: $0) }
                        )
                        .id(selectedView)
                    }
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

                if sharedStateManager.navigationMenuStyle == .radial {
                    FloatingRadialLauncher(
                        isMenuOpen: $sharedStateManager.isMenuOpen,
                        selectedView: $selectedView,
                        onSelectMenu: { selectMenu($0) }
                    )
                } else {
                    drawerNavigationOverlay(drawerWidth: drawerWidth)
                }
            }
        }
        .modifier(SharedContentModifiers(
            sharedStateManager: sharedStateManager,
            subscription: subscription,
            hasCompletedOnboarding: $hasCompletedOnboarding,
            isShowingOnboarding: $isShowingOnboarding,
            isShowingPaywall: $isShowingPaywall,
            paywallHighlight: $paywallHighlight,
            viewContext: viewContext,
            onAppearSetup: onAppearSetup,
            onPendingMenuChange: { menu in
                applyMenuSelection(menu)
                sharedStateManager.pendingMenuSelection = nil
            },
            onProChange: { isPro in
                if isPro { isShowingPaywall = false }
            },
            confirmRemoteReset: confirmRemoteReset,
            dismissRemoteReset: dismissRemoteReset
        ))
    }

    @ViewBuilder
    private func drawerNavigationOverlay(drawerWidth: CGFloat) -> some View {
        // Backdrop dimming
        if sharedStateManager.isMenuOpen || isDraggingDrawer {
            let opacity: Double = {
                if sharedStateManager.isMenuOpen {
                    let dragFraction = max(0, min(1, 1.0 + (drawerDragOffset / drawerWidth)))
                    return 0.38 * dragFraction
                } else {
                    let dragFraction = max(0, min(1, drawerDragOffset / drawerWidth))
                    return 0.38 * dragFraction
                }
            }()

            Color.black.opacity(opacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        sharedStateManager.isMenuOpen = false
                        drawerDragOffset = 0
                        isDraggingDrawer = false
                    }
                }
                .transition(.opacity)
        }

        // Side Drawer Panel
        let currentOffset: CGFloat = {
            if sharedStateManager.isMenuOpen {
                return min(0, drawerDragOffset)
            } else {
                return -drawerWidth + max(0, drawerDragOffset)
            }
        }()

        SideDrawerMenuView(
            isDrawerOpen: $sharedStateManager.isMenuOpen,
            selectedView: $selectedView,
            onSelectMenu: { selectMenu($0) },
            onUpgradePro: { presentPaywall(for: $0) }
        )
        .frame(width: drawerWidth)
        .offset(x: currentOffset)
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    if sharedStateManager.isMenuOpen {
                        if value.translation.width < 0 {
                            isDraggingDrawer = true
                            drawerDragOffset = value.translation.width
                        }
                    }
                }
                .onEnded { value in
                    isDraggingDrawer = false
                    if sharedStateManager.isMenuOpen {
                        if value.translation.width < -45 || value.predictedEndTranslation.width < -90 {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                sharedStateManager.isMenuOpen = false
                                drawerDragOffset = 0
                            }
                        } else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                drawerDragOffset = 0
                            }
                        }
                    }
                }
        )
        .ignoresSafeArea(edges: .vertical)

        // Edge swipe detector when drawer is closed (open purely by sliding from left)
        if !sharedStateManager.isMenuOpen && !sharedStateManager.showSplashScreen {
            Color.clear
                .frame(width: 44)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 8, coordinateSpace: .local)
                        .onChanged { value in
                            if value.startLocation.x <= 48 && value.translation.width > 0 {
                                isDraggingDrawer = true
                                drawerDragOffset = min(drawerWidth, value.translation.width)
                            }
                        }
                        .onEnded { value in
                            isDraggingDrawer = false
                            if value.translation.width > 40 || value.predictedEndTranslation.width > 80 {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                    sharedStateManager.isMenuOpen = true
                                    drawerDragOffset = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                    sharedStateManager.isMenuOpen = false
                                    drawerDragOffset = 0
                                }
                            }
                        }
                )
                .ignoresSafeArea(edges: .vertical)
        }
    }
    #endif

    private func onAppearSetup() {
        if !hasAppliedInitialMainSection {
            hasAppliedInitialMainSection = true
            selectedView = .items
        }
        if let menu = sharedStateManager.pendingMenuSelection {
            applyMenuSelection(menu)
            sharedStateManager.pendingMenuSelection = nil
        }
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

#if os(macOS)
private struct MacSidebarView: View {
    @Binding var selectedView: MenuViewType
    var onSelectMenu: (MenuViewType) -> Void
    @EnvironmentObject private var subscription: SubscriptionService
    @EnvironmentObject private var themeService: ThemeService
    @State private var menuItems: [MenuViewType] = []
    @State private var hiddenItems: Set<MenuViewType> = []

    private let userDefaults = UserDefaults.standard
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let menuOrderKey = "MenuOrder"
    private let hiddenMenuItemsKey = "HiddenMenuItems"

    private var mainSidebarItems: [MenuViewType] {
        MenuViewType.sidebarItems(
            from: menuItems,
            hidden: hiddenItems,
            pinHomeToTop: true,
            pinBottomItems: [.profile, .settings],
            includePinnedBottom: false
        )
    }

    private var footerSidebarItems: [MenuViewType] {
        [.profile, .settings].filter { !hiddenItems.contains($0) }
    }

    var body: some View {
        List(selection: $selectedView) {
            Section("InkSlate") {
                ForEach(mainSidebarItems, id: \.self) { menu in
                    sidebarRow(for: menu)
                }
            }
            if !footerSidebarItems.isEmpty {
                Section {
                    ForEach(footerSidebarItems, id: \.self) { menu in
                        sidebarRow(for: menu)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("InkSlate")
        .tint(themeService.accentColor)
        .onAppear {
            loadMenuConfiguration()
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
                .filter { ($0.object as? NSUbiquitousKeyValueStore) === cloudStore }
                .receive(on: DispatchQueue.main)
        ) { _ in
            loadMenuConfiguration()
        }
        .onChange(of: selectedView) { _, newValue in
            onSelectMenu(newValue)
        }
    }

    @ViewBuilder
    private func sidebarRow(for menu: MenuViewType) -> some View {
        Label {
            HStack {
                Text(menu.menuTitle)
                Spacer()
                if menu.requiresPro && !subscription.isPro {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: menu.icon)
        }
        .tag(menu)
    }

    private func loadMenuConfiguration() {
        let menuOrder: [String]?
        if let cloudOrder = cloudStore.array(forKey: menuOrderKey) as? [String], !cloudOrder.isEmpty {
            menuOrder = cloudOrder
        } else if let localOrder = userDefaults.array(forKey: menuOrderKey) as? [String], !localOrder.isEmpty {
            menuOrder = localOrder
            cloudStore.set(localOrder, forKey: menuOrderKey)
            cloudStore.synchronize()
        } else {
            menuOrder = nil
        }

        if let savedOrder = menuOrder {
            let orderedItems = savedOrder.compactMap { MenuViewType(rawValue: $0) }
            menuItems = orderedItems.isEmpty ? MenuViewType.allCases : orderedItems
        } else {
            menuItems = MenuViewType.allCases
        }

        let hiddenItemsData: [String]?
        if let cloudHidden = cloudStore.array(forKey: hiddenMenuItemsKey) as? [String], !cloudHidden.isEmpty {
            hiddenItemsData = cloudHidden
        } else if let localHidden = userDefaults.array(forKey: hiddenMenuItemsKey) as? [String], !localHidden.isEmpty {
            hiddenItemsData = localHidden
            cloudStore.set(localHidden, forKey: hiddenMenuItemsKey)
            cloudStore.synchronize()
        } else {
            hiddenItemsData = nil
        }

        if let hiddenData = hiddenItemsData {
            hiddenItems = Set(hiddenData.compactMap { MenuViewType(rawValue: $0) })
        } else {
            hiddenItems = []
        }
    }
}
#endif

private struct SharedContentModifiers: ViewModifier {
    @ObservedObject var sharedStateManager: SharedStateManager
    @ObservedObject var subscription: SubscriptionService
    @Binding var hasCompletedOnboarding: Bool
    @Binding var isShowingOnboarding: Bool
    @Binding var isShowingPaywall: Bool
    @Binding var paywallHighlight: MenuViewType?
    var viewContext: NSManagedObjectContext
    var onAppearSetup: () -> Void
    var onPendingMenuChange: (MenuViewType) -> Void
    var onProChange: (Bool) -> Void
    var confirmRemoteReset: () -> Void
    var dismissRemoteReset: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear(perform: onAppearSetup)
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
                onPendingMenuChange(menu)
            }
            .onChange(of: subscription.isPro) { _, isPro in
                onProChange(isPro)
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
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: .inkSlateOpenSettings)) { _ in
                paywallHighlight = nil
            }
            #endif
    }
}

// MARK: - Main Content Container
struct MainContentView: View {
    let selectedView: MenuViewType
    var onRequestUpgrade: (MenuViewType) -> Void = { _ in }

    @EnvironmentObject private var subscription: SubscriptionService

    var body: some View {
        Group {
            if selectedView.requiresPro && !subscription.isPro {
                ProLockedFeatureView(feature: selectedView) {
                    onRequestUpgrade(selectedView)
                }
            } else {
                moduleContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: subscription.isPro)
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
