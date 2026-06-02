import SwiftUI
import CoreData
import Security
import os

private let settingsLog = Logger(subsystem: "com.lucas.InkSlateNew", category: "Settings")

private enum InkSlateSupport {
    static let githubIssuesURL = URL(string: "https://github.com/sirlwaldron/InkSlate/issues")!
}

// MARK: - Settings Feature Views
struct SettingsView: View {
    @State private var showingMenuReorder = false
    @State private var showingProfileCustomization = false
    @State private var showingThemeSettings = false
    @State private var showingNotificationSettings = false
    @State private var showingCloudKitTroubleshooting = false
    @State private var showingPaywall = false
    @EnvironmentObject private var subscription: SubscriptionService
    @State private var showingFactoryResetWarning = false
    @State private var showingFactoryResetConfirmation = false
    @State private var factoryResetError: String?
    @State private var factoryResetSuccessMessage: String?
    @State private var isPerformingFactoryReset = false
    @EnvironmentObject var shared: SharedStateManager
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.openURL) private var openURL
    var body: some View {
        List {
            SettingsHeaderCard()
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            Section {
                if subscription.isPro {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(DesignSystem.Colors.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("InkSlate Pro")
                                .font(DesignSystem.Typography.headline)
                            Text(proStatusSubtitle)
                                .font(DesignSystem.Typography.footnote)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    SettingsRowButton(
                        title: "Upgrade to InkSlate Pro",
                        subtitle: "Mind Maps, Journal, Recipes, and more",
                        systemImage: "sparkles",
                        tint: DesignSystem.Colors.accent
                    ) {
                        showingPaywall = true
                    }
                }
            } header: {
                Text("InkSlate Pro")
            } footer: {
                if !subscription.isPro {
                    Text("Notes, Budget, and Calendar are free forever.")
                }
            }
            
            Section("Appearance") {
                SettingsRowButton(
                    title: "Profile",
                    systemImage: "person.crop.circle",
                    tint: DesignSystem.Colors.accent
                ) {
                    showingProfileCustomization = true
                }
                
                SettingsRowButton(
                    title: "Theme & Display",
                    systemImage: "paintbrush",
                    tint: DesignSystem.Colors.accent
                ) {
                    showingThemeSettings = true
                }
            }
            
            Section("Notifications") {
                SettingsRowButton(
                    title: "Reminders",
                    subtitle: "Journal, capture nudge, cook timers",
                    systemImage: "bell.badge",
                    tint: DesignSystem.Colors.accent
                ) {
                    showingNotificationSettings = true
                }
            }

            Section("Navigation") {
                SettingsRowButton(
                    title: "Menu Order",
                    subtitle: "Reorder or hide tabs · Pro modules marked",
                    systemImage: "list.bullet.rectangle",
                    tint: DesignSystem.Colors.accent
                ) {
                    showingMenuReorder = true
                }
            }
            
            Section("Sync") {
                SettingsRowButton(
                    title: "iCloud Sync",
                    subtitle: "Status, errors, and troubleshooting",
                    systemImage: "icloud",
                    tint: DesignSystem.Colors.accent
                ) {
                    showingCloudKitTroubleshooting = true
                }
            }
            
            Section("Support") {
                SettingsRowButton(
                    title: "Report a bug",
                    subtitle: "GitHub Issues",
                    systemImage: "ladybug",
                    tint: DesignSystem.Colors.accent
                ) {
                    openURL(InkSlateSupport.githubIssuesURL)
                }
            }
            
            Section {
                SettingsRowButton(
                    title: "Factory Reset",
                    subtitle: isPerformingFactoryReset
                        ? "Erasing data and CloudKit photos…"
                        : "Delete all data on this device (iCloud deletions may take time)",
                    systemImage: "trash",
                    tint: DesignSystem.Colors.error,
                    isDestructive: true
                ) {
                    showingFactoryResetWarning = true
                }
                .disabled(isPerformingFactoryReset)
            } header: {
                Text("Danger Zone")
            } footer: {
                VStack(spacing: 10) {
                    Text("In loving memory of my Father")
                        .font(.footnote)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    Text("🕊️")
                        .font(.footnote)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Settings")
        .inlineNavigationTitle()
        #if os(iOS)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        #endif
        .sheet(isPresented: $showingMenuReorder) {
            MenuReorderView()
                .environmentObject(subscription)
        }
        .sheet(isPresented: $showingProfileCustomization) {
            ProfileCustomizationView(profileService: ProfileService.shared)
        }
        .sheet(isPresented: $showingThemeSettings) {
            ThemeSettingsView()
                .environmentObject(ThemeService.shared)
                .presentationBackgroundInteraction(.enabled)
        }
        .sheet(isPresented: $showingNotificationSettings) {
            NavigationStack {
                NotificationSettingsView()
            }
        }
        .sheet(isPresented: $showingCloudKitTroubleshooting) {
            CloudKitTroubleshootingView()
        }
        .fullScreenCoverIfAvailable(isPresented: $showingPaywall) {
            PaywallView()
                .environmentObject(subscription)
                .environmentObject(ThemeService.shared)
        }
        .alert("⚠️ Factory Reset Warning", isPresented: $showingFactoryResetWarning) {
            Button("Continue", role: .destructive) {
                showingFactoryResetConfirmation = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete ALL your data including notes, journals, todos, recipes, and all other content. This action cannot be undone. Are you absolutely sure you want to continue?")
        }
        .alert("🔥 Final Confirmation", isPresented: $showingFactoryResetConfirmation) {
            Button("DELETE EVERYTHING", role: .destructive) {
                performFactoryReset()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This is your last chance to cancel. Clicking 'DELETE EVERYTHING' removes all InkSlate data from this device immediately. If iCloud is enabled, CloudKit will propagate those deletes to your account over time (not always instant while offline).")
        }
        .alert("Factory reset", isPresented: Binding(
            get: { factoryResetError != nil },
            set: { if !$0 { factoryResetError = nil } }
        )) {
            Button("OK", role: .cancel) { factoryResetError = nil }
        } message: {
            Text(factoryResetError ?? "")
        }
        .alert("Factory reset complete", isPresented: Binding(
            get: { factoryResetSuccessMessage != nil },
            set: { if !$0 { factoryResetSuccessMessage = nil } }
        )) {
            Button("OK", role: .cancel) { factoryResetSuccessMessage = nil }
        } message: {
            Text(factoryResetSuccessMessage ?? "")
        }
    }

    private var proStatusSubtitle: String {
        guard let id = subscription.activeProductID else {
            return "Active subscription"
        }
        switch id {
        case InkSlateProducts.lifetime: return "Lifetime access"
        case InkSlateProducts.yearly: return "Yearly plan"
        case InkSlateProducts.monthly: return "Monthly plan"
        default: return "Active subscription"
        }
    }
    
    private func performFactoryReset() {
        guard !isPerformingFactoryReset else { return }
        isPerformingFactoryReset = true
        factoryResetError = nil
        factoryResetSuccessMessage = nil

        Task { @MainActor in
            var cloudKitPhotoWarning: String?
            defer { isPerformingFactoryReset = false }

            _ = FactoryResetService.shared.requestRemoteReset()

            do {
                try FactoryResetService.shared.performLocalReset(
                    viewContext: viewContext,
                    shared: shared,
                    preserveResetToken: true
                )
            } catch {
                factoryResetError = error.localizedDescription
                settingsLog.error("Factory reset failed: \(error.localizedDescription)")
                return
            }

            do {
                try await CloudKitAssetService.shared.deleteAllCloudAssetsForFactoryReset()
            } catch {
                cloudKitPhotoWarning = error.localizedDescription
                settingsLog.error("Factory reset CloudKit photos: \(error.localizedDescription)")
            }

            if let cloudKitPhotoWarning {
                factoryResetSuccessMessage =
                    "All data on this device was erased. Some iCloud photos may still be deleting: \(cloudKitPhotoWarning). Open Settings → iCloud Sync if items reappear after you go online."
            } else {
                factoryResetSuccessMessage =
                    "All InkSlate data on this device was erased. If iCloud is enabled, deletions will propagate to your other devices when online."
            }
        }
    }
}

// MARK: - Settings UI Components

private struct SettingsRowButton: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    let tint: Color
    var isDestructive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SettingsIcon(systemImage: systemImage, tint: tint, isDestructive: isDestructive)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(isDestructive ? tint : DesignSystem.Colors.textPrimary)
                        .font(DesignSystem.Typography.body.weight(.medium))
                    
                    if let subtitle {
                        Text(subtitle)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .font(DesignSystem.Typography.subheadline)
                            .lineLimit(2)
                    }
                }
                
                Spacer(minLength: 8)
                
                Image(systemName: "chevron.right")
                    .font(DesignSystem.Typography.callout.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens \(title)"))
    }
}

private struct SettingsIcon: View {
    let systemImage: String
    let tint: Color
    let isDestructive: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(isDestructive ? 0.12 : 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5)
                )
                .frame(width: 32, height: 32)
            
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
        }
        .accessibilityHidden(true)
    }
}

