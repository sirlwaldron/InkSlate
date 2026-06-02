import SwiftUI
import CoreData
import PhotosUI

// MARK: - Main Tab View Wrapper
struct RecipeTabView: View {
    @StateObject private var recipeTimerController = RecipeTimerController()

    var body: some View {
        TabView {
            ModernRecipeMainView()
                .environmentObject(recipeTimerController)
                .tabItem {
                    Label("Recipes", systemImage: "book.fill")
                }

            ShoppingListMainView()
                .environmentObject(recipeTimerController)
                .tabItem {
                    Label("Shopping", systemImage: "cart.fill")
                }

            PantryMainView()
                .environmentObject(recipeTimerController)
                .tabItem {
                    Label("Pantry", systemImage: "refrigerator.fill")
                }
        }
    }
}

// MARK: - Modern Recipe Main View
struct ModernRecipeMainView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Recipe.createdDate, ascending: false)])
    private var allRecipes: FetchedResults<Recipe>

    @State private var searchText = ""
    @StateObject private var searchDebouncer = SearchDebouncer(delay: 0.25)
    @State private var showingAddRecipe = false
    @State private var showingFilters = false
    @State private var selectedCategory: RecipeCategory?
    @State private var selectedSort: SortOption = .dateNewest
    @State private var showFavoritesOnly = false
    @State private var showingStats = false
    @State private var displayedRecipes: [Recipe] = []

    private var filteredRecipes: [Recipe] { displayedRecipes }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        searchBar
                        filterChips

                        if filteredRecipes.isEmpty {
                            if searchText.isEmpty && selectedCategory == nil && !showFavoritesOnly {
                                ModernEmptyRecipesView()
                            } else {
                                SearchEmptyView(searchText: searchText.isEmpty ? "your filters" : searchText)
                            }
                        } else {
                            LazyVStack(spacing: DesignSystem.Spacing.md) {
                                ForEach(filteredRecipes, id: \.objectID) { recipe in
                                    ModernRecipeCard(recipe: recipe)
                                }
                            }
                        }

                        addCard
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.xl)
                }
                .refreshable { await refreshRecipes() }
            }
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: DesignSystem.Spacing.md) {
                        Button {
                            showingStats = true
                            lightHaptic()
                        } label: {
                            Image(systemName: "chart.bar")
                        }
                        Button {
                            showingAddRecipe = true
                            lightHaptic()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .onAppear {
            let ids = Set(allRecipes.compactMap { $0.id })
            RecipeImageStore.cleanupOrphanedImages(validRecipeIDs: ids)
            searchDebouncer.searchText = searchText
            fetchFilteredRecipes()
        }
        .onChange(of: searchText) { _, newValue in
            searchDebouncer.searchText = newValue
        }
        .onChange(of: searchDebouncer.debouncedText) { _, _ in
            fetchFilteredRecipes()
        }
        .onChange(of: selectedCategory) { _, _ in
            fetchFilteredRecipes()
        }
        .onChange(of: selectedSort) { _, _ in
            fetchFilteredRecipes()
        }
        .onChange(of: showFavoritesOnly) { _, _ in
            fetchFilteredRecipes()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: viewContext)) { _ in
            fetchFilteredRecipes()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudKitDataRefreshed)) { _ in
            fetchFilteredRecipes()
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

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DesignSystem.Colors.textSecondary)
            TextField("Search recipes, ingredients…", text: $searchText)
                .textFieldStyle(.plain)
                .font(DesignSystem.Typography.body)
            if !searchText.isEmpty {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        searchText = ""
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm + 2)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
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
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                            .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                    )
                    .cornerRadius(DesignSystem.CornerRadius.lg)
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
        Button(action: {
            showingAddRecipe = true
            lightHaptic()
        }) {
            HStack {
                Image(systemName: "plus")
                    .font(DesignSystem.Typography.title3)
                Text("Add recipe")
                    .font(DesignSystem.Typography.body)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.lg)
            .foregroundColor(DesignSystem.Colors.accent)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func fetchFilteredRecipes() {
        let query = searchDebouncer.debouncedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedCategory = selectedCategory
        let showFavoritesOnly = showFavoritesOnly
        let selectedSort = selectedSort

        let container = PersistenceController.shared.container
        let viewContext = viewContext

        Task.detached(priority: .userInitiated) {
            let bg = container.newBackgroundContext()
            bg.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

            let objectIDs: [NSManagedObjectID] = await bg.perform {
                let request = NSFetchRequest<NSManagedObjectID>(entityName: "Recipe")
                request.resultType = .managedObjectIDResultType
                request.fetchBatchSize = 50
                request.includesPendingChanges = true

                var predicates: [NSPredicate] = []

                if !query.isEmpty {
                    predicates.append(
                        NSPredicate(
                            format: "(name CONTAINS[cd] %@) OR (recipeDescription CONTAINS[cd] %@) OR (instructions CONTAINS[cd] %@) OR (SUBQUERY(ingredients, $i, $i.name CONTAINS[cd] %@).@count > 0)",
                            query, query, query, query
                        )
                    )
                }

                if let category = selectedCategory {
                    predicates.append(NSPredicate(format: "cuisine == %@", category.rawValue))
                }

                if showFavoritesOnly {
                    predicates.append(NSPredicate(format: "isFavorite == YES"))
                }

                if !predicates.isEmpty {
                    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                }

                request.sortDescriptors = sortDescriptors(for: selectedSort)

                return (try? bg.fetch(request)) ?? []
            }

            await MainActor.run {
                var recipes: [Recipe] = objectIDs.compactMap { id in
                    (try? viewContext.existingObject(with: id)) as? Recipe
                }
                if selectedSort == .quickest {
                    recipes.sort {
                        Int($0.prepTime + $0.cookTime) < Int($1.prepTime + $1.cookTime)
                    }
                }
                displayedRecipes = recipes
            }
        }
    }

    private func sortDescriptors(for option: SortOption) -> [NSSortDescriptor] {
        switch option {
        case .dateNewest:
            return [NSSortDescriptor(key: "createdDate", ascending: false)]
        case .dateOldest:
            return [NSSortDescriptor(key: "createdDate", ascending: true)]
        case .nameAZ:
            return [NSSortDescriptor(key: "name", ascending: true)]
        case .nameZA:
            return [NSSortDescriptor(key: "name", ascending: false)]
        case .ratingHigh:
            return [NSSortDescriptor(key: "rating", ascending: false)]
        case .ratingLow:
            return [NSSortDescriptor(key: "rating", ascending: true)]
        case .quickest:
            return [NSSortDescriptor(key: "createdDate", ascending: false)]
        }
    }

    private func refreshRecipes() async {
        try? await Task.sleep(for: .milliseconds(350))
        await MainActor.run {
            fetchFilteredRecipes()
        }
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
            }
            .foregroundColor(color)
            
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.md)
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
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
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        Text("Statistics")
                            .font(DesignSystem.Typography.largeTitle)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        Text("Totals and categories")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .padding(.top)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                        RecipeStatCard(
                            title: "Total Recipes",
                            value: "\(recipes.count)",
                            icon: "book.fill",
                            color: DesignSystem.Colors.accent
                        )
                        
                        RecipeStatCard(
                            title: "Favorites",
                            value: "\(recipes.filter { $0.isFavorite }.count)",
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
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        Text("Categories")
                            .font(DesignSystem.Typography.title3)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
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
                                        .foregroundColor(DesignSystem.Colors.accent)
                                }
                                .padding(DesignSystem.Spacing.md)
                                .background(DesignSystem.Colors.surface)
                                .cornerRadius(DesignSystem.CornerRadius.md)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                        .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                                )
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Statistics")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
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
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm + 2)
            .background(isActive ? DesignSystem.Colors.accent : DesignSystem.Colors.backgroundSecondary)
            .foregroundColor(isActive ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textPrimary)
            .cornerRadius(DesignSystem.CornerRadius.lg)
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
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Enhanced Recipe Card
struct ModernRecipeCard: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var recipeTimers: RecipeTimerController
    @State private var showingDetail = false
    @State private var isPressed = false
    @ObservedObject var recipe: Recipe

    private var activeTimerRows: [RecipeCardTimerRow] {
        recipeTimers.activeTimerRows(for: recipe)
    }

    var body: some View {
        Button(role: .none, action: { showingDetail = true }) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(alignment: .top, spacing: 12) {
                    RecipeCardImage(path: recipe.imageUrl)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.name ?? "Untitled Recipe")
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .lineLimit(1)

                        if let cuisine = recipe.cuisine, !cuisine.isEmpty {
                            Text(cuisine)
                                .font(DesignSystem.Typography.caption)
                                .fontWeight(.medium)
                                .foregroundColor(DesignSystem.Colors.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(DesignSystem.Colors.accent.opacity(0.12))
                                .cornerRadius(6)
                        }

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

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .padding(.top, 2)
                }

                if !activeTimerRows.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(activeTimerRows) { row in
                                HStack(spacing: 4) {
                                    Image(systemName: row.isRunning ? "timer" : "pause.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(DesignSystem.Colors.accent)
                                    Text(row.title)
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                    Text(recipeTimers.timeString(from: row.remainingSeconds))
                                        .font(DesignSystem.Typography.caption)
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                        .foregroundColor(row.remainingSeconds <= 10 ? DesignSystem.Colors.error : DesignSystem.Colors.textPrimary)
                                }
                                .padding(.horizontal, DesignSystem.Spacing.md)
                                .padding(.vertical, 5)
                                .background(DesignSystem.Colors.accent.opacity(0.1))
                                .cornerRadius(DesignSystem.CornerRadius.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                                        .stroke(DesignSystem.Colors.accent.opacity(0.22), lineWidth: 0.5)
                                )
                            }
                        }
                    }
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDetail) {
            ModernRecipeDetailView(recipe: recipe)
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
    @State private var image: PlatformImage?
    
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
            } else if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .task(id: path) {
            guard let path, !path.hasPrefix("http") else {
                image = nil
                return
            }
            image = await RecipeImageStore.loadDisplayImage(path: path)
        }
    }
    
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
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
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "book.closed")
                .font(.system(size: 44))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("No recipes yet")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Tap + to add your first recipe.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

