//
//  PlacesViews.swift
//  InkSlate
//
//  Redesigned Places Feature - Modern Minimalist UI
//

import SwiftUI
import CoreData
#if canImport(UIKit)
import UIKit
#endif

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

private func inferredPlaceType(for place: Place) -> PlaceType {
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
    
    return .place
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
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PlaceCategory.name, ascending: true)]
    ) private var allCategories: FetchedResults<PlaceCategory>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Place.name, ascending: true)]
    ) private var allPlaces: FetchedResults<Place>
    
    @State private var selectedTab: PlaceType = .restaurant
    @State private var searchText = ""
    @State private var showingQuickAdd = false
    @State private var animateHeader = false
    
    private func filteredCategories(for type: PlaceType) -> [PlaceCategory] {
        Array(allCategories).filter { category in
            // If category has a type set, use it directly
            if let categoryType = category.type {
                return categoryType == type.rawValue
            }
            // For backward compatibility: infer type for categories without type set
            return inferredPlaceType(for: category) == type
        }
    }
    
    private var totalPlaces: Int {
        allPlaces.count
    }
    
    private var visitedPlaces: Int {
        allPlaces.filter { $0.isVisited }.count
    }
    
    private var wishlistPlaces: Int {
        allPlaces.filter { !$0.isVisited }.count
    }
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
        VStack(spacing: 0) {
                    // Header Section
                    headerSection
                    
                    // Stats Cards
                    statsSection
                        .padding(.top, DesignSystem.Spacing.lg)
                    
                    // Type Selector
                    typeSelector
                        .padding(.top, DesignSystem.Spacing.xl)
                    
                    // Categories Grid
                    categoriesSection
                        .padding(.top, DesignSystem.Spacing.lg)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, 100)
            }
        }
        .sheet(isPresented: $showingQuickAdd) {
            QuickAddPlaceView(type: selectedTab)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                animateHeader = true
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                Text("Places")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Text("Your personal guide")
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                
                Spacer()
                
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
        HStack(spacing: DesignSystem.Spacing.md) {
            PlaceStatCard(
                title: "Total",
                value: "\(totalPlaces)",
                icon: "map",
                gradient: [DesignSystem.Colors.accent, DesignSystem.Colors.accentLight]
            )
            
            PlaceStatCard(
                title: "Visited",
                value: "\(visitedPlaces)",
                icon: "checkmark.circle",
                gradient: [DesignSystem.Colors.success, DesignSystem.Colors.success.opacity(0.7)]
            )
            
            PlaceStatCard(
                title: "Wishlist",
                value: "\(wishlistPlaces)",
                icon: "star",
                gradient: [DesignSystem.Colors.warning, DesignSystem.Colors.warning.opacity(0.7)]
            )
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
                Text("Categories")
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
                            CategoryCard(
                                category: category,
                type: selectedTab,
                                placeCount: allPlaces.filter { $0.category?.id == category.id }.count
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    
                    // Add Category Card
                    AddCategoryCard(type: selectedTab)
                }
            }
        }
        .opacity(animateHeader ? 1 : 0)
        .offset(y: animateHeader ? 0 : 10)
        .animation(.easeOut(duration: 0.6).delay(0.3), value: animateHeader)
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
        .sheet(isPresented: $showingNewCategory) {
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
        .sheet(isPresented: $showingNewCategory) {
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
                                placeCount: allPlaces.filter { $0.category?.id == category.id }.count
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteCategory(category)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
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
        .sheet(isPresented: $showingNewCategory) {
            NewCategoryView(type: type)
        }
    }
    
    private func deleteCategory(_ category: PlaceCategory) {
        mediumHaptic()
        let uncategorized = getOrCreateUncategorizedCategory()
        let placesInCategory = allPlaces.filter { $0.category?.id == category.id }
        for place in placesInCategory {
            place.category = uncategorized
            place.modifiedDate = Date()
        }
        viewContext.delete(category)
        try? viewContext.save()
    }
    
    private func getOrCreateUncategorizedCategory() -> PlaceCategory {
        let fetch = NSFetchRequest<PlaceCategory>(entityName: "PlaceCategory")
        fetch.fetchLimit = 1
        fetch.predicate = NSPredicate(format: "name == %@ AND type == %@", "Uncategorized", type.rawValue)
        if let existing = try? viewContext.fetch(fetch).first {
            return existing
        }
        
        let category = PlaceCategory(context: viewContext)
        category.id = UUID()
        category.name = "Uncategorized"
        category.type = type.rawValue
        category.icon = "tray"
        category.color = "#6B7280"
        category.sortOrder = -1
        category.createdDate = Date()
        category.modifiedDate = Date()
        viewContext.insert(category)
        try? viewContext.save()
        return category
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
                    // Icon Preview
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: type.gradient.map { $0.opacity(0.15) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: type.icon)
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(type.gradient[0])
                    }
                    .padding(.top, DesignSystem.Spacing.xl)
                    
                    // Name Input
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
                        category.icon = type.lowercaseKey
                        category.type = type.rawValue
        
                        do {
                            try viewContext.save()
            dismiss()
                        } catch {
                            print("Failed to create category: \(error.localizedDescription)")
                        }
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
            // If category has a type set, use it directly
            if let categoryType = category.type {
                return categoryType == type.rawValue
            }
            // For backward compatibility: infer type for categories without type set
            return inferredPlaceType(for: category) == type
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DesignSystem.Spacing.xl) {
                        // Name Input
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
                        
                        // Category Selector
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
                        
                        // Wishlist Toggle
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
                    .disabled(name.isEmpty || selectedCategory == nil)
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
        let newPlace = Place(context: viewContext)
        newPlace.id = UUID()
        newPlace.name = name
        newPlace.isVisited = !isWishlist
        newPlace.category = selectedCategory
        newPlace.createdDate = Date()
        newPlace.modifiedDate = Date()
        newPlace.rating = 5
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Failed to save place: \(error.localizedDescription)")
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
    
    private var places: [Place] {
        var filtered: [Place]
        
        if wishlistOnly {
            filtered = Array(allPlaces).filter { !$0.isVisited }
        } else if favoritesOnly {
            filtered = Array(allPlaces).filter { $0.isFavorite }
        } else if let category = category {
            filtered = Array(allPlaces).filter { $0.category?.id == category.id }
        } else {
            // "All Places" view (includes uncategorized).
            filtered = Array(allPlaces)
        }
        
        // Apply search filter
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
                        // Search Bar
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
                        
                        // Places List
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
            ToolbarItem(placement: .primaryAction) {
            Button {
                    lightHaptic()
                showingNewPlace = true
            } label: {
                Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewPlace) {
            PlaceEditorView(category: category, place: nil, type: type)
        }
        .sheet(item: $selectedPlace) { place in
            PlaceDetailView(place: place)
        }
    }
    
    private func deletePlace(_ place: Place) {
        mediumHaptic()
        viewContext.delete(place)
        try? viewContext.save()
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
    let place: Place
    let type: PlaceType
    let onTap: () -> Void
    
    @State private var photoImage: PlatformImage?
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Photo or Placeholder
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
                
                // Content
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
                
                // Chevron
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
        .onAppear {
            loadPhoto()
        }
    }
    
    private func loadPhoto() {
        guard let photoURL = place.photoURL, photoImage == nil else { return }
        Task {
            if let image = try? await CloudKitAssetService.shared.downloadPhoto(recordName: photoURL) {
                await MainActor.run {
                    photoImage = image
                }
            }
        }
    }
}

// MARK: - Place Detail View
struct PlaceDetailView: View {
    let place: Place
    @State private var showingEditSheet = false
    @State private var photoImage: PlatformImage?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DesignSystem.Spacing.lg) {
                    // Photo Section
                    if let image = photoImage {
                        Image(platformImage: image)
                            .resizable()
                            .scaledToFill()
                                .frame(height: 220)
                                .frame(maxWidth: .infinity)
                            .clipped()
                                .cornerRadius(DesignSystem.CornerRadius.xl)
                        } else {
                            // Gradient Placeholder
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
                        
                        // Header Info
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
                            }
                        }
                        
                        // Quick Tags
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
                        
                        // Details Section
                        if hasDetails {
                            DetailsSectionView(place: place)
                        }
                        
                        // Rating Section
                    if place.isVisited {
                            RatingSectionView(place: place)
                        }
                        
                        // Notes Section
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
            .sheet(isPresented: $showingEditSheet) {
                PlaceEditorView(category: place.category, place: place, type: inferredPlaceType(for: place))
            }
            .onAppear {
                loadPhoto()
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
    
    private func loadPhoto() {
        guard let photoURL = place.photoURL, photoImage == nil else { return }
        Task {
            if let image = try? await CloudKitAssetService.shared.downloadPhoto(recordName: photoURL) {
                await MainActor.run {
                    photoImage = image
                }
            }
        }
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
    
    @State private var name = ""
    @State private var location = ""
    @State private var address = ""
    @State private var priceRange = ""
    @State private var cuisineType = ""
    @State private var bestTimeToGo = ""
    @State private var whoToBring = ""
    @State private var entryFee = ""
    @State private var notes = ""
    @State private var dishRecommendations = ""
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
    @State private var selectedCategory: PlaceCategory?
    @State private var dateVisited = Date()
    @State private var isSaving = false
    @State private var currentSection = 0
    
    private var categories: [PlaceCategory] {
        Array(allCategories).filter { category in
            // If category has a type set, use it directly
            if let categoryType = category.type {
                return categoryType == type.rawValue
            }
            // For backward compatibility: infer type for categories without type set
            return inferredPlaceType(for: category) == type
        }
    }
    
    init(category: PlaceCategory?, place: Place?, type: PlaceType) {
        self.category = category
        self.place = place
        self.type = type
        
        _selectedCategory = State(initialValue: place?.category ?? category)
        _name = State(initialValue: place?.name ?? "")
        _address = State(initialValue: place?.address ?? "")
        _notes = State(initialValue: place?.notes ?? "")
        _hasVisited = State(initialValue: place?.isVisited ?? false)
        _isFavorite = State(initialValue: place?.isFavorite ?? false)
        _rating = State(initialValue: Double(place?.rating ?? 5))
        _dateVisited = State(initialValue: place?.visitedDate ?? Date())
        _location = State(initialValue: place?.city ?? "")
        _priceRange = State(initialValue: place?.priceRange ?? "")
        _cuisineType = State(initialValue: place?.cuisineType ?? "")
        _bestTimeToGo = State(initialValue: place?.bestTimeToGo ?? "")
        _whoToBring = State(initialValue: place?.whoToBring ?? "")
        _entryFee = State(initialValue: place?.entryFee ?? "")
        _dishRecommendations = State(initialValue: place?.dishRecommendations ?? "")
        _wouldReturn = State(initialValue: place?.wouldReturn ?? true)
        _priceRating = State(initialValue: Double(place?.priceRating ?? 5))
        _qualityRating = State(initialValue: Double(place?.qualityRating ?? 5))
        _atmosphereRating = State(initialValue: Double(place?.atmosphereRating ?? 5))
        _funFactorRating = State(initialValue: Double(place?.funFactorRating ?? 5))
        _sceneryRating = State(initialValue: Double(place?.sceneryRating ?? 5))
        _selectedImage = State(initialValue: nil)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DesignSystem.Spacing.xl) {
                        // Photo Section
                        photoSection
                        
                        // Basic Info Section
                        basicInfoSection
                        
                        // Details Section
                        detailsSection
                        
                        // Visit Status Section
                        visitStatusSection
                        
                        // Ratings Section (if visited)
                        if hasVisited {
                            ratingsSection
                        }
                        
                        // Notes Section
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
                                await savePlace()
                                isSaving = false
                                dismiss()
                            }
                        }
                        .disabled(name.isEmpty || selectedCategory == nil)
                        .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $selectedImage)
            }
            .task {
                if let place = place, let photoURL = place.photoURL, selectedImage == nil {
                    if let image = try? await CloudKitAssetService.shared.downloadPhoto(recordName: photoURL) {
                        selectedImage = image
                    }
                }
            }
        }
    }
    
    // MARK: - Photo Section
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Photo")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Button {
                showingImagePicker = true
            } label: {
                    if let image = selectedImage {
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
        }
    }
    
    // MARK: - Basic Info Section
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Basic Info")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            VStack(spacing: DesignSystem.Spacing.md) {
                EditorTextField(title: "Name", placeholder: "Place name", text: $name)
                EditorTextField(title: "Location/City", placeholder: "City or region", text: $location)
                EditorTextField(title: "Address", placeholder: "Full address", text: $address)
                
                // Category Picker
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Category")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(categories) { cat in
                    Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedCategory = cat
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
                // Price Range Picker
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Price Range")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach(["$", "$$", "$$$", "$$$$"], id: \.self) { price in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                    EditorTextField(title: "Cuisine Type", placeholder: "Italian, Japanese, etc.", text: $cuisineType)
                    EditorTextField(title: "Dish Recommendations", placeholder: "Must-try dishes", text: $dishRecommendations)
                }
                
                EditorTextField(title: "Best Time to Go", placeholder: "Morning, weekend, etc.", text: $bestTimeToGo)
                EditorTextField(title: "Who to Bring", placeholder: "Friends, family, date, etc.", text: $whoToBring)
                        
                        if type != .restaurant {
                    EditorTextField(title: "Entry Fee", placeholder: "Free, $10, etc.", text: $entryFee)
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
    
    // MARK: - Visit Status Section
    private var visitStatusSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Visit Status")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            VStack(spacing: DesignSystem.Spacing.md) {
                Toggle(isOn: $isFavorite) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundColor(isFavorite ? DesignSystem.Colors.warning : DesignSystem.Colors.textTertiary)
                        Text("Favorite")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                }
                .tint(DesignSystem.Colors.warning)
                
                Toggle(isOn: $hasVisited) {
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
                    DatePicker("Date Visited", selection: $dateVisited, displayedComponents: .date)
                        .font(DesignSystem.Typography.body)
                    
                    Toggle(isOn: $wouldReturn) {
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
                RatingSlider(title: "Overall", value: $rating, color: DesignSystem.Colors.accent)
                RatingSlider(title: "Price", value: $priceRating, color: DesignSystem.Colors.success)
                RatingSlider(title: "Quality", value: $qualityRating, color: DesignSystem.Colors.info)
                RatingSlider(title: "Atmosphere", value: $atmosphereRating, color: DesignSystem.Colors.warning)
                
                if type != .restaurant {
                    RatingSlider(title: "Fun Factor", value: $funFactorRating, color: DesignSystem.Colors.error)
                    RatingSlider(title: "Scenery", value: $sceneryRating, color: DesignSystem.Colors.info)
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
            
            TextEditor(text: $notes)
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
    private func savePlace() async {
        let ratingInt = Int16(rating)
        let priceRatingInt = Int16(priceRating)
        let qualityRatingInt = Int16(qualityRating)
        let atmosphereRatingInt = Int16(atmosphereRating)
        let funFactorRatingInt = Int16(funFactorRating)
        let sceneryRatingInt = Int16(sceneryRating)
        
        if let existingPlace = place {
            existingPlace.name = name
            existingPlace.address = address
            existingPlace.city = location
            existingPlace.notes = notes
            existingPlace.isVisited = hasVisited
            existingPlace.isFavorite = isFavorite
            existingPlace.rating = ratingInt
            existingPlace.visitedDate = hasVisited ? dateVisited : nil
            existingPlace.category = selectedCategory
            existingPlace.priceRange = priceRange
            existingPlace.cuisineType = cuisineType
            existingPlace.bestTimeToGo = bestTimeToGo
            existingPlace.whoToBring = whoToBring
            existingPlace.entryFee = entryFee
            existingPlace.dishRecommendations = dishRecommendations
            existingPlace.wouldReturn = wouldReturn
            existingPlace.overallRating = ratingInt
            existingPlace.priceRating = priceRatingInt
            existingPlace.qualityRating = qualityRatingInt
            existingPlace.atmosphereRating = atmosphereRatingInt
            existingPlace.funFactorRating = funFactorRatingInt
            existingPlace.sceneryRating = sceneryRatingInt
            
            if let image = selectedImage, let placeID = existingPlace.id {
                if let oldPhotoURL = existingPlace.photoURL {
                    try? await CloudKitAssetService.shared.deletePhoto(recordName: oldPhotoURL)
                }
                do {
                    let photoURL = try await CloudKitAssetService.shared.uploadPhoto(image, for: placeID)
                    existingPlace.photoURL = photoURL
                } catch {
                    print("Failed to upload photo: \(error.localizedDescription)")
                }
            } else if selectedImage == nil, let oldPhotoURL = existingPlace.photoURL {
                try? await CloudKitAssetService.shared.deletePhoto(recordName: oldPhotoURL)
                existingPlace.photoURL = nil
            }
            
            existingPlace.modifiedDate = Date()
        } else {
            let newPlace = Place(context: viewContext)
            let placeID = UUID()
            newPlace.id = placeID
            newPlace.name = name
            newPlace.address = address
            newPlace.city = location
            newPlace.notes = notes
            newPlace.isVisited = hasVisited
            newPlace.isFavorite = isFavorite
            newPlace.rating = ratingInt
            newPlace.visitedDate = hasVisited ? dateVisited : nil
            newPlace.category = selectedCategory
            newPlace.priceRange = priceRange
            newPlace.cuisineType = cuisineType
            newPlace.bestTimeToGo = bestTimeToGo
            newPlace.whoToBring = whoToBring
            newPlace.entryFee = entryFee
            newPlace.dishRecommendations = dishRecommendations
            newPlace.wouldReturn = wouldReturn
            newPlace.overallRating = ratingInt
            newPlace.priceRating = priceRatingInt
            newPlace.qualityRating = qualityRatingInt
            newPlace.atmosphereRating = atmosphereRatingInt
            newPlace.funFactorRating = funFactorRatingInt
            newPlace.sceneryRating = sceneryRatingInt
            
            if let image = selectedImage {
                do {
                    let photoURL = try await CloudKitAssetService.shared.uploadPhoto(image, for: placeID)
                    newPlace.photoURL = photoURL
                } catch {
                    print("Failed to upload photo: \(error.localizedDescription)")
                }
            }
            
            newPlace.createdDate = Date()
            newPlace.modifiedDate = Date()
            viewContext.insert(newPlace)
        }
        
        try? viewContext.save()
        lightHaptic()
    }
}

// MARK: - Editor Text Field
struct EditorTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            TextField(placeholder, text: $text)
                .font(DesignSystem.Typography.body)
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
            if let img = info[.originalImage] as? UIImage { parent.image = img }
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
                panel.allowedContentTypes = [.png, .jpeg]
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url,
                   let data = try? Data(contentsOf: url),
                   let img = platformImage(from: data) { image = img }
                dismiss()
            }
            Button("Cancel") { dismiss() }
        }
        .padding()
        .frame(minWidth: 260, minHeight: 100)
    }
}
#endif