private struct SettingsHeaderCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignSystem.Colors.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5)
                    )
                    .frame(width: 52, height: 52)
                
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.accent)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("InkSlate")
                    .font(DesignSystem.Typography.title3.weight(.medium))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                Text("Personalize your workspace")
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()
        }
        .padding(14)
        .minimalistCard(.filled)
    }
}

// MARK: - App-owned UserDefaults keys
enum InkSlateUserDefaultsKeys {
    static let all: [String] = [
        "MenuOrder",
        "HiddenMenuItems",
        
        "lastSelectedFolderID",
        
        "selectedCalendarIdentifiers",
        
        "profileUserName",
        "profileUserIcon",
        "profileUserImage",
        
        "lastQuoteDate",
        "currentQuoteId",
        
        "theme.isDarkMode",
        "theme.accentTheme",
        "theme.dynamicFonts",
        "theme.fontSize",

        "hasCompletedOnboarding",

        "budget.didEnsureDefaultSubcategories",

        "migration.schemaFixups.version",

        "lastSyncDate",

        JournalDailyDefaults.bookIDUserDefaultsKey,

        "notifications.journal.enabled",
        "notifications.journal.hour",
        "notifications.journal.minute",
        "notifications.nudge.enabled",
        "notifications.nudge.hour",
        "notifications.nudge.minute",
        "notifications.nudge.lastScheduledFireTime",
        "notifications.cookTimer.enabled"
    ]
}

