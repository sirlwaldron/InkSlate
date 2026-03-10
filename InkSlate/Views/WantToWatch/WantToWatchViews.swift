//
//  WantToWatchViews.swift
//  InkSlate
//
//  Created by Lucas Waldron on 1/2/25.
//

import SwiftUI
import CoreData

// MARK: - Want to Watch Main View
struct WantToWatchMainView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WantToWatchItem.createdDate, ascending: false)],
        animation: .default)
    private var allItems: FetchedResults<WantToWatchItem>
    
    @State private var searchText = ""
    @State private var searchResults: [TMDBItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var showingWatchedOnly = false
    @State private var selectedFilter: WatchFilter? = nil // nil means "All"
    @State private var selectedCategory: String? = nil // nil means "All Categories"
    @State private var showingStats = false
    @State private var animateCards = false
    
    enum WatchFilter: String, CaseIterable {
        case upNext = "Up Next"
        case watched = "Watched"
        case all = "All"
        
        var icon: String {
            switch self {
            case .upNext: return "play.circle.fill"
            case .watched: return "checkmark.circle.fill"
            case .all: return "list.bullet"
            }
        }
        
        var color: Color {
            switch self {
            case .upNext: return DesignSystem.Colors.info
            case .watched: return DesignSystem.Colors.success
            case .all: return DesignSystem.Colors.accent
            }
        }
    }
    
    var notWatchedItems: [WantToWatchItem] {
        allItems.filter { !$0.isWatched }
    }
    
    var watchedItems: [WantToWatchItem] {
        allItems.filter { $0.isWatched }
    }
    
    var filteredItems: [WantToWatchItem] {
        let items: [WantToWatchItem]
        if let filter = selectedFilter {
            switch filter {
            case .upNext: items = notWatchedItems
            case .watched: items = watchedItems
            case .all: items = Array(allItems)
            }
        } else {
            // Show all when no filter is selected
            items = Array(allItems)
        }
        
        // Apply category filter if one is selected
        if let category = selectedCategory {
            return items.filter { $0.category == category }
        }
        
        return items
    }
    
    // Group items by category
    var groupedItems: [String: [WantToWatchItem]] {
        Dictionary(grouping: filteredItems) { item in
            item.category
        }
    }
    
    // Get counts for each category (based on current filter)
    func getCategoryCount(_ category: String) -> Int {
        let items: [WantToWatchItem]
        if let filter = selectedFilter {
            switch filter {
            case .upNext: items = notWatchedItems
            case .watched: items = watchedItems
            case .all: items = Array(allItems)
            }
        } else {
            items = Array(allItems)
        }
        return items.filter { $0.category == category }.count
    }
    
    // Ordered categories for display
    var orderedCategories: [String] {
        let standardCategories = ["anime", "tv", "movie"]
        let existingCategories = Set(groupedItems.keys)
        let additionalCategories = existingCategories.subtracting(standardCategories).sorted()
        return standardCategories + additionalCategories
    }
    
    var body: some View {
        ZStack {
            // Animated gradient background
            LinearGradient(
                colors: [
                    DesignSystem.Colors.background,
                    DesignSystem.Colors.backgroundSecondary.opacity(0.3),
            DesignSystem.Colors.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                .ignoresSafeArea()
            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: animateCards)
            
            NavigationView {
                ScrollView {
                VStack(spacing: 0) {
                        // Enhanced Header with Stats
                        VStack(spacing: DesignSystem.Spacing.lg) {
                            // Main Header
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("🎬")
                                            .font(.system(size: 28))
                                    Text("Want to Watch")
                                        .font(DesignSystem.Typography.largeTitle)
                                        .fontWeight(.bold)
                                        .foregroundColor(DesignSystem.Colors.textPrimary)
                                    }
                                    
                                    Text("Your personal entertainment hub")
                                        .font(DesignSystem.Typography.callout)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                }
                                
                                Spacer()
                                
                                // Stats Button
                                Button(action: { showingStats.toggle() }) {
                                    VStack(spacing: 2) {
                                        Image(systemName: "chart.bar.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                        Text("Stats")
                                            .font(DesignSystem.Typography.caption)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(DesignSystem.Colors.info)
                                    .padding(8)
                                    .background(DesignSystem.Colors.info.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            // Quick Stats Row
                            HStack(spacing: DesignSystem.Spacing.lg) {
                                StatCard(
                                    title: "Total",
                                    value: "\(allItems.count)",
                                    icon: "list.bullet",
                                    color: DesignSystem.Colors.accent
                                )
                                
                                StatCard(
                                    title: "Up Next",
                                    value: "\(notWatchedItems.count)",
                                    icon: "play.circle",
                                    color: DesignSystem.Colors.info
                                )
                                
                                StatCard(
                                    title: "Watched",
                                    value: "\(watchedItems.count)",
                                    icon: "checkmark.circle",
                                    color: DesignSystem.Colors.success
                                )
                            }
                            
                            // Enhanced Search Bar
                            SearchBarEnhanced(text: $searchText)
                        }
                        .padding(DesignSystem.Spacing.lg)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(DesignSystem.Colors.surface)
                                .shadow(color: DesignSystem.Shadows.small, radius: 8, x: 0, y: 4)
                        )
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.top, DesignSystem.Spacing.sm)
                    
                        // Combined Filter Bar
                        if searchText.isEmpty {
                            VStack(spacing: DesignSystem.Spacing.sm) {
                                // Category Tabs Row
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: DesignSystem.Spacing.sm) {
                                        // All Categories tab
                                        CompactCategoryTab(
                                            title: "All",
                                            icon: "square.grid.2x2",
                                            isSelected: selectedCategory == nil,
                                            count: nil,
                                            color: DesignSystem.Colors.accent
                                        ) {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                selectedCategory = nil
                                            }
                                        }
                                        
                                        // Anime tab
                                        CompactCategoryTab(
                                            title: "Anime",
                                            icon: "sparkles",
                                            isSelected: selectedCategory == "anime",
                                            count: getCategoryCount("anime"),
                                            color: .purple
                                        ) {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                selectedCategory = "anime"
                                            }
                                        }
                                        
                                        // TV Shows tab
                                        CompactCategoryTab(
                                            title: "TV",
                                            icon: "tv.fill",
                                            isSelected: selectedCategory == "tv",
                                            count: getCategoryCount("tv"),
                                            color: DesignSystem.Colors.success
                                        ) {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                selectedCategory = "tv"
                                            }
                                        }
                                        
                                        // Movies tab
                                        CompactCategoryTab(
                                            title: "Movies",
                                            icon: "film.fill",
                                            isSelected: selectedCategory == "movie",
                                            count: getCategoryCount("movie"),
                                            color: DesignSystem.Colors.info
                                        ) {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                selectedCategory = "movie"
                                            }
                                        }
                                    }
                                    .padding(.horizontal, DesignSystem.Spacing.lg)
                                }
                                
                                // Status Filter Pills Row
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: DesignSystem.Spacing.sm) {
                                        ForEach(WatchFilter.allCases.filter { $0 != .all }, id: \.self) { filter in
                                            CompactFilterPill(
                                                filter: filter,
                                                isSelected: selectedFilter == filter,
                                                count: getCount(for: filter)
                                            ) {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    // Toggle behavior: if already selected, deselect to show all
                                                    if selectedFilter == filter {
                                                        selectedFilter = nil
                                                    } else {
                                                        selectedFilter = filter
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, DesignSystem.Spacing.lg)
                                }
                            }
                            .padding(.vertical, DesignSystem.Spacing.sm)
                    }
                    
                    // Content
                    if isSearching {
                            VStack(spacing: DesignSystem.Spacing.xl) {
                            Spacer()
                            LottieLoadingView()
                            Text("Searching...")
                                .font(DesignSystem.Typography.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            Spacer()
                        }
                            .frame(height: 300)
                    } else if !searchText.isEmpty && !searchResults.isEmpty {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                            HStack {
                                Text("Search Results")
                                    .font(DesignSystem.Typography.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                Spacer()
                                Text("\(searchResults.count)")
                                    .font(DesignSystem.Typography.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(DesignSystem.Colors.info)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(DesignSystem.Colors.info.opacity(0.1))
                                        .cornerRadius(12)
                            }
                                .padding(.horizontal, DesignSystem.Spacing.lg)
                            
                                LazyVStack(spacing: DesignSystem.Spacing.md) {
                                    ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, item in
                                        SearchResultCardEnhanced(item: item) {
                                            addToWantToWatch(item)
                                        }
                                        .transition(.asymmetric(
                                            insertion: .scale.combined(with: .opacity),
                                            removal: .scale.combined(with: .opacity)
                                        ))
                                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.1), value: searchResults.count)
                                    }
                                }
                                .padding(.horizontal, DesignSystem.Spacing.lg)
                        }
                    } else if !searchText.isEmpty && searchResults.isEmpty {
                        VStack(spacing: DesignSystem.Spacing.xl) {
                            Spacer()
                                Image(systemName: "magnifyingglass.circle")
                                    .font(.system(size: 64, weight: .light))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                            
                                VStack(spacing: 12) {
                                Text("No Results")
                                    .font(DesignSystem.Typography.title1)
                                    .fontWeight(.bold)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                
                                Text("Try searching with different keywords")
                                    .font(DesignSystem.Typography.callout)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            Spacer()
                        }
                            .frame(height: 300)
                    } else {
                        if allItems.isEmpty {
                            VStack(spacing: DesignSystem.Spacing.xl) {
                                Spacer()
                                    Image(systemName: "popcorn.fill")
                                    .font(.system(size: 64, weight: .light))
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                                
                                VStack(spacing: 12) {
                                    Text("Your list is empty")
                                        .font(DesignSystem.Typography.largeTitle)
                                        .fontWeight(.bold)
                                        .foregroundColor(DesignSystem.Colors.textPrimary)
                                    
                                    Text("Search and add movies & TV shows to get started")
                                        .font(DesignSystem.Typography.callout)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                Spacer()
                            }
                                .frame(height: 300)
                            .padding(DesignSystem.Spacing.xl)
                        } else {
                            if selectedCategory != nil {
                                // Show flat list when a category is selected
                                LazyVStack(spacing: DesignSystem.Spacing.md) {
                                    ForEach(Array(filteredItems.enumerated()), id: \.element.objectID) { index, item in
                                        WantToWatchItemCardEnhanced(item: item, isWatched: item.isWatched)
                                            .transition(.asymmetric(
                                                insertion: .scale.combined(with: .opacity),
                                                removal: .scale.combined(with: .opacity)
                                            ))
                                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.05), value: filteredItems)
                                    }
                                }
                                .padding(.horizontal, DesignSystem.Spacing.lg)
                                .padding(.bottom, DesignSystem.Spacing.xl)
                            } else {
                                // Show grouped items when no category is selected
                                LazyVStack(spacing: DesignSystem.Spacing.lg) {
                                    ForEach(orderedCategories, id: \.self) { category in
                                        if let items = groupedItems[category], !items.isEmpty {
                                            MediaCategorySection(
                                                category: category,
                                                items: items
                                            )
                                        }
                                    }
                                }
                                .padding(.horizontal, DesignSystem.Spacing.lg)
                                .padding(.bottom, DesignSystem.Spacing.xl)
                            }
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .onChange(of: searchText) { _, newValue in
                performSearch(newValue)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5)) {
                    animateCards = true
                }
            }
            .sheet(isPresented: $showingStats) {
                WatchStatsView(items: allItems)
            }
            }
        }
    }
    
    private func getCount(for filter: WatchFilter) -> Int {
        switch filter {
        case .upNext: return notWatchedItems.count
        case .watched: return watchedItems.count
        case .all: return allItems.count
        }
    }
    
    private func getCountForCurrentFilter() -> Int {
        if let filter = selectedFilter {
            return getCount(for: filter)
        }
        return allItems.count
    }
    
    private func performSearch(_ query: String) {
        searchTask?.cancel()
        
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                try Task.checkCancellation()
                let results = try await TMDBService.shared.searchMulti(query: trimmed)
                
                if !Task.isCancelled {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                if !Task.isCancelled {
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }
    
    private func addToWantToWatch(_ item: TMDBItem) {
        let newItem = WantToWatchItem(context: viewContext)
        newItem.id = UUID()  // Required for CloudKit sync
        newItem.createdDate = Date()
        newItem.modifiedDate = Date()
        newItem.tmdbId = Int32(item.id)
        newItem.title = item.displayTitle
        newItem.overview = item.overview
        newItem.posterPath = item.posterPath
        newItem.backdropPath = item.backdropPath
        newItem.rating = item.rating
        newItem.isMovie = item.mediaType == "movie"
        newItem.releaseDate = TMDBService.shared.parseDate(item.releaseDate ?? item.firstAirDate)
        newItem.createdDate = Date()
        newItem.modifiedDate = Date()
        newItem.isWatched = false
        
        // Set default category based on isMovie
        newItem.mediaCategory = item.mediaType == "movie" ? "movie" : "tv"
        
        // Fetch details to determine if anime (async, will update category if needed)
        Task {
            await determineAndSetCategory(for: newItem)
        }
        
        do {
            try viewContext.save()
            searchText = ""
            searchResults = []
        } catch {
            // Failed to add item to watch list
        }
    }
    
    private func determineAndSetCategory(for item: WantToWatchItem) async {
        do {
            let details = try await TMDBService.shared.fetchFullDetails(
                id: Int(item.tmdbId),
                isMovie: item.isMovie
            )
            
            // Check if it's anime based on genres
            // TMDB Anime genre ID is 16 (Animation), and we also check for common anime-related genre names
            let isAnime = details.genres.contains { genre in
                genre.id == 16 || // Animation genre ID
                genre.name.lowercased().contains("anime") ||
                (genre.name == "Animation" && item.overview?.lowercased().contains("japan") == true)
            }
            
            await MainActor.run {
                if isAnime {
                    item.mediaCategory = "anime"
                } else {
                    item.mediaCategory = item.isMovie ? "movie" : "tv"
                }
                item.modifiedDate = Date()
                
                do {
                    try viewContext.save()
                } catch {
                    // Failed to update category
                }
            }
        } catch {
            // If fetching fails, keep the default category
        }
    }
}

// MARK: - Stat Card Component
struct StatCard: View {
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
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Category Tab Component
struct CategoryTab: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let count: Int?
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(title)
                    .font(DesignSystem.Typography.callout)
                    .fontWeight(.medium)
                
                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? color : color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(color, lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Compact Category Tab Component
struct CompactCategoryTab: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let count: Int?
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                
                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                
                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.25) : color.opacity(0.2))
                        .cornerRadius(6)
                }
            }
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? color : color.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Compact Filter Pill Component
struct CompactFilterPill: View {
    let filter: WantToWatchMainView.WatchFilter
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: filter.icon)
                    .font(.system(size: 11, weight: .semibold))
                
                Text(filter.rawValue)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.25) : filter.color.opacity(0.2))
                        .cornerRadius(6)
                }
            }
            .foregroundColor(isSelected ? .white : filter.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? filter.color : filter.color.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Filter Pill Component
struct FilterPill: View {
    let filter: WantToWatchMainView.WatchFilter
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.system(size: 12, weight: .semibold))
                
                Text(filter.rawValue)
                    .font(DesignSystem.Typography.callout)
                    .fontWeight(.medium)
                
                if count > 0 {
                    Text("\(count)")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(filter.color.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .foregroundColor(isSelected ? .white : filter.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? filter.color : filter.color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(filter.color, lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Watch Stats View
struct WatchStatsView: View {
    let items: FetchedResults<WantToWatchItem>
    @Environment(\.dismiss) private var dismiss
    
    var watchedCount: Int {
        items.filter { $0.isWatched }.count
    }
    
    var notWatchedCount: Int {
        items.filter { !$0.isWatched }.count
    }
    
    var movieCount: Int {
        items.filter { $0.isMovie }.count
    }
    
    var tvCount: Int {
        items.filter { !$0.isMovie }.count
    }
    
    var averageRating: Double {
        let ratedItems = items.filter { $0.rating > 0 }
        guard !ratedItems.isEmpty else { return 0 }
        return ratedItems.reduce(0) { $0 + $1.rating } / Double(ratedItems.count)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    // Header
                    VStack(spacing: DesignSystem.Spacing.md) {
                        Text("📊")
                            .font(.system(size: 48))
                        
                        Text("Watch Statistics")
                            .font(DesignSystem.Typography.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        Text("Your entertainment journey")
                            .font(DesignSystem.Typography.callout)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .padding(.top, DesignSystem.Spacing.lg)
                    
                    // Stats Grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignSystem.Spacing.lg) {
                        StatCard(
                            title: "Total Items",
                            value: "\(items.count)",
                            icon: "list.bullet",
                            color: DesignSystem.Colors.accent
                        )
                        
                        StatCard(
                            title: "Watched",
                            value: "\(watchedCount)",
                            icon: "checkmark.circle",
                            color: DesignSystem.Colors.success
                        )
                        
                        StatCard(
                            title: "Up Next",
                            value: "\(notWatchedCount)",
                            icon: "play.circle",
                            color: DesignSystem.Colors.info
                        )
                        
                        StatCard(
                            title: "Movies",
                            value: "\(movieCount)",
                            icon: "film",
                            color: DesignSystem.Colors.warning
                        )
                        
                        StatCard(
                            title: "TV Shows",
                            value: "\(tvCount)",
                            icon: "tv",
                            color: DesignSystem.Colors.error
                        )
                        
                        StatCard(
                            title: "Avg Rating",
                            value: String(format: "%.1f", averageRating),
                            icon: "star.fill",
                            color: DesignSystem.Colors.warning
                        )
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    // Progress Ring
                    if items.count > 0 {
                        VStack(spacing: DesignSystem.Spacing.md) {
                            Text("Watch Progress")
                                .font(DesignSystem.Typography.title2)
                                .fontWeight(.bold)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            ZStack {
                                Circle()
                                    .stroke(DesignSystem.Colors.border, lineWidth: 8)
                                    .frame(width: 120, height: 120)
                                
                                Circle()
                                    .trim(from: 0, to: CGFloat(watchedCount) / CGFloat(items.count))
                                    .stroke(
                                        LinearGradient(
                                            colors: [DesignSystem.Colors.success, DesignSystem.Colors.info],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                    )
                                    .frame(width: 120, height: 120)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.easeInOut(duration: 1.5), value: watchedCount)
                                
                                VStack(spacing: 2) {
                                    Text("\(Int((CGFloat(watchedCount) / CGFloat(items.count)) * 100))%")
                                        .font(DesignSystem.Typography.title1)
                                        .fontWeight(.bold)
                                        .foregroundColor(DesignSystem.Colors.textPrimary)
                                    
                                    Text("Complete")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                }
                            }
                        }
                        .padding(DesignSystem.Spacing.xl)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(DesignSystem.Colors.surface)
                                .shadow(color: DesignSystem.Shadows.small, radius: 4, x: 0, y: 2)
                        )
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                    }
                    
                    Spacer(minLength: DesignSystem.Spacing.xl)
                }
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.info)
                }
            }
        }
    }
}

// MARK: - Want to Watch Item Card
struct WantToWatchItemCard: View {
    @ObservedObject var item: WantToWatchItem
    let isWatched: Bool
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Poster Image
            AsyncImage(url: posterURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(DesignSystem.Colors.backgroundSecondary)
                    .overlay(
                        Image(systemName: item.isMovie ? "film" : "tv")
                            .font(.system(size: 14))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    )
            }
            .frame(width: 40, height: 60)
            .cornerRadius(DesignSystem.CornerRadius.sm)
            .clipped()
            
            // Content
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(item.title ?? "Unknown")
                    .font(DesignSystem.Typography.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                HStack(spacing: DesignSystem.Spacing.sm) {
                    // Media Type Icon
                    Image(systemName: item.isMovie ? "film" : "tv")
                        .font(.system(size: 10))
                        .foregroundColor(item.isMovie ? DesignSystem.Colors.info : DesignSystem.Colors.success)
                    
                    // Rating
                    if item.rating > 0 {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundColor(DesignSystem.Colors.warning)
                            Text(String(format: "%.1f", item.rating))
                                .font(DesignSystem.Typography.caption)
                                .fontWeight(.medium)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    }
                    
                    Spacer()
                }
                
                // Release Date
                if let releaseDate = item.releaseDate {
                    Text(formatDate(releaseDate))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }
            
            Spacer()
            
            // Toggle Button
            Button(action: toggleWatchedStatus) {
                Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isWatched ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
        .shadow(
            color: DesignSystem.Shadows.small,
            radius: 1,
            x: 0,
            y: 1
        )
    }
    
    private var posterURL: URL? {
        guard let posterPath = item.posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func toggleWatchedStatus() {
        withAnimation(.easeInOut(duration: 0.2)) {
            item.isWatched.toggle()
            item.modifiedDate = Date()
            
            if item.isWatched {
                item.watchedDate = Date()
            } else {
                item.watchedDate = nil
            }
            
            do {
                try viewContext.save()
            } catch {
                // Failed to toggle watched status
            }
        }
    }
}

// MARK: - Enhanced Search Bar
struct SearchBarEnhanced: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .font(.system(size: 16, weight: .semibold))
            
            TextField("Search movies, shows...", text: $text)
                .font(DesignSystem.Typography.body)
                .fontWeight(.medium)
                .textInputAutocapitalization(.none)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .focused($isFocused)
                .tint(DesignSystem.Colors.info)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(12)
        .background(DesignSystem.Colors.backgroundSecondary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? DesignSystem.Colors.info : DesignSystem.Colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Lottie-like Loading Animation
struct LottieLoadingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(DesignSystem.Colors.info.opacity(0.6))
                    .frame(width: 12, height: 12)
                    .offset(x: CGFloat(cos(Double(index) * .pi * 2 / 3)) * 25)
                    .offset(y: CGFloat(sin(Double(index) * .pi * 2 / 3)) * 25)
                    .scaleEffect(isAnimating ? 1 : 0.6)
                    .animation(
                        Animation.easeInOut(duration: 1)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .frame(width: 60, height: 60)
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Enhanced Search Result Card
struct SearchResultCardEnhanced: View {
    let item: TMDBItem
    let onAdd: () -> Void
    @State private var isPressed = false
    @State private var isAdded = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Enhanced Poster with gradient overlay
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: item.posterURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [DesignSystem.Colors.backgroundSecondary, DesignSystem.Colors.backgroundTertiary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            VStack(spacing: 4) {
                                Image(systemName: item.mediaType == "movie" ? "film" : "tv")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                                Text(item.mediaType == "movie" ? "Movie" : "TV")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                            }
                        )
                }
                .frame(width: 60, height: 90)
                .cornerRadius(12)
                .clipped()
                
                // Media type badge
                HStack(spacing: 3) {
                    Image(systemName: item.mediaType == "movie" ? "film" : "tv")
                        .font(.system(size: 8, weight: .bold))
                    Text(item.mediaType == "movie" ? "Movie" : "TV")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(DesignSystem.Colors.textPrimary.opacity(0.8))
                .cornerRadius(6)
                .padding(6)
            }
            
            // Enhanced Content
            VStack(alignment: .leading, spacing: 8) {
                Text(item.displayTitle)
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                
                // Rating and date row
                HStack(spacing: 12) {
                    if item.rating > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.warning)
                            Text(String(format: "%.1f", item.rating))
                                .font(DesignSystem.Typography.caption)
                                .fontWeight(.bold)
                                .foregroundColor(DesignSystem.Colors.warning)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(DesignSystem.Colors.warning.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    Spacer()
                    
                    if let dateString = item.displayDate {
                        Text(TMDBService.shared.formatDisplayDate(dateString) ?? "")
                            .font(DesignSystem.Typography.caption)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(DesignSystem.Colors.textSecondary.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                
                // Overview preview
                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            
            // Enhanced Add Button
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    onAdd()
                    isAdded = true
                    isPressed = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    isPressed = false
                }
            }) {
                VStack(spacing: 4) {
                    Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(isAdded ? DesignSystem.Colors.success : DesignSystem.Colors.info)
                    
                    Text(isAdded ? "Added!" : "Add")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isAdded ? DesignSystem.Colors.success : DesignSystem.Colors.info)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
                .shadow(
                    color: DesignSystem.Shadows.small,
                    radius: isPressed ? 2 : 6,
                    x: 0,
                    y: isPressed ? 1 : 3
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
    }
}

// MARK: - Item Detail View
struct ItemDetailView: View {
    @ObservedObject var item: WantToWatchItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var isPressed = false
    @State private var fullDetails: TMDBFullDetails?
    @State private var isLoadingDetails = false
    @State private var loadError: String?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    // Hero Section
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        // Poster
                        AsyncImage(url: posterURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [DesignSystem.Colors.backgroundSecondary, DesignSystem.Colors.backgroundTertiary],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: item.isMovie ? "film" : "tv")
                                            .font(.system(size: 32, weight: .medium))
                                            .foregroundColor(DesignSystem.Colors.textTertiary)
                                        Text(item.isMovie ? "Movie" : "TV Show")
                                            .font(DesignSystem.Typography.headline)
                                            .foregroundColor(DesignSystem.Colors.textTertiary)
                                    }
                                )
                        }
                        .frame(width: 200, height: 300)
                        .cornerRadius(16)
                        .clipped()
                        .shadow(color: DesignSystem.Shadows.medium, radius: 8, x: 0, y: 4)
                        
                        // Title and Info
                        VStack(spacing: DesignSystem.Spacing.md) {
                            Text(item.title ?? "Unknown")
                                .font(DesignSystem.Typography.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .multilineTextAlignment(.center)
                            
                            // Tagline
                            if let tagline = fullDetails?.tagline, !tagline.isEmpty {
                                Text("\"\(tagline)\"")
                                    .font(DesignSystem.Typography.callout)
                                    .italic()
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            
                            // Info Row
                            HStack(spacing: DesignSystem.Spacing.md) {
                                if item.rating > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(DesignSystem.Colors.warning)
                                        Text(String(format: "%.1f", item.rating))
                                            .font(DesignSystem.Typography.callout)
                                            .fontWeight(.bold)
                                            .foregroundColor(DesignSystem.Colors.warning)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(DesignSystem.Colors.warning.opacity(0.1))
                                    .cornerRadius(10)
                                }
                                
                                if let runtime = fullDetails?.runtime, runtime > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "clock")
                                            .font(.system(size: 12, weight: .medium))
                                        Text(formatRuntime(runtime))
                                            .font(DesignSystem.Typography.callout)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(DesignSystem.Colors.backgroundSecondary)
                                    .cornerRadius(10)
                                }
                                
                                if let releaseDate = item.releaseDate {
                                    Text(formatYear(releaseDate))
                                        .font(DesignSystem.Typography.callout)
                                        .fontWeight(.medium)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(DesignSystem.Colors.backgroundSecondary)
                                        .cornerRadius(10)
                                }
                            }
                            
                            // TV Show Info
                            if !item.isMovie, let seasons = fullDetails?.numberOfSeasons, let episodes = fullDetails?.numberOfEpisodes {
                                HStack(spacing: DesignSystem.Spacing.md) {
                                    Label("\(seasons) Season\(seasons == 1 ? "" : "s")", systemImage: "tv")
                                    Label("\(episodes) Episodes", systemImage: "play.rectangle.on.rectangle")
                                }
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            
                            // Genres
                            if let genres = fullDetails?.genres, !genres.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(genres.prefix(4)) { genre in
                                            Text(genre.name)
                                                .font(DesignSystem.Typography.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(DesignSystem.Colors.info)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(DesignSystem.Colors.info.opacity(0.1))
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                            }
                            
                            // Status Badge
                            HStack(spacing: 6) {
                                Image(systemName: item.isWatched ? "checkmark.circle.fill" : "clock.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(item.isWatched ? "Watched" : "Up Next")
                                    .font(DesignSystem.Typography.callout)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(item.isWatched ? DesignSystem.Colors.success : DesignSystem.Colors.info)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background((item.isWatched ? DesignSystem.Colors.success : DesignSystem.Colors.info).opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(DesignSystem.Colors.surface)
                            .shadow(color: DesignSystem.Shadows.small, radius: 4, x: 0, y: 2)
                    )
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    // Cast Section
                    if let cast = fullDetails?.cast, !cast.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            Text("Cast")
                                .font(DesignSystem.Typography.title2)
                                .fontWeight(.bold)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .padding(.horizontal, DesignSystem.Spacing.lg)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: DesignSystem.Spacing.md) {
                                    ForEach(cast) { actor in
                                        CastMemberCard(actor: actor)
                                    }
                                }
                                .padding(.horizontal, DesignSystem.Spacing.lg)
                            }
                        }
                    }
                    
                    // Director/Creator Section
                    if let directors = fullDetails?.directors, !directors.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            Text(item.isMovie ? "Director" : "Created By")
                                .font(DesignSystem.Typography.title2)
                                .fontWeight(.bold)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(directors) { person in
                                    HStack(spacing: 12) {
                                        AsyncImage(url: person.profileURL) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Circle()
                                                .fill(DesignSystem.Colors.backgroundSecondary)
                                                .overlay(
                                                    Image(systemName: "person.fill")
                                                        .foregroundColor(DesignSystem.Colors.textTertiary)
                                                )
                                        }
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(person.name)
                                                .font(DesignSystem.Typography.body)
                                                .fontWeight(.medium)
                                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                            Text(person.job)
                                                .font(DesignSystem.Typography.caption)
                                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(DesignSystem.Spacing.lg)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(DesignSystem.Colors.surface)
                                .shadow(color: DesignSystem.Shadows.small, radius: 4, x: 0, y: 2)
                        )
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                    }
                    
                    // Overview Section
                    if let overview = item.overview, !overview.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            Text("Overview")
                                .font(DesignSystem.Typography.title2)
                                .fontWeight(.bold)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            Text(overview)
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .lineSpacing(4)
                        }
                        .padding(DesignSystem.Spacing.lg)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(DesignSystem.Colors.surface)
                                .shadow(color: DesignSystem.Shadows.small, radius: 4, x: 0, y: 2)
                        )
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                    }
                    
                    // Loading indicator for details
                    if isLoadingDetails {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading details...")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        .padding()
                    }
                    
                    // Action Buttons
                    VStack(spacing: DesignSystem.Spacing.md) {
                        Button(action: toggleWatchedStatus) {
                            HStack(spacing: 8) {
                                Image(systemName: item.isWatched ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .semibold))
                                Text(item.isWatched ? "Mark as Unwatched" : "Mark as Watched")
                                    .font(DesignSystem.Typography.headline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(item.isWatched ? DesignSystem.Colors.error : DesignSystem.Colors.success)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(isPressed ? 0.98 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
                        .onLongPressGesture(minimumDuration: 0.1, maximumDistance: 50) {
                            // Long press feedback
                        } onPressingChanged: { pressing in
                            isPressed = pressing
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    Spacer(minLength: DesignSystem.Spacing.xl)
                }
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.info)
                }
            }
            .task {
                await loadFullDetails()
            }
        }
    }
    
    private var posterURL: URL? {
        guard let posterPath = item.posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }
    
    private func formatRuntime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
    
    private func loadFullDetails() async {
        guard fullDetails == nil else { return }
        isLoadingDetails = true
        
        do {
            let details = try await TMDBService.shared.fetchFullDetails(
                id: Int(item.tmdbId),
                isMovie: item.isMovie
            )
            await MainActor.run {
                fullDetails = details
                isLoadingDetails = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoadingDetails = false
            }
        }
    }
    
    private func toggleWatchedStatus() {
        withAnimation(.easeInOut(duration: 0.15)) {
            item.isWatched.toggle()
            item.modifiedDate = Date()
            
            if item.isWatched {
                item.watchedDate = Date()
            } else {
                item.watchedDate = nil
            }
        }
        
        do {
            try viewContext.save()
        } catch {
            print("Error toggling watched status: \(error)")
        }
    }
}

