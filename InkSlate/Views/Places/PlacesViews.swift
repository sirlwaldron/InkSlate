import SwiftUI
import CoreData
import os
#if canImport(UIKit)
import UIKit
#endif

fileprivate let placesLog = Logger(subsystem: "com.lucas.InkSlateNew", category: "Places")

// MARK: - Supporting Types & Helpers

enum PlaceType: String, CaseIterable, Identifiable {
    case restaurant = "Restaurants"
    case activity = "Activities"
    case place = "Places"
    
    var id: String { rawValue }
    var lowercaseKey: String { rawValue.lowercased() }
    
    var icon: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .activity: return "figure.run"
        case .place: return "mappin.and.ellipse"
        }
    }
    
    var gradient: [Color] {
        switch self {
        case .restaurant: return [Color(hex: "#FF6B6B") ?? .red, Color(hex: "#EE5A5A") ?? .red]
        case .activity: return [Color(hex: "#4ECDC4") ?? .teal, Color(hex: "#44A08D") ?? .teal]
        case .place: return [Color(hex: "#667EEA") ?? .blue, Color(hex: "#764BA2") ?? .purple]
        }
    }
}

private func inferredPlaceType(for category: PlaceCategory) -> PlaceType {
    if let marker = category.icon?.lowercased() {
        if marker.contains("restaurant") || marker.contains("fork") || marker.contains("knife") {
            return .restaurant
        }
        if marker.contains("activity") || marker.contains("figure") || marker.contains("run") || marker.contains("sport") {
            return .activity
        }
        if marker.contains("place") || marker.contains("map") || marker.contains("location") {
            return .place
        }
        if PlaceType.allCases.contains(where: { $0.lowercaseKey == marker }) {
            return PlaceType.allCases.first(where: { $0.lowercaseKey == marker }) ?? .place
        }
    }
    
    if let name = category.name?.lowercased() {
        if name.contains("restaurant") || name.contains("dining") || name.contains("food") || name.contains("cafe") {
            return .restaurant
        }
        if name.contains("activity") || name.contains("park") || name.contains("gym") || name.contains("adventure") || name.contains("event") {
            return .activity
        }
        if name.contains("place") || name.contains("travel") || name.contains("destination") {
            return .place
        }
    }
    
    return .place
}

private func inferredPlaceType(for place: Place, uncategorizedAs defaultTab: PlaceType? = nil) -> PlaceType {
    if let category = place.category {
        return inferredPlaceType(for: category)
    }
    
    if let notes = place.notes?.lowercased() {
        if notes.contains("food") || notes.contains("restaurant") {
            return .restaurant
        }
        if notes.contains("activity") || notes.contains("park") || notes.contains("event") {
            return .activity
        }
    }
    
    return defaultTab ?? .place
}

fileprivate func getOrCreateUncategorizedPlaceCategory(for type: PlaceType, context: NSManagedObjectContext) -> PlaceCategory {
    let fetch = NSFetchRequest<PlaceCategory>(entityName: "PlaceCategory")
    fetch.predicate = NSPredicate(format: "sortOrder == %d AND type == %@", -1, type.rawValue)
    fetch.sortDescriptors = [
        NSSortDescriptor(key: "createdDate", ascending: true),
        NSSortDescriptor(key: "name", ascending: true)
    ]
    let matches = (try? context.fetch(fetch)) ?? []
    if let keeper = matches.first {
        if matches.count > 1 {
            mergeDuplicateUncategorizedCategories(keeper: keeper, duplicates: Array(matches.dropFirst()), context: context)
        }
        return keeper
    }
    
    let category = PlaceCategory(context: context)
    category.id = UUID()
    category.name = "Uncategorized"
    category.type = type.rawValue
    category.icon = "tray"
    category.color = "#6B7280"
    category.sortOrder = -1
    category.createdDate = Date()
    category.modifiedDate = Date()
    context.insert(category)
    context.saveQuietly(module: "Places")
    return category
}

fileprivate func mergeDuplicateUncategorizedCategories(
    keeper: PlaceCategory,
    duplicates: [PlaceCategory],
    context: NSManagedObjectContext
) {
    guard !duplicates.isEmpty else { return }
    for dup in duplicates {
        if let places = dup.places as? Set<Place> {
            for place in places {
                place.category = keeper
                place.modifiedDate = Date()
            }
        }
        context.delete(dup)
    }
    keeper.modifiedDate = Date()
    context.saveQuietly(module: "Places")
}

