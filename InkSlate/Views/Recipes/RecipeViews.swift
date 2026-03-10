//
//  RecipeViews.swift
//  InkSlate
//
//  Created by UI Overhaul on 9/29/25.
//  Enhanced with comprehensive recipe features + Shopping List + Pantry Management
//  Refactored with modular architecture and improved error handling
//

import SwiftUI
import CoreData
import PhotosUI

// Import modular components
// Models are imported via RecipeModels.swift, ShoppingModels.swift, PantryModels.swift
// Services are imported via RecipeImageStore.swift, RecipeService.swift
// ViewModels are imported via CookModeViewModel.swift
// Extensions are imported via RecipeExtensions.swift

// MARK: - Main Tab View Wrapper
struct RecipeTabView: View {
    var body: some View {
        TabView {
            ModernRecipeMainView()
                .tabItem {
                    Label("Recipes", systemImage: "book.fill")
                }
            
            ShoppingListMainView()
                .tabItem {
                    Label("Shopping", systemImage: "cart.fill")
                }
            
            PantryMainView()
                .tabItem {
                    Label("Pantry", systemImage: "refrigerator.fill")
                }
        }
    }
}

// MARK: - Modern Recipe Main View
struct ModernRecipeMainView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var sharedState: SharedStateManager

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Recipe.createdDate, ascending: false)])
    private var allRecipes: FetchedResults<Recipe>

    @State private var searchText = ""
    @State private var showingAddRecipe = false
    @State private var showingFilters = false
    @State private var selectedCategory: RecipeCategory?
    @State private var selectedSort: SortOption = .dateNewest
    @State private var showFavoritesOnly = false
    @State private var refreshing = false
    @State private var showingStats = false

    private var filteredRecipes: [Recipe] {
        let allRecipesArray = Array(allRecipes)
        
        // Use RecipeService for filtering and sorting
        let filtered = RecipeService.searchRecipes(
            allRecipesArray,
            searchText: searchText,
            category: selectedCategory,
            favoritesOnly: showFavoritesOnly
        )
        
        return RecipeService.sortRecipes(filtered, by: selectedSort)
    }

    var body: some View {
        ZStack {
            // Animated gradient background
            LinearGradient(
                colors: [DesignSystem.Colors.background, DesignSystem.Colors.backgroundSecondary.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: refreshing)
            
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    header
                    searchBar
                        filterChips
                    
                    if filteredRecipes.isEmpty {
                            if searchText.isEmpty && selectedCategory == nil && !showFavoritesOnly {
                            ModernEmptyRecipesView()
                        } else {
                                SearchEmptyView(searchText: searchText.isEmpty ? "your filters" : searchText)
                        }
                    } else {
                            LazyVStack(spacing: DesignSystem.Spacing.lg) {
                                ForEach(Array(filteredRecipes.enumerated()), id: \.element.objectID) { index, recipe in
                            ModernRecipeCard(recipe: recipe)
                                        .transition(.asymmetric(
                                            insertion: .scale.combined(with: .opacity),
                                            removal: .scale.combined(with: .opacity)
                                        ))
                                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(Double(index) * 0.1), value: filteredRecipes.count)
                                }
                        }
                    }
                    
                    addCard
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
            }
            .refreshable { await refreshRecipes() }
            .navigationBarHidden(true)
            }
        }
        .sheet(isPresented: $showingAddRecipe) {
            ModernAddRecipeView()
        }
        .sheet(isPresented: $showingFilters) {
            FilterSortView(
                selectedCategory: $selectedCategory,
                selectedSort: $selectedSort,
                showFavoritesOnly: $showFavoritesOnly
            )
        }
        .sheet(isPresented: $showingStats) {
            RecipeStatsView(recipes: Array(allRecipes))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: 16) {
                // Hamburger menu
                Button {
                    sharedState.toggleMenu()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("🍳 My Recipes")
                        .font(DesignSystem.Typography.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text("\(filteredRecipes.count) recipes in your collection")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 12) {
                    Button(action: { showingStats = true }) {
                        Image(systemName: "chart.bar.fill")
                            .font(.title3)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    Button(action: { showingAddRecipe = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DesignSystem.Colors.textSecondary)
            TextField("Search recipes, ingredients...", text: $searchText)
                .textFieldStyle(.plain)
                .font(DesignSystem.Typography.body)
            if !searchText.isEmpty {
                Button(action: { 
                    withAnimation(.spring()) {
                        searchText = ""
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .fill(DesignSystem.Colors.backgroundTertiary)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Button(action: { showingFilters = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("Sort & Filter")
                    }
                    .font(DesignSystem.Typography.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DesignSystem.Colors.accent)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
                
                if showFavoritesOnly {
                    FilterChip(title: "Favorites", icon: "heart.fill", isActive: true) {
                        withAnimation(.spring()) {
                            showFavoritesOnly = false
                        }
                    }
                }
                
                if let category = selectedCategory {
                    FilterChip(title: category.rawValue, icon: category.icon, isActive: true) {
                        withAnimation(.spring()) {
                            selectedCategory = nil
                        }
                    }
                }
                
                ForEach(RecipeCategory.allCases.filter { $0 != selectedCategory }, id: \.self) { category in
                    FilterChip(title: category.rawValue, icon: category.icon, isActive: false) {
                        withAnimation(.spring()) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
        }
        .padding(.horizontal, -DesignSystem.Spacing.lg)
    }

    private var addCard: some View {
        Button(action: { showingAddRecipe = true }) {
            HStack {
                Image(systemName: "plus")
                    .font(.title3)
                Text("Add New Recipe")
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .foregroundColor(DesignSystem.Colors.textInverse)
            .background(
                LinearGradient(
                    colors: [DesignSystem.Colors.accent, DesignSystem.Colors.accent.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .shadow(color: DesignSystem.Colors.accent.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func refreshRecipes() async {
        refreshing = true
        try? await Task.sleep(for: .seconds(1))
        refreshing = false
    }
}

// MARK: - Recipe Stat Card Component
struct RecipeStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(value)
                    .font(DesignSystem.Typography.headline)
                    .fontWeight(.bold)
            }
            .foregroundColor(color)
            
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Recipe Stats View
struct RecipeStatsView: View {
    @Environment(\.dismiss) private var dismiss
    let recipes: [Recipe]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("📊 Recipe Statistics")
                            .font(DesignSystem.Typography.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Your cooking journey at a glance")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .padding(.top)
                    
                    // Stats Grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                        RecipeStatCard(
                            title: "Total Recipes",
                            value: "\(recipes.count)",
                            icon: "book.fill",
                            color: DesignSystem.Colors.accent
                        )
                        
                        RecipeStatCard(
                            title: "Favorites",
                            value: "\(recipes.filter { $0.rating >= Int16(RecipeConstants.favoriteRatingThreshold) }.count)",
                            icon: "heart.fill",
                            color: .red
                        )
                        
                        RecipeStatCard(
                            title: "Avg Rating",
                            value: String(format: "%.1f", recipes.map { Double($0.rating) }.reduce(0, +) / Double(max(recipes.count, 1))),
                            icon: "star.fill",
                            color: .yellow
                        )
                        
                        RecipeStatCard(
                            title: "Avg Time",
                            value: "\(Int(recipes.map { Double($0.totalTime) }.reduce(0, +) / Double(max(recipes.count, 1))))m",
                            icon: "clock.fill",
                            color: .blue
                        )
                    }
                    
                    // Category Breakdown
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Categories")
                            .font(DesignSystem.Typography.title2)
                            .fontWeight(.semibold)
                        
                        ForEach(RecipeCategory.allCases, id: \.self) { category in
                            let count = recipes.filter { $0.cuisine == category.rawValue }.count
                            if count > 0 {
                                HStack {
                                    Image(systemName: category.icon)
                                        .foregroundColor(category.color)
                                    Text(category.rawValue)
                                        .font(DesignSystem.Typography.body)
                                    Spacer()
                                    Text("\(count)")
                                        .font(DesignSystem.Typography.body)
                                        .fontWeight(.semibold)
                                        .foregroundColor(DesignSystem.Colors.accent)
                                }
                                .padding()
                                .background(DesignSystem.Colors.backgroundSecondary)
                                .cornerRadius(DesignSystem.CornerRadius.md)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let title: String
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
                if isActive {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
            }
            .font(DesignSystem.Typography.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? DesignSystem.Colors.accent : DesignSystem.Colors.backgroundSecondary)
            .foregroundColor(isActive ? .white : DesignSystem.Colors.textPrimary)
            .cornerRadius(16)
            .scaleEffect(isActive ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
        }
    }
}

// MARK: - Filter & Sort Sheet
struct FilterSortView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCategory: RecipeCategory?
    @Binding var selectedSort: SortOption
    @Binding var showFavoritesOnly: Bool
    
    var body: some View {
        NavigationStack {
            List {
                Section("Sort By") {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button(action: { selectedSort = option; lightHaptic() }) {
                            HStack {
                                Text(option.rawValue)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                Spacer()
                                if selectedSort == option {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(DesignSystem.Colors.accent)
                                }
                            }
                        }
                    }
                }
                
                Section("Filter by Category") {
                    Button(action: { selectedCategory = nil; lightHaptic() }) {
                        HStack {
                            Text("All Categories")
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            Spacer()
                            if selectedCategory == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(DesignSystem.Colors.accent)
                            }
                        }
                    }
                    
                    ForEach(RecipeCategory.allCases, id: \.self) { category in
                        Button(action: { selectedCategory = category; lightHaptic() }) {
                            HStack {
                                Image(systemName: category.icon)
                                Text(category.rawValue)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                Spacer()
                                if selectedCategory == category {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(DesignSystem.Colors.accent)
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Toggle("Show Favorites Only", isOn: $showFavoritesOnly)
                }
            }
            .navigationTitle("Sort & Filter")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Enhanced Recipe Card
struct ModernRecipeCard: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingDetail = false
    @State private var isPressed = false
    @ObservedObject var recipe: Recipe

    var body: some View {
        Button(role: .none, action: { showingDetail = true }) {
            HStack(spacing: 12) {
                // Compact Recipe Image
                RecipeCardImage(path: recipe.imageUrl)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Recipe Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.name ?? "Untitled Recipe")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    
                    if let description = recipe.recipeDescription, !description.isEmpty {
                        Text(description)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .lineLimit(2)
                    }
                    
                    HStack(spacing: 12) {
                        if let servingsString = recipe.servings, let servingsInt = Int(servingsString), servingsInt > 0 {
                        Label("\(servingsString)", systemImage: "person.2")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        
                        Label("\(Int(recipe.prepTime + recipe.cookTime))m", systemImage: "clock")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        HStack(spacing: 2) {
                            ForEach(0..<5) { star in
                                Image(systemName: star < Int(recipe.rating) ? "star.fill" : "star")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Action Button
                Button(action: { showingDetail = true }) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DesignSystem.Colors.backgroundTertiary)
                    .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDetail) {
            ModernRecipeDetailView(recipe: recipe)
        }
    }
    
    private func toggleFavorite() {
        recipe.rating = recipe.rating >= Int16(RecipeConstants.favoriteRatingThreshold) ? 0 : 5
        do {
            try viewContext.save()
        } catch {
            handleRecipeError(error, context: "Failed to update favorite status")
        }
    }
    
    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
            .fill(DesignSystem.Colors.backgroundSecondary)
            .frame(height: 200)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text("No Image")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            )
    }
}

private struct RecipeCardImage: View {
    let path: String?
    
    var body: some View {
        Group {
            if let path,
               path.hasPrefix("http"),
               let url = URL(string: path) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholder
                }
            } else if let image = RecipeImageStore.loadImage(path: path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
    }
    
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(DesignSystem.Colors.backgroundSecondary)
            .overlay(
                Image(systemName: "photo")
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            )
    }
}

// MARK: - Empty State Views
struct ModernEmptyRecipesView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundColor(DesignSystem.Colors.accent)
            
            VStack(spacing: 8) {
                Text("No Recipes Yet")
                    .font(DesignSystem.Typography.title2)
                    .fontWeight(.semibold)
                
                Text("Start building your recipe collection by adding your first recipe!")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

struct SearchEmptyView: View {
    let searchText: String
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            
            VStack(spacing: 8) {
                Text("No Results Found")
                    .font(DesignSystem.Typography.title2)
                    .fontWeight(.semibold)
                
                Text("No recipes match '\(searchText)'. Try adjusting your search or filters.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Add/Edit Recipe
struct ModernAddRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let editingRecipe: Recipe?
    
    @State private var name = ""
    @State private var recipeDescription = ""
    @State private var selectedCategory: RecipeCategory = .dinner
    @State private var rating = 0
    @State private var imageItem: PhotosPickerItem?
    @State private var imagePreview: UIImage?
    @State private var existingImagePath: String = ""
    @State private var selectedImageData: Data?
    @State private var ingredients: [RecipeIngredientData] = []
    @State private var steps: [RecipeStep] = []
    @State private var prepTime = 0
    @State private var cookTime = 0
    @State private var servings = 4
    @State private var selectedTags: Set<DietaryTag> = []
    @State private var notesText = ""
    
    init(editingRecipe: Recipe? = nil) {
        self.editingRecipe = editingRecipe
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                    PhotosPicker(selection: $imageItem, matching: .images) {
                        imageSection
                    }
                    .onChange(of: imageItem) { _, newItem in
                        guard let newItem else {
                            selectedImageData = nil
                            return
                        }
                        Task {
                            if let data = try? await newItem.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                selectedImageData = data
                                imagePreview = image
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        TextField("Recipe Name", text: $name)
                            .textFieldStyle(MinimalistInputFieldStyle(state: .normal))
                            .font(DesignSystem.Typography.title2)
                        
                        TextField("Description", text: $recipeDescription, axis: .vertical)
                            .textFieldStyle(MinimalistInputFieldStyle(state: .normal))
                            .lineLimit(3...6)

                        HStack(spacing: 16) {
                            VStack(alignment: .leading) {
                                Text("Category")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(RecipeCategory.allCases, id: \.self) { category in
                                HStack {
                                    Image(systemName: category.icon)
                                    Text(category.rawValue)
                                }.tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .leading) {
                                Text("Rating")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                HStack(spacing: 4) {
                            ForEach(1...5, id: \.self) { i in
                                Image(systemName: i <= rating ? "star.fill" : "star")
                                    .foregroundColor(i <= rating ? .yellow : DesignSystem.Colors.textTertiary)
                                    .onTapGesture {
                                                withAnimation(.spring()) {
                                        rating = i
                                                }
                                        lightHaptic()
                                            }
                                    }
                                }
                            }
                        }
                        
                        HStack(spacing: 16) {
                            VStack(alignment: .leading) {
                                Text("Prep Time (min)")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                Stepper("\(prepTime)", value: $prepTime, in: 0...300, step: 5)
                            }
                            
                            VStack(alignment: .leading) {
                                Text("Cook Time (min)")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                Stepper("\(cookTime)", value: $cookTime, in: 0...480, step: 5)
                            }
                        }
                        
                        VStack(alignment: .leading) {
                            Text("Servings")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            Stepper("\(servings) servings", value: $servings, in: 1...20)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dietary Tags")
                            .font(DesignSystem.Typography.title3)
                            .fontWeight(.semibold)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                            ForEach(DietaryTag.allCases, id: \.self) { tag in
                                Button(action: { toggleTag(tag) }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: tag.icon)
                                        Text(tag.rawValue)
                                    }
                                    .font(DesignSystem.Typography.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedTags.contains(tag) ? DesignSystem.Colors.accent : DesignSystem.Colors.backgroundSecondary)
                                    .foregroundColor(selectedTags.contains(tag) ? .white : DesignSystem.Colors.textPrimary)
                                    .cornerRadius(16)
                                }
                                .scaleEffect(selectedTags.contains(tag) ? 1.05 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTags.contains(tag))
                            }
                        }
                    }

                    IngredientsSection(ingredients: $ingredients)
                    StepsSection(steps: $steps)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(DesignSystem.Typography.title3)
                            .fontWeight(.semibold)
                        TextField("Additional notes or modifications...", text: $notesText, axis: .vertical)
                            .textFieldStyle(MinimalistInputFieldStyle(state: .normal))
                            .lineLimit(3...6)
                    }

                    Button(action: saveRecipe) {
                        Text(editingRecipe == nil ? "Save Recipe" : "Update Recipe")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(DesignSystem.Colors.textInverse)
                            .background(
                                LinearGradient(
                                    colors: [DesignSystem.Colors.accent, DesignSystem.Colors.accent.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(DesignSystem.CornerRadius.lg)
                            .shadow(color: DesignSystem.Colors.accent.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .disabled(name.isEmpty || ingredients.isEmpty || steps.isEmpty)
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle(editingRecipe == nil ? "New Recipe" : "Edit Recipe")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            loadRecipeData()
        }
    }
    
    private var imageSection: some View {
        Group {
            if let image = currentImagePreview {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .clipped()
                    .cornerRadius(DesignSystem.CornerRadius.md)
            } else {
                imagePlaceholder
            }
        }
    }
    
    private var currentImagePreview: UIImage? {
        if let imagePreview {
            return imagePreview
        }
        return RecipeImageStore.loadImage(path: existingImagePath)
    }
    
    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
            .fill(
                LinearGradient(
                    colors: [DesignSystem.Colors.backgroundSecondary, DesignSystem.Colors.backgroundTertiary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(height: 220)
            .overlay(
                VStack {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 32))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text("Add Photo")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            )
    }
    
    private func toggleTag(_ tag: DietaryTag) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedTags.contains(tag) {
                selectedTags.remove(tag)
            } else {
                selectedTags.insert(tag)
            }
        }
        lightHaptic()
    }
    
    private func loadRecipeData() {
        guard let recipe = editingRecipe else { return }
        name = recipe.name ?? ""
        recipeDescription = recipe.recipeDescription ?? ""
        existingImagePath = recipe.imageUrl ?? ""
        imagePreview = RecipeImageStore.loadImage(path: existingImagePath)
        rating = Int(recipe.rating)
        prepTime = Int(recipe.prepTime)
        cookTime = Int(recipe.cookTime)
        servings = Int(recipe.servings ?? "1") ?? 1
        notesText = recipe.recipeNotes
        selectedTags = recipe.dietaryTagsSet
        steps = recipe.recipeSteps
        if steps.isEmpty, !recipe.recipeNotes.isEmpty {
            steps = [
                RecipeStep(
                    instruction: recipe.recipeNotes
                )
            ]
        }
        
        if let category = RecipeCategory.allCases.first(where: { $0.rawValue == recipe.cuisine }) {
            selectedCategory = category
        }
        
        if let recipeIngredients = recipe.ingredients?.allObjects as? [RecipeIngredient] {
            ingredients = recipeIngredients.map { ingredient in
                RecipeIngredientData(
                    name: ingredient.name ?? "",
                    amount: ingredient.notes?.isEmpty == false ? ingredient.notes! : ingredient.formattedAmount,
                    unit: ingredient.unit ?? ""
                )
            }
        }
    }

    private func saveRecipe() {
        let recipe = editingRecipe ?? Recipe(context: viewContext)
        
        if recipe.id == nil {
            recipe.id = UUID()
            recipe.createdDate = Date()
        }
        
        recipe.name = name
        recipe.recipeDescription = recipeDescription
        recipe.cuisine = selectedCategory.rawValue
        recipe.rating = Int16(rating)
        recipe.modifiedDate = Date()
        recipe.prepTime = Int16(prepTime)
        recipe.cookTime = Int16(cookTime)
        recipe.servings = String(servings)
        let cleanedSteps = steps.filter { !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        recipe.updateDetails(steps: cleanedSteps, notes: notesText)
        recipe.updateDietaryTags(selectedTags)
        
        // Save image with proper error handling
        if let data = selectedImageData, let recipeID = recipe.id {
            do {
                // Validate image data before saving
                if RecipeValidation.validateImageData(data) {
                    let path = try RecipeImageStore.saveImage(
                        data: data,
                        for: recipeID,
                        replacing: recipe.imageUrl
                    )
                    recipe.imageUrl = path
                    existingImagePath = path
                    imagePreview = UIImage(data: data)
                    selectedImageData = nil
                } else {
                    print("Warning: Invalid image data, skipping image save")
                    // Continue saving recipe without image
                }
            } catch {
                print("Error saving recipe image: \(error.localizedDescription)")
                // Continue saving recipe without image - don't fail the entire save
            }
        } else if let currentPath = recipe.imageUrl, currentPath.isEmpty {
            recipe.imageUrl = nil
        } else if recipe.imageUrl == nil && !existingImagePath.isEmpty {
            recipe.imageUrl = existingImagePath
        }
        
        if let existingIngredients = recipe.ingredients?.allObjects as? [RecipeIngredient] {
            existingIngredients.forEach(viewContext.delete)
        }
        
        for ingredientData in ingredients {
            let ingredient = RecipeIngredient(context: viewContext)
            ingredient.id = UUID()
            ingredient.createdDate = Date()  // Required for CloudKit sync
            ingredient.modifiedDate = Date()  // Required for CloudKit sync
            ingredient.name = ingredientData.name
            let rawAmount = ingredientData.amount.trimmingCharacters(in: .whitespacesAndNewlines)
            ingredient.amount = RecipeService.parseAmountString(rawAmount) ?? 0.0
            ingredient.notes = rawAmount
            ingredient.unit = ingredientData.unit
            ingredient.recipe = recipe
        }
        
        do {
            try viewContext.save()
            lightHaptic()
            dismiss()
        } catch {
            print("Error saving recipe: \(error.localizedDescription)")
            // In production, show an alert to the user
            handleRecipeError(error, context: "Failed to save recipe")
        }
    }
}

// MARK: - Ingredients Section
struct IngredientsSection: View {
    @Binding var ingredients: [RecipeIngredientData]
    @State private var showingAdd = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ingredients")
                    .font(DesignSystem.Typography.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { showingAdd = true }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(DesignSystem.Colors.accent)
                }
            }
            
            if ingredients.isEmpty {
                Text("No ingredients added yet")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .cornerRadius(DesignSystem.CornerRadius.md)
            } else {
                ForEach(ingredients.indices, id: \.self) { index in
                    let ingredient = ingredients[index]
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ingredient.name)
                                .font(DesignSystem.Typography.body)
                            Text("\(ingredient.amount) \(ingredient.unit)")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        Spacer()
                        Button(action: { 
                            withAnimation(.spring()) {
                                var items = ingredients
                                items.remove(at: index)
                                ingredients = items
                            }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddIngredientView { ingredient in
                withAnimation(.spring()) {
                    ingredients.append(ingredient)
                }
                showingAdd = false
            }
        }
    }
}

struct AddIngredientView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (RecipeIngredientData) -> Void
    
    @State private var name = ""
    @State private var amount = ""
    @State private var unit = "cups"
    
    let units = ["cups", "tbsp", "tsp", "oz", "lbs", "g", "kg", "ml", "L", "whole", "pinch", "to taste"]
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Ingredient Name", text: $name)
                TextField("Amount", text: $amount)
                    .keyboardType(.decimalPad)
                Picker("Unit", selection: $unit) {
                    ForEach(units, id: \.self) { unit in
                        Text(unit).tag(unit)
                    }
                }
            }
            .navigationTitle("Add Ingredient")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        let ingredient = RecipeIngredientData(name: name, amount: amount, unit: unit)
                        onAdd(ingredient)
                    }
                    .disabled(name.isEmpty || amount.isEmpty)
                }
            }
        }
    }
}

// MARK: - Steps Section
struct StepsSection: View {
    @Binding var steps: [RecipeStep]
    @State private var showingAdd = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Instructions")
                    .font(DesignSystem.Typography.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { showingAdd = true }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(DesignSystem.Colors.accent)
                }
            }
            
            if steps.isEmpty {
                Text("No steps added yet")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .cornerRadius(DesignSystem.CornerRadius.md)
            } else {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(DesignSystem.Typography.title3)
                            .fontWeight(.bold)
                            .foregroundColor(DesignSystem.Colors.accent)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.instruction)
                                .font(DesignSystem.Typography.body)
                            if let timer = step.timerMinutes {
                                Label("\(timer) minutes", systemImage: "timer")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: { 
                            withAnimation(.spring()) {
                                var items = steps
                                items.remove(at: index)
                                steps = items
                            }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddStepView { step in
                withAnimation(.spring()) {
                    steps.append(step)
                }
                showingAdd = false
            }
        }
    }
}

struct AddStepView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (RecipeStep) -> Void
    
    @State private var instruction = ""
    @State private var hasTimer = false
    @State private var timerMinutes = 0
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Instruction", text: $instruction, axis: .vertical)
                    .lineLimit(3...8)
                
                Toggle("Add Timer", isOn: $hasTimer)
                
                if hasTimer {
                    Stepper("Timer: \(timerMinutes) minutes", value: $timerMinutes, in: 1...180)
                }
            }
            .navigationTitle("Add Step")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        let step = RecipeStep(
                            instruction: instruction,
                            timerMinutes: hasTimer ? timerMinutes : nil
                        )
                        onAdd(step)
                    }
                    .disabled(instruction.isEmpty)
                }
            }
        }
    }
}

// MARK: - Detail View
struct ModernRecipeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var recipe: Recipe
    
    @State private var showCookMode = false
    @State private var showingEdit = false
    @State private var showingDeleteAlert = false
    @State private var showingAddToList = false
    @State private var showingShareSheet = false
    @State private var currentServings: Int
    @State private var deletedRecipe: Recipe? // For undo functionality
    
    init(recipe: Recipe) {
        self.recipe = recipe
        _currentServings = State(initialValue: Int(recipe.servings ?? "1") ?? 1)
    }

    var body: some View {
        NavigationStack {
        ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                if let image = RecipeImageStore.loadImage(path: recipe.imageUrl) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 300)
                        .clipped()
                        .cornerRadius(DesignSystem.CornerRadius.md)
                        .shadow(radius: 4, y: 2)
                } else if let imageUrl = recipe.imageUrl,
                          imageUrl.hasPrefix("http"),
                          let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .fill(DesignSystem.Colors.backgroundSecondary)
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                    .shadow(radius: 4, y: 2)
                } else {
                    Rectangle()
                        .fill(DesignSystem.Colors.backgroundSecondary)
                        .frame(height: 300)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                }
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        VStack(alignment: .leading, spacing: 8) {
                Text(recipe.name ?? "Untitled Recipe")
                    .font(DesignSystem.Typography.largeTitle)
                    .fontWeight(.bold)
                            
                            if let category = recipe.cuisine {
                                HStack {
                                    if let cat = RecipeCategory.allCases.first(where: { $0.rawValue == category }) {
                                        Image(systemName: cat.icon)
                                        Text(category)
                                    } else {
                                        Text(category)
                                    }
                                }
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            
                            if recipe.rating > 0 {
                                HStack(spacing: 4) {
                                    ForEach(1...5, id: \.self) { i in
                                        Image(systemName: i <= recipe.rating ? "star.fill" : "star")
                                            .foregroundColor(i <= recipe.rating ? .yellow : DesignSystem.Colors.textTertiary)
                                    }
                                }
                            }
                        }

                if let desc = recipe.recipeDescription, !desc.isEmpty {
                    Text(desc)
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                        HStack(spacing: 24) {
                            if recipe.prepTime > 0 {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Prep Time")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                    HStack {
                                        Image(systemName: "clock")
                                        Text("\(recipe.prepTime)m")
                                    }
                                    .font(DesignSystem.Typography.body)
                                    .fontWeight(.medium)
                                }
                            }
                            
                            if recipe.cookTime > 0 {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Cook Time")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                    HStack {
                                        Image(systemName: "flame")
                                        Text("\(recipe.cookTime)m")
                                    }
                                    .font(DesignSystem.Typography.body)
                                    .fontWeight(.medium)
                                }
                            }
                            
                            if (recipe.prepTime + recipe.cookTime) > 0 {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Total Time")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                    HStack {
                                        Image(systemName: "timer")
                                        Text("\(recipe.totalTime)m")
                                    }
                                    .font(DesignSystem.Typography.body)
                                    .fontWeight(.medium)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignSystem.Colors.backgroundSecondary)
                        .cornerRadius(DesignSystem.CornerRadius.md)
                        
                        // Dietary tags removed - not in Core Data model
                        
                        let ingredients = recipe.ingredientsArray
                        if !ingredients.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Ingredients")
                                        .font(DesignSystem.Typography.title2)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    if let servingsString = recipe.servings, let servingsInt = Int(servingsString), servingsInt > 0 {
                                        HStack {
                                            Button(action: { if currentServings > 1 { currentServings -= 1 } }) {
                                                Image(systemName: "minus.circle")
                                            }
                                            Text("\(currentServings)")
                                                .frame(width: 30)
                                            Button(action: { currentServings += 1 }) {
                                                Image(systemName: "plus.circle")
                                            }
                                        }
                                        .font(DesignSystem.Typography.body)
                                    }
                                }
                                
                                ForEach(ingredients) { ingredient in
                                    HStack {
                                        Text("•")
                                        Text(scaledIngredient(ingredient))
                                            .font(DesignSystem.Typography.body)
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                                
                                Button(action: { showingAddToList = true }) {
                                    HStack {
                                        Image(systemName: "cart.badge.plus")
                                        Text("Add to Shopping List")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(DesignSystem.Colors.backgroundSecondary)
                                    .foregroundColor(DesignSystem.Colors.accent)
                                    .cornerRadius(DesignSystem.CornerRadius.md)
                                }
                            }
                        }
                        
                        Divider()
                        
                        let steps = recipe.recipeSteps
                        if !steps.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Instructions")
                                    .font(DesignSystem.Typography.title2)
                                    .fontWeight(.semibold)
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                Text("\(index + 1).")
                                                    .font(DesignSystem.Typography.body)
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(DesignSystem.Colors.accent)
                                                Text(step.instruction)
                                                    .font(DesignSystem.Typography.body)
                                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                            }
                                            
                                            if let timer = step.timerMinutes, timer > 0 {
                                                Label("\(timer) minute timer", systemImage: "timer")
                                                    .font(DesignSystem.Typography.caption)
                                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                            }
                                        }
                                    }
                                }
                                
                                Button(action: { showCookMode = true }) {
                                    HStack {
                                        Image(systemName: "play.fill")
                                        Text("Start Cook Mode")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            colors: [DesignSystem.Colors.accent, DesignSystem.Colors.accent.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(DesignSystem.CornerRadius.lg)
                                    .shadow(color: DesignSystem.Colors.accent.opacity(0.3), radius: 8, x: 0, y: 4)
                                }
                            }
                        }
                        
                        if !recipe.recipeNotes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notes")
                                    .font(DesignSystem.Typography.title3)
                                    .fontWeight(.semibold)
                                Text(recipe.recipeNotes)
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }
            }
            .padding(DesignSystem.Spacing.lg)
                }
        }
        .background(DesignSystem.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
        .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showingEdit = true }) {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(action: toggleFavorite) {
                            Label(
                                recipe.rating >= Int16(RecipeConstants.favoriteRatingThreshold) ? "Remove from Favorites" : "Add to Favorites",
                                systemImage: recipe.rating >= Int16(RecipeConstants.favoriteRatingThreshold) ? "heart.slash" : "heart"
                            )
                        }
                        Divider()
                        Button(action: { showingShareSheet = true }) {
                            Label("Share Recipe", systemImage: "square.and.arrow.up")
                        }
                        Button(action: exportRecipe) {
                            Label("Export Recipe", systemImage: "doc.text")
                        }
                        Divider()
                        Button(role: .destructive, action: { showingDeleteAlert = true }) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showCookMode) {
            EnhancedCookModeView(recipe: recipe)
        }
        .sheet(isPresented: $showingEdit) {
            ModernAddRecipeView(editingRecipe: recipe)
        }
        .sheet(isPresented: $showingAddToList) {
            AddRecipeIngredientsToListView(recipe: recipe)
        }
        .sheet(isPresented: $showingShareSheet) {
            let shareItems = RecipeExportService.shareRecipe(recipe)
            ShareSheet(items: shareItems)
        }
        .alert("Delete Recipe?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteRecipe()
            }
        } message: {
            Text("This action cannot be undone. You can undo this action within 5 seconds.")
        }
    }
    
    private func scaledIngredient(_ ingredient: RecipeIngredient) -> String {
        let unit = ingredient.unit ?? ""
        let name = ingredient.name ?? ""
            let rawAmount = ingredient.rawAmountString
            
            guard
                let servingsString = recipe.servings,
                let originalServings = Double(servingsString),
                originalServings > 0,
                let baseAmount = RecipeService.parseAmountString(rawAmount)
        else {
            return "\(rawAmount) \(unit) \(name)".trimmingCharacters(in: .whitespaces)
        }
        
        let scale = Double(currentServings) / originalServings
        let scaled = baseAmount * scale
        let formatted: String
        if scaled.truncatingRemainder(dividingBy: 1) == 0 {
            formatted = String(Int(scaled))
        } else {
            formatted = String(format: "%.2f", scaled)
        }
        
        return "\(formatted) \(unit) \(name)".trimmingCharacters(in: .whitespaces)
    }
    
    private func toggleFavorite() {
        lightHaptic()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            // Toggle favorite by changing rating
            recipe.rating = recipe.rating >= Int16(RecipeConstants.favoriteRatingThreshold) ? 0 : 5
        }
        
        do {
            try viewContext.save()
        } catch {
            print("Error saving recipe: \(error.localizedDescription)")
            handleRecipeError(error, context: "Failed to update favorite status")
        }
    }
    
    private func exportRecipe() {
        let text = RecipeExportService.exportRecipe(recipe)
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
    
    private func deleteRecipe() {
        // Store reference for undo (soft delete approach)
        deletedRecipe = recipe
        viewContext.delete(recipe)
        
        do {
            try viewContext.save()
            
            // Show undo toast/alert (simplified - in production use a toast system)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                // After 5 seconds, clear the undo reference
                deletedRecipe = nil
            }
            
            dismiss()
        } catch {
            print("Error deleting recipe: \(error.localizedDescription)")
            handleRecipeError(error, context: "Failed to delete recipe")
            deletedRecipe = nil
        }
    }
}

