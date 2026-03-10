//
//  SettingsViews.swift
//  InkSlate
//
//  Created by Lucas Waldron on 9/29/25.
//

import SwiftUI
import CoreData
import Security

// MARK: - App Legal URLs (read from Info.plist keys PrivacyPolicyURL, TermsOfUseURL)
private enum AppLegalURLs {
    static var privacyPolicy: String {
        Bundle.main.object(forInfoDictionaryKey: "PrivacyPolicyURL") as? String
            ?? "https://sirlwaldron.github.io/InkSlate/privacy.html"
    }
    static var termsOfUse: String {
        Bundle.main.object(forInfoDictionaryKey: "TermsOfUseURL") as? String
            ?? "https://sirlwaldron.github.io/InkSlate/terms.html"
    }
}

// MARK: - Settings Feature Views
struct SettingsView: View {
    @State private var showingMenuReorder = false
    @State private var showingPrivacySettings = false
    @State private var showingProfileCustomization = false
    @State private var showingCloudKitTroubleshooting = false
    @State private var showingFactoryResetWarning = false
    @State private var showingFactoryResetConfirmation = false
    @EnvironmentObject var shared: SharedStateManager
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        List {
            Section("Profile & Personalization") {
                Button(action: {
                    showingProfileCustomization = true
                }) {
                    HStack {
                        Image(systemName: "person.circle")
                            .foregroundColor(DesignSystem.Colors.accent)
                            .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                        Text("Customize Profile")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .font(.caption)
                            .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                    }
                }
                .foregroundColor(.primary)
            }
            
            Section("Menu Customization") {
                Button(action: {
                    showingMenuReorder = true
                }) {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundColor(DesignSystem.Colors.accent)
                            .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                        Text("Reorder Menu Items")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .font(.caption)
                            .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                    }
                }
                .foregroundColor(.primary)
            }
            
            Section("Privacy & Security") {
                Button(action: {
                    showingPrivacySettings = true
                }) {
                    HStack {
                        Image(systemName: "lock.shield")
                            .foregroundColor(DesignSystem.Colors.accent)
                            .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                        Text("Privacy Settings")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .font(.caption)
                            .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                    }
                }
                .foregroundColor(.primary)
            }
            
            Section("Data & Sync") {
                Button(action: {
                    showingCloudKitTroubleshooting = true
                }) {
                    HStack {
                        Image(systemName: "icloud")
                            .foregroundColor(DesignSystem.Colors.accent)
                            .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                        Text("iCloud Sync Troubleshooting")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .font(.caption)
                            .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                    }
                }
                .foregroundColor(.primary)
            }
            
            
            Section("Danger Zone") {
                Button(action: {
                    showingFactoryResetWarning = true
                }) {
                    HStack {
                        Image(systemName: "trash.circle.fill")
                            .foregroundColor(.red)
                            .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                        Text("Factory Reset")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .font(.caption)
                            .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                    }
                }
                .foregroundColor(.red)
            }
            