fileprivate func deduplicateUncategorizedPlaceCategories(in context: NSManagedObjectContext) {
    for type in PlaceType.allCases {
        let fetch = NSFetchRequest<PlaceCategory>(entityName: "PlaceCategory")
        fetch.predicate = NSPredicate(format: "sortOrder == %d AND type == %@", -1, type.rawValue)
        fetch.sortDescriptors = [
            NSSortDescriptor(key: "createdDate", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        let matches = (try? context.fetch(fetch)) ?? []
        guard let keeper = matches.first, matches.count > 1 else { continue }
        mergeDuplicateUncategorizedCategories(keeper: keeper, duplicates: Array(matches.dropFirst()), context: context)
    }
}

// MARK: - Date Formatter
private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter
}()

// MARK: - Main Places View
struct PlacesMainView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    
    @FetchRequest private var allCategories: FetchedResults<PlaceCategory>
    @FetchRequest private var allPlaces: FetchedResults<Place>

    init() {
        let categoryRequest = NSFetchRequest<PlaceCategory>(entityName: "PlaceCategory")
        categoryRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PlaceCategory.name, ascending: true)]
        categoryRequest.fetchBatchSize = 50
        _allCategories = FetchRequest(fetchRequest: categoryRequest, animation: .default)

        let placeRequest = NSFetchRequest<Place>(entityName: "Place")
        placeRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Place.name, ascending: true)]
        placeRequest.fetchBatchSize = 50
        _allPlaces = FetchRequest(fetchRequest: placeRequest, animation: .default)
    }
    
    @State private var selectedTab: PlaceType = .restaurant
    @State private var searchText = ""
    @State private var showingQuickAdd = false
    @State private var animateHeader = false
    
    @State private var editingCategory: PlaceCategory?
    @State private var categoryToDelete: PlaceCategory?
    
    private func filteredCategories(for type: PlaceType) -> [PlaceCategory] {
        Array(allCategories).filter { category in
            if let categoryType = category.type {
                return categoryType == type.rawValue
            }
            return inferredPlaceType(for: category) == type
        }
    }
    
    private var placesForSelectedTab: [Place] {
        allPlaces.filter { inferredPlaceType(for: $0, uncategorizedAs: selectedTab) == selectedTab }
    }
    
    var body: some View {
        // Own stack so map/category pushes don't stick on ContentView's outer NavigationStack.
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        headerSection
                        
                        statsSection
                            .padding(.top, DesignSystem.Spacing.lg)
                        
                        typeSelector
                            .padding(.top, DesignSystem.Spacing.xl)
                        
                        categoriesSection
                            .padding(.top, DesignSystem.Spacing.lg)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.bottom, 100)
                }
            }
            .inkSlateSheet(isPresented: $showingQuickAdd) {
                QuickAddPlaceView(type: selectedTab)
            }
            .inkSlateSheet(item: $editingCategory) { category in
                EditPlaceCategoryView(category: category, type: selectedTab)
            }
            .alert(
                "Delete Category and Places?",
                isPresented: Binding(
                    get: { categoryToDelete != nil },
                    set: { if !$0 { categoryToDelete = nil } }
                ),
                presenting: categoryToDelete
            ) { category in
                Button("Cancel", role: .cancel) { categoryToDelete = nil }
                Button("Delete", role: .destructive) {
                    deleteCategory(category, for: selectedTab)
                    categoryToDelete = nil
                }
            } message: { category in
                let name = (category.name ?? "This category").trimmingCharacters(in: .whitespacesAndNewlines)
                let count = category.places?.count ?? 0
                Text("This will permanently delete '\(name.isEmpty ? "Untitled" : name)' and \(count) place\(count == 1 ? "" : "s") inside it. This can’t be undone.")
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) {
                    animateHeader = true
                }
                deduplicateUncategorizedPlaceCategories(in: viewContext)
                Task {
                    await PlaceImageStore.migrateLocalPhotosToCloudKit(in: viewContext)
                }
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle(for: selectedTab))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Text(headerSubtitle(for: selectedTab))
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                
                Spacer()
                
                NavigationLink {
                    PlacesMapView()
                } label: {
                    Image(systemName: "map")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.accent)
                        .frame(width: 36, height: 36)
                        .background(DesignSystem.Colors.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DesignSystem.Colors.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .padding(.trailing, DesignSystem.Spacing.sm)
                
                Button {
                    lightHaptic()
                    showingQuickAdd = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textInverse)
                        .frame(width: 36, height: 36)
                        .background(DesignSystem.Colors.accent)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.top, DesignSystem.Spacing.md)
        .opacity(animateHeader ? 1 : 0)
        .offset(y: animateHeader ? 0 : -10)
    }
    
    // MARK: - Stats Section
    private var statsSection: some View {
        Group {
            let total = placesForSelectedTab.count
            let visited = placesForSelectedTab.reduce(into: 0) { $0 += $1.isVisited ? 1 : 0 }
            let favorites = placesForSelectedTab.reduce(into: 0) { $0 += $1.isFavorite ? 1 : 0 }
            let wishlist = total - visited
            switch selectedTab {
            case .restaurant:
                HStack(spacing: DesignSystem.Spacing.md) {
                    PlaceStatCard(
                        title: "Visited",
                        value: "\(visited)",
                        icon: "checkmark.circle",
                        gradient: [DesignSystem.Colors.success, DesignSystem.Colors.success.opacity(0.7)]
                    )
                    
                    PlaceStatCard(
                        title: "Wishlist",
                        value: "\(wishlist)",
                        icon: "star",
                        gradient: [DesignSystem.Colors.warning, DesignSystem.Colors.warning.opacity(0.7)]
                    )
                    
                    PlaceStatCard(
                        title: "Favorites",
                        value: "\(favorites)",
                        icon: "heart.fill",
                        gradient: [DesignSystem.Colors.error, DesignSystem.Colors.error.opacity(0.7)]
                    )
                }
            case .activity:
                HStack(spacing: DesignSystem.Spacing.md) {
                    PlaceStatCard(
                        title: "Total",
                        value: "\(total)",
                        icon: "sparkles",
                        gradient: [DesignSystem.Colors.accent, DesignSystem.Colors.accentLight]
                    )
                    
                    PlaceStatCard(
                        title: "Visited",
                        value: "\(visited)",
                        icon: "checkmark.circle",
                        gradient: [DesignSystem.Colors.success, DesignSystem.Colors.success.opacity(0.7)]
                    )
                    
                    PlaceStatCard(
                        title: "Favorites",
                        value: "\(favorites)",
                        icon: "heart.fill",
                        gradient: [DesignSystem.Colors.error, DesignSystem.Colors.error.opacity(0.7)]
                    )
                }
            case .place:
                HStack(spacing: DesignSystem.Spacing.md) {
                    PlaceStatCard(
                        title: "Total",
                        value: "\(total)",
                        icon: "map",
                        gradient: [DesignSystem.Colors.accent, DesignSystem.Colors.accentLight]
                    )
                    
                    PlaceStatCard(
                        title: "Visited",
                        value: "\(visited)",
                        icon: "checkmark.circle",
                        gradient: [DesignSystem.Colors.success, DesignSystem.Colors.success.opacity(0.7)]
                    )
                    
                    PlaceStatCard(
                        title: "Wishlist",
                        value: "\(wishlist)",
                        icon: "bookmark.fill",
                        gradient: [DesignSystem.Colors.warning, DesignSystem.Colors.warning.opacity(0.7)]
                    )
                }
            }
        }
        .opacity(animateHeader ? 1 : 0)
        .offset(y: animateHeader ? 0 : 10)
        .animation(.easeOut(duration: 0.6).delay(0.1), value: animateHeader)
    }
    
    // MARK: - Type Selector
    private var typeSelector: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Browse by Type")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            HStack(spacing: DesignSystem.Spacing.md) {
                ForEach(PlaceType.allCases) { type in
                    TypePill(
                        type: type,
                        isSelected: selectedTab == type,
                        action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTab = type
                            }
                            lightHaptic()
                        }
                    )
                }
            }
        }
        .opacity(animateHeader ? 1 : 0)
        .offset(y: animateHeader ? 0 : 10)
        .animation(.easeOut(duration: 0.6).delay(0.2), value: animateHeader)
    }
    
    // MARK: - Categories Section
    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text(categoriesTitle(for: selectedTab))
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Spacer()
                
                NavigationLink {
                    AllCategoriesView(type: selectedTab, categories: filteredCategories(for: selectedTab))
                } label: {
                    Text("See All")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.accent)
                }
            }
            
            let categories = filteredCategories(for: selectedTab)
            
            if categories.isEmpty {
                EmptyCategoriesView(type: selectedTab)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.md),
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.md)
                ], spacing: DesignSystem.Spacing.md) {
                    ForEach(categories) { category in
                        NavigationLink {
                            PlacesListView(category: category, type: selectedTab)
                        } label: {
                            categoryCard(for: category, type: selectedTab)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .contextMenu {
                            Button {
                                // Delay so the context menu finishes dismissing before the sheet presents.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    editingCategory = category
                                }
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            
                            Button(role: .destructive) {
                                // Delay so the context menu finishes dismissing before the alert presents.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    categoryToDelete = category
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    
                    AddCategoryCard(type: selectedTab)
                }
            }
        }
        .opacity(animateHeader ? 1 : 0)
        .offset(y: animateHeader ? 0 : 10)
        .animation(.easeOut(duration: 0.6).delay(0.3), value: animateHeader)
    }
}

private extension PlacesMainView {
    func deleteCategory(_ category: PlaceCategory, for type: PlaceType) {
        mediumHaptic()
        let fetch = NSFetchRequest<Place>(entityName: "Place")
        fetch.predicate = NSPredicate(format: "category == %@", category)
        if let places = try? viewContext.fetch(fetch) {
            for place in places {
                viewContext.delete(place)
            }
        }
        viewContext.delete(category)
        _ = viewContext.inkSlateSave(module: "Places")
    }
    
    func getOrCreateUncategorizedCategory(for type: PlaceType) -> PlaceCategory {
        getOrCreateUncategorizedPlaceCategory(for: type, context: viewContext)
    }

    func headerTitle(for type: PlaceType) -> String {
        switch type {
        case .restaurant: return "Restaurants"
        case .activity: return "Activities"
        case .place: return "Places"
        }
    }
    
    func headerSubtitle(for type: PlaceType) -> String {
        switch type {
        case .restaurant: return "Save spots you want to try (and the ones you loved)."
        case .activity: return "Track experiences, adventures, and favorites."
        case .place: return "Your personal guide to destinations."
        }
    }
    
    func categoriesTitle(for type: PlaceType) -> String {
        switch type {
        case .restaurant: return "Cuisine & Lists"
        case .activity: return "Types of Fun"
        case .place: return "Collections"
        }
    }
    
    @ViewBuilder
    func categoryCard(for category: PlaceCategory, type: PlaceType) -> some View {
        let placeCount = category.places?.count ?? 0
        switch type {
        case .restaurant:
            RestaurantCategoryCard(category: category, placeCount: placeCount)
        case .activity:
            ActivityCategoryCard(category: category, placeCount: placeCount)
        case .place:
            PlaceCategoryCard(category: category, placeCount: placeCount)
        }
    }
}

private struct CategoryContextMenuEditButton: View {
    let category: PlaceCategory
    let type: PlaceType
    
    @State private var showingEdit = false
    
    var body: some View {
        Button {
            DispatchQueue.main.async {
                showingEdit = true
            }
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .inkSlateSheet(isPresented: $showingEdit) {
            EditPlaceCategoryView(category: category, type: type)
        }
    }
}

// MARK: - Place Stat Card
struct PlaceStatCard: View {
    let title: String
    let value: String
    let icon: String
    let gradient: [Color]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(gradient[0])
                
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Type Pill
struct TypePill: View {
    let type: PlaceType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: type.icon)
                    .font(.system(size: 11, weight: .medium))
                