// MARK: - Add Recipe Ingredients to Shopping List
struct AddRecipeIngredientsToListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    let recipe: Recipe
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "cart.fill.badge.plus")
                    .font(.system(size: 60))
                    .foregroundColor(DesignSystem.Colors.accent)
                
                Text("Add Ingredients?")
                    .font(DesignSystem.Typography.title2)
                    .fontWeight(.semibold)
                
                Text("All ingredients from \"\(recipe.name ?? "this recipe")\" will be added to your shopping list.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button(action: addIngredientsToList) {
                        Text("Add to Shopping List")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(DesignSystem.Colors.accent)
                            .foregroundColor(.white)
                            .cornerRadius(DesignSystem.CornerRadius.lg)
                    }
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .padding()
            }
            .padding()
            .navigationTitle("Add Ingredients")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func addIngredientsToList() {
        do {
            try RecipeService.addRecipeIngredientsToShoppingList(recipe: recipe, in: viewContext)
            lightHaptic()
            dismiss()
        } catch {
            print("Failed to add ingredients: \(error.localizedDescription)")
            handleRecipeError(error, context: "Failed to add ingredients to shopping list")
        }
    }
}

// MARK: - Enhanced Cook Mode
struct EnhancedCookModeView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    
    @StateObject private var viewModel = CookModeViewModel()
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                    .foregroundColor(.white)
                            .padding()
                    }
                    Spacer()
                    Text("Cook Mode")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(viewModel.currentStepIndex + 1)/\(viewModel.steps.count)")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                }
                .background(Color.black.opacity(0.5))
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 4)
                        
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: geometry.size.width * CGFloat(viewModel.progress), height: 4)
                    }
                }
                .frame(height: 4)
                
                if let step = viewModel.currentStep {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Step \(viewModel.currentStepIndex + 1)")
                            .font(.title3)
                                    .foregroundColor(.white.opacity(0.7))
                                
                                Text(step.instruction)
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                                
                                if let timerMinutes = step.timerMinutes {
                                    timerView(for: step, minutes: timerMinutes)
                                        .environmentObject(viewModel)
                                }
                            }
                            
                            Spacer(minLength: 40)
                        }
                        .padding(32)
                    }
                } else {
                    completionView
                }
                
                HStack(spacing: 20) {
                    Button(action: { viewModel.previousStep() }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Previous")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(12)
                    }
                    .disabled(viewModel.currentStepIndex == 0)
                    .opacity(viewModel.currentStepIndex == 0 ? 0.3 : 1)
                    
                    Button(action: {
                        if viewModel.isComplete {
                            dismiss()
                        } else {
                            viewModel.nextStep()
                        }
                    }) {
                        HStack {
                            Text(viewModel.isComplete ? "Finish" : "Next")
                            Image(systemName: "chevron.right")
                        }
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        .cornerRadius(12)
                    }
            }
            .padding()
        }
    }
        .onAppear {
            viewModel.loadSteps(from: recipe.recipeSteps)
        }
    }
    
    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("Recipe Complete!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Great job! Your \(recipe.name ?? "recipe") is ready to enjoy.")
                .font(.title3)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .cornerRadius(12)
            }
            .padding()
        }
    }
    
    private func timerView(for step: RecipeStep, minutes: Int) -> some View {
        CookModeTimerView(step: step, minutes: minutes)
    }
}