            // Memorial
            Section {
                EmptyView()
            } footer: {
                VStack(spacing: 8) {
                    Text("In loving memory of my Father")
                        .font(.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    Text("🕊️")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingMenuReorder) {
            MenuReorderView()
        }
        .sheet(isPresented: $showingPrivacySettings) {
            PrivacySettingsView()
        }
        .sheet(isPresented: $showingProfileCustomization) {
            ProfileCustomizationView(profileService: ProfileService())
        }
        .sheet(isPresented: $showingCloudKitTroubleshooting) {
            CloudKitTroubleshootingView()
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
            Text("This is your last chance to cancel. Clicking 'DELETE EVERYTHING' will permanently erase all your data from this device and iCloud. This cannot be undone.")
        }
    }
    
    private func performFactoryReset() {
        // Delete all Core Data models
        do {
            // Delete all notes and projects
            let notesRequest: NSFetchRequest<Notes> = Notes.fetchRequest()
            let notes = try viewContext.fetch(notesRequest)
            for note in notes {
                viewContext.delete(note)
            }
            
            let projectRequest: NSFetchRequest<FSProject> = FSProject.fetchRequest()
            let projects = try viewContext.fetch(projectRequest)
            for project in projects {
                viewContext.delete(project)
            }
            
            let projectSettingsRequest: NSFetchRequest<ProjectSettings> = ProjectSettings.fetchRequest()
            let projectSettings = try viewContext.fetch(projectSettingsRequest)
            for settings in projectSettings {
                viewContext.delete(settings)
            }
            
            let tagRequest: NSFetchRequest<FSTag> = FSTag.fetchRequest()
            let tags = try viewContext.fetch(tagRequest)
            for tag in tags {
                viewContext.delete(tag)
            }
            
            // Delete all journal books and entries
            let journalBookRequest: NSFetchRequest<JournalBook> = JournalBook.fetchRequest()
            let journalBooks = try viewContext.fetch(journalBookRequest)
            for book in journalBooks {
                viewContext.delete(book)
            }
            
            let journalEntryRequest: NSFetchRequest<JournalEntry> = JournalEntry.fetchRequest()
            let journalEntries = try viewContext.fetch(journalEntryRequest)
            for entry in journalEntries {
                viewContext.delete(entry)
            }
            
            // Delete all todo tabs and tasks
            let todoTabRequest: NSFetchRequest<TodoTab> = TodoTab.fetchRequest()
            let todoTabs = try viewContext.fetch(todoTabRequest)
            for tab in todoTabs {
                viewContext.delete(tab)
            }
            
            let todoTaskRequest: NSFetchRequest<TodoTask> = TodoTask.fetchRequest()
            let todoTasks = try viewContext.fetch(todoTaskRequest)
            for task in todoTasks {
                viewContext.delete(task)
            }
            
            // Delete all mind maps and nodes
            let mindMapRequest: NSFetchRequest<MindMap> = MindMap.fetchRequest()
            let mindMaps = try viewContext.fetch(mindMapRequest)
            for mindMap in mindMaps {
                viewContext.delete(mindMap)
            }
            
            let mindMapNodeRequest: NSFetchRequest<MindMapNode> = MindMapNode.fetchRequest()
            let mindMapNodes = try viewContext.fetch(mindMapNodeRequest)
            for node in mindMapNodes {
                viewContext.delete(node)
            }
            
            // Delete all places and categories
            let placeCategoryRequest: NSFetchRequest<PlaceCategory> = PlaceCategory.fetchRequest()
            let placeCategories = try viewContext.fetch(placeCategoryRequest)
            for category in placeCategories {
                viewContext.delete(category)
            }
            
            let placeRequest: NSFetchRequest<Place> = Place.fetchRequest()
            let places = try viewContext.fetch(placeRequest)
            for place in places {
                viewContext.delete(place)
            }
            
            // Delete all Place photos from CloudKit (stored separately)
            Task {
                try? await CloudKitAssetService.shared.deleteAllPlacePhotos()
            }
            
            // Delete all quotes
            let quoteRequest: NSFetchRequest<Quote> = Quote.fetchRequest()
            let quotes = try viewContext.fetch(quoteRequest)
            for quote in quotes {
                viewContext.delete(quote)
            }
            
            // Delete all want to watch items
            let wantToWatchRequest: NSFetchRequest<WantToWatchItem> = WantToWatchItem.fetchRequest()
            let wantToWatchItems = try viewContext.fetch(wantToWatchRequest)
            for item in wantToWatchItems {
                viewContext.delete(item)
            }
            
            // Delete all budget categories, subcategories, and items
            let budgetCategoryRequest: NSFetchRequest<BudgetCategory> = BudgetCategory.fetchRequest()
            let budgetCategories = try viewContext.fetch(budgetCategoryRequest)
            for category in budgetCategories {
                viewContext.delete(category)
            }
            
            let budgetSubcategoryRequest: NSFetchRequest<BudgetSubcategory> = BudgetSubcategory.fetchRequest()
            let budgetSubcategories = try viewContext.fetch(budgetSubcategoryRequest)
            for subcategory in budgetSubcategories {
                viewContext.delete(subcategory)
            }
            
            let budgetItemRequest: NSFetchRequest<BudgetItem> = BudgetItem.fetchRequest()
            let budgetItems = try viewContext.fetch(budgetItemRequest)
            for item in budgetItems {
                viewContext.delete(item)
            }
            
            // Delete all recipes and ingredients
            let recipeRequest: NSFetchRequest<Recipe> = Recipe.fetchRequest()
            let recipes = try viewContext.fetch(recipeRequest)
            for recipe in recipes {
                viewContext.delete(recipe)
            }

            let recipeIngredientRequest: NSFetchRequest<RecipeIngredient> = RecipeIngredient.fetchRequest()
            let ingredients = try viewContext.fetch(recipeIngredientRequest)
            for ingredient in ingredients {
                viewContext.delete(ingredient)
            }
            
            // Delete all shopping list items
            let shoppingItemRequest: NSFetchRequest<ShoppingItemEntity> = ShoppingItemEntity.fetchRequest()
            let shoppingItems = try viewContext.fetch(shoppingItemRequest)
            for item in shoppingItems {
                viewContext.delete(item)
            }
            
            // Delete all pantry items
            let pantryItemRequest: NSFetchRequest<PantryItemEntity> = PantryItemEntity.fetchRequest()
            let pantryItems = try viewContext.fetch(pantryItemRequest)
            for item in pantryItems {
                viewContext.delete(item)
            }
            
            // Save changes to Core Data
            try viewContext.save()
            
            // Clear all UserDefaults with specific keys
            let defaults = UserDefaults.standard
            
            // Clear all InkSlate-specific UserDefaults keys
            let inkSlateKeys = [
                "MenuOrder",
                "HiddenMenuItems", 
                "lastSyncDate",
                "lastSelectedFolderID",
                "profileUserName",
                "profileUserIcon",
                "profileUserImage",
                "lastQuoteDate",
                "currentQuoteId"
            ]
            
            for key in inkSlateKeys {
                defaults.removeObject(forKey: key)
            }
            
            // Clear all other UserDefaults (nuclear option)
            let dictionary = defaults.dictionaryRepresentation()
            for key in dictionary.keys {
                defaults.removeObject(forKey: key)
            }
            defaults.synchronize()
            
            // Clear iCloud key-value storage to prevent settings from syncing back
            clearICloudKeyValueStore()
            
            // Clear Keychain data (encrypted notes passwords)
            clearKeychainData()
            
            // Clear any locally stored files (profile images, recipe images, exports, etc.)
            clearLocalFileStorage()
            
            // Reset profile data and any observable shared state
            ProfileService().resetToDefaults()
            // Reset shared state
            shared.resetToDefaults()
            
        } catch {
            // Handle error silently - user doesn't need to see technical errors
            print("Factory reset error: \(error)")
        }
    }
    
    private func clearICloudKeyValueStore() {
        let cloudStore = NSUbiquitousKeyValueStore.default
        let cloudKeys = cloudStore.dictionaryRepresentation.keys
        
        for key in cloudKeys {
            cloudStore.removeObject(forKey: key)
        }
        cloudStore.synchronize()
    }
    
    private func clearKeychainData() {
        let keychainService = "co.inkslate.encryption"
        
        // Delete all keychain items for our service
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("Keychain clear error: \(status)")
        }
    }
    