                Text(type.rawValue)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .foregroundColor(isSelected ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textPrimary)
            .background(
                isSelected
                    ? AnyView(LinearGradient(colors: type.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyView(DesignSystem.Colors.surface)
            )
            .cornerRadius(DesignSystem.CornerRadius.xl)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl)
                    .stroke(isSelected ? Color.clear : DesignSystem.Colors.border, lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Category Card
struct CategoryCard: View {
    let category: PlaceCategory
    let type: PlaceType
    let placeCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        HStack {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: type.gradient.map { $0.opacity(0.15) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: type.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(type.gradient[0])
                }
                
                            Spacer()
                
                Text("\(placeCount)")
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .cornerRadius(DesignSystem.CornerRadius.sm)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name ?? "Unnamed")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                
                Text("\(placeCount) place\(placeCount == 1 ? "" : "s")")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Add Category Card
struct AddCategoryCard: View {
    let type: PlaceType
    @State private var showingNewCategory = false
    
    var body: some View {
                Button {
            lightHaptic()
                    showingNewCategory = true
                } label: {
            VStack(spacing: DesignSystem.Spacing.md) {
                ZStack {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundColor(DesignSystem.Colors.border)
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                
                Text("New Category")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(DesignSystem.Colors.backgroundSecondary.opacity(0.5))
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                    .foregroundColor(DesignSystem.Colors.border)
            )
        }
        .inkSlateSheet(isPresented: $showingNewCategory) {
            NewCategoryView(type: type)
        }
    }
}

// MARK: - Empty Categories View
struct EmptyCategoriesView: View {
    let type: PlaceType
    @State private var showingNewCategory = false
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: type.icon)
                .font(.system(size: 32))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("No categories yet")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Text("Create your first \(type.rawValue.lowercased()) category")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            
            Button {
                lightHaptic()
                showingNewCategory = true
            } label: {
                Text("Create Category")
                    .font(DesignSystem.Typography.button)
                    .foregroundColor(DesignSystem.Colors.textInverse)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.accent)
                    .cornerRadius(DesignSystem.CornerRadius.md)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xxl)
        .inkSlateSheet(isPresented: $showingNewCategory) {
            NewCategoryView(type: type)
        }
    }
}

// MARK: - All Categories View
struct AllCategoriesView: View {
    let type: PlaceType
    let categories: [PlaceCategory]
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingNewCategory = false
    @State private var editingCategory: PlaceCategory?
    @State private var categoryToDelete: PlaceCategory?
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Place.name, ascending: true)]
    ) private var allPlaces: FetchedResults<Place>
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.md),
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.md)
                ], spacing: DesignSystem.Spacing.md) {
                    ForEach(categories) { category in
                        NavigationLink {
                            PlacesListView(category: category, type: type)
                        } label: {
                            CategoryCard(
                                category: category,
                                type: type,
                                placeCount: category.places?.count ?? 0
                            )
                            .contextMenu {
                                Button {
                                    // Delay so the context menu finishes dismissing before the sheet presents.
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        editingCategory = category
                                    }
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                
                                Button(role: .destructive) {
                                    // Delay so the context menu finishes dismissing before the alert presents.
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        categoryToDelete = category
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
        }
        .navigationTitle(type.rawValue)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    lightHaptic()
                    showingNewCategory = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .inkSlateSheet(isPresented: $showingNewCategory) {
            NewCategoryView(type: type)
        }
        .inkSlateSheet(item: $editingCategory) { category in
            EditPlaceCategoryView(category: category, type: type)
        }
        .alert(
            "Delete Category and Places?",
            isPresented: Binding(
                get: { categoryToDelete != nil },
                set: { if !$0 { categoryToDelete = nil } }
            ),
            presenting: categoryToDelete
        ) { category in
            Button("Cancel", role: .cancel) { categoryToDelete = nil }
            Button("Delete", role: .destructive) {
                deleteCategory(category)
                categoryToDelete = nil
            }
        } message: { category in
            let name = (category.name ?? "This category").trimmingCharacters(in: .whitespacesAndNewlines)
            let count = category.places?.count ?? 0
            Text("This will permanently delete '\(name.isEmpty ? "Untitled" : name)' and \(count) place\(count == 1 ? "" : "s") inside it. This can’t be undone.")
        }
    }
    
    private func deleteCategory(_ category: PlaceCategory) {
        mediumHaptic()
        let fetch = NSFetchRequest<Place>(entityName: "Place")
        fetch.predicate = NSPredicate(format: "category == %@", category)
        if let places = try? viewContext.fetch(fetch) {
            for place in places {
                viewContext.delete(place)
            }
        }
        viewContext.delete(category)
        _ = viewContext.inkSlateSave(module: "Places")
    }
    
    private func getOrCreateUncategorizedCategory() -> PlaceCategory {
        getOrCreateUncategorizedPlaceCategory(for: type, context: viewContext)
    }
}

// MARK: - New Category View
struct NewCategoryView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let type: PlaceType
    @State private var categoryName = ""
    @FocusState private var isNameFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                
                VStack(spacing: DesignSystem.Spacing.xl) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: type.gradient.map { $0.opacity(0.15) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: type.icon)
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(type.gradient[0])
                    }
                    .padding(.top, DesignSystem.Spacing.xl)
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Category Name")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        TextField("Enter name", text: $categoryName)
                            .font(DesignSystem.Typography.body)
                            .padding(DesignSystem.Spacing.md)
                            .background(DesignSystem.Colors.surface)
                            .cornerRadius(DesignSystem.CornerRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                    .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                            )
                            .focused($isNameFocused)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    Spacer()
                }
            }
            .navigationTitle("New Category")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createCategory()
                    }
                    .disabled(categoryName.isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                isNameFocused = true
            }
        }
    }
    
    private func createCategory() {
        lightHaptic()
        let category = PlaceCategory(context: viewContext)
        category.name = categoryName
        category.id = UUID()
        category.createdDate = Date()
        category.modifiedDate = Date()
        category.icon = type.icon
        category.type = type.rawValue
        category.sortOrder = 0
        
        if viewContext.inkSlateSave(module: "Places") {
            dismiss()
        }
    }
}

// MARK: - Edit Category View
private struct EditPlaceCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let category: PlaceCategory
    let type: PlaceType
    
    @State private var categoryName: String
    @State private var selectedIcon: String
    @FocusState private var isNameFocused: Bool
    
    @State private var showingDeleteConfirmation = false
    
    init(category: PlaceCategory, type: PlaceType) {
        self.category = category
        self.type = type
        _categoryName = State(initialValue: category.name ?? "")
        let initialIcon = (category.icon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        _selectedIcon = State(initialValue: initialIcon.isEmpty ? type.icon : initialIcon)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DesignSystem.Spacing.xl) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: type.gradient.map { $0.opacity(0.15) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: selectedIcon)
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(type.gradient[0])
                        }
                        .padding(.top, DesignSystem.Spacing.xl)
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Category Name")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            
                            TextField("Enter name", text: $categoryName)
                                .font(DesignSystem.Typography.body)
                                .padding(DesignSystem.Spacing.md)
                                .background(DesignSystem.Colors.surface)
                                .cornerRadius(DesignSystem.CornerRadius.md)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                        .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                                )
                                .focused($isNameFocused)
                        }
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            Text("Icon")
                                .font(DesignSystem.Typography.headline)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .padding(.horizontal, DesignSystem.Spacing.lg)
                            
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 44, maximum: 56), spacing: DesignSystem.Spacing.md)
                            ], spacing: DesignSystem.Spacing.md) {
                                ForEach(iconOptions(for: type), id: \.self) { icon in
                                    Button {
                                        selectedIcon = icon
                                        lightHaptic()
                                    } label: {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(selectedIcon == icon ? type.gradient[0].opacity(0.15) : DesignSystem.Colors.surface)
                                                .frame(width: 44, height: 44)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(selectedIcon == icon ? type.gradient[0] : DesignSystem.Colors.border, lineWidth: selectedIcon == icon ? 1 : 0.5)
                                                )
                                            
                                            Image(systemName: icon)
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(selectedIcon == icon ? type.gradient[0] : DesignSystem.Colors.textPrimary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                        }
                        
                        Spacer(minLength: 24)
                        
                        if canDeleteCategory {
                            VStack(spacing: DesignSystem.Spacing.md) {
                                Button(role: .destructive) {
                                    showingDeleteConfirmation = true
                                } label: {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Delete Category")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(DesignSystem.Spacing.lg)
                                    .background(DesignSystem.Colors.error.opacity(0.12))
                                    .foregroundColor(DesignSystem.Colors.error)
                                    .cornerRadius(DesignSystem.CornerRadius.lg)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                                            .stroke(DesignSystem.Colors.error.opacity(0.35), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .padding(.bottom, DesignSystem.Spacing.xl)
                        }
                    }
                }
            }
            .navigationTitle("Edit Category")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .alert("Delete Category and Places?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteCategory()
                }
            } message: {
                let name = (category.name ?? "This category").trimmingCharacters(in: .whitespacesAndNewlines)
                let count = placeCountInCategory()
                Text("This will permanently delete '\(name.isEmpty ? "Untitled" : name)' and \(count) place\(count == 1 ? "" : "s") inside it. This can’t be undone.")
            }
        }
    }
    
    private func save() {
        let trimmedName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        category.name = trimmedName
        category.icon = selectedIcon
        category.modifiedDate = Date()
        viewContext.saveQuietly(module: "Places")
        dismiss()
    }
    
    private var canDeleteCategory: Bool { true }

    private func placeCountInCategory() -> Int {
        let fetch = NSFetchRequest<Place>(entityName: "Place")
        fetch.predicate = NSPredicate(format: "category == %@", category)
        return (try? viewContext.count(for: fetch)) ?? 0
    }
    
    private func deleteCategory() {
        let fetch = NSFetchRequest<Place>(entityName: "Place")
        fetch.predicate = NSPredicate(format: "category == %@", category)
        if let places = try? viewContext.fetch(fetch) {
            for place in places {
                viewContext.delete(place)
            }
        }

        viewContext.delete(category)
        _ = viewContext.inkSlateSave(module: "Places")
        dismiss()
    }
    
    private func iconOptions(for type: PlaceType) -> [String] {
        switch type {
        case .restaurant:
            return [
                "fork.knife",
                "cup.and.saucer",
                "wineglass",
                "birthday.cake",
                "takeoutbag.and.cup.and.straw",
                "leaf",
                "fish",
                "flame",
                "carrot",
                "mug"
            ]
        case .activity:
            return [
                "figure.run",
                "figure.hiking",
                "figure.tennis",
                "bicycle",
                "dumbbell",
                "sportscourt",
                "camera",
                "paintpalette",
                "music.note",
                "ticket"
            ]
        case .place:
            return [
                "mappin.and.ellipse",
                "map",
                "building.2",
                "house",
                "mountain.2",
                "beach.umbrella",
                "binoculars",
                "airplane",
                "tram",
                "parkingsign.circle"
            ]
        }
    }
}