// MARK: - Menu Reorder View
struct MenuReorderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscription: SubscriptionService
    @State private var menuItems: [MenuViewType] = MenuViewType.allCases
    @State private var hiddenItems: Set<MenuViewType> = []
    
    private let userDefaults = UserDefaults.standard
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let menuOrderKey = "MenuOrder"
    private let hiddenMenuItemsKey = "HiddenMenuItems"
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(menuItems.filter { !hiddenItems.contains($0) }, id: \.self) { item in
                        HStack(spacing: DesignSystem.Spacing.md) {
                            Image(systemName: item.icon)
                                .foregroundColor(item.requiresPro && !subscription.isPro ? .gray : .blue)
                                .frame(width: 24)
                            Text(item.menuTitle)
                            if item.requiresPro {
                                ProFeatureBadge(compact: true)
                            }
                            Spacer()
                            HStack(spacing: DesignSystem.Spacing.md) {
                                Button(action: {
                                    toggleVisibility(for: item)
                                }) {
                                    Image(systemName: "eye.slash")
                                        .foregroundColor(.red)
                                        .frame(width: 24, height: 24)
                                }
                                Image(systemName: "arrow.up.arrow.down")
                                    .foregroundColor(.gray)
                                    .frame(width: 24, height: 24)
                            }
                            .frame(width: (24 * 2) + DesignSystem.Spacing.md)
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove(perform: moveVisibleItems)
                } header: {
                    Text("Visible Menu Items")
                } footer: {
                    Text("Modules marked PRO require InkSlate Pro to open.")
                }
                
                if !hiddenItems.isEmpty {
                    Section {
                        ForEach(Array(hiddenItems).sorted(by: { $0.menuTitle < $1.menuTitle }), id: \.self) { item in
                            HStack(spacing: DesignSystem.Spacing.md) {
                                Image(systemName: item.icon)
                                    .foregroundColor(.gray)
                                    .frame(width: 24)
                                Text(item.menuTitle)
                                    .foregroundColor(.gray)
                                if item.requiresPro {
                                    ProFeatureBadge(compact: true)
                                }
                                Spacer()
                                HStack(spacing: DesignSystem.Spacing.md) {
                                    Button(action: {
                                        toggleVisibility(for: item)
                                    }) {
                                        Image(systemName: "eye")
                                            .foregroundColor(.green)
                                            .frame(width: 24, height: 24)
                                    }
                                    Image(systemName: "arrow.up.arrow.down")
                                        .foregroundColor(.gray)
                                        .frame(width: 24, height: 24)
                                        .hidden()
                                }
                                .frame(width: (24 * 2) + DesignSystem.Spacing.md)
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("Hidden Menu Items")
                    }
                }
            }
            .navigationTitle("Customize Menu")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        saveMenuConfiguration()
                        dismiss()
                    }
                }
            }
        }
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
    }
    
    private func moveVisibleItems(from source: IndexSet, to destination: Int) {
        let visibleItems = menuItems.filter { !hiddenItems.contains($0) }
        var newOrder = visibleItems
        newOrder.move(fromOffsets: source, toOffset: destination)
        
        var updatedMenuItems: [MenuViewType] = []
        for item in newOrder {
            if menuItems.contains(item) {
                updatedMenuItems.append(item)
            }
        }
        for item in menuItems {
            if hiddenItems.contains(item) && !updatedMenuItems.contains(item) {
                updatedMenuItems.append(item)
            }
        }
        menuItems = updatedMenuItems
    }
    
    private func toggleVisibility(for item: MenuViewType) {
        if hiddenItems.contains(item) {
            hiddenItems.remove(item)
        } else {
            hiddenItems.insert(item)
        }
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
            if !orderedItems.isEmpty {
                menuItems = orderedItems
            }
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
        }
    }
    
    private func saveMenuConfiguration() {
        let menuOrderArray = menuItems.map { $0.rawValue }
        let hiddenItemsArray = Array(hiddenItems).map { $0.rawValue }
        
        cloudStore.set(menuOrderArray, forKey: menuOrderKey)
        cloudStore.set(hiddenItemsArray, forKey: hiddenMenuItemsKey)
        cloudStore.synchronize()
        
        userDefaults.set(menuOrderArray, forKey: menuOrderKey)
        userDefaults.set(hiddenItemsArray, forKey: hiddenMenuItemsKey)
    }
}