struct SearchEmptyView: View {
    let searchText: String
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("No matches")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Nothing matches “\(searchText)”. Try different words or filters.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Add/Edit Recipe
struct ModernAddRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let editingRecipe: Recipe?

    private enum EditorSection: String, CaseIterable, Identifiable {
        case basics = "Basics"
        case ingredients = "Ingredients"
        case steps = "Steps"
        case notes = "Notes"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .basics: return "slider.horizontal.3"
            case .ingredients: return "carrot"
            case .steps: return "list.number"
            case .notes: return "note.text"
            }
        }
    }
    
    @State private var activeSection: EditorSection = .basics
    @State private var showValidation = false
    
    @State private var name = ""
    @State private var recipeDescription = ""
    @State private var selectedCategory: RecipeCategory = .dinner
    @State private var rating = 0
    @State private var imageItem: PhotosPickerItem?
    @State private var imagePreview: PlatformImage?
    @State private var existingImagePath: String = ""
    @State private var selectedImageData: Data?
    @State private var isSavingRecipe = false
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

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Picker("Section", selection: $activeSection) {
                            ForEach(EditorSection.allCases) { section in
                                Label(section.rawValue, systemImage: section.icon)
                                    .tag(section)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        if showValidation && !canSave {
                            validationHint
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    
                    Group {
                        switch activeSection {
                        case .basics:
                            basicsSection
                        case .ingredients:
                            IngredientsSection(ingredients: $ingredients)
                        case .steps:
                            StepsSection(steps: $steps)
                        case .notes:
                            notesSection
                        }
                    }
                    
                    Button(action: attemptSave) {
                        Text(editingRecipe == nil ? "Save Recipe" : "Update Recipe")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(DesignSystem.Colors.textInverse)
                            .background(DesignSystem.Colors.accent)
                            .cornerRadius(DesignSystem.CornerRadius.md)
                    }
                    .disabled(!canSave || isSavingRecipe)
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle(editingRecipe == nil ? "New Recipe" : "Edit Recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(editingRecipe == nil ? "Save" : "Update") {
                        attemptSave()
                    }
                    .disabled(!canSave || isSavingRecipe)
                }
            }
        }
        .onAppear {
            loadRecipeData()
        }
    }

    private var validationHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("To save, add:")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            VStack(alignment: .leading, spacing: 4) {
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("Recipe name", systemImage: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            .font(DesignSystem.Typography.caption)
        }
        .padding()
        .background(DesignSystem.Colors.backgroundSecondary)
        .cornerRadius(DesignSystem.CornerRadius.md)
    }
    
    private var basicsSection: some View {
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
                       let image = platformImage(from: data) {
                        selectedImageData = data
                        imagePreview = image
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                TextField("Recipe Name", text: $name)
                    .textFieldStyle(MinimalistInputFieldStyle(state: .normal))
                    .font(DesignSystem.Typography.title2)
                
                TextField("Description (optional)", text: $recipeDescription, axis: .vertical)
                    .textFieldStyle(MinimalistInputFieldStyle(state: .normal))
                    .lineLimit(3...6)
            }
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
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
                                }
                                .tag(category)
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
            
            DisclosureGroup {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 8) {
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
                            .foregroundColor(selectedTags.contains(tag) ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textPrimary)
                            .cornerRadius(DesignSystem.CornerRadius.md)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Dietary Tags")
                        .font(DesignSystem.Typography.title3)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    if !selectedTags.isEmpty {
                        Text("\(selectedTags.count)")
                            .font(DesignSystem.Typography.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(DesignSystem.Colors.backgroundSecondary)
                            .cornerRadius(12)
                    }
                }
            }
            .padding()
            .background(DesignSystem.Colors.backgroundSecondary)
            .cornerRadius(DesignSystem.CornerRadius.md)
        }
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            TextField("Tips, substitutions, or anything to remember...", text: $notesText, axis: .vertical)
                .textFieldStyle(MinimalistInputFieldStyle(state: .normal))
                .lineLimit(4...10)
        }
    }
    
    private func attemptSave() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            withAnimation(.spring()) {
                showValidation = true
            }
            activeSection = .basics
            lightHaptic()
            return
        }
        showValidation = false
        Task { await saveRecipe() }
    }
    
    private var imageSection: some View {
        Group {
            if let image = currentImagePreview {
                Image(platformImage: image)
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
    
    private var currentImagePreview: PlatformImage? {
        if let imagePreview {
            return imagePreview
        }
        return nil
    }
    
    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
            .fill(DesignSystem.Colors.backgroundSecondary)
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
        Task {
            let path = existingImagePath
            guard !path.isEmpty else { return }
            imagePreview = await RecipeImageStore.loadDisplayImage(path: path)
        }
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
                    id: ingredient.id ?? UUID(),
                    name: ingredient.name ?? "",
                    amount: ingredient.notes?.isEmpty == false ? ingredient.notes! : ingredient.formattedAmount,
                    unit: ingredient.unit ?? ""
                )
            }
        }
    }

    @MainActor
    private func saveRecipe() async {
        guard !isSavingRecipe else { return }
        isSavingRecipe = true
        defer { isSavingRecipe = false }

        let recipe = editingRecipe ?? Recipe(context: viewContext)
        
        if recipe.id == nil {
            recipe.id = UUID()
            recipe.createdDate = Date()
            recipe.isFavorite = false
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
        
        var imageAttachmentFailed = false
        let previousImagePath = recipe.imageUrl

        if let data = selectedImageData, let recipeID = recipe.id, let image = platformImage(from: data) {
            if RecipeValidation.validateImageData(data) {
                do {
                    let recordName = try await CloudKitAssetService.shared.uploadRecipePhoto(image, for: recipeID)
                    recipe.imageUrl = recordName
                    existingImagePath = recordName
                    imagePreview = image
                    selectedImageData = nil
                    await deleteRecipeImageAsset(at: previousImagePath, excluding: recordName)
                    if let previousImagePath, !RecipeImageStore.isCloudRecordName(previousImagePath) {
                        RecipeImageStore.deleteImage(at: previousImagePath)
                    }
                } catch {
                    imageAttachmentFailed = true
                }
            } else {
                imageAttachmentFailed = true
            }
        } else if let recipeID = recipe.id,
                  let path = recipe.imageUrl,
                  !path.isEmpty,
                  !RecipeImageStore.isCloudRecordName(path),
                  !path.hasPrefix("http"),
                  let localImage = await RecipeImageStore.loadImage(path: path) {
            do {
                let recordName = try await CloudKitAssetService.shared.uploadRecipePhoto(localImage, for: recipeID)
                recipe.imageUrl = recordName
                existingImagePath = recordName
                RecipeImageStore.deleteImage(at: path)
            } catch {
                imageAttachmentFailed = true
            }
        } else if let currentPath = recipe.imageUrl, currentPath.isEmpty {
            recipe.imageUrl = nil
        } else if recipe.imageUrl == nil && !existingImagePath.isEmpty {
            recipe.imageUrl = existingImagePath
        }
        
        let now = Date()
        let existingIngredients: [RecipeIngredient] = (recipe.ingredients?.allObjects as? [RecipeIngredient]) ?? []
        let existingByID: [UUID: RecipeIngredient] = Dictionary(
            uniqueKeysWithValues: existingIngredients.compactMap { ing in
                guard let id = ing.id else { return nil }
                return (id, ing)
            }
        )

        let incomingIDs = Set(ingredients.map(\.id))

        for existing in existingIngredients {
            if let id = existing.id, !incomingIDs.contains(id) {
                viewContext.delete(existing)
            }
        }

        for ingredientData in ingredients {
            let ingredient = existingByID[ingredientData.id] ?? RecipeIngredient(context: viewContext)

            if ingredient.id == nil {
                ingredient.id = ingredientData.id
                ingredient.createdDate = now
                ingredient.recipe = recipe
            }

            ingredient.modifiedDate = now
            ingredient.name = ingredientData.name
            let rawAmount = ingredientData.amount.trimmingCharacters(in: .whitespacesAndNewlines)
            ingredient.amount = RecipeService.parseAmountString(rawAmount) ?? 0.0
            ingredient.notes = rawAmount
            ingredient.unit = ingredientData.unit
            ingredient.recipe = recipe
        }
        
        if viewContext.inkSlateSave(module: "Recipes") {
            if imageAttachmentFailed {
                ErrorHandlingService.shared.reportOperationFailure(
                    module: "Recipes",
                    detail: "Your recipe was saved, but the photo couldn't be attached. Try adding it again."
                )
            }
            lightHaptic()
            dismiss()
        }
    }

    private func deleteRecipeImageAsset(at path: String?, excluding keepRecordName: String? = nil) async {
        guard let path, !path.isEmpty, path != keepRecordName else { return }
        if RecipeImageStore.isCloudRecordName(path) {
            try? await CloudKitAssetService.shared.deleteRecipePhoto(recordName: path)
        } else {
            RecipeImageStore.deleteImage(at: path)
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
                ForEach(ingredients) { ingredient in
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
                                ingredients.removeAll { $0.id == ingredient.id }
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
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Picker("Unit", selection: $unit) {
                    ForEach(units, id: \.self) { unit in
                        Text(unit).tag(unit)
                    }
                }
            }
            .navigationTitle("Add Ingredient")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
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
                    .foregroundColor(DesignSystem.Colors.textPrimary)
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
                    Stepper("Timer: \(timerMinutes) minutes", value: $timerMinutes, in: 1...720, step: 1)
                    HStack(spacing: 10) {
                        Button("+1 hr") {
                            timerMinutes = min(720, timerMinutes + 60)
                            lightHaptic()
                        }
                        .buttonStyle(.bordered)
                        Button("+15m") {
                            timerMinutes = min(720, timerMinutes + 15)
                            lightHaptic()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .navigationTitle("Add Step")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
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
    @State private var shareItems: [Any] = []
    @State private var currentServings: Int
    @State private var headerImage: PlatformImage?
    
    init(recipe: Recipe) {
        self.recipe = recipe
        _currentServings = State(initialValue: Int(recipe.servings ?? "1") ?? 1)
    }

    private var cookTimerStep: RecipeStep {
        RecipeStep(id: RecipeTimerStepID.cookTime(for: recipe), instruction: "Cook time", timerMinutes: nil)
    }

    var body: some View {
        NavigationStack {
        ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                if let headerImage {
                    Image(platformImage: headerImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 300)
                        .clipped()
                        .cornerRadius(DesignSystem.CornerRadius.md)
                        .shadow(color: DesignSystem.Shadows.small, radius: 3, x: 0, y: 1)
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
                    .shadow(color: DesignSystem.Shadows.small, radius: 3, x: 0, y: 1)
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
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
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
                                    HStack(spacing: 6) {
                                        Image(systemName: "flame")
                                            .font(DesignSystem.Typography.body)
                                            .foregroundColor(DesignSystem.Colors.textSecondary)
                                        CookModeTimerView(step: cookTimerStep, minutes: Int(recipe.cookTime), recipeName: recipe.name)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                        
                        let dietary = Array(recipe.dietaryTagsSet).sorted { $0.rawValue < $1.rawValue }
                        if !dietary.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Dietary")
                                    .font(DesignSystem.Typography.title3)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)],
                                    alignment: .leading,
                                    spacing: 8
                                ) {
                                    ForEach(dietary, id: \.self) { tag in
                                        Label(tag.rawValue, systemImage: tag.icon)
                                            .font(DesignSystem.Typography.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(DesignSystem.Colors.backgroundSecondary)
                                            .cornerRadius(DesignSystem.CornerRadius.md)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        let ingredients = recipe.ingredientsArray
                        if !ingredients.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                Text("Ingredients")
                                    .font(DesignSystem.Typography.title3)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
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
                                    .foregroundColor(DesignSystem.Colors.accent)
                                    .background(DesignSystem.Colors.surface)
                                    .cornerRadius(DesignSystem.CornerRadius.md)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                            .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                                    )
                                }
                            }
                        }
                        
                        Divider()
                        
                        let steps = recipe.recipeSteps
                        if !steps.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Instructions")
                                    .font(DesignSystem.Typography.title3)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                
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
                                                CookModeTimerView(step: step, minutes: timer, recipeName: recipe.name)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(.leading, 22)
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
                                    .foregroundColor(DesignSystem.Colors.textInverse)
                                    .background(DesignSystem.Colors.accent)
                                    .cornerRadius(DesignSystem.CornerRadius.md)
                                }
                            }
                        }
                        
                        if !recipe.recipeNotes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notes")
                                    .font(DesignSystem.Typography.title3)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
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
            .navigationTitle(recipe.name ?? "Recipe")
            .inlineNavigationTitle()
        .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: { showingEdit = true }) {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(action: toggleFavorite) {
                            Label(
                                recipe.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                                systemImage: recipe.isFavorite ? "heart.slash" : "heart"
                            )
                        }
                        Divider()
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
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showCookMode) {
            EnhancedCookModeView(recipe: recipe)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingEdit) {
            ModernAddRecipeView(editingRecipe: recipe)
        }
        .sheet(isPresented: $showingAddToList) {
            AddRecipeIngredientsToListView(recipe: recipe)
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: shareItems)
        }
        .alert("Delete Recipe?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteRecipe()
            }
        } message: {
            Text("This will permanently delete this recipe. This action cannot be undone.")
        }
        .task(id: recipe.imageUrl) {
            guard let path = recipe.imageUrl, !path.hasPrefix("http") else {
                headerImage = nil
                return
            }
            headerImage = await RecipeImageStore.loadDisplayImage(path: path)
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
            recipe.isFavorite.toggle()
        }

        _ = viewContext.inkSlateSave(module: "Recipes")
    }

    private func exportRecipe() {
        shareItems = RecipeExportService.shareRecipe(recipe)
        showingShareSheet = true
    }
    
    private func deleteRecipe() {
        let imagePath = recipe.imageUrl
        viewContext.delete(recipe)

        if viewContext.inkSlateSave(module: "Recipes") {
            Task {
                await deleteRecipeImageAsset(at: imagePath)
            }
            dismiss()
        }
    }

    private func deleteRecipeImageAsset(at path: String?, excluding keepRecordName: String? = nil) async {
        guard let path, !path.isEmpty, path != keepRecordName else { return }
        if RecipeImageStore.isCloudRecordName(path) {
            try? await CloudKitAssetService.shared.deleteRecipePhoto(recordName: path)
        } else {
            RecipeImageStore.deleteImage(at: path)
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
            .inlineNavigationTitle()
        }
    }
    
    private func addIngredientsToList() {
        do {
            try RecipeService.addRecipeIngredientsToShoppingList(recipe: recipe, in: viewContext)
            lightHaptic()
            dismiss()
        } catch {
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
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(DesignSystem.Colors.backgroundTertiary)
                            .frame(height: 4)
                        Capsule()
                            .fill(DesignSystem.Colors.accent)
                            .frame(width: max(4, geometry.size.width * CGFloat(min(1, viewModel.progress))), height: 4)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.top, DesignSystem.Spacing.sm)
                
                if viewModel.steps.isEmpty {
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        Spacer()
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 48))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        Text("No cooking steps yet")
                            .font(DesignSystem.Typography.title3)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        Text("Add steps in the recipe editor, then try Cook Mode again.")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DesignSystem.Spacing.xl)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let step = viewModel.currentStep {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                                Text("Step \(viewModel.currentStepIndex + 1)")
                                    .font(DesignSystem.Typography.title3)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                
                                Text(step.instruction)
                                    .font(DesignSystem.Typography.title2)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                    .multilineTextAlignment(.leading)
                                
                                if let timerMinutes = step.timerMinutes {
                                    timerView(for: step, minutes: timerMinutes)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            Spacer(minLength: DesignSystem.Spacing.xxl)
                        }
                        .padding(DesignSystem.Spacing.lg)
                    }
                } else {
                    completionView
                }
                
                if viewModel.steps.isEmpty {
                    Button(action: { dismiss() }) {
                        Text("Close")
                            .frame(maxWidth: .infinity)
                    }
                    .minimalistButton(variant: .primary, size: .large)
                    .padding(DesignSystem.Spacing.lg)
                } else {
                    HStack(spacing: DesignSystem.Spacing.md) {
                        Button(action: { viewModel.previousStep() }) {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Previous")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .minimalistButton(variant: .secondary, size: .large)
                        .disabled(viewModel.currentStepIndex == 0)
                        .opacity(viewModel.currentStepIndex == 0 ? 0.35 : 1)

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
                            .frame(maxWidth: .infinity)
                        }
                        .minimalistButton(variant: .primary, size: .large)
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface)
                    .overlay(
                        Rectangle()
                            .fill(DesignSystem.Colors.border.opacity(0.5))
                            .frame(height: 0.5),
                        alignment: .top
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.background.ignoresSafeArea())
            .navigationTitle("Cook Mode")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Text("\(viewModel.steps.isEmpty ? "—" : "\(min(viewModel.currentStepIndex + 1, viewModel.steps.count))/\(viewModel.steps.count)")")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .onAppear {
            viewModel.loadSteps(from: recipe.recipeSteps)
        }
    }
    
    private var completionView: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(DesignSystem.Colors.success)
            
            Text("Recipe complete")
                .font(DesignSystem.Typography.largeTitle)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Text("Great job! Your \(recipe.name ?? "recipe") is ready to enjoy.")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.lg)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .minimalistButton(variant: .primary, size: .large)
            .padding(DesignSystem.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
    }
    
    private func timerView(for step: RecipeStep, minutes: Int) -> some View {
        CookModeTimerView(step: step, minutes: minutes, recipeName: recipe.name)
    }
}