// MARK: - Per-type Category Cards (unique templates)
private struct RestaurantCategoryCard: View {
    let category: PlaceCategory
    let placeCount: Int
    
    private var displayIcon: String {
        let icon = (category.icon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return icon.isEmpty ? "fork.knife" : icon
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [
                            Color(hex: "#FF6B6B") ?? .red,
                            Color(hex: "#EE5A5A") ?? .red
                        ].map { $0.opacity(0.18) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: displayIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#FF6B6B") ?? .red)
                }
                
                Spacer()
                
                Text("\(placeCount)")
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .cornerRadius(DesignSystem.CornerRadius.sm)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(category.name ?? "Unnamed")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    Text("Dishes • Dates • Spots")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
    }
}

private struct ActivityCategoryCard: View {
    let category: PlaceCategory
    let placeCount: Int
    
    private var displayIcon: String {
        let icon = (category.icon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return icon.isEmpty ? "figure.run" : icon
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [
                            Color(hex: "#4ECDC4") ?? .teal,
                            Color(hex: "#44A08D") ?? .teal
                        ].map { $0.opacity(0.16) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: displayIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#4ECDC4") ?? .teal)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundColor(DesignSystem.Colors.error.opacity(0.7))
                    Text("\(placeCount)")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DesignSystem.Colors.backgroundSecondary)
                .cornerRadius(DesignSystem.CornerRadius.md)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name ?? "Unnamed")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                
                Text("Experiences to repeat")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
    }
}

private struct PlaceCategoryCard: View {
    let category: PlaceCategory
    let placeCount: Int
    
    private var displayIcon: String {
        let icon = (category.icon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return icon.isEmpty ? "mappin.and.ellipse" : icon
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [
                            Color(hex: "#667EEA") ?? .blue,
                            Color(hex: "#764BA2") ?? .purple
                        ].map { $0.opacity(0.16) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: displayIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#667EEA") ?? .blue)
                }
                
                Spacer()
                
                Text("\(placeCount) saved")
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .cornerRadius(DesignSystem.CornerRadius.md)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name ?? "Unnamed")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                
                Text("Trips • Cities • Favorites")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Quick Add Place View
struct QuickAddPlaceView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let type: PlaceType
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PlaceCategory.name, ascending: true)]
    ) private var allCategories: FetchedResults<PlaceCategory>
    
    @State private var name = ""
    @State private var selectedCategory: PlaceCategory?
    @State private var isWishlist = true
    @FocusState private var isNameFocused: Bool
    
    private var categories: [PlaceCategory] {
        Array(allCategories).filter { category in
            if let categoryType = category.type {
                return categoryType == type.rawValue
            }
            return inferredPlaceType(for: category) == type
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DesignSystem.Spacing.xl) {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Name")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            
                            TextField("What's the place called?", text: $name)
                                .font(DesignSystem.Typography.body)
                                .padding(DesignSystem.Spacing.md)
                                .background(DesignSystem.Colors.surface)
                                .cornerRadius(DesignSystem.CornerRadius.md)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                        .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                                )
                                .focused($isNameFocused)
                        }
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Category")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            
                            if categories.isEmpty {
                                Text("Create a category first")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                                    .padding(DesignSystem.Spacing.md)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: DesignSystem.Spacing.sm) {
                                        ForEach(categories) { category in
                                            Button {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    selectedCategory = category
                                                }
                                                lightHaptic()
                                            } label: {
                                                Text(category.name ?? "Unnamed")
                                                    .font(DesignSystem.Typography.caption)
                                                    .fontWeight(.medium)
                                                    .padding(.horizontal, DesignSystem.Spacing.md)
                                                    .padding(.vertical, DesignSystem.Spacing.sm)
                                                    .foregroundColor(selectedCategory?.id == category.id ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textPrimary)
                                                    .background(
                                                        selectedCategory?.id == category.id
                                                            ? AnyView(LinearGradient(colors: type.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                                                            : AnyView(DesignSystem.Colors.surface)
                                                    )
                                                    .cornerRadius(DesignSystem.CornerRadius.md)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                                            .stroke(selectedCategory?.id == category.id ? Color.clear : DesignSystem.Colors.border, lineWidth: 0.5)
                                                    )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Status")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            
                            HStack(spacing: DesignSystem.Spacing.md) {
                                StatusButton(
                                    title: "Wishlist",
                                    icon: "star",
                                    isSelected: isWishlist,
                                    gradient: [DesignSystem.Colors.warning, DesignSystem.Colors.warning.opacity(0.7)]
                                ) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        isWishlist = true
                                    }
                                    lightHaptic()
                                }
                                
                                StatusButton(
                                    title: "Visited",
                                    icon: "checkmark.circle",
                                    isSelected: !isWishlist,
                                    gradient: [DesignSystem.Colors.success, DesignSystem.Colors.success.opacity(0.7)]
                                ) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        isWishlist = false
                                    }
                                    lightHaptic()
                                }
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                }
            }
            .navigationTitle("Add Place")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        savePlaceQuick()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                isNameFocused = true
                if selectedCategory == nil {
                    selectedCategory = categories.first
                }
            }
        }
    }
    
    private func savePlaceQuick() {
        lightHaptic()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newPlace = Place(context: viewContext)
        newPlace.id = UUID()
        newPlace.name = trimmedName.isEmpty ? "Untitled Place" : trimmedName
        newPlace.isVisited = !isWishlist
        newPlace.category = selectedCategory ?? getOrCreateUncategorizedPlaceCategory(for: type, context: viewContext)
        newPlace.createdDate = Date()
        newPlace.modifiedDate = Date()
        newPlace.rating = 10

        do {
            try viewContext.saveWithCloudKitSync()
            dismiss()
        } catch {
            placesLog.error("Quick add place save failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Status Button
struct StatusButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let gradient: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                
                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.md)
            .foregroundColor(isSelected ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textPrimary)
            .background(
                isSelected
                    ? AnyView(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyView(DesignSystem.Colors.surface)
            )
            .cornerRadius(DesignSystem.CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(isSelected ? Color.clear : DesignSystem.Colors.border, lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Places List View
struct PlacesListView: View {
    let category: PlaceCategory?
    let type: PlaceType
    var wishlistOnly: Bool = false
    var favoritesOnly: Bool = false
    
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Place.name, ascending: true)],
        animation: .default)
    private var allPlaces: FetchedResults<Place>
    
    @State private var showingNewPlace = false
    @State private var selectedPlace: Place?
    @State private var searchText = ""
    @State private var showingEditCategory = false
    
    private var places: [Place] {
        var filtered: [Place]
        
        if wishlistOnly {
            filtered = Array(allPlaces).filter { !$0.isVisited }
        } else if favoritesOnly {
            filtered = Array(allPlaces).filter { $0.isFavorite }
        } else if let category = category {
            filtered = Array(allPlaces).filter { $0.category?.id == category.id }
        } else {
            filtered = Array(allPlaces)
        }
        
        if !searchText.isEmpty {
            filtered = filtered.filter {
                ($0.name ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.address ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.notes ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered.sorted { first, second in
            if first.isVisited != second.isVisited {
                return !first.isVisited
            }
            return first.rating > second.rating
        }
    }
    
    private var title: String {
        if wishlistOnly { return "Wishlist" }
        if favoritesOnly { return "Favorites" }
        return category?.name ?? "Places"
    }
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()
            
            if places.isEmpty && searchText.isEmpty {
                EmptyPlacesView(type: type) {
                    showingNewPlace = true
                }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: DesignSystem.Spacing.md) {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                            
                            TextField("Search places...", text: $searchText)
                                .font(DesignSystem.Typography.body)
                        }
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(DesignSystem.CornerRadius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                        )
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.top, DesignSystem.Spacing.sm)
                        
            ForEach(places) { place in
                            PlaceCard(place: place, type: type) {
                    selectedPlace = place
                            }
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .contextMenu {
                                Button(role: .destructive) {
                                    deletePlace(place)
                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        
                        if places.isEmpty && !searchText.isEmpty {
                            VStack(spacing: DesignSystem.Spacing.md) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 32))
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                                Text("No results found")
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignSystem.Spacing.xxl)
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationTitle(title)
        .inlineNavigationTitle()
        .toolbar {
            if category != nil && !wishlistOnly && !favoritesOnly {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        lightHaptic()
                        showingEditCategory = true
                    } label: {
                        Label("Edit Category", systemImage: "pencil")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
            Button {
                    lightHaptic()
                showingNewPlace = true
            } label: {
                Image(systemName: "plus")
                }
            }
        }
        .inkSlateSheet(isPresented: $showingEditCategory) {
            if let category {
                EditPlaceCategoryView(category: category, type: type)
            }
        }
        .inkSlateSheet(isPresented: $showingNewPlace) {
            PlaceEditorView(category: category, place: nil, type: type)
        }
        .inkSlateSheet(item: $selectedPlace) { place in
            PlaceDetailView(place: place)
        }
    }
    
    private func deletePlace(_ place: Place) {
        mediumHaptic()
        viewContext.delete(place)
        viewContext.inkSlateSave(module: "Places")
    }
}

// MARK: - Empty Places View
struct EmptyPlacesView: View {
    let type: PlaceType
    let addAction: () -> Void
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: type.gradient.map { $0.opacity(0.1) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 80, height: 80)
                
                Image(systemName: type.icon)
                    .font(.system(size: 32))
                    .foregroundColor(type.gradient[0])
            }
            
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("No places yet")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Text("Add your first place to get started")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            
            Button(action: addAction) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Add Place")
                        .font(DesignSystem.Typography.button)
                        .fontWeight(.semibold)
                }
                .foregroundColor(DesignSystem.Colors.textInverse)
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.vertical, DesignSystem.Spacing.md)
                .background(LinearGradient(colors: type.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .cornerRadius(DesignSystem.CornerRadius.md)
            }
        }
    }
}