// MARK: - Shopping List View
struct ShoppingListMainView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var sharedState: SharedStateManager
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ShoppingItemEntity.isChecked, ascending: true),
            NSSortDescriptor(keyPath: \ShoppingItemEntity.createdDate, ascending: false)
        ],
        animation: .spring()
    )
    private var shoppingItems: FetchedResults<ShoppingItemEntity>
    
    @State private var quickName = ""
    @State private var quickAmount = ""
    @State private var quickUnit = ""
    @State private var quickCategory: ShoppingCategory = .general
    @State private var quickCustomCategory = ""
    @FocusState private var quickNameFocused: Bool

    private var uncheckedCount: Int {
        shoppingItems.filter { !$0.isChecked }.count
    }

    private var groupedItems: [(category: String, items: [ShoppingItemEntity])] {
        let groups = Dictionary(grouping: shoppingItems) { item in
            let raw = item.category?.trimmingCharacters(in: .whitespacesAndNewlines)
            return raw?.isEmpty == false ? raw! : "General"
        }

        return groups
            .map { entry in
                (category: entry.key,
                 items: entry.value.sorted {
                    ($0.isChecked ? 1 : 0, $0.createdDate ?? .distantPast) <
                    ($1.isChecked ? 1 : 0, $1.createdDate ?? .distantPast)
                 })
            }
            .sorted { lhs, rhs in
                lhs.category.localizedCaseInsensitiveCompare(rhs.category) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 16) {
                    Button {
                        sharedState.toggleMenu()
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                    
                    Text("Shopping List")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                
            List {
                    Section {
                        QuickAddShoppingItemRow(
                            name: $quickName,
                            amount: $quickAmount,
                            unit: $quickUnit,
                            selectedCategory: $quickCategory,
                            customCategory: $quickCustomCategory,
                            onCommit: addQuickItem,
                            isNameFocused: $quickNameFocused
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } header: {
                        ShoppingListSummaryHeader(
                            totalItems: shoppingItems.count,
                            uncheckedCount: uncheckedCount
                        )
                    }

                    if shoppingItems.isEmpty {
                        EmptyShoppingListView(onAdd: { quickNameFocused = true })
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(groupedItems, id: \.category) { group in
                            Section(header: ShoppingListSectionHeader(
                                category: group.category,
                                uncheckedCount: group.items.filter { !$0.isChecked }.count
                            )) {
                                ForEach(group.items) { item in
                                    ShoppingListRow(
                                        item: item,
                                        onToggle: { toggle(item) }
                                    )
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteItem(item)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.horizontal, DesignSystem.Spacing.lg)
                .listRowInsets(EdgeInsets())
                .safeAreaInset(edge: .bottom) {
                    ShoppingListFooterBar(
                        itemCount: shoppingItems.count,
                        incompleteCount: uncheckedCount,
                        onClear: deleteAllItems
                    )
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func addQuickItem() {
        let trimmedName = quickName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCustomCategory = quickCustomCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        if quickCategory == .other && trimmedCustomCategory.isEmpty { return }

        // Check for duplicates (only unchecked items)
        let fetchRequest: NSFetchRequest<ShoppingItemEntity> = ShoppingItemEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "name == %@ AND isChecked == NO",
            trimmedName
        )
        fetchRequest.fetchLimit = 1
        
        if let existing = try? viewContext.fetch(fetchRequest), !existing.isEmpty {
            // Item already exists, just show a haptic feedback
            lightHaptic()
            return
        }

        let now = Date()
        let item = ShoppingItemEntity(context: viewContext)
        item.id = UUID()
        item.createdDate = now
        item.modifiedDate = now  // Critical for CloudKit sync
        item.name = trimmedName
        item.amount = quickAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        item.unit = quickUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCategory: String = {
            if quickCategory == .other {
                return trimmedCustomCategory.isEmpty ? "Other" : trimmedCustomCategory
            } else {
                return quickCategory.rawValue
            }
        }()
        item.category = resolvedCategory
        item.isChecked = false

        do {
            try viewContext.save()
            lightHaptic()
            quickName = ""
            quickAmount = ""
            quickUnit = ""
            quickCategory = .general
            quickCustomCategory = ""
            quickNameFocused = true
        } catch {
            print("Failed to save quick item: \(error.localizedDescription)")
            handleRecipeError(error, context: "Failed to add shopping item")
        }
    }

    private func toggle(_ item: ShoppingItemEntity) {
        lightHaptic()
        item.isChecked.toggle()
        item.modifiedDate = Date()  // Critical for CloudKit sync
        saveContext()
    }

    private func deleteItem(_ item: ShoppingItemEntity) {
            viewContext.delete(item)
        saveContext()
    }

    private func deleteAllItems() {
        guard !shoppingItems.isEmpty else { return }
        shoppingItems.forEach(viewContext.delete)
        saveContext()
    }
    
    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            print("Failed to save shopping items: \(error.localizedDescription)")
        }
    }
}

private struct EmptyShoppingListView: View {
    let onAdd: () -> Void
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "cart")
                .font(.system(size: 48, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.accent)
            
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("Your list is empty")
                    .font(DesignSystem.Typography.title3)
                    .fontWeight(.semibold)
                Text("Add items manually or from a recipe to start planning your next grocery run.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            
            Button(action: onAdd) {
                Label("Add Item", systemImage: "plus")
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.semibold)
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(DesignSystem.Colors.accent)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .fill(DesignSystem.Colors.backgroundSecondary)
        )
    }
}

private struct ShoppingListFooterBar: View {
    let itemCount: Int
    let incompleteCount: Int
    let onClear: () -> Void
    
    private var statusText: String {
        if itemCount == 0 {
            return "No items yet"
        } else if incompleteCount == 0 {
            return "\(itemCount) item\(itemCount == 1 ? "" : "s") • all checked"
        } else {
            return "\(itemCount) item\(itemCount == 1 ? "" : "s") • \(incompleteCount) to pick up"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0)
            
            HStack(spacing: DesignSystem.Spacing.md) {
                Label {
                    Text(statusText)
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.medium)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                } icon: {
                    Image(systemName: "cart")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.accent)
                }
                
                Spacer()
                
                Button(role: .destructive) {
                    guard itemCount > 0 else { return }
                    lightHaptic()
                    onClear()
                } label: {
                    Label("Clear List", systemImage: "trash")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.semibold)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(
                            Capsule()
                                .fill(DesignSystem.Colors.backgroundSecondary)
                        )
                }
                .disabled(itemCount == 0)
                .opacity(itemCount == 0 ? 0.4 : 1)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.md)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
        .background(.ultraThinMaterial)
        .background(
            Color(.systemBackground)
                .opacity(0.9)
        )
        .overlay(
            Divider()
                .padding(.top, -0.5),
            alignment: .top
        )
        .shadow(color: Color.black.opacity(0.04), radius: 18, y: -6)
    }
}

private struct ShoppingListSummaryHeader: View {
    let totalItems: Int
    let uncheckedCount: Int

    private var statusText: String {
        if totalItems == 0 { return "Ready to start shopping?" }
        if uncheckedCount == 0 { return "All items checked off!" }
        return "\(uncheckedCount) to pick up"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Grocery Run")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            HStack(spacing: 8) {
                Text(statusText)
                    .font(DesignSystem.Typography.headline)
                    .fontWeight(.semibold)

                Spacer()

                if totalItems > 0 {
                    Text("\(totalItems) items total")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.bottom, DesignSystem.Spacing.xs)
    }
}

private struct ShoppingListSectionHeader: View {
    let category: String
    let uncheckedCount: Int

    var body: some View {
        HStack {
            Text(category)
                .font(DesignSystem.Typography.caption)
                .fontWeight(.medium)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            if uncheckedCount > 0 {
                Text("\(uncheckedCount) remaining")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.top, DesignSystem.Spacing.xs)
    }
}

private struct QuickAddShoppingItemRow: View {
    @Binding var name: String
    @Binding var amount: String
    @Binding var unit: String
    @Binding var selectedCategory: ShoppingCategory
    @Binding var customCategory: String
    let onCommit: () -> Void
    @FocusState.Binding var isNameFocused: Bool

    private var canSubmit: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCustom = customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { return false }
        if selectedCategory == .other && trimmedCustom.isEmpty { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Quick Add")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                TextField("Add an item (e.g. \"Eggs\")", text: $name)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit { if canSubmit { onCommit() } }
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .fill(DesignSystem.Colors.backgroundTertiary)
                    )

                HStack(spacing: DesignSystem.Spacing.sm) {
                    TextField("Qty", text: $amount)
                        .submitLabel(.next)
                        .onSubmit { if canSubmit { onCommit() } }
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .frame(width: 90)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                .fill(DesignSystem.Colors.backgroundTertiary)
                        )

                    TextField("Unit", text: $unit)
                        .submitLabel(.next)
                        .onSubmit { if canSubmit { onCommit() } }
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .frame(width: 90)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                .fill(DesignSystem.Colors.backgroundTertiary)
                        )

                    Spacer(minLength: 0)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach(ShoppingCategory.allCases, id: \.self) { category in
                            let isSelected = selectedCategory == category
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    selectedCategory = category
                                }
                            } label: {
                                Label(category.rawValue, systemImage: category.icon)
                                    .font(DesignSystem.Typography.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, DesignSystem.Spacing.md)
                                    .padding(.vertical, DesignSystem.Spacing.sm)
                                    .background(
                                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                            .fill(isSelected ? DesignSystem.Colors.accent.opacity(0.18) : DesignSystem.Colors.backgroundTertiary)
                                    )
                                    .foregroundColor(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.xs)
                }

                if selectedCategory == .other {
                    TextField("Category name", text: $customCategory)
                        .submitLabel(.done)
                        .onSubmit { if canSubmit { onCommit() } }
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                .fill(DesignSystem.Colors.backgroundTertiary)
                        )
                }

                HStack {
                    Spacer()
                    Button(action: onCommit) {
                        Label("Add Item", systemImage: "plus")
                            .font(DesignSystem.Typography.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .background(DesignSystem.Colors.accent)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.4)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .fill(DesignSystem.Colors.backgroundSecondary)
            )
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
    }
}