// MARK: - Shopping List View
struct ShoppingListMainView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @SectionedFetchRequest(
        sectionIdentifier: \ShoppingItemEntity.category,
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ShoppingItemEntity.category, ascending: true),
            NSSortDescriptor(keyPath: \ShoppingItemEntity.isChecked, ascending: true),
            NSSortDescriptor(keyPath: \ShoppingItemEntity.createdDate, ascending: false)
        ],
        animation: .spring()
    )
    private var shoppingSections: SectionedFetchResults<String?, ShoppingItemEntity>
    
    @State private var quickName = ""
    @State private var quickAmount = ""
    @State private var quickUnit = ""
    @State private var quickCategory: ShoppingCategory = .general
    @State private var quickCustomCategory = ""
    @FocusState private var quickNameFocused: Bool

    private var allShoppingItems: [ShoppingItemEntity] {
        shoppingSections.flatMap { Array($0) }
    }

    private var uncheckedCount: Int {
        allShoppingItems.filter { !$0.isChecked }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                VStack(spacing: 0) {
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
                        ShoppingListSummaryHeader(totalItems: allShoppingItems.count, uncheckedCount: uncheckedCount)
                    }

                    if allShoppingItems.isEmpty {
                        EmptyShoppingListView(onAdd: { quickNameFocused = true })
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(shoppingSections, id: \.id) { section in
                            let rawCategory = (section.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            let category = rawCategory.isEmpty ? "General" : rawCategory
                            Section(
                                header: ShoppingListSectionHeader(
                                    category: category,
                                    uncheckedCount: section.filter { !$0.isChecked }.count
                                )
                            ) {
                                ForEach(section) { item in
                                    ShoppingListRow(
                                        item: item,
                                        onToggle: { toggle(item) }
                                    )
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(DesignSystem.Colors.surface)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteItem(item)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .contextMenu {
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
                        itemCount: allShoppingItems.count,
                        incompleteCount: uncheckedCount,
                        onClear: deleteAllItems
                    )
                }
                }
            }
            .navigationTitle("Shopping")
        }
    }

    private func addQuickItem() {
        let trimmedName = quickName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCustomCategory = quickCustomCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        if quickCategory == .other && trimmedCustomCategory.isEmpty { return }

        let fetchRequest: NSFetchRequest<ShoppingItemEntity> = ShoppingItemEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "name == %@ AND isChecked == NO",
            trimmedName
        )
        fetchRequest.fetchLimit = 1
        
        if let existing = try? viewContext.fetch(fetchRequest), !existing.isEmpty {
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

        if viewContext.inkSlateSave(module: "Recipes") {
            lightHaptic()
            quickName = ""
            quickAmount = ""
            quickUnit = ""
            quickCategory = .general
            quickCustomCategory = ""
            quickNameFocused = true
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
        let items = allShoppingItems
        guard !items.isEmpty else { return }
        items.forEach(viewContext.delete)
        saveContext()
    }
    
    private func saveContext() {
        _ = viewContext.inkSlateSave(module: "Recipes")
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

    @State private var showingClearConfirm = false
    
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
                    showingClearConfirm = true
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
            Color.adaptiveSystemBackground
                .opacity(0.9)
        )
        .confirmationDialog(
            "Clear shopping list?",
            isPresented: $showingClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete all items", role: .destructive) {
                lightHaptic()
                onClear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all items from your shopping list.")
        }
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
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

        if viewContext.inkSlateSave(module: "Recipes") {
            lightHaptic()
            dismiss()
        }
    }
}