// MARK: - Place Card
struct PlaceCard: View {
    @ObservedObject var place: Place
    let type: PlaceType
    let onTap: () -> Void
    
    @State private var photoImage: PlatformImage?
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignSystem.Spacing.md) {
                ZStack {
            if let image = photoImage {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            } else {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .fill(LinearGradient(colors: type.gradient.map { $0.opacity(0.15) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 64, height: 64)
                            .overlay(
                                Image(systemName: type.icon)
                                    .font(.system(size: 20))
                                    .foregroundColor(type.gradient[0])
                            )
                    }
                }
                
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack {
                        Text(place.name ?? "Unnamed")
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                    if !place.isVisited {
                        Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(DesignSystem.Colors.warning)
                    }
                }
                
                if !(place.address?.isEmpty ?? true) {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "mappin")
                                .font(.system(size: 8))
                    Text(place.address ?? "")
                        .lineLimit(1)
                        }
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                
                    HStack(spacing: DesignSystem.Spacing.md) {
                    if place.isVisited {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                ForEach(0..<5) { index in
                                    Image(systemName: index < Int(place.rating / 2) ? "star.fill" : "star")
                                        .font(.system(size: 8))
                                        .foregroundColor(index < Int(place.rating / 2) ? DesignSystem.Colors.warning : DesignSystem.Colors.textTertiary)
                                }
                            }
                        }
                        
                        if let cuisineType = place.cuisineType, !cuisineType.isEmpty {
                            Text(cuisineType)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DesignSystem.Colors.backgroundSecondary)
                                .cornerRadius(DesignSystem.CornerRadius.xs)
                        }
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .task(id: place.photoURL) {
            await loadPhoto()
        }
    }
    
    @MainActor
    private func loadPhoto() async {
        guard let photoURL = place.photoURL else { return }
        if photoImage == nil {
            photoImage = PlaceImageStore.cachedImage(path: photoURL)
        }
        let image = await PlaceImageStore.loadDisplayImage(path: photoURL)
        if Task.isCancelled { return }
        photoImage = image
    }
}

// MARK: - Place Detail View
struct PlaceDetailView: View {
    @ObservedObject var place: Place
    @State private var showingEditSheet = false
    @State private var photoImage: PlatformImage?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DesignSystem.Spacing.lg) {
                    if let image = photoImage {
                        Image(platformImage: image)
                            .resizable()
                            .scaledToFill()
                                .frame(height: 220)
                                .frame(maxWidth: .infinity)
                            .clipped()
                                .cornerRadius(DesignSystem.CornerRadius.xl)
                        } else {
                            let type = inferredPlaceType(for: place)
                            ZStack {
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl)
                                    .fill(LinearGradient(colors: type.gradient.map { $0.opacity(0.3) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(height: 160)
                                
                                Image(systemName: type.icon)
                                    .font(.system(size: 48))
                                    .foregroundColor(type.gradient[0].opacity(0.5))
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            HStack {
                            Text(place.name ?? "Unnamed Place")
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                
                                Spacer()
                                
                                if !place.isVisited {
                                    WishlistBadge()
                                }
                            }
                            
                            if !(place.address?.isEmpty ?? true) {
                                HStack(spacing: DesignSystem.Spacing.sm) {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundColor(DesignSystem.Colors.accent)
                                        .font(.system(size: 14))
                                    Text(place.address ?? "")
                                        .font(DesignSystem.Typography.body)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                }
                            } else if let city = place.city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
                                HStack(spacing: DesignSystem.Spacing.sm) {
                                    Image(systemName: "building.2.crop.circle.fill")
                                        .foregroundColor(DesignSystem.Colors.accent)
                                        .font(.system(size: 14))
                                    Text(city)
                                        .font(DesignSystem.Typography.body)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                }
                            }
                        }
                        
                        if hasQuickTags {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: DesignSystem.Spacing.sm) {
                                    if let cuisineType = place.cuisineType, !cuisineType.isEmpty {
                                        QuickTag(icon: "fork.knife", text: cuisineType)
                                    }
                                    if let priceRange = place.priceRange, !priceRange.isEmpty {
                                        QuickTag(icon: "dollarsign.circle", text: priceRange)
                                    }
                                    if let bestTime = place.bestTimeToGo, !bestTime.isEmpty {
                                        QuickTag(icon: "clock", text: bestTime)
                                    }
                                }
                            }
                        }
                        
                        if hasDetails {
                            DetailsSectionView(place: place)
                        }
                        
                        if let videoURL = place.videoURL, !videoURL.isEmpty {
                            VideoLinkButton(rawURL: videoURL)
                        }
                        
                    if place.isVisited {
                            RatingSectionView(place: place)
                        }
                        
                        if let notes = place.notes, !notes.isEmpty {
                            NotesSectionView(notes: notes)
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Details")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        showingEditSheet = true
                    }
                    .fontWeight(.medium)
                }
            }
            .inkSlateSheet(isPresented: $showingEditSheet) {
                PlaceEditorView(category: place.category, place: place, type: inferredPlaceType(for: place))
            }
            .task(id: place.photoURL) {
                await loadPhoto()
            }
        }
    }
    
    private var hasQuickTags: Bool {
        !(place.cuisineType?.isEmpty ?? true) ||
        !(place.priceRange?.isEmpty ?? true) ||
        !(place.bestTimeToGo?.isEmpty ?? true)
    }
    
    private var hasDetails: Bool {
        !(place.bestTimeToGo?.isEmpty ?? true) ||
        !(place.whoToBring?.isEmpty ?? true) ||
        !(place.entryFee?.isEmpty ?? true) ||
        !(place.dishRecommendations?.isEmpty ?? true)
    }
    
    @MainActor
    private func loadPhoto() async {
        guard let photoURL = place.photoURL else { return }
        if photoImage == nil {
            photoImage = PlaceImageStore.cachedImage(path: photoURL)
        }
        let image = await PlaceImageStore.loadDisplayImage(path: photoURL)
        if Task.isCancelled { return }
        photoImage = image
    }
}