private struct ShoppingListRow: View {
    let item: ShoppingItemEntity
    let onToggle: () -> Void

    private var amountText: String? {
        let amount = item.wrappedAmount
        let unit = item.wrappedUnit
        let combined = "\(amount) \(unit)".trimmingCharacters(in: .whitespaces)
        return combined.isEmpty ? nil : combined
    }

    private var categoryText: String? {
        let raw = (item.category ?? item.wrappedCategory).trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Button(action: onToggle) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(item.isChecked ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary)
                    .scaleEffect(item.isChecked ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: item.isChecked)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.wrappedName)
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(item.isChecked ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.textPrimary)
                    .strikethrough(item.isChecked, color: DesignSystem.Colors.textSecondary)

                HStack(spacing: 8) {
                    if let categoryText {
                        InfoChip(text: categoryText, icon: "tag.fill")
                    }
                    if let amountText {
                        InfoChip(text: amountText, icon: "scalemass")
                    }

                    if let source = item.recipeSource {
                        InfoChip(text: source, icon: "book.fill")
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .fill(DesignSystem.Colors.backgroundSecondary)
        )
    }
}

private struct InfoChip: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(DesignSystem.Typography.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DesignSystem.Colors.backgroundTertiary)
        .foregroundColor(DesignSystem.Colors.textSecondary)
        .clipShape(Capsule())
    }
}