// MARK: - Pantry Main View
struct PantryMainView: View {
    @State private var selectedCategory: PantryCategory = .fridge
    @State private var showingAddItem = false
    @State private var searchText = ""
    @Namespace private var animation
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack(spacing: DesignSystem.Spacing.md) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        TextField("Search \(selectedCategory.rawValue)", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(DesignSystem.Typography.body)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                lightHaptic()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm + 2)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                    )
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DesignSystem.Spacing.sm) {
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
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                    }
                    .padding(.bottom, DesignSystem.Spacing.md)
                    
                    Rectangle()
                        .fill(DesignSystem.Colors.border.opacity(0.35))
                        .frame(height: 0.5)
                    
                    PantrySectionView(
                        category: selectedCategory,
                        searchText: $searchText,
                        onAddTapped: { showingAddItem = true }
                    )
                    .id(selectedCategory)
                }
            }
            .navigationTitle("Pantry")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        lightHaptic()
                        showingAddItem = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddItem) {
                AddPantryItemView(category: selectedCategory)
            }
        }
    }
}

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
    @Binding private var searchText: String
    @FocusState private var quickNameFocused: Bool
    
    @State private var quickName = ""
    @State private var quickQuantity = "1"
    @State private var quickUnit = ""
    
    private let category: PantryCategory
    private let onAddTapped: () -> Void
    
    init(category: PantryCategory, searchText: Binding<String>, onAddTapped: @escaping () -> Void) {
        self.category = category
        self._searchText = searchText
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
        let filteredItems = items.filter { item in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return item.wrappedName.localizedCaseInsensitiveContains(query)
        }
        
        List {
            Section {
                QuickAddPantryItemRow(
                    name: $quickName,
                    quantity: $quickQuantity,
                    unit: $quickUnit,
                    category: category,
                    onCommit: addQuickItem,
                    onAddDetails: onAddTapped,
                    isNameFocused: $quickNameFocused
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if items.isEmpty {
                EmptyPantrySectionView(category: category, onAdd: { quickNameFocused = true })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if filteredItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textTertiary.opacity(0.6))
                    
                    Text("No matches")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    if !searchText.isEmpty {
                        Button("Clear search") {
                            searchText = ""
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(filteredItems) { item in
                    PantryItemRowView(item: item)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(DesignSystem.Colors.surface)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteItem(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
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
        .scrollContentBackground(.hidden)
    }
    
    private func addQuickItem() {
        let trimmedName = quickName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let now = Date()
        let item = PantryItemEntity(context: viewContext)
        item.id = UUID()
        item.name = trimmedName
        let qty = quickQuantity.trimmingCharacters(in: .whitespacesAndNewlines)
        item.quantity = qty.isEmpty ? "1" : qty
        item.unit = quickUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        item.category = category.rawValue
        item.createdDate = now
        item.modifiedDate = now
        item.notes = ""

        if viewContext.inkSlateSave(module: "Pantry") {
            quickName = ""
            quickQuantity = "1"
            quickUnit = ""
            lightHaptic()
        }
    }
    
    private func deleteItem(_ item: PantryItemEntity) {
        viewContext.delete(item)
        saveContext()
        lightHaptic()
    }
    
    private func saveContext() {
        _ = viewContext.inkSlateSave(module: "Pantry")
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
                
                Text("Use Quick Add above, or tap the button below")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onAdd) {
                Label("Add Item", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(DesignSystem.Colors.accent)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

private struct QuickAddPantryItemRow: View {
    @Binding var name: String
    @Binding var quantity: String
    @Binding var unit: String
    let category: PantryCategory
    let onCommit: () -> Void
    let onAddDetails: () -> Void
    @FocusState.Binding var isNameFocused: Bool

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Label("Quick Add", systemImage: category.icon)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Spacer()
                Button("More options…", action: onAddDetails)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.accent)
            }

            TextField("Add to \(category.rawValue) (e.g. Milk)", text: $name)
                .focused($isNameFocused)
                .submitLabel(.done)
                .onSubmit { if canSubmit { onCommit() } }
                .textFieldStyle(.plain)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .fill(DesignSystem.Colors.backgroundTertiary)
                )

            HStack(spacing: DesignSystem.Spacing.sm) {
                TextField("Qty", text: $quantity)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .submitLabel(.done)
                    .onSubmit { if canSubmit { onCommit() } }
                    .textFieldStyle(.plain)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .frame(width: 72)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .fill(DesignSystem.Colors.backgroundTertiary)
                    )

                TextField("Unit", text: $unit)
                    .submitLabel(.done)
                    .onSubmit { if canSubmit { onCommit() } }
                    .textFieldStyle(.plain)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .frame(width: 88)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .fill(DesignSystem.Colors.backgroundTertiary)
                    )

                Spacer(minLength: 0)

                Button(action: onCommit) {
                    Label("Add", systemImage: "plus")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(canSubmit ? DesignSystem.Colors.accent : DesignSystem.Colors.backgroundTertiary)
                        .foregroundColor(canSubmit ? .white : DesignSystem.Colors.textTertiary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
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
    @State private var expirationDate = Date().addingTimeInterval(7 * 24 * 60 * 60)
    @State private var hasExpiration = false
    
    private let commonUnits = ["", "oz", "lb", "g", "kg", "cups", "tbsp", "tsp", "ml", "L", "pcs"]
    private let spiceUnits = ["", "pinch", "dash", "tsp", "tbsp", "g", "oz", "jar", "tin", "bottle", "packet", "stick", "pcs"]
    
    private var unitMenuOptions: [String] {
        category == .spices ? spiceUnits : commonUnits
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 24) {
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
                    
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("QTY")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                                .tracking(0.5)
                            
                            TextField("1", text: $quantity)
                                .font(.system(size: 17, weight: .regular))
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
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
                                ForEach(unitMenuOptions, id: \.self) { u in
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
            .inlineNavigationTitle()
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

        if viewContext.inkSlateSave(module: "Pantry") {
            lightHaptic()
            dismiss()
        }
    }
}