// MARK: - Wishlist Badge
struct WishlistBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 8))
            Text("Wishlist")
                .font(DesignSystem.Typography.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(DesignSystem.Colors.warning)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DesignSystem.Colors.warning.opacity(0.1))
        .cornerRadius(DesignSystem.CornerRadius.sm)
    }
}

// MARK: - Quick Tag
struct QuickTag: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(DesignSystem.Typography.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(DesignSystem.Colors.textSecondary)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.backgroundSecondary)
        .cornerRadius(DesignSystem.CornerRadius.md)
    }
}

// MARK: - Details Section View
struct DetailsSectionView: View {
    let place: Place
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Details")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                if let bestTime = place.bestTimeToGo, !bestTime.isEmpty {
                    DetailRow(icon: "clock.fill", title: "Best Time", value: bestTime)
                }
                if let whoToBring = place.whoToBring, !whoToBring.isEmpty {
                    DetailRow(icon: "person.2.fill", title: "Who to Bring", value: whoToBring)
                }
                if let entryFee = place.entryFee, !entryFee.isEmpty {
                    DetailRow(icon: "ticket.fill", title: "Entry Fee", value: entryFee)
                }
                if let recommendations = place.dishRecommendations, !recommendations.isEmpty {
                    DetailRow(icon: "star.circle.fill", title: "Recommended", value: recommendations)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Detail Row
struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(DesignSystem.Colors.accent)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                Text(value)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Rating Section View
struct RatingSectionView: View {
    let place: Place
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Your Experience")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            VStack(spacing: DesignSystem.Spacing.md) {
                RatingBar(title: "Overall", rating: place.overallRating, color: DesignSystem.Colors.accent)
                RatingBar(title: "Price", rating: place.priceRating, color: DesignSystem.Colors.success)
                RatingBar(title: "Quality", rating: place.qualityRating, color: DesignSystem.Colors.info)
                RatingBar(title: "Atmosphere", rating: place.atmosphereRating, color: DesignSystem.Colors.warning)
                
                if place.category?.name?.lowercased().contains("restaurant") != true {
                    RatingBar(title: "Fun Factor", rating: place.funFactorRating, color: DesignSystem.Colors.error)
                    RatingBar(title: "Scenery", rating: place.sceneryRating, color: DesignSystem.Colors.info)
                }
                
                Divider()
                    .padding(.vertical, DesignSystem.Spacing.xs)
                
                HStack {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.Colors.accent)
                        Text("Visited \(place.visitedDate ?? Date(), formatter: dateFormatter)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: place.wouldReturn ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(place.wouldReturn ? DesignSystem.Colors.success : DesignSystem.Colors.error)
                        Text(place.wouldReturn ? "Would return" : "Would not return")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Rating Bar
struct RatingBar: View {
    let title: String
    let rating: Int16
    let color: Color
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .frame(width: 70, alignment: .leading)
            
            GeometryReader { geometry in
            ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DesignSystem.Colors.backgroundTertiary)
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                        .frame(width: geometry.size.width * CGFloat(rating) / 10, height: 6)
                }
            }
            .frame(height: 6)
            
            Text("\(rating)")
                .font(DesignSystem.Typography.caption)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(width: 24, alignment: .trailing)
        }
    }
}