private struct PantryItemRow: View {
    let item: PantryItemEntity

    private var quantityText: String? {
        let combined = "\(item.wrappedQuantity) \(item.wrappedUnit)".trimmingCharacters(in: .whitespaces)
        return combined.isEmpty ? nil : combined
    }

    private var expirationText: String? {
        guard let date = item.expirationDate else { return nil }
        return "Expires \(DateFormatter.shortDate.string(from: date))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text(item.wrappedName)
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.medium)
                Spacer()
                if let expirationText {
                    InfoChip(text: expirationText, icon: "calendar")
                }
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                if let quantityText {
                    InfoChip(text: quantityText, icon: "scalemass")
                }

                InfoChip(text: item.wrappedCategory.rawValue, icon: item.wrappedCategory.icon)
            }

            if !item.wrappedNotes.isEmpty {
                Text(item.wrappedNotes)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .fill(DesignSystem.Colors.backgroundSecondary)
        )
    }
}

struct AddShoppingItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var name = ""
    @State private var amount = ""
    @State private var unit = ""
    @State private var category = "Other"
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Item Name", text: $name)
                    TextField("Amount", text: $amount)
                    TextField("Unit", text: $unit)
                }
                
                Section("Category") {
                    TextField("Category", text: $category)
                }
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addItem()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func addItem() {
        let item = ShoppingItemEntity(context: viewContext)
        item.id = UUID()
        let now = Date()
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.amount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        item.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        item.category = category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Other" : category
        item.createdDate = now
        item.modifiedDate = now  // Critical for CloudKit sync
        item.isChecked = false
        
        do {
            try viewContext.save()
            lightHaptic()
            dismiss()
        } catch {
            print("Failed to save shopping item: \(error.localizedDescription)")
        }
    }
}