// MARK: - Cast Member Card
struct CastMemberCard: View {
    let actor: TMDBCastMember
    
    var body: some View {
        VStack(spacing: 8) {
            AsyncImage(url: actor.profileURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(DesignSystem.Colors.backgroundSecondary)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 24))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    )
            }
            .frame(width: 80, height: 100)
            .cornerRadius(10)
            .clipped()
            
            VStack(spacing: 2) {
                Text(actor.name)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                if let character = actor.character, !character.isEmpty {
                    Text(character)
                        .font(.system(size: 10))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 80)
        }
    }
}

// MARK: - Media Category Section
struct MediaCategorySection: View {
    let category: String
    let items: [WantToWatchItem]
    
    var categoryTitle: String {
        switch category {
        case "anime": return "Anime"
        case "tv": return "TV Shows"
        case "movie": return "Movies"
        default: return category.capitalized
        }
    }
    
    var categoryIcon: String {
        switch category {
        case "anime": return "sparkles"
        case "tv": return "tv.fill"
        case "movie": return "film.fill"
        default: return "play.circle.fill"
        }
    }
    
    var categoryColor: Color {
        switch category {
        case "anime": return .purple
        case "tv": return DesignSystem.Colors.success
        case "movie": return DesignSystem.Colors.info
        default: return DesignSystem.Colors.accent
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Category Header
            HStack(spacing: 8) {
                Image(systemName: categoryIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(categoryColor)
                
                Text(categoryTitle)
                    .font(DesignSystem.Typography.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("\(items.count)")
                    .font(DesignSystem.Typography.callout)
                    .fontWeight(.medium)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(categoryColor.opacity(0.1))
                    .cornerRadius(8)
                
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            
            // Items in this category
            LazyVStack(spacing: DesignSystem.Spacing.md) {
                ForEach(Array(items.enumerated()), id: \.element.objectID) { index, item in
                    WantToWatchItemCardEnhanced(item: item, isWatched: item.isWatched)
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.05), value: items)
                }
            }
        }
    }
}

// MARK: - Enhanced Want to Watch Item Card
struct WantToWatchItemCardEnhanced: View {
    @ObservedObject var item: WantToWatchItem
    let isWatched: Bool
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showDelete = false
    @State private var showDeleteConfirmation = false
    @State private var isPressed = false
    @State private var showDetails = false
    