// MARK: - Notes Section View
struct NotesSectionView: View {
    let notes: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Notes")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Text(notes)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .padding(DesignSystem.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.surface)
                .cornerRadius(DesignSystem.CornerRadius.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                        .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Place Editor View
struct PlaceEditorView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PlaceCategory.name, ascending: true)],
        animation: .default)
    private var allCategories: FetchedResults<PlaceCategory>
    
    let category: PlaceCategory?
    let place: Place?
    let type: PlaceType
    
    @State private var hasLoadedInitialValues = false
    @State private var hasUserEdits = false
    
    @State private var name = ""
    @State private var location = ""
    @State private var address = ""
    @State private var latitude: Double = 0
    @State private var longitude: Double = 0
    @State private var priceRange = ""
    @State private var cuisineType = ""
    @State private var bestTimeToGo = ""
    @State private var whoToBring = ""
    @State private var entryFee = ""
    @State private var notes = ""
    @State private var dishRecommendations = ""
    @State private var videoURL = ""
    @State private var hasVisited = false
    @State private var isFavorite = false
    @State private var wouldReturn = true
    @State private var rating: Double = 5
    @State private var priceRating: Double = 5
    @State private var qualityRating: Double = 5
    @State private var atmosphereRating: Double = 5
    @State private var funFactorRating: Double = 5
    @State private var sceneryRating: Double = 5
    @State private var selectedImage: PlatformImage?
    @State private var showingImagePicker = false
    @State private var photoChanged = false
    @State private var photoRemoved = false
    @State private var existingPhotoURL: String?
    @State private var selectedCategory: PlaceCategory?
    @State private var dateVisited = Date()
    @State private var isSaving = false
    @State private var saveFailedMessage: String?
    @State private var currentSection = 0
    
    private var categories: [PlaceCategory] {
        Array(allCategories).filter { category in
            if let categoryType = category.type {
                return categoryType == type.rawValue
            }
            return inferredPlaceType(for: category) == type
        }
    }
    
    private func dirty(_ binding: Binding<String>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                hasUserEdits = true
                binding.wrappedValue = newValue
            }
        )
    }
    
    private func dirty(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                hasUserEdits = true
                binding.wrappedValue = newValue
            }
        )
    }
    
    private func dirty(_ binding: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                hasUserEdits = true
                binding.wrappedValue = newValue
            }
        )
    }
    
    private func dirty(_ binding: Binding<Date>) -> Binding<Date> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                hasUserEdits = true
                binding.wrappedValue = newValue
            }
        )
    }
    
    private func dirtyCategory(_ binding: Binding<PlaceCategory?>) -> Binding<PlaceCategory?> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                hasUserEdits = true
                binding.wrappedValue = newValue
            }
        )
    }
    
    private func loadDraftFromPlaceIfNeeded() {
        guard let place else { return }
        guard !hasUserEdits else { return }
        guard !hasLoadedInitialValues else { return }
        
        selectedCategory = place.category ?? category
        name = place.name ?? ""
        address = place.address ?? ""
        latitude = place.latitude
        longitude = place.longitude
        notes = place.notes ?? ""
        hasVisited = place.isVisited
        isFavorite = place.isFavorite
        rating = Double(place.rating)
        dateVisited = place.visitedDate ?? Date()
        location = place.city ?? ""
        priceRange = place.priceRange ?? ""
        cuisineType = place.cuisineType ?? ""
        bestTimeToGo = place.bestTimeToGo ?? ""
        whoToBring = place.whoToBring ?? ""
        entryFee = place.entryFee ?? ""
        dishRecommendations = place.dishRecommendations ?? ""
        videoURL = place.videoURL ?? ""
        wouldReturn = place.wouldReturn
        priceRating = Double(place.priceRating)
        qualityRating = Double(place.qualityRating)
        atmosphereRating = Double(place.atmosphereRating)
        funFactorRating = Double(place.funFactorRating)
        sceneryRating = Double(place.sceneryRating)
        existingPhotoURL = place.photoURL
        photoChanged = false
        photoRemoved = false
        
        hasLoadedInitialValues = true
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DesignSystem.Spacing.xl) {
                        photoSection
                        
                        basicInfoSection
                        
                        detailsSection
                        
                        visitStatusSection
                        
                        if hasVisited {
                            ratingsSection
                        }
                        
                        notesSection
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(place == nil ? "New Place" : "Edit Place")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button("Save") {
                            Task {
                                isSaving = true
                                saveFailedMessage = nil
                                let saved = await savePlace()
                                isSaving = false
                                if saved { dismiss() }
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .inkSlateSheet(isPresented: $showingImagePicker) {
                ImagePicker(image: Binding(
                    get: { selectedImage },
                    set: { newImage in
                        selectedImage = newImage
                        if newImage != nil {
                            photoChanged = true
                            photoRemoved = false
                            hasUserEdits = true
                        }
                    }
                ))
            }
            .task(id: place?.objectID) {
                loadDraftFromPlaceIfNeeded()
            }
            .onChange(of: place?.modifiedDate, initial: false) { _, _ in
                if !hasUserEdits {
                    hasLoadedInitialValues = false
                    loadDraftFromPlaceIfNeeded()
                }
            }
            .task(id: place?.photoURL) {
                guard !photoChanged, !photoRemoved else { return }
                if let place = place, let photoURL = place.photoURL, selectedImage == nil {
                    selectedImage = await PlaceImageStore.loadDisplayImage(path: photoURL)
                    existingPhotoURL = photoURL
                }
            }
            .onAppear {
                guard place == nil, selectedCategory == nil else { return }
                selectedCategory = category ?? categories.first
            }
            .alert("Couldn’t save", isPresented: Binding(
                get: { saveFailedMessage != nil },
                set: { if !$0 { saveFailedMessage = nil } }
            )) {
                Button("OK", role: .cancel) { saveFailedMessage = nil }
            } message: {
                Text(saveFailedMessage ?? "")
            }
        }
    }
    
    // MARK: - Photo Section
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Photo")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            ZStack(alignment: .topTrailing) {
                Button {
                    showingImagePicker = true
                } label: {
                    if let image = selectedImage, !photoRemoved {
                        Image(platformImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .cornerRadius(DesignSystem.CornerRadius.lg)
                            .overlay(
                                ZStack {
                                    Color.black.opacity(0.3)
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                }
                                .cornerRadius(DesignSystem.CornerRadius.lg)
                                .opacity(0.7)
                            )
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                                .fill(DesignSystem.Colors.backgroundSecondary)
                                .frame(height: 120)
                            
                            VStack(spacing: DesignSystem.Spacing.sm) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                                Text("Add Photo")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                
                if selectedImage != nil, !photoRemoved {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedImage = nil
                            photoRemoved = true
                            photoChanged = false
                            hasUserEdits = true
                        }
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
        }
    }
    
    // MARK: - Basic Info Section
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Basic Info")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            VStack(spacing: DesignSystem.Spacing.md) {
                AddressAutocompleteField(
                    title: "Name",
                    placeholder: "Search a place or type a name",
                    text: $name,
                    mode: .placeName,
                    onResolved: { resolved in
                        hasUserEdits = true
                        address = resolved.address
                        latitude = resolved.coordinate.latitude
                        longitude = resolved.coordinate.longitude
                        if let city = resolved.city, !city.isEmpty {
                            location = city
                        }
                    },
                    onManualEdit: {
                        // A typed name is just a label; keep any existing coordinates.
                        hasUserEdits = true
                    }
                )
                EditorTextField(title: "Location/City", placeholder: "City or region", text: dirty($location))
                AddressAutocompleteField(
                    title: "Address",
                    placeholder: "Search for an address",
                    text: $address,
                    onResolved: { resolved in
                        hasUserEdits = true
                        latitude = resolved.coordinate.latitude
                        longitude = resolved.coordinate.longitude
                        if let city = resolved.city, !city.isEmpty, location.isEmpty {
                            location = city
                        }
                    },
                    onManualEdit: {
                        hasUserEdits = true
                        // Typed edits invalidate the old pin; background geocoding re-locates it.
                        latitude = 0
                        longitude = 0
                    }
                )
                
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Category")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(categories) { cat in
                    Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        dirtyCategory($selectedCategory).wrappedValue = cat
                                    }
                                    lightHaptic()
                    } label: {
                                    Text(cat.name ?? "Unnamed")
                                        .font(DesignSystem.Typography.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, DesignSystem.Spacing.md)
                                        .padding(.vertical, DesignSystem.Spacing.sm)
                                        .foregroundColor(selectedCategory?.id == cat.id ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textPrimary)
                                        .background(
                                            selectedCategory?.id == cat.id
                                                ? AnyView(LinearGradient(colors: type.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                                                : AnyView(DesignSystem.Colors.surface)
                                        )
                                        .cornerRadius(DesignSystem.CornerRadius.md)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                                .stroke(selectedCategory?.id == cat.id ? Color.clear : DesignSystem.Colors.border, lineWidth: 0.5)
                                        )
                                }
                            }
                        }
                    }
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Details Section
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Details")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            VStack(spacing: DesignSystem.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Price Range")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach(["$", "$$", "$$$", "$$$$"], id: \.self) { price in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    hasUserEdits = true
                                    priceRange = priceRange == price ? "" : price
                                }
                                lightHaptic()
                            } label: {
                                Text(price)
                                    .font(DesignSystem.Typography.caption)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, DesignSystem.Spacing.sm)
                                    .foregroundColor(priceRange == price ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textPrimary)
                                    .background(priceRange == price ? DesignSystem.Colors.success : DesignSystem.Colors.backgroundSecondary)
                                    .cornerRadius(DesignSystem.CornerRadius.sm)
                            }
                        }
                    }
                }
                
                if type == .restaurant {
                    EditorTextField(title: "Cuisine Type", placeholder: "Italian, Japanese, etc.", text: dirty($cuisineType))
                    EditorTextField(title: "Dish Recommendations", placeholder: "Must-try dishes", text: dirty($dishRecommendations))
                }
                
                EditorTextField(title: "Best Time to Go", placeholder: "Morning, weekend, etc.", text: dirty($bestTimeToGo))
                EditorTextField(title: "Who to Bring", placeholder: "Friends, family, date, etc.", text: dirty($whoToBring))
                        
                        if type != .restaurant {
                    EditorTextField(title: "Entry Fee", placeholder: "Free, $10, etc.", text: dirty($entryFee))
                }
                
                EditorTextField(
                    title: "Video Link",
                    placeholder: "TikTok or YouTube URL",
                    text: dirty($videoURL),
                    isURL: true
                )
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Visit Status Section
    private var visitStatusSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Visit Status")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            VStack(spacing: DesignSystem.Spacing.md) {
                Toggle(isOn: dirty($isFavorite)) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundColor(isFavorite ? DesignSystem.Colors.warning : DesignSystem.Colors.textTertiary)
                        Text("Favorite")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                }
                .tint(DesignSystem.Colors.warning)
                
                Toggle(isOn: dirty($hasVisited)) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: hasVisited ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(hasVisited ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary)
                        Text("I've Been Here")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                }
                .tint(DesignSystem.Colors.success)
                
                if hasVisited {
                    DatePicker("Date Visited", selection: dirty($dateVisited), displayedComponents: .date)
                        .font(DesignSystem.Typography.body)
                    
                    Toggle(isOn: dirty($wouldReturn)) {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Image(systemName: wouldReturn ? "arrow.counterclockwise.circle.fill" : "xmark.circle")
                                .foregroundColor(wouldReturn ? DesignSystem.Colors.info : DesignSystem.Colors.textTertiary)
                            Text("Would Return")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                        }
                    }
                    .tint(DesignSystem.Colors.info)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Ratings Section
    private var ratingsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Ratings")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            VStack(spacing: DesignSystem.Spacing.lg) {
                RatingSlider(title: "Overall", value: dirty($rating), color: DesignSystem.Colors.accent)
                RatingSlider(title: "Price", value: dirty($priceRating), color: DesignSystem.Colors.success)
                RatingSlider(title: "Quality", value: dirty($qualityRating), color: DesignSystem.Colors.info)
                RatingSlider(title: "Atmosphere", value: dirty($atmosphereRating), color: DesignSystem.Colors.warning)
                
                if type != .restaurant {
                    RatingSlider(title: "Fun Factor", value: dirty($funFactorRating), color: DesignSystem.Colors.error)
                    RatingSlider(title: "Scenery", value: dirty($sceneryRating), color: DesignSystem.Colors.info)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Notes Section
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Notes")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            TextEditor(text: dirty($notes))
                .font(DesignSystem.Typography.body)
                .frame(minHeight: 100)
                .padding(DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.surface)
                .cornerRadius(DesignSystem.CornerRadius.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                        .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                )
        }
    }
    
    // MARK: - Save Place
    @MainActor
    private func savePlace() async -> Bool {
        let ratingInt = Int16(rating)
        let priceRatingInt = Int16(priceRating)
        let qualityRatingInt = Int16(qualityRating)
        let atmosphereRatingInt = Int16(atmosphereRating)
        let funFactorRatingInt = Int16(funFactorRating)
        let sceneryRatingInt = Int16(sceneryRating)

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "Untitled Place" : trimmedName

        if let existingPlace = place {
            existingPlace.name = resolvedName
            existingPlace.address = address
            existingPlace.latitude = latitude
            existingPlace.longitude = longitude
            existingPlace.city = location
            existingPlace.notes = notes
            existingPlace.isVisited = hasVisited
            existingPlace.isFavorite = isFavorite
            existingPlace.rating = ratingInt
            existingPlace.visitedDate = hasVisited ? dateVisited : nil
            existingPlace.category = selectedCategory ?? category
            existingPlace.priceRange = priceRange
            existingPlace.cuisineType = cuisineType
            existingPlace.bestTimeToGo = bestTimeToGo
            existingPlace.whoToBring = whoToBring
            existingPlace.entryFee = entryFee
            existingPlace.dishRecommendations = dishRecommendations
            existingPlace.videoURL = MediaLink.storedString(from: videoURL)
            existingPlace.wouldReturn = wouldReturn
            existingPlace.overallRating = ratingInt
            existingPlace.priceRating = priceRatingInt
            existingPlace.qualityRating = qualityRatingInt
            existingPlace.atmosphereRating = atmosphereRatingInt
            existingPlace.funFactorRating = funFactorRatingInt
            existingPlace.sceneryRating = sceneryRatingInt
            
            let photoResult = await resolvePlacePhoto(
                placeID: existingPlace.id,
                previousPath: existingPlace.photoURL ?? existingPhotoURL
            )
            applyPlacePhotoResult(photoResult, to: existingPlace)
            
            existingPlace.modifiedDate = Date()
        } else {
            let newPlace = Place(context: viewContext)
            let placeID = UUID()
            newPlace.id = placeID
            newPlace.name = resolvedName
            newPlace.address = address
            newPlace.latitude = latitude
            newPlace.longitude = longitude
            newPlace.city = location
            newPlace.notes = notes
            newPlace.isVisited = hasVisited
            newPlace.isFavorite = isFavorite
            newPlace.rating = ratingInt
            newPlace.visitedDate = hasVisited ? dateVisited : nil
            newPlace.category = selectedCategory ?? category
            newPlace.priceRange = priceRange
            newPlace.cuisineType = cuisineType
            newPlace.bestTimeToGo = bestTimeToGo
            newPlace.whoToBring = whoToBring
            newPlace.entryFee = entryFee
            newPlace.dishRecommendations = dishRecommendations
            newPlace.videoURL = MediaLink.storedString(from: videoURL)
            newPlace.wouldReturn = wouldReturn
            newPlace.overallRating = ratingInt
            newPlace.priceRating = priceRatingInt
            newPlace.qualityRating = qualityRatingInt
            newPlace.atmosphereRating = atmosphereRatingInt
            newPlace.funFactorRating = funFactorRatingInt
            newPlace.sceneryRating = sceneryRatingInt
            
            let photoResult = await resolvePlacePhoto(placeID: placeID, previousPath: nil)
            applyPlacePhotoResult(photoResult, to: newPlace)
            
            newPlace.createdDate = Date()
            newPlace.modifiedDate = Date()
        }
        
        if viewContext.inkSlateSave(module: "Places") {
            lightHaptic()
            return true
        }

        saveFailedMessage = "Failed to save."
        return false
    }

    private enum PlacePhotoSaveResult {
        case unchanged
        case removed
        case cloud(String)
        case localOnly(String)
        case failed
    }

    private func resolvePlacePhoto(placeID: UUID?, previousPath: String?) async -> PlacePhotoSaveResult {
        if photoRemoved {
            await deletePlacePhotoAsset(at: previousPath)
            return .removed
        }

        guard photoChanged, let image = selectedImage, let placeID else {
            return .unchanged
        }

        let normalized = PlaceImageStore.normalizedJPEGData(from: image)
            .flatMap { platformImage(from: $0) } ?? image

        do {
            let photoURL = try await CloudKitAssetService.shared.uploadPhoto(normalized, for: placeID)
            PlaceImageStore.cacheSyncedImage(normalized, recordName: photoURL)
            if let previousPath, previousPath != photoURL {
                await deletePlacePhotoAsset(at: previousPath)
            }
            return .cloud(photoURL)
        } catch {
            do {
                let fileName = try PlaceImageStore.saveImage(
                    normalized,
                    for: placeID,
                    replacing: previousPath.flatMap { PlaceImageStore.isCloudRecordName($0) ? nil : $0 }
                )
                ErrorHandlingService.shared.reportOperationFailure(
                    module: "Places",
                    detail: "Photo saved on this device, but iCloud sync failed. It will retry when you open Places."
                )
                return .localOnly(fileName)
            } catch {
                saveFailedMessage = "Photo couldn't be saved: \(error.localizedDescription)"
                ErrorHandlingService.shared.reportOperationFailure(
                    module: "Places",
                    detail: "Photo save failed: \(error.localizedDescription)"
                )
                return .failed
            }
        }
    }

    private func applyPlacePhotoResult(_ result: PlacePhotoSaveResult, to place: Place) {
        switch result {
        case .unchanged:
            break
        case .removed:
            place.photoURL = nil
            existingPhotoURL = nil
        case .cloud(let url), .localOnly(let url):
            place.photoURL = url
            existingPhotoURL = url
        case .failed:
            break
        }
    }

    private func deletePlacePhotoAsset(at path: String?) async {
        guard let path, !path.isEmpty else { return }
        if PlaceImageStore.isCloudRecordName(path) {
            try? await CloudKitAssetService.shared.deletePhoto(recordName: path)
        } else {
            PlaceImageStore.deleteImage(at: path)
        }
    }
}