// MARK: - Pantry Main View (Fridge + Spices)
struct PantryMainView: View {
    @EnvironmentObject private var sharedState: SharedStateManager
    @State private var selectedCategory: PantryCategory = .fridge
    @State private var showingAddItem = false
    @Namespace private var animation
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Modern header with menu
                HStack(alignment: .center, spacing: 16) {
                    Button {
                        sharedState.toggleMenu()
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                    
                    Text("Pantry")
                        .font(.system(size: 28, weight: .bold, design: .default))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Spacer()
                    
                    Button {
                        lightHaptic()
                        showingAddItem = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .stroke(DesignSystem.Colors.textTertiary.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
                
                // Modern pill category selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PantryCategory.allCases, id: \.self) { category in
                            PantryCategoryPill(
                                category: category,
                                isSelected: selectedCategory == category,
                                namespace: animation
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedCategory = category
                                    lightHaptic()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 12)
                
                // Subtle divider
                Rectangle()
                    .fill(DesignSystem.Colors.textTertiary.opacity(0.1))
                    .frame(height: 1)
                
                // Content
                PantrySectionView(
                    category: selectedCategory,
                    onAddTapped: { showingAddItem = true }
                )
            }
            .background(DesignSystem.Colors.background)
            .navigationBarHidden(true)
        .sheet(isPresented: $showingAddItem) {
            AddPantryItemView(category: selectedCategory)
            }
        }
    }
}

// Modern pill-style category button
private struct PantryCategoryPill: View {
    let category: PantryCategory
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(category.rawValue)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textTertiary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(DesignSystem.Colors.backgroundSecondary)
                            .matchedGeometryEffect(id: "pill", in: namespace)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pantry Section View
struct PantrySectionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest private var items: FetchedResults<PantryItemEntity>
    