    private func clearLocalFileStorage() {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        if let fileURLs = try? fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: []) {
            for fileURL in fileURLs {
                do {
                    try fileManager.removeItem(at: fileURL)
                } catch {
                    print("Failed to remove \(fileURL.lastPathComponent): \(error)")
                }
            }
        }
    }
}

// MARK: - Menu Reorder View
struct MenuReorderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var menuItems: [MenuViewType] = MenuViewType.allCases
    @State private var hiddenItems: Set<MenuViewType> = []
    
    private let userDefaults = UserDefaults.standard
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let menuOrderKey = "MenuOrder"
    private let hiddenMenuItemsKey = "HiddenMenuItems"
    
    var body: some View {
        NavigationView {
            List {
                Section("Visible Menu Items") {
                    ForEach(menuItems.filter { !hiddenItems.contains($0) }, id: \.self) { item in
                        HStack {
                            Image(systemName: item.icon)
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text(item.rawValue)
                            Spacer()
                            Button(action: {
                                toggleVisibility(for: item)
                            }) {
                                Image(systemName: "eye.slash")
                                    .foregroundColor(.red)
                            }
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove(perform: moveVisibleItems)
                }
                
                if !hiddenItems.isEmpty {
                    Section("Hidden Menu Items") {
                        ForEach(Array(hiddenItems), id: \.self) { item in
                            HStack {
                                Image(systemName: item.icon)
                                    .foregroundColor(.gray)
                                    .frame(width: 24)
                                Text(item.rawValue)
                                    .foregroundColor(.gray)
                                Spacer()
                                Button(action: {
                                    toggleVisibility(for: item)
                                }) {
                                    Image(systemName: "eye")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Customize Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveMenuConfiguration()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadMenuConfiguration()
            setupCloudStoreObserver()
        }
    }
    
    private func setupCloudStoreObserver() {
        // Listen for iCloud sync changes
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [self] _ in
            loadMenuConfiguration()
        }
    }
    
    private func moveVisibleItems(from source: IndexSet, to destination: Int) {
        let visibleItems = menuItems.filter { !hiddenItems.contains($0) }
        var newOrder = visibleItems
        newOrder.move(fromOffsets: source, toOffset: destination)
        
        // Update the main menuItems array with the new order
        var updatedMenuItems: [MenuViewType] = []
        for item in newOrder {
            if menuItems.contains(item) {
                updatedMenuItems.append(item)
            }
        }
        // Add hidden items at the end
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
        // Try to load from iCloud first, fallback to local UserDefaults for migration
        let menuOrder: [String]?
        if let cloudOrder = cloudStore.array(forKey: menuOrderKey) as? [String], !cloudOrder.isEmpty {
            menuOrder = cloudOrder
        } else if let localOrder = userDefaults.array(forKey: menuOrderKey) as? [String], !localOrder.isEmpty {
            menuOrder = localOrder
            // Migrate to iCloud
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
        
        // Load hidden items
        let hiddenItemsData: [String]?
        if let cloudHidden = cloudStore.array(forKey: hiddenMenuItemsKey) as? [String], !cloudHidden.isEmpty {
            hiddenItemsData = cloudHidden
        } else if let localHidden = userDefaults.array(forKey: hiddenMenuItemsKey) as? [String], !localHidden.isEmpty {
            hiddenItemsData = localHidden
            // Migrate to iCloud
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
        
        // Save to iCloud Key-Value Store for syncing
        cloudStore.set(menuOrderArray, forKey: menuOrderKey)
        cloudStore.set(hiddenItemsArray, forKey: hiddenMenuItemsKey)
        cloudStore.synchronize()
        
        // Also save locally as backup
        userDefaults.set(menuOrderArray, forKey: menuOrderKey)
        userDefaults.set(hiddenItemsArray, forKey: hiddenMenuItemsKey)
    }
}

// MARK: - Privacy Settings View
struct PrivacySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var analyticsEnabled = false
    @State private var crashReportingEnabled = true
    @State private var dataCollectionEnabled = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Legal") {
                    if let url = URL(string: AppLegalURLs.privacyPolicy) {
                        Link("Privacy Policy", destination: url)
                    }
                    if let url = URL(string: AppLegalURLs.termsOfUse) {
                        Link("Terms of Use", destination: url)
                    }
                }
                
                Section("Analytics & Privacy") {
                    Toggle("Analytics", isOn: $analyticsEnabled)
                    Toggle("Crash Reporting", isOn: $crashReportingEnabled)
                    Toggle("Data Collection", isOn: $dataCollectionEnabled)
                }
                
                Section("Data Control") {
                    Button("Clear All Data") {
                        clearAllData()
                    }
                    .foregroundColor(.red)
                    
                    Button("Reset Privacy Settings") {
                        resetPrivacySettings()
                    }
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("Privacy Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func clearAllData() {
        // Implement data clearing logic
    }
    
    private func resetPrivacySettings() {
        analyticsEnabled = false
        crashReportingEnabled = true
        dataCollectionEnabled = false
    }
}