// MARK: - Editor Text Field
struct EditorTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isURL: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            TextField(placeholder, text: $text)
                .font(DesignSystem.Typography.body)
                #if os(iOS)
                .keyboardType(isURL ? .URL : .default)
                .textInputAutocapitalization(isURL ? .never : .sentences)
                .autocorrectionDisabled(isURL)
                #endif
                .padding(DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.backgroundSecondary)
                .cornerRadius(DesignSystem.CornerRadius.sm)
        }
    }
}

// MARK: - Rating Slider
struct RatingSlider: View {
    let title: String
    @Binding var value: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Spacer()
                
                Text("\(Int(value))/10")
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            
            Slider(value: $value, in: 1...10, step: 1)
                .tint(color)
        }
    }
}

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Image Picker
#if canImport(UIKit)
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: PlatformImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let img = info[.originalImage] as? UIImage {
                if let data = PlaceImageStore.normalizedJPEGData(from: img),
                   let normalized = UIImage(data: data) {
                    parent.image = normalized
                } else {
                    parent.image = img
                }
            }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
#elseif canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
struct ImagePicker: View {
    @Binding var image: PlatformImage?
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 16) {
            Text("Choose an image")
            Button("Choose Image…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image]
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url,
                   let data = try? Data(contentsOf: url),
                   let img = platformImage(from: data) {
                    if let jpeg = PlaceImageStore.normalizedJPEGData(from: img),
                       let normalized = platformImage(from: jpeg) {
                        image = normalized
                    } else {
                        image = img
                    }
                }
                dismiss()
            }
            Button("Cancel") { dismiss() }
        }
        .padding()
        .frame(minWidth: 260, minHeight: 100)
    }
}
#endif
