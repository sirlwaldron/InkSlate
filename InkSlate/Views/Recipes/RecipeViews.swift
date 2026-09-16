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
    @State private var selectedCategory: RecipeCategory?
    @State private var selectedSort: SortOption = .dateNewest
    @State private var showFavoritesOnly = false
    @State private var showingStats = false
    @State private var displayedRecipes: [Recipe] = []
    @State private var recipePendingDelete: Recipe?
    @State private var filterGeneration = 0

    private var filteredRecipes: [Recipe] { displayedRecipes }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                List {
                    if filteredRecipes.isEmpty {
                        Group {
                            if searchText.isEmpty && selectedCategory == nil && !showFavoritesOnly {
                                ModernEmptyRecipesView(onAdd: { showingAddRecipe = true })
                            } else {
                                SearchEmptyView(searchText: searchText.isEmpty ? "your filters" : searchText)
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: DesignSystem.Spacing.xl, leading: DesignSystem.Spacing.lg, bottom: 0, trailing: DesignSystem.Spacing.lg))
                    } else {
                        ForEach(filteredRecipes, id: \.objectID) { recipe in
                            RecipeCardRow(
                                recipe: recipe,
                                onDelete: { recipePendingDelete = recipe }
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(
                                top: DesignSystem.Spacing.xs + 2,
                                leading: DesignSystem.Spacing.lg,
                                bottom: DesignSystem.Spacing.xs + 2,
                                trailing: DesignSystem.Spacing.lg
                            ))
                        }
                        
                        addCard
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(
                                top: DesignSystem.Spacing.xs + 2,
                                leading: DesignSystem.Spacing.lg,
                                bottom: DesignSystem.Spacing.xl,
                                trailing: DesignSystem.Spacing.lg
                            ))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await refreshRecipes() }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: DesignSystem.Spacing.md) {
                    searchBar
                    filterChips
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.top, DesignSystem.Spacing.sm)
                .padding(.bottom, DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.background)
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
            .alert("Delete Recipe?", isPresented: Binding(
                get: { recipePendingDelete != nil },
                set: { if !$0 { recipePendingDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { recipePendingDelete = nil }
                Button("Delete", role: .destructive) {
                    if let recipe = recipePendingDelete {
                        deleteRecipe(recipe)
                    }
                    recipePendingDelete = nil
                }
            } message: {
                Text("This will permanently delete “\(recipePendingDelete?.name ?? "this recipe")”. This action cannot be undone.")
            }
        }
        .onAppear {
            // Skip orphan cleanup while the recipe store looks empty — CloudKit may still
            // be importing, and wiping Documents/RecipeImages would drop covers that rematch.
            if !allRecipes.isEmpty {
                let ids = Set(allRecipes.compactMap { $0.id })
                RecipeImageStore.cleanupOrphanedImages(validRecipeIDs: ids)
            }
            searchDebouncer.searchText = searchText
            fetchFilteredRecipes()
            Task {
                await RecipeImageStore.migrateLocalPhotosToCloudKit(in: viewContext)
                fetchFilteredRecipes()
            }
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
        .inkSlateSheet(isPresented: $showingAddRecipe) {
            ModernAddRecipeView()
        }
        .inkSlateSheet(isPresented: $showingStats) {
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

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Menu {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button {
                            selectedSort = option
                            lightHaptic()
                        } label: {
                            if selectedSort == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(selectedSort.rawValue)
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
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                FilterChip(title: "Favorites", icon: showFavoritesOnly ? "heart.fill" : "heart", isActive: showFavoritesOnly) {
                    withAnimation(.spring()) {
                        showFavoritesOnly.toggle()
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
    
    private func deleteRecipe(_ recipe: Recipe) {
        let imagePath = recipe.imageUrl
        viewContext.delete(recipe)
        if viewContext.inkSlateSave(module: "Recipes") {
            lightHaptic()
            Task {
                guard let imagePath, !imagePath.isEmpty else { return }
                if RecipeImageStore.isCloudRecordName(imagePath) {
                    try? await CloudKitAssetService.shared.deleteRecipePhoto(recordName: imagePath)
                } else {
                    RecipeImageStore.deleteImage(at: imagePath)
                }
            }
            fetchFilteredRecipes()
        }
    }

    private func fetchFilteredRecipes() {
        filterGeneration += 1
        let generation = filterGeneration
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
                guard generation == filterGeneration else { return }
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

// MARK: - Recipe Card Row (open + actions)
struct RecipeCardRow: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var recipe: Recipe
    let onDelete: () -> Void
    
    @State private var showingDetail = false
    @State private var showingEdit = false
    @State private var showingAddToList = false
    @State private var showingCookMode = false
    
    var body: some View {
        // Use a Button + sheet instead of NavigationLink(value:). Recipe lives inside
        // ContentView's NavigationStack and RecipeTabView's TabView, so value-based
        // links often stop opening after sheets, filters, or tab switches.
        Button {
            showingDetail = true
            lightHaptic()
        } label: {
            ModernRecipeCard(recipe: recipe, onToggleFavorite: toggleFavorite)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: toggleFavorite) {
                Label(
                    recipe.isFavorite ? "Unfavorite" : "Favorite",
                    systemImage: recipe.isFavorite ? "heart.slash" : "heart"
                )
            }
            .tint(.pink)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            if !recipe.recipeSteps.isEmpty {
                Button {
                    showingCookMode = true
                } label: {
                    Label("Start Cook Mode", systemImage: "play.fill")
                }
            }
            if !recipe.ingredientsArray.isEmpty {
                Button {
                    showingAddToList = true
                } label: {
                    Label("Add to Shopping List", systemImage: "cart.badge.plus")
                }
            }
            Button {
                showingEdit = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(action: toggleFavorite) {
                Label(
                    recipe.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: recipe.isFavorite ? "heart.slash" : "heart"
                )
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .inkSlateSheet(isPresented: $showingDetail) {
            NavigationStack {
                ModernRecipeDetailView(recipe: recipe)
            }
        }
        .inkSlateSheet(isPresented: $showingEdit) {
            ModernAddRecipeView(editingRecipe: recipe)
        }
        .inkSlateSheet(isPresented: $showingAddToList) {
            AddRecipeIngredientsToListView(recipe: recipe, onAdded: nil)
        }
        .cookModePresentation(isPresented: $showingCookMode, recipe: recipe)
    }
    
    private func toggleFavorite() {
        lightHaptic()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            recipe.isFavorite.toggle()
        }
        _ = viewContext.inkSlateSave(module: "Recipes")
    }
}

// MARK: - Enhanced Recipe Card
struct ModernRecipeCard: View {
    @EnvironmentObject private var recipeTimers: RecipeTimerController
    @ObservedObject var recipe: Recipe
    var onToggleFavorite: (() -> Void)? = nil

    private var activeTimerRows: [RecipeCardTimerRow] {
        recipeTimers.activeTimerRows(for: recipe)
    }
    
    private var totalMinutes: Int {
        Int(recipe.prepTime + recipe.cookTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                RecipeCardImage(path: recipe.imageUrl)
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(recipe.name ?? "Untitled Recipe")
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .lineLimit(2)
                        
                        Spacer(minLength: 0)
                        
                        Button {
                            onToggleFavorite?()
                        } label: {
                            Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                                .font(.body)
                                .foregroundColor(recipe.isFavorite ? .pink : DesignSystem.Colors.textTertiary)
                                .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                                .contentShape(Rectangle())
                        }
                        // borderless keeps this control independently tappable inside a List row Button
                        .buttonStyle(.borderless)
                        .accessibilityLabel(recipe.isFavorite ? "Remove from favorites" : "Add to favorites")
                    }

                    if let description = recipe.recipeDescription, !description.isEmpty {
                        Text(description)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 6) {
                        if let cuisine = recipe.cuisine, !cuisine.isEmpty {
                            RecipeMetaChip(text: cuisine, icon: RecipeCategory.allCases.first(where: { $0.rawValue == cuisine })?.icon)
                        }
                        if totalMinutes > 0 {
                            RecipeMetaChip(text: "\(totalMinutes)m", icon: "clock")
                        }
                        if recipe.rating > 0 {
                            RecipeMetaChip(text: "\(recipe.rating)", icon: "star.fill", tint: .yellow)
                        }
                    }
                }
            }

            if !activeTimerRows.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach(activeTimerRows) { row in
                            HStack(spacing: 4) {
                                Image(systemName: row.isRunning ? "timer" : "pause.circle.fill")
                                    .font(DesignSystem.Typography.caption)
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
}

private struct RecipeMetaChip: View {
    let text: String
    var icon: String? = nil
    var tint: Color? = nil
    
    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .foregroundColor(tint ?? DesignSystem.Colors.accent)
            }
            Text(text)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .font(DesignSystem.Typography.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(DesignSystem.Colors.backgroundSecondary)
        .cornerRadius(DesignSystem.CornerRadius.lg)
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
            // Show cached bitmap immediately; refresh from disk/CloudKit in the background.
            if image == nil {
                image = RecipeImageStore.cachedImage(path: path)
            }
            let loaded = await RecipeImageStore.loadDisplayImage(path: path)
            if Task.isCancelled { return }
            image = loaded
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

// MARK: - Cook Mode Presentation

extension View {
    /// Presents Cook Mode immersively: full-screen on iOS, large sheet on macOS.
    @ViewBuilder
    func cookModePresentation(isPresented: Binding<Bool>, recipe: Recipe) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented) {
            EnhancedCookModeView(recipe: recipe)
        }
        #else
        inkSlateSheet(isPresented: isPresented) {
            EnhancedCookModeView(recipe: recipe)
                .inkSlateSheetDetents([.large])
        }
        #endif
    }
}

// MARK: - Empty State Views
struct RecipesEmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text(title)
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text(message)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            if let actionTitle, let action {
                Button(action: {
                    lightHaptic()
                    action()
                }) {
                    Text(actionTitle)
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                }
                .minimalistButton(variant: .primary, size: .medium)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

struct ModernEmptyRecipesView: View {
    var onAdd: (() -> Void)? = nil
    
    var body: some View {
        RecipesEmptyStateView(
            icon: "book.closed",
            title: "No recipes yet",
            message: "Save your favorite meals and build shopping lists from them.",
            actionTitle: onAdd == nil ? nil : "Add Your First Recipe",
            action: onAdd
        )
    }
}

struct SearchEmptyView: View {
    let searchText: String
    
    var body: some View {
        RecipesEmptyStateView(
            icon: "magnifyingglass",
            title: "No matches",
            message: "Nothing matches “\(searchText)”. Try different words or filters."
        )
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
    @State private var imageRemoved = false
    @State private var isLoadingPickerImage = false
    @State private var isSavingRecipe = false
    @State private var ingredients: [RecipeIngredientData] = []
    @State private var steps: [RecipeStep] = []
    @State private var prepTime = 0
    @State private var cookTime = 0
    @State private var servings = 4
    @State private var selectedTags: Set<DietaryTag> = []
    @State private var notesText = ""
    @State private var videoURL = ""
    
    init(editingRecipe: Recipe? = nil) {
        self.editingRecipe = editingRecipe
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func segmentTitle(for section: EditorSection) -> String {
        switch section {
        case .ingredients:
            let count = ingredients.filter(\.hasName).count
            return count > 0 ? "\(section.rawValue) (\(count))" : section.rawValue
        case .steps:
            let count = steps.filter { !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            return count > 0 ? "\(section.rawValue) (\(count))" : section.rawValue
        default:
            return section.rawValue
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Picker("Section", selection: $activeSection) {
                        ForEach(EditorSection.allCases) { section in
                            Text(segmentTitle(for: section))
                                .tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if showValidation && !canSave {
                        validationHint
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.top, DesignSystem.Spacing.md)
                .padding(.bottom, DesignSystem.Spacing.sm)
                
                Group {
                    switch activeSection {
                    case .basics:
                        ScrollView {
                            basicsSection
                                .padding(DesignSystem.Spacing.lg)
                        }
                    case .ingredients:
                        IngredientsSection(ingredients: $ingredients)
                    case .steps:
                        StepsSection(steps: $steps)
                    case .notes:
                        ScrollView {
                            notesSection
                                .padding(DesignSystem.Spacing.lg)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(DesignSystem.Colors.background)
            .safeAreaInset(edge: .bottom) {
                Button(action: attemptSave) {
                    Text(editingRecipe == nil ? "Save Recipe" : "Update Recipe")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(DesignSystem.Colors.textInverse)
                        .background(canSave && !isSavingRecipe && !isLoadingPickerImage ? DesignSystem.Colors.accent : DesignSystem.Colors.accent.opacity(0.4))
                        .cornerRadius(DesignSystem.CornerRadius.md)
                }
                .buttonStyle(.plain)
                .disabled(!canSave || isSavingRecipe || isLoadingPickerImage)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.background)
            }
            .navigationTitle(editingRecipe == nil ? "New Recipe" : "Edit Recipe")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
            ZStack(alignment: .topTrailing) {
                PhotosPicker(selection: $imageItem, matching: .images) {
                    imageSection
                }
                
                if currentImagePreview != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            imageItem = nil
                            imagePreview = nil
                            selectedImageData = nil
                            imageRemoved = true
                        }
                        lightHaptic()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, .black.opacity(0.55))
                            .padding(DesignSystem.Spacing.sm)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove photo")
                }
            }
            .onChange(of: imageItem) { _, newItem in
                guard let newItem else {
                    selectedImageData = nil
                    isLoadingPickerImage = false
                    return
                }
                Task {
                    await loadPickerImage(from: newItem)
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
                
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Video Link")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    TextField("TikTok or YouTube URL", text: $videoURL)
                        .textFieldStyle(MinimalistInputFieldStyle(state: .normal))
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
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

    @MainActor
    private func loadPickerImage(from item: PhotosPickerItem) async {
        isLoadingPickerImage = true
        defer { isLoadingPickerImage = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                ErrorHandlingService.shared.reportOperationFailure(
                    module: "Recipes",
                    detail: "Couldn't read that photo. If it's in iCloud, download it on this device and try again."
                )
                return
            }
            guard let jpeg = RecipeImageStore.normalizedJPEGData(from: data),
                  let image = platformImage(from: jpeg) else {
                ErrorHandlingService.shared.reportOperationFailure(
                    module: "Recipes",
                    detail: "That photo is too large or in an unsupported format. Try another image."
                )
                return
            }
            selectedImageData = jpeg
            imagePreview = image
            imageRemoved = false
        } catch {
            ErrorHandlingService.shared.reportOperationFailure(
                module: "Recipes",
                detail: "Couldn't load the photo: \(error.localizedDescription)"
            )
        }
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
        videoURL = recipe.videoURL ?? ""
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

        // Finish any in-flight PhotosPicker load so Save doesn't race past the new image.
        if isLoadingPickerImage {
            for _ in 0..<100 where isLoadingPickerImage {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        if selectedImageData == nil, let imageItem, !imageRemoved {
            await loadPickerImage(from: imageItem)
        }

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
        recipe.videoURL = MediaLink.storedString(from: videoURL)
        let cleanedSteps = steps.filter { !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        recipe.updateDetails(steps: cleanedSteps, notes: notesText)
        recipe.updateDietaryTags(selectedTags)
        
        var imageAttachmentFailed = false
        let previousImagePath = recipe.imageUrl

        if imageRemoved && selectedImageData == nil {
            await deleteRecipeImageAsset(at: previousImagePath)
            recipe.imageUrl = nil
            existingImagePath = ""
        } else if let data = selectedImageData, let recipeID = recipe.id {
            let uploadResult = await attachRecipePhoto(data: data, recipeID: recipeID, previousPath: previousImagePath)
            switch uploadResult {
            case .cloud(let recordName, let image):
                recipe.imageUrl = recordName
                existingImagePath = recordName
                imagePreview = image
                selectedImageData = nil
            case .localOnly(let fileName, let image):
                recipe.imageUrl = fileName
                existingImagePath = fileName
                imagePreview = image
                selectedImageData = nil
                imageAttachmentFailed = true
            case .failed:
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
                RecipeImageStore.cacheSyncedImage(localImage, recordName: recordName)
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
        let cleanedIngredients = ingredients.filter(\.hasName)
        let existingIngredients: [RecipeIngredient] = (recipe.ingredients?.allObjects as? [RecipeIngredient]) ?? []
        let existingByID: [UUID: RecipeIngredient] = Dictionary(
            uniqueKeysWithValues: existingIngredients.compactMap { ing in
                guard let id = ing.id else { return nil }
                return (id, ing)
            }
        )

        let incomingIDs = Set(cleanedIngredients.map(\.id))

        for existing in existingIngredients {
            if let id = existing.id, !incomingIDs.contains(id) {
                viewContext.delete(existing)
            }
        }

        for ingredientData in cleanedIngredients {
            let ingredient = existingByID[ingredientData.id] ?? RecipeIngredient(context: viewContext)

            if ingredient.id == nil {
                ingredient.id = ingredientData.id
                ingredient.createdDate = now
                ingredient.recipe = recipe
            }

            ingredient.modifiedDate = now
            ingredient.name = ingredientData.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawAmount = ingredientData.amount.trimmingCharacters(in: .whitespacesAndNewlines)
            ingredient.amount = RecipeService.parseAmountString(rawAmount) ?? 0.0
            ingredient.notes = rawAmount
            ingredient.unit = ingredientData.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            ingredient.recipe = recipe
        }
        
        if viewContext.inkSlateSave(module: "Recipes") {
            if imageAttachmentFailed {
                ErrorHandlingService.shared.reportOperationFailure(
                    module: "Recipes",
                    detail: "Your recipe was saved, but the photo couldn't sync to iCloud yet. It stays on this device and will retry next time you open Recipes."
                )
            }
            lightHaptic()
            dismiss()
        }
    }

    private enum RecipePhotoAttachResult {
        case cloud(recordName: String, image: PlatformImage)
        case localOnly(fileName: String, image: PlatformImage)
        case failed
    }

    /// Prefer CloudKit, but always keep a local file if upload fails so the photo isn't dropped.
    private func attachRecipePhoto(
        data: Data,
        recipeID: UUID,
        previousPath: String?
    ) async -> RecipePhotoAttachResult {
        let jpeg = RecipeImageStore.normalizedJPEGData(from: data) ?? data
        guard RecipeValidation.validateImageData(jpeg),
              let image = platformImage(from: jpeg) else {
            return .failed
        }

        do {
            let recordName = try await CloudKitAssetService.shared.uploadRecipePhoto(image, for: recipeID)
            RecipeImageStore.cacheSyncedImage(image, recordName: recordName)
            await deleteRecipeImageAsset(at: previousPath, excluding: recordName)
            if let previousPath, !RecipeImageStore.isCloudRecordName(previousPath) {
                RecipeImageStore.deleteImage(at: previousPath)
            }
            return .cloud(recordName: recordName, image: image)
        } catch {
            do {
                let fileName = try RecipeImageStore.saveImage(
                    data: jpeg,
                    for: recipeID,
                    replacing: previousPath.flatMap { RecipeImageStore.isCloudRecordName($0) ? nil : $0 }
                )
                return .localOnly(fileName: fileName, image: image)
            } catch {
                return .failed
            }
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

// MARK: - Editor List Style

private extension View {
    @ViewBuilder
    func editorListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }
}

// MARK: - Ingredients Section
struct IngredientsSection: View {
    @Binding var ingredients: [RecipeIngredientData]
    @State private var showingAdd = false
    @State private var editingIngredient: RecipeIngredientData?
    
    var body: some View {
        List {
            Section {
                if ingredients.isEmpty {
                    Text("No ingredients added yet")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(DesignSystem.Colors.backgroundSecondary)
                } else {
                    ForEach(ingredients) { ingredient in
                        Button {
                            editingIngredient = ingredient
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ingredient.name.isEmpty ? "Untitled ingredient" : ingredient.name)
                                        .font(DesignSystem.Typography.body)
                                        .foregroundColor(ingredient.name.isEmpty ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.textPrimary)
                                    if !ingredient.quantityLabel.isEmpty {
                                        Text(ingredient.quantityLabel)
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundColor(DesignSystem.Colors.textSecondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "pencil")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(DesignSystem.Colors.surface)
                    }
                    .onMove { source, destination in
                        ingredients.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        withAnimation(.spring()) {
                            ingredients.remove(atOffsets: offsets)
                        }
                    }
                }
                
                Button {
                    showingAdd = true
                    lightHaptic()
                } label: {
                    Label("Add Ingredient", systemImage: "plus.circle.fill")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.accent)
                }
                .buttonStyle(.plain)
                .listRowBackground(DesignSystem.Colors.surface)
            } header: {
                Text("Ingredients")
            } footer: {
                Text("Tap to edit. Drag to reorder. Swipe left to delete. Amount and unit are optional.")
            }
        }
        .editorListStyle()
        .scrollContentBackground(.hidden)
        .inkSlateSheet(isPresented: $showingAdd) {
            IngredientEditorView { ingredient in
                withAnimation(.spring()) {
                    ingredients.append(ingredient)
                }
                showingAdd = false
            }
        }
        .inkSlateSheet(item: $editingIngredient) { ingredient in
            IngredientEditorView(existing: ingredient) { updated in
                if let index = ingredients.firstIndex(where: { $0.id == updated.id }) {
                    withAnimation(.spring()) {
                        ingredients[index] = updated
                    }
                }
                editingIngredient = nil
            }
        }
    }
}

struct IngredientEditorView: View {
    @Environment(\.dismiss) private var dismiss
    private let existing: RecipeIngredientData?
    let onSave: (RecipeIngredientData) -> Void
    
    @State private var name: String
    @State private var amount: String
    @State private var unit: String
    
    /// Empty string = no unit (name-only ingredients).
    private let units = ["", "cups", "tbsp", "tsp", "oz", "lbs", "g", "kg", "ml", "L", "whole", "pinch", "clove", "slice", "piece", "to taste"]
    
    private var isEditing: Bool { existing != nil }
    
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    init(existing: RecipeIngredientData? = nil, onSave: @escaping (RecipeIngredientData) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _amount = State(initialValue: existing?.amount ?? "")
        _unit = State(initialValue: existing?.unit ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ingredient Name", text: $name)
                }
                
                Section {
                    TextField("Amount (optional)", text: $amount)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Picker("Unit (optional)", selection: $unit) {
                        Text("None").tag("")
                        ForEach(units.filter { !$0.isEmpty }, id: \.self) { unitOption in
                            Text(unitOption).tag(unitOption)
                        }
                    }
                } footer: {
                    Text("You can leave amount and unit blank if you only want the ingredient name.")
                }
            }
            .navigationTitle(isEditing ? "Edit Ingredient" : "Add Ingredient")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isEditing ? "Save" : "Add") {
                        let ingredient = RecipeIngredientData(
                            id: existing?.id ?? UUID(),
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            amount: amount.trimmingCharacters(in: .whitespacesAndNewlines),
                            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        onSave(ingredient)
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

// MARK: - Steps Section
struct StepsSection: View {
    @Binding var steps: [RecipeStep]
    @State private var showingAdd = false
    @State private var editingStep: RecipeStep?
    
    var body: some View {
        List {
            Section {
                if steps.isEmpty {
                    Text("No steps added yet")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(DesignSystem.Colors.backgroundSecondary)
                } else {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        Button {
                            editingStep = step
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(DesignSystem.Typography.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(DesignSystem.Colors.accent)
                                    .frame(width: 30)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.instruction)
                                        .font(DesignSystem.Typography.body)
                                        .foregroundColor(DesignSystem.Colors.textPrimary)
                                    if let timer = step.timerMinutes {
                                        Label("\(timer) minutes", systemImage: "timer")
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundColor(DesignSystem.Colors.textSecondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "pencil")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(DesignSystem.Colors.surface)
                    }
                    .onMove { source, destination in
                        steps.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        withAnimation(.spring()) {
                            steps.remove(atOffsets: offsets)
                        }
                    }
                }
                
                Button {
                    showingAdd = true
                    lightHaptic()
                } label: {
                    Label("Add Step", systemImage: "plus.circle.fill")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.accent)
                }
                .buttonStyle(.plain)
                .listRowBackground(DesignSystem.Colors.surface)
            } header: {
                Text("Instructions")
            } footer: {
                Text("Tap to edit. Drag to reorder. Swipe left to delete.")
            }
        }
        .editorListStyle()
        .scrollContentBackground(.hidden)
        .inkSlateSheet(isPresented: $showingAdd) {
            StepEditorView { step in
                withAnimation(.spring()) {
                    steps.append(step)
                }
                showingAdd = false
            }
        }
        .inkSlateSheet(item: $editingStep) { step in
            StepEditorView(existing: step) { updated in
                if let index = steps.firstIndex(where: { $0.id == updated.id }) {
                    withAnimation(.spring()) {
                        steps[index] = updated
                    }
                }
                editingStep = nil
            }
        }
    }
}

struct StepEditorView: View {
    @Environment(\.dismiss) private var dismiss
    private let existing: RecipeStep?
    let onSave: (RecipeStep) -> Void
    
    @State private var instruction: String
    @State private var hasTimer: Bool
    @State private var timerMinutes: Int
    
    private var isEditing: Bool { existing != nil }
    
    init(existing: RecipeStep? = nil, onSave: @escaping (RecipeStep) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _instruction = State(initialValue: existing?.instruction ?? "")
        _hasTimer = State(initialValue: (existing?.timerMinutes ?? 0) > 0)
        _timerMinutes = State(initialValue: max(1, existing?.timerMinutes ?? 1))
    }
    
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
            .navigationTitle(isEditing ? "Edit Step" : "Add Step")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isEditing ? "Save" : "Add") {
                        let step = RecipeStep(
                            id: existing?.id ?? UUID(),
                            instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines),
                            timerMinutes: hasTimer ? timerMinutes : nil
                        )
                        onSave(step)
                    }
                    .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
    @State private var recentlyAddedIngredientIDs: Set<NSManagedObjectID> = []
    @State private var cartToast: CartAddedToast?
    @State private var cartIconBounce = false
    
    init(recipe: Recipe) {
        self.recipe = recipe
        _currentServings = State(initialValue: Int(recipe.servings ?? "1") ?? 1)
    }

    private var cookTimerStep: RecipeStep {
        RecipeStep(id: RecipeTimerStepID.cookTime(for: recipe), instruction: "Cook time", timerMinutes: nil)
    }

    var body: some View {
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
                }
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text(recipe.name ?? "Untitled Recipe")
                                .font(DesignSystem.Typography.largeTitle)
                                .fontWeight(.semibold)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            HStack(spacing: DesignSystem.Spacing.md) {
                                if let category = recipe.cuisine {
                                    HStack(spacing: 4) {
                                        if let cat = RecipeCategory.allCases.first(where: { $0.rawValue == category }) {
                                            Image(systemName: cat.icon)
                                        }
                                        Text(category)
                                    }
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                }
                                
                                if recipe.rating > 0 {
                                    HStack(spacing: 3) {
                                        ForEach(1...5, id: \.self) { i in
                                            Image(systemName: i <= recipe.rating ? "star.fill" : "star")
                                                .font(DesignSystem.Typography.caption)
                                                .foregroundColor(i <= recipe.rating ? .yellow : DesignSystem.Colors.textTertiary)
                                        }
                                    }
                                }
                            }
                        }

                if let desc = recipe.recipeDescription, !desc.isEmpty {
                    Text(desc)
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                if let videoURL = recipe.videoURL, !videoURL.isEmpty {
                    VideoLinkButton(rawURL: videoURL)
                }
                        
                        if !recipe.recipeSteps.isEmpty {
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
                            .buttonStyle(.plain)
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
                                
                                Button(action: { showingAddToList = true }) {
                                    HStack {
                                        Image(systemName: "cart.badge.plus")
                                        Text("Add to Shopping List")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, DesignSystem.Spacing.md)
                                    .foregroundColor(DesignSystem.Colors.accent)
                                    .background(DesignSystem.Colors.surface)
                                    .cornerRadius(DesignSystem.CornerRadius.md)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                            .stroke(DesignSystem.Colors.accent.opacity(0.4), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                
                                ForEach(ingredients, id: \.objectID) { ingredient in
                                    let justAdded = recentlyAddedIngredientIDs.contains(ingredient.objectID)
                                    HStack(spacing: 12) {
                                        Text("•")
                                        Text(scaledIngredient(ingredient))
                                            .font(DesignSystem.Typography.body)
                                        Spacer(minLength: 8)
                                        Button {
                                            addSingleIngredientToList(ingredient)
                                        } label: {
                                            Image(systemName: justAdded ? "checkmark.circle.fill" : "cart.badge.plus")
                                                .font(.body)
                                                .foregroundColor(justAdded ? .green : DesignSystem.Colors.accent)
                                                .frame(width: 36, height: 36)
                                                .contentShape(Rectangle())
                                                .scaleEffect(justAdded ? 1.15 : 1.0)
                                                .symbolEffect(.bounce, value: justAdded)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(justAdded)
                                        .accessibilityLabel(
                                            justAdded
                                            ? "Added \(ingredient.name ?? "ingredient") to shopping list"
                                            : "Add \(ingredient.name ?? "ingredient") to shopping list"
                                        )
                                    }
                                    .padding(.vertical, 4)
                                    .animation(.spring(response: 0.35, dampingFraction: 0.65), value: justAdded)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button(action: toggleFavorite) {
                            Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                                .foregroundColor(recipe.isFavorite ? .pink : nil)
                        }
                        .accessibilityLabel(recipe.isFavorite ? "Remove from favorites" : "Add to favorites")
                        
                        if !recipe.ingredientsArray.isEmpty {
                            Button {
                                showingAddToList = true
                            } label: {
                                Image(systemName: "cart.badge.plus")
                                    .scaleEffect(cartIconBounce ? 1.25 : 1.0)
                                    .symbolEffect(.bounce, value: cartIconBounce)
                            }
                            .accessibilityLabel("Add ingredients to shopping list")
                        }
                        
                        Menu {
                            Button(action: { showingEdit = true }) {
                                Label("Edit", systemImage: "pencil")
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
                }
            }
        .cookModePresentation(isPresented: $showCookMode, recipe: recipe)
        .inkSlateSheet(isPresented: $showingEdit) {
            ModernAddRecipeView(editingRecipe: recipe)
        }
        .inkSlateSheet(isPresented: $showingAddToList) {
            AddRecipeIngredientsToListView(recipe: recipe) { addedCount in
                playCartAddedFeedback(
                    message: addedCount == 1
                        ? "Added to shopping list"
                        : "Added \(addedCount) items to shopping list"
                )
            }
        }
        .inkSlateSheet(isPresented: $showingShareSheet) {
            PlatformShareSheet(items: shareItems)
        }
        .alert("Delete Recipe?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteRecipe()
            }
        } message: {
            Text("This will permanently delete this recipe. This action cannot be undone.")
        }
        .overlay(alignment: .bottom) {
            if let cartToast {
                CartAddedToastBanner(message: cartToast.message)
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.92)))
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.lg)
                    .id(cartToast.id)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.72), value: cartToast?.id)
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
    
    private func addSingleIngredientToList(_ ingredient: RecipeIngredient) {
        do {
            let added = try RecipeService.addIngredientToShoppingList(
                ingredient,
                recipe: recipe,
                in: viewContext
            )
            if added == 0 {
                lightHaptic()
                ErrorHandlingService.shared.reportOperationFailure(
                    module: "Recipes",
                    detail: "“\(ingredient.name ?? "That item")” is already on your shopping list."
                )
                return
            }
            
            let objectID = ingredient.objectID
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                recentlyAddedIngredientIDs.insert(objectID)
            }
            playCartAddedFeedback(message: "Added to shopping list")
            
            Task {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        _ = recentlyAddedIngredientIDs.remove(objectID)
                    }
                }
            }
        } catch {
            handleRecipeError(error, context: "Failed to add ingredient to shopping list")
        }
    }
    
    private func playCartAddedFeedback(message: String) {
        mediumHaptic()
        let toast = CartAddedToast(message: message)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
            cartToast = toast
            cartIconBounce.toggle()
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                guard cartToast?.id == toast.id else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    cartToast = nil
                }
            }
        }
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

// MARK: - Cart added feedback

private struct CartAddedToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

private struct CartAddedToastBanner: View {
    let message: String
    @State private var iconBounce = false
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "cart.fill.badge.plus")
                .font(.system(size: 16, weight: .semibold))
                .scaleEffect(iconBounce ? 1.2 : 1.0)
            Text(message)
                .font(DesignSystem.Typography.body)
                .fontWeight(.medium)
                .lineLimit(2)
        }
        .foregroundColor(DesignSystem.Colors.textInverse)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(DesignSystem.Colors.accent)
                .shadow(color: DesignSystem.Shadows.small, radius: 8, x: 0, y: 4)
        )
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                iconBounce = true
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.12)) {
                iconBounce = false
            }
        }
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(message)
    }
}

// MARK: - Add Recipe Ingredients to Shopping List
struct AddRecipeIngredientsToListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    let recipe: Recipe
    var onAdded: ((Int) -> Void)? = nil
    
    @State private var selectedObjectIDs: Set<NSManagedObjectID> = []
    @State private var didAdd = false
    @State private var showSuccess = false
    @State private var addedCount = 0
    
    private var ingredients: [RecipeIngredient] {
        recipe.ingredientsArray.sorted {
            ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
        }
    }
    
    private var allSelected: Bool {
        !ingredients.isEmpty && selectedObjectIDs.count == ingredients.count
    }
    
    private var selectedIngredients: [RecipeIngredient] {
        ingredients.filter { selectedObjectIDs.contains($0.objectID) }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    if ingredients.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "cart")
                                .font(.system(size: 48))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            Text("No ingredients to add")
                                .font(DesignSystem.Typography.title3)
                            Text("This recipe doesn't have any ingredients yet.")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else {
                        List {
                            Section {
                                ForEach(ingredients, id: \.objectID) { ingredient in
                                    let isSelected = selectedObjectIDs.contains(ingredient.objectID)
                                    Button {
                                        toggleSelection(ingredient.objectID)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(ingredient.name ?? "Ingredient")
                                                    .font(DesignSystem.Typography.body)
                                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                                let quantity = [
                                                    ingredient.rawAmountString,
                                                    ingredient.unit ?? ""
                                                ]
                                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                                    .filter { !$0.isEmpty }
                                                    .joined(separator: " ")
                                                if !quantity.isEmpty {
                                                    Text(quantity)
                                                        .font(DesignSystem.Typography.caption)
                                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                                }
                                            }
                                            
                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                Text("Choose ingredients from \"\(recipe.name ?? "this recipe")\"")
                            } footer: {
                                Text("Items already on your list (same name) will be skipped.")
                            }
                        }
                    }
                }
                .opacity(showSuccess ? 0.25 : 1)
                
                if showSuccess {
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.green)
                            .scaleEffect(showSuccess ? 1 : 0.4)
                        Text(addedCount == 1 ? "Added to shopping list" : "Added \(addedCount) items")
                            .font(DesignSystem.Typography.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                    .padding(28)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                            .fill(DesignSystem.Colors.backgroundSecondary)
                            .shadow(color: DesignSystem.Shadows.small, radius: 10, x: 0, y: 4)
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .navigationTitle("Add to Shopping List")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(didAdd)
                }
                ToolbarItem(placement: .primaryAction) {
                    if !ingredients.isEmpty && !showSuccess {
                        Button(allSelected ? "Deselect All" : "Select All") {
                            if allSelected {
                                selectedObjectIDs.removeAll()
                            } else {
                                selectedObjectIDs = Set(ingredients.map(\.objectID))
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !ingredients.isEmpty && !showSuccess {
                    Button(action: addIngredientsToList) {
                        Text(selectedObjectIDs.isEmpty
                              ? "Select Ingredients"
                              : "Add \(selectedObjectIDs.count) to Shopping List")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedObjectIDs.isEmpty ? DesignSystem.Colors.backgroundSecondary : DesignSystem.Colors.accent)
                            .foregroundColor(selectedObjectIDs.isEmpty ? DesignSystem.Colors.textSecondary : .white)
                            .cornerRadius(DesignSystem.CornerRadius.lg)
                    }
                    .disabled(selectedObjectIDs.isEmpty || didAdd)
                    .padding()
                    .background(DesignSystem.Colors.background)
                }
            }
            .onAppear {
                selectedObjectIDs = Set(ingredients.map(\.objectID))
            }
        }
    }
    
    private func toggleSelection(_ objectID: NSManagedObjectID) {
        if selectedObjectIDs.contains(objectID) {
            selectedObjectIDs.remove(objectID)
        } else {
            selectedObjectIDs.insert(objectID)
        }
    }
    
    private func addIngredientsToList() {
        guard !selectedObjectIDs.isEmpty else { return }
        do {
            let added = try RecipeService.addRecipeIngredientsToShoppingList(
                recipe: recipe,
                in: viewContext,
                ingredients: selectedIngredients
            )
            didAdd = true
            if added == 0 {
                lightHaptic()
                ErrorHandlingService.shared.reportOperationFailure(
                    module: "Recipes",
                    detail: "Those ingredients are already on your shopping list."
                )
                didAdd = false
                return
            }
            
            mediumHaptic()
            addedCount = added
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showSuccess = true
            }
            
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                await MainActor.run {
                    onAdded?(added)
                    dismiss()
                }
            }
        } catch {
            didAdd = false
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
                } else {
                    #if os(iOS)
                    TabView(selection: $viewModel.currentStepIndex) {
                        ForEach(Array(viewModel.steps.enumerated()), id: \.element.id) { index, step in
                            stepPage(for: step, index: index)
                                .tag(index)
                        }
                        completionView
                            .tag(viewModel.steps.count)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.25), value: viewModel.currentStepIndex)
                    #else
                    if let step = viewModel.currentStep {
                        stepPage(for: step, index: viewModel.currentStepIndex)
                    } else {
                        completionView
                    }
                    #endif
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
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
        }
        .onDisappear {
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
    }
    
    private func stepPage(for step: RecipeStep, index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Text("Step \(index + 1)")
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
    @State private var editingItem: ShoppingItemEntity?
    @State private var showDoneSection = false
    @State private var feedbackToast: CartAddedToast?

    private var allShoppingItems: [ShoppingItemEntity] {
        shoppingSections.flatMap { Array($0) }
    }

    private var checkedItems: [ShoppingItemEntity] {
        allShoppingItems.filter { $0.isChecked }
    }

    private var uncheckedCount: Int {
        allShoppingItems.count - checkedItems.count
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
                            let uncheckedItems = section.filter { !$0.isChecked }
                            if !uncheckedItems.isEmpty {
                                let rawCategory = (section.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                let category = rawCategory.isEmpty ? "General" : rawCategory
                                Section(
                                    header: ShoppingListSectionHeader(
                                        category: category,
                                        uncheckedCount: uncheckedItems.count
                                    )
                                ) {
                                    ForEach(uncheckedItems) { item in
                                        shoppingRow(for: item)
                                    }
                                }
                            }
                        }
                        
                        if !checkedItems.isEmpty {
                            Section {
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        showDoneSection.toggle()
                                    }
                                    lightHaptic()
                                } label: {
                                    HStack {
                                        Label("Done (\(checkedItems.count))", systemImage: "checkmark.circle.fill")
                                            .font(DesignSystem.Typography.headline)
                                            .foregroundColor(DesignSystem.Colors.textSecondary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundColor(DesignSystem.Colors.textTertiary)
                                            .rotationEffect(.degrees(showDoneSection ? 90 : 0))
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                
                                if showDoneSection {
                                    ForEach(checkedItems, id: \.objectID) { item in
                                        shoppingRow(for: item)
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
                        checkedCount: checkedItems.count,
                        incompleteCount: uncheckedCount,
                        onClearAll: deleteAllItems,
                        onClearChecked: deleteCheckedItems
                    )
                }
                }
            }
            .navigationTitle("Shopping")
            .inkSlateSheet(item: $editingItem) { item in
                ShoppingItemEditorView(item: item)
            }
            .overlay(alignment: .bottom) {
                if let feedbackToast {
                    CartAddedToastBanner(message: feedbackToast.message)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.bottom, 80)
                        .id(feedbackToast.id)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.72), value: feedbackToast?.id)
        }
    }
    
    @ViewBuilder
    private func shoppingRow(for item: ShoppingItemEntity) -> some View {
        ShoppingListRow(
            item: item,
            onToggle: { toggle(item) },
            onTap: { editingItem = item }
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
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                toggle(item)
            } label: {
                Label(item.isChecked ? "Uncheck" : "Check", systemImage: item.isChecked ? "circle" : "checkmark.circle.fill")
            }
            .tint(DesignSystem.Colors.success)
        }
        .contextMenu {
            Button {
                editingItem = item
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteItem(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func showFeedback(_ message: String) {
        feedbackToast = CartAddedToast(message: message)
        let toastID = feedbackToast?.id
        Task {
            try? await Task.sleep(for: .seconds(2))
            if feedbackToast?.id == toastID {
                feedbackToast = nil
            }
        }
    }

    private func addQuickItem() {
        let trimmedName = quickName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCustomCategory = quickCustomCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        if quickCategory == .other && trimmedCustomCategory.isEmpty { return }

        let fetchRequest: NSFetchRequest<ShoppingItemEntity> = ShoppingItemEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "name ==[cd] %@ AND isChecked == NO",
            trimmedName
        )
        fetchRequest.fetchLimit = 1
        
        if let existing = try? viewContext.fetch(fetchRequest), !existing.isEmpty {
            lightHaptic()
            showFeedback("“\(trimmedName)” is already on your list")
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

    private func deleteCheckedItems() {
        let items = checkedItems
        guard !items.isEmpty else { return }
        items.forEach(viewContext.delete)
        if viewContext.inkSlateSave(module: "Recipes") {
            showDoneSection = false
            showFeedback("Cleared \(items.count) checked item\(items.count == 1 ? "" : "s")")
        }
    }
    
    private func saveContext() {
        _ = viewContext.inkSlateSave(module: "Recipes")
    }
}

// MARK: - Shopping Item Editor
struct ShoppingItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var item: ShoppingItemEntity
    
    @State private var name: String = ""
    @State private var amount: String = ""
    @State private var unit: String = ""
    @State private var category: String = ""
    
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $name)
                    TextField("Amount (optional)", text: $amount)
                    TextField("Unit (optional)", text: $unit)
                }
                
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(ShoppingCategory.allCases.filter { $0 != .other }, id: \.rawValue) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat.rawValue)
                        }
                        if !category.isEmpty && !ShoppingCategory.allCases.contains(where: { $0.rawValue == category }) {
                            Text(category).tag(category)
                        }
                    }
                    TextField("Custom category", text: $category)
                }
                
                if let source = item.recipeSource {
                    Section {
                        Label("From \(source)", systemImage: "book.fill")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
            }
            .navigationTitle("Edit Item")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .onAppear {
            name = item.wrappedName
            amount = item.wrappedAmount
            unit = item.wrappedUnit
            category = (item.category ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if category.isEmpty { category = ShoppingCategory.general.rawValue }
        }
    }
    
    private func save() {
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.amount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        item.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        item.category = trimmedCategory.isEmpty ? ShoppingCategory.general.rawValue : trimmedCategory
        item.modifiedDate = Date()  // Critical for CloudKit sync
        
        if viewContext.inkSlateSave(module: "Recipes") {
            lightHaptic()
            dismiss()
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
    let checkedCount: Int
    let incompleteCount: Int
    let onClearAll: () -> Void
    let onClearChecked: () -> Void

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
                
                if checkedCount > 0 {
                    Button {
                        lightHaptic()
                        onClearChecked()
                    } label: {
                        Label("Clear Checked", systemImage: "checkmark.circle.badge.xmark")
                            .font(DesignSystem.Typography.caption)
                            .fontWeight(.semibold)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(
                                Capsule()
                                    .fill(DesignSystem.Colors.backgroundSecondary)
                            )
                    }
                }
                
                Button(role: .destructive) {
                    guard itemCount > 0 else { return }
                    showingClearConfirm = true
                } label: {
                    Label("Clear All", systemImage: "trash")
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
                onClearAll()
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
    
    @State private var showDetails = false

    private var canSubmit: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCustom = customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { return false }
        if selectedCategory == .other && trimmedCustom.isEmpty { return false }
        return true
    }
    
    private var detailsSummary: String? {
        var parts: [String] = []
        let qty = "\(amount.trimmingCharacters(in: .whitespaces)) \(unit.trimmingCharacters(in: .whitespaces))".trimmingCharacters(in: .whitespaces)
        if !qty.isEmpty { parts.append(qty) }
        if selectedCategory != .general {
            parts.append(selectedCategory == .other ? (customCategory.isEmpty ? "Other" : customCategory) : selectedCategory.rawValue)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(DesignSystem.Colors.accent)
                
                TextField("Add an item (e.g. \"Eggs\")", text: $name)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit { if canSubmit { onCommit() } }
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.body)
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showDetails.toggle()
                    }
                    lightHaptic()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(showDetails || detailsSummary != nil ? DesignSystem.Colors.accent : DesignSystem.Colors.textTertiary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showDetails ? "Hide item details" : "Add quantity or category")
                
                Button(action: onCommit) {
                    Text("Add")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(DesignSystem.Colors.accent)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.4)
            }
            
            if !showDetails, let detailsSummary {
                Text(detailsSummary)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(.leading, 34)
            }
            
            if showDetails {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        TextField("Qty", text: $amount)
                            .submitLabel(.done)
                            .onSubmit { if canSubmit { onCommit() } }
                            .textFieldStyle(.plain)
                            .padding(.horizontal, DesignSystem.Spacing.md)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .frame(width: 90)
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
                            .textFieldStyle(.plain)
                            .padding(.horizontal, DesignSystem.Spacing.md)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                    .fill(DesignSystem.Colors.backgroundTertiary)
                            )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .fill(DesignSystem.Colors.backgroundSecondary)
        )
        .padding(.vertical, DesignSystem.Spacing.sm)
    }
}

private struct ShoppingListRow: View {
    let item: ShoppingItemEntity
    let onToggle: () -> Void
    var onTap: (() -> Void)? = nil

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
            .buttonStyle(.plain)

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
            
            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .fill(DesignSystem.Colors.backgroundSecondary)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
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
            .inkSlateSheet(isPresented: $showingAddItem) {
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
                .font(DesignSystem.Typography.headline)
                .fontWeight(isSelected ? .semibold : .regular)
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
    @State private var editingItem: PantryItemEntity?
    
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
                        .font(DesignSystem.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    if !searchText.isEmpty {
                        Button("Clear search") {
                            searchText = ""
                        }
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(filteredItems) { item in
                    PantryItemRowView(item: item, onEdit: { editingItem = item })
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
                            Button {
                                editingItem = item
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
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
        .inkSlateSheet(item: $editingItem) { item in
            PantryItemEditorView(item: item)
        }
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
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Text("Use Quick Add above, or tap the button below")
                    .font(DesignSystem.Typography.headline)
                    .fontWeight(.regular)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onAdd) {
                Label("Add Item", systemImage: "plus")
                    .font(DesignSystem.Typography.headline)
                    .fontWeight(.semibold)
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
                            .font(DesignSystem.Typography.footnote)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                            .tracking(0.5)
                        
                        TextField("What are you adding?", text: $name)
                            .font(DesignSystem.Typography.title3)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .focused($isNameFocused)
                        
                        Rectangle()
                            .fill(isNameFocused ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textTertiary.opacity(0.3))
                            .frame(height: 1)
                    }
                    
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("QTY")
                                .font(DesignSystem.Typography.footnote)
                                .fontWeight(.medium)
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                                .tracking(0.5)
                            
                            TextField("1", text: $quantity)
                                .font(DesignSystem.Typography.title3)
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
                                .font(DesignSystem.Typography.footnote)
                                .fontWeight(.medium)
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
                                        .font(DesignSystem.Typography.title3)
                                        .foregroundColor(DesignSystem.Colors.textPrimary)
                                    Image(systemName: "chevron.down")
                                        .font(DesignSystem.Typography.caption)
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
                                .font(DesignSystem.Typography.footnote)
                                .fontWeight(.medium)
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
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Add to \(category.rawValue)")
                        .font(DesignSystem.Typography.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        addItem()
                    } label: {
                        Text("Done")
                            .font(DesignSystem.Typography.title3)
                            .fontWeight(.medium)
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
        .inkSlateSheetDetents([.medium])
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

// MARK: - Pantry Item Editor
struct PantryItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var item: PantryItemEntity
    
    @State private var name = ""
    @State private var quantity = "1"
    @State private var unit = ""
    @State private var category: PantryCategory = .pantry
    @State private var hasExpiration = false
    @State private var expirationDate = Date().addingTimeInterval(7 * 24 * 60 * 60)
    @State private var notes = ""
    
    private let commonUnits = ["", "oz", "lb", "g", "kg", "cups", "tbsp", "tsp", "ml", "L", "pcs", "pinch", "jar", "bottle", "packet"]
    
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $name)
                    TextField("Quantity", text: $quantity)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Picker("Unit", selection: $unit) {
                        ForEach(commonUnits, id: \.self) { u in
                            Text(u.isEmpty ? "None" : u).tag(u)
                        }
                        if !unit.isEmpty && !commonUnits.contains(unit) {
                            Text(unit).tag(unit)
                        }
                    }
                }
                
                Section("Location") {
                    Picker("Category", selection: $category) {
                        ForEach(PantryCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                }
                
                Section("Expiration") {
                    Toggle("Has expiration date", isOn: $hasExpiration)
                    if hasExpiration {
                        DatePicker("Expires", selection: $expirationDate, displayedComponents: .date)
                    }
                }
                
                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Edit Item")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .onAppear {
            name = item.wrappedName
            quantity = item.wrappedQuantity.isEmpty ? "1" : item.wrappedQuantity
            unit = item.wrappedUnit
            category = item.wrappedCategory
            if let date = item.expirationDate {
                hasExpiration = true
                expirationDate = date
            }
            notes = item.wrappedNotes
        }
    }
    
    private func save() {
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuantity = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        item.quantity = trimmedQuantity.isEmpty ? "1" : trimmedQuantity
        item.unit = unit
        item.category = category.rawValue
        item.expirationDate = hasExpiration ? expirationDate : nil
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        item.modifiedDate = Date()  // Critical for CloudKit sync
        
        if viewContext.inkSlateSave(module: "Pantry") {
            lightHaptic()
            dismiss()
        }
    }
}