    private let category: PantryCategory
    private let onAddTapped: () -> Void
    
    init(category: PantryCategory, onAddTapped: @escaping () -> Void) {
        self.category = category
        self.onAddTapped = onAddTapped
        _items = FetchRequest(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \PantryItemEntity.expirationDate, ascending: true),
                NSSortDescriptor(keyPath: \PantryItemEntity.createdDate, ascending: false)
            ],
            predicate: NSPredicate(format: "category == %@", category.rawValue),
            animation: .default
        )
    }
    
    var body: some View {
            List {
            if items.isEmpty {
                EmptyPantrySectionView(category: category, onAdd: onAddTapped)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(items) { item in
                    PantryItemRowView(item: item)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteItem(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
    }
    
    private func deleteItem(_ item: PantryItemEntity) {
        viewContext.delete(item)
        saveContext()
        lightHaptic()
    }
    
    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            print("Failed to save pantry context: \(error.localizedDescription)")
        }
    }
}

private struct EmptyPantrySectionView: View {
    let category: PantryCategory
    let onAdd: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: category.icon)
                .font(.system(size: 32, weight: .light))
                .foregroundColor(DesignSystem.Colors.textTertiary.opacity(0.4))
            
            VStack(spacing: 4) {
                Text(category.emptyStateTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Text("Tap + to add items")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

// MARK: - Add Pantry Item View (Reusable)
struct AddPantryItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @FocusState private var isNameFocused: Bool
    
    let category: PantryCategory
    
    @State private var name = ""
    @State private var quantity = "1"
    @State private var unit = ""
    @State private var expirationDate = Date().addingTimeInterval(7 * 24 * 60 * 60) // Default 1 week
    @State private var hasExpiration = false
    
    private let commonUnits = ["", "oz", "lb", "g", "kg", "cups", "tbsp", "tsp", "ml", "L", "pcs"]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 24) {
                    // Name field - modern underline style
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ITEM NAME")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                            .tracking(0.5)
                        
                        TextField("What are you adding?", text: $name)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .focused($isNameFocused)
                        
                        Rectangle()
                            .fill(isNameFocused ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textTertiary.opacity(0.3))
                            .frame(height: 1)
                    }
                    
                    // Quantity and unit row
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("QTY")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                                .tracking(0.5)
                            
                            TextField("1", text: $quantity)
                                .font(.system(size: 17, weight: .regular))
                                .keyboardType(.numberPad)
                                .frame(width: 60)
                            
                            Rectangle()
                                .fill(DesignSystem.Colors.textTertiary.opacity(0.3))
                                .frame(width: 60, height: 1)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("UNIT")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                                .tracking(0.5)
                            
                            Menu {
                                ForEach(commonUnits, id: \.self) { u in
                                    Button(u.isEmpty ? "None" : u) {
                                        unit = u
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(unit.isEmpty ? "None" : unit)
                                        .font(.system(size: 17, weight: .regular))
                                        .foregroundColor(DesignSystem.Colors.textPrimary)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12))
                                        .foregroundColor(DesignSystem.Colors.textTertiary)
                                }
                            }
                            
                            Rectangle()
                                .fill(DesignSystem.Colors.textTertiary.opacity(0.3))
                                .frame(width: 80, height: 1)
                        }
                        
                        Spacer()
                    }
                    
                    // Expiration - cleaner toggle
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("EXPIRATION")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                                .tracking(0.5)
                            
                            Spacer()
                            
                            Toggle("", isOn: $hasExpiration)
                                .labelsHidden()
                                .tint(DesignSystem.Colors.textPrimary)
                        }
                        
                    if hasExpiration {
                            DatePicker("", selection: $expirationDate, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                    }
                }
                }
                .padding(24)
                
                Spacer()
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Add to \(category.rawValue)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        addItem()
                    } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(name.isEmpty ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.textPrimary)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isNameFocused = true
        }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    
    private func addItem() {
        let now = Date()
        let item = PantryItemEntity(context: viewContext)
        item.id = UUID()
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.quantity = quantity.isEmpty ? "1" : quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        item.unit = unit
        item.category = category.rawValue
        item.createdDate = now
        item.modifiedDate = now
        item.expirationDate = hasExpiration ? expirationDate : nil
        item.notes = ""
        
        do {
            try viewContext.save()
            lightHaptic()
            dismiss()
        } catch {
            print("Failed to save pantry item: \(error.localizedDescription)")
        }
    }
}