    var body: some View {
        Button(action: { showDetails = true }) {
        HStack(spacing: 12) {
                // Enhanced Poster with gradient overlay
                ZStack(alignment: .bottomLeading) {
                AsyncImage(url: posterURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [DesignSystem.Colors.backgroundSecondary, DesignSystem.Colors.backgroundTertiary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: item.isMovie ? "film" : "tv")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(DesignSystem.Colors.textTertiary)
                                    Text(item.isMovie ? "Movie" : "TV")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.textTertiary)
                                }
                            )
                    }
                    .frame(width: 60, height: 90)
                    .cornerRadius(12)
                .clipped()
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isWatched ? DesignSystem.Colors.success : DesignSystem.Colors.border,
                                lineWidth: isWatched ? 2 : 1
                            )
                    )
                    
                    // Media type badge
                    HStack(spacing: 3) {
                        Image(systemName: item.isMovie ? "film" : "tv")
                            .font(.system(size: 8, weight: .bold))
                        Text(item.isMovie ? "Movie" : "TV")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(DesignSystem.Colors.textPrimary.opacity(0.8))
                    .cornerRadius(6)
                    .padding(6)
                
                // Watched indicator
                if isWatched {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                    Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.success)
                                    .background(
                                        Circle()
                                            .fill(DesignSystem.Colors.textPrimary.opacity(0.9))
                                            .frame(width: 22, height: 22)
                                    )
                        .padding(4)
                            }
                        }
                }
            }
            
                // Enhanced Content
                VStack(alignment: .leading, spacing: 8) {
                Text(item.title ?? "Unknown")
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                
                    // Rating and date row
                    HStack(spacing: 12) {
                    if item.rating > 0 {
                            HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                    .font(.system(size: 10, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.warning)
                            Text(String(format: "%.1f", item.rating))
                                .font(DesignSystem.Typography.caption)
                                    .fontWeight(.bold)
                                .foregroundColor(DesignSystem.Colors.warning)
                        }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(DesignSystem.Colors.warning.opacity(0.1))
                            .cornerRadius(6)
                    }
                    
                    Spacer()
                    
                    if let releaseDate = item.releaseDate {
                        Text(formatDate(releaseDate))
                            .font(DesignSystem.Typography.caption)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(DesignSystem.Colors.textSecondary.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                    
                    // Status indicator
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: isWatched ? "checkmark.circle.fill" : "clock.fill")
                                .font(.system(size: 10))
                                .foregroundColor(isWatched ? DesignSystem.Colors.success : DesignSystem.Colors.info)
                            Text(isWatched ? "Watched" : "Up Next")
                                .font(DesignSystem.Typography.caption)
                                .fontWeight(.medium)
                                .foregroundColor(isWatched ? DesignSystem.Colors.success : DesignSystem.Colors.info)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((isWatched ? DesignSystem.Colors.success : DesignSystem.Colors.info).opacity(0.1))
                        .cornerRadius(8)
                        
                        Spacer()
                    }
            }
            
            // Action Buttons
                VStack(spacing: 8) {
                // Toggle Button
                Button(action: toggleWatchedStatus) {
                    Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(isWatched ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                    .scaleEffect(isPressed ? 0.9 : 1.0)
                
                // Delete Button
                Button(action: {
                    showDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                            .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.error)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
        }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(DesignSystem.Colors.surface)
                    .shadow(
                        color: DesignSystem.Shadows.small,
                        radius: isPressed ? 2 : 6,
                        x: 0,
                        y: isPressed ? 1 : 3
                    )
            )
        .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isWatched ? DesignSystem.Colors.success.opacity(0.3) : DesignSystem.Colors.border,
                        lineWidth: 1
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0.1, maximumDistance: 50) {
            // Long press feedback
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Item", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteItem()
            }
        } message: {
            Text("Are you sure you want to delete \"\(item.title ?? "this item")\"? This action cannot be undone.")
        }
        .sheet(isPresented: $showDetails) {
            ItemDetailView(item: item)
        }
    }
    
    private var posterURL: URL? {
        guard let posterPath = item.posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func toggleWatchedStatus() {
        withAnimation(.easeInOut(duration: 0.15)) {
            item.isWatched.toggle()
            item.modifiedDate = Date()
            
            if item.isWatched {
                item.watchedDate = Date()
            } else {
                item.watchedDate = nil
            }
        }
        
        do {
            try viewContext.save()
        } catch {
            print("Error toggling watched status: \(error)")
        }
    }
    
    private func deleteItem() {
        withAnimation(.easeInOut(duration: 0.3)) {
            viewContext.delete(item)
        }
        
        do {
            try viewContext.save()
        } catch {
            // Error deleting item
        }
    }
}

// MARK: - Border Radius Helper
extension View {
    func borderRadius(_ radius: CGFloat, border: Color? = nil) -> some View {
        self
            .cornerRadius(radius)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(border ?? Color.clear, lineWidth: 1.5)
            )
    }
}

#Preview {
    WantToWatchMainView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}

