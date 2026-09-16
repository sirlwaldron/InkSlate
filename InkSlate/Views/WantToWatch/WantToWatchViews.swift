import SwiftUI
import CoreData
import os

fileprivate let wantToWatchLog = Logger(subsystem: "com.lucas.InkSlateNew", category: "WantToWatch")

// MARK: - Layout helpers
private enum WatchShelfLayout {
    /// Target ~4–5 posters visible per shelf / grid row.
    static let posterMinWidth: CGFloat = 96
    static let posterMaxWidth: CGFloat = 128
    static let posterAspect: CGFloat = 1.5
    static let shelfSpacing: CGFloat = 10
    static let gridSpacing: CGFloat = 12

    static var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: posterMinWidth, maximum: posterMaxWidth), spacing: gridSpacing)]
    }

    static func shelfPosterWidth(containerWidth: CGFloat, visibleCount: CGFloat = 4.4) -> CGFloat {
        let available = max(containerWidth - DesignSystem.Spacing.lg * 2, posterMinWidth * 2)
        let width = (available - shelfSpacing * (visibleCount - 1)) / visibleCount
        return min(max(width, posterMinWidth), posterMaxWidth)
    }
}

// MARK: - Want to Watch Main View
struct WantToWatchMainView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest private var allItems: FetchedResults<WantToWatchItem>

    init() {
        let request = NSFetchRequest<WantToWatchItem>(entityName: "WantToWatchItem")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WantToWatchItem.createdDate, ascending: false)]
        request.fetchBatchSize = 50
        _allItems = FetchRequest(fetchRequest: request, animation: .default)
    }

    @State private var searchText = ""
    @State private var searchResults: [TMDBItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var searchErrorMessage: String?
    @State private var selectedFilter: WatchFilter? = nil
    @State private var selectedCategory: String? = nil
    @State private var showingStats = false

    enum WatchFilter: String, CaseIterable {
        case upNext = "Up Next"
        case watched = "Watched"
        case all = "All"

        var icon: String {
            switch self {
            case .upNext: return "play.circle.fill"
            case .watched: return "checkmark.circle.fill"
            case .all: return "square.grid.2x2"
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
            items = Array(allItems)
        }

        if let category = selectedCategory {
            return items.filter { $0.watchShelfCategory == category }
        }

        return items
    }

    var groupedItems: [String: [WantToWatchItem]] {
        Dictionary(grouping: filteredItems) { $0.watchShelfCategory }
    }

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
        return items.filter { $0.watchShelfCategory == category }.count
    }

    var orderedCategories: [String] {
        let standardCategories = ["anime", "tv", "movie"]
        let existingCategories = Set(groupedItems.keys)
        let additionalCategories = existingCategories
            .subtracting(standardCategories)
            .filter { $0 != "cartoon" }
            .sorted()
        return standardCategories + additionalCategories
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            NavigationStack {
                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        headerSection
                        filterSection

                        if isSearching {
                            statusBlock(icon: nil, title: "Searching…", message: nil, showProgress: true)
                        } else if let error = searchErrorMessage, !searchText.isEmpty {
                            statusBlock(
                                icon: "exclamationmark.triangle",
                                title: "Search unavailable",
                                message: error,
                                showProgress: false
                            )
                        } else if !searchText.isEmpty && !searchResults.isEmpty {
                            searchResultsSection
                        } else if !searchText.isEmpty && searchResults.isEmpty {
                            statusBlock(
                                icon: "magnifyingglass",
                                title: "No results",
                                message: "Try a different title or keyword",
                                showProgress: false
                            )
                        } else if allItems.isEmpty {
                            statusBlock(
                                icon: "popcorn",
                                title: "Your shelves are empty",
                                message: "Search above to add movies and shows",
                                showProgress: false
                            )
                        } else {
                            librarySection
                        }
                    }
                    .padding(.bottom, DesignSystem.Spacing.xxl)
                }
                .navigationBarHiddenIfPossible(true)
                .onChange(of: searchText) { _, newValue in
                    performSearch(newValue)
                }
                .onAppear {
                    if selectedCategory == "cartoon" {
                        selectedCategory = "tv"
                    }
                }
                .inkSlateSheet(isPresented: $showingStats) {
                    WatchStatsView(items: allItems)
                }
                .keyboardDismissToolbar()
            }
        }
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Want to Watch")
                        .font(DesignSystem.Typography.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text(subtitleText)
                        .font(DesignSystem.Typography.callout)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                Button {
                    showingStats = true
                } label: {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.info)
                        .frame(width: 36, height: 36)
                        .background(DesignSystem.Colors.info.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Watch statistics")
            }

            SearchBarEnhanced(text: $searchText)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.sm)
    }

    private var subtitleText: String {
        let upNext = notWatchedItems.count
        let watched = watchedItems.count
        if allItems.isEmpty {
            return "Build your watchlist"
        }
        return "\(upNext) up next · \(watched) watched"
    }

    // MARK: Filters

    private var filterSection: some View {
        Group {
            if searchText.isEmpty {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            CompactCategoryTab(
                                title: "All",
                                icon: "square.grid.2x2",
                                isSelected: selectedCategory == nil,
                                count: nil,
                                color: DesignSystem.Colors.accent
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedCategory = nil
                                }
                            }

                            CompactCategoryTab(
                                title: "TV",
                                icon: "tv.fill",
                                isSelected: selectedCategory == "tv",
                                count: getCategoryCount("tv"),
                                color: DesignSystem.Colors.success
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedCategory = "tv"
                                }
                            }

                            CompactCategoryTab(
                                title: "Movies",
                                icon: "film.fill",
                                isSelected: selectedCategory == "movie",
                                count: getCategoryCount("movie"),
                                color: DesignSystem.Colors.info
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedCategory = "movie"
                                }
                            }

                            CompactCategoryTab(
                                title: "Anime",
                                icon: "sparkles",
                                isSelected: selectedCategory == "anime",
                                count: getCategoryCount("anime"),
                                color: .purple
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedCategory = "anime"
                                }
                            }
                        }
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(WatchFilter.allCases.filter { $0 != .all }, id: \.self) { filter in
                                CompactFilterPill(
                                    filter: filter,
                                    isSelected: selectedFilter == filter,
                                    count: getCount(for: filter)
                                ) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedFilter = selectedFilter == filter ? nil : filter
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                    }
                }
            }
        }
    }

    // MARK: Library

    @ViewBuilder
    private var librarySection: some View {
        if selectedCategory != nil {
            // Filtered category → full poster grid (~4–5 across)
            LazyVGrid(columns: WatchShelfLayout.gridColumns, spacing: WatchShelfLayout.gridSpacing) {
                ForEach(filteredItems, id: \.objectID) { item in
                    WatchPosterCard(item: item)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
        } else {
            // Browse mode → horizontal shelves by category
            LazyVStack(spacing: DesignSystem.Spacing.xl) {
                ForEach(orderedCategories, id: \.self) { category in
                    if let items = groupedItems[category], !items.isEmpty {
                        WatchShelfSection(category: category, items: items)
                    }
                }
            }
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Search Results")
                    .font(DesignSystem.Typography.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Spacer()
                Text("\(searchResults.count)")
                    .font(DesignSystem.Typography.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)

            LazyVGrid(columns: WatchShelfLayout.gridColumns, spacing: WatchShelfLayout.gridSpacing) {
                ForEach(searchResults, id: \.id) { item in
                    SearchPosterCard(item: item) {
                        addToWantToWatch(item)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
        }
    }

    private func statusBlock(icon: String?, title: String, message: String?, showProgress: Bool) -> some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            if showProgress {
                ProgressView()
                    .controlSize(.regular)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }

            Text(title)
                .font(DesignSystem.Typography.title2)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            if let message {
                Text(message)
                    .font(DesignSystem.Typography.callout)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignSystem.Spacing.xxl)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    private func getCount(for filter: WatchFilter) -> Int {
        switch filter {
        case .upNext: return notWatchedItems.count
        case .watched: return watchedItems.count
        case .all: return allItems.count
        }
    }

    private func performSearch(_ query: String) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if TMDBConfig.apiKey == nil {
            searchResults = []
            isSearching = false
            searchErrorMessage = TMDBError.missingAPIKey.localizedDescription
            return
        }

        if trimmed.isEmpty {
            searchResults = []
            isSearching = false
            searchErrorMessage = nil
            return
        }

        isSearching = true
        searchErrorMessage = nil
        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                try Task.checkCancellation()
                let results = try await TMDBService.shared.searchMulti(query: trimmed)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    searchResults = results
                    isSearching = false
                    searchErrorMessage = nil
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    searchResults = []
                    isSearching = false
                    searchErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func addToWantToWatch(_ item: TMDBItem) {
        guard item.mediaType == "movie" || item.mediaType == "tv" else { return }

        let dupReq: NSFetchRequest<WantToWatchItem> = WantToWatchItem.fetchRequest()
        dupReq.fetchLimit = 1
        dupReq.predicate = NSPredicate(format: "tmdbId == %d AND isMovie == %@", item.id, NSNumber(value: item.mediaType == "movie"))
        if let existing = try? viewContext.fetch(dupReq), !existing.isEmpty {
            searchText = ""
            searchResults = []
            return
        }

        let newItem = WantToWatchItem(context: viewContext)
        newItem.id = UUID()
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
        newItem.isWatched = false
        newItem.mediaCategory = item.mediaType == "movie" ? "movie" : "tv"

        Task {
            await determineAndSetCategory(for: newItem)
        }

        if viewContext.inkSlateSave(module: "WantToWatch") {
            searchText = ""
            searchResults = []
        }
    }

    private func determineAndSetCategory(for item: WantToWatchItem) async {
        do {
            let details = try await TMDBService.shared.fetchFullDetails(
                id: Int(item.tmdbId),
                isMovie: item.isMovie
            )

            await MainActor.run {
                guard !item.isDeleted, item.managedObjectContext != nil else { return }
                item.mediaCategory = WantToWatchMediaCategory.fromTMDBGenres(
                    isMovie: item.isMovie,
                    genres: details.genres,
                    overview: details.overview ?? item.overview,
                    originalLanguage: details.originalLanguage,
                    originCountries: details.originCountries,
                    networkNames: details.networkNames
                )
                item.modifiedDate = Date()
                _ = viewContext.inkSlateSave(module: "WantToWatch")
            }
        } catch {
            // Keep default category from media type.
        }
    }
}

// MARK: - Horizontal Shelf Section
struct WatchShelfSection: View {
    let category: String
    let items: [WantToWatchItem]

    var categoryTitle: String {
        switch category {
        case "anime": return "Anime"
        case "cartoon", "tv": return "TV"
        case "movie": return "Movies"
        default: return category.capitalized
        }
    }

    var categoryIcon: String {
        switch category {
        case "anime": return "sparkles"
        case "cartoon", "tv": return "tv.fill"
        case "movie": return "film.fill"
        default: return "play.circle.fill"
        }
    }

    var categoryColor: Color {
        switch category {
        case "anime": return .purple
        case "cartoon", "tv": return DesignSystem.Colors.success
        case "movie": return DesignSystem.Colors.info
        default: return DesignSystem.Colors.accent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(spacing: 8) {
                Image(systemName: categoryIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(categoryColor)

                Text(categoryTitle)
                    .font(DesignSystem.Typography.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("\(items.count)")
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(categoryColor.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)

            GeometryReader { geo in
                let posterWidth = WatchShelfLayout.shelfPosterWidth(containerWidth: geo.size.width)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: WatchShelfLayout.shelfSpacing) {
                        ForEach(items, id: \.objectID) { item in
                            WatchPosterCard(item: item)
                                .frame(width: posterWidth)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                }
            }
            .frame(height: shelfRowHeight)
        }
    }

    private var shelfRowHeight: CGFloat {
        // Sized for ~4.4 posters across a typical phone width, plus title/meta.
        let sampleWidth = WatchShelfLayout.shelfPosterWidth(containerWidth: 390)
        return sampleWidth * WatchShelfLayout.posterAspect + 48
    }
}

// MARK: - Poster Card (library item)
struct WatchPosterCard: View {
    @ObservedObject var item: WantToWatchItem
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showDetails = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Button {
                    showDetails = true
                } label: {
                    posterImage
                }
                .buttonStyle(.plain)

                // Watched toggle — own button, no parent gesture stealing taps
                Button {
                    toggleWatchedStatus()
                } label: {
                    Image(systemName: item.isWatched ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            item.isWatched ? DesignSystem.Colors.success : Color.white.opacity(0.95),
                            item.isWatched ? Color.white : Color.black.opacity(0.35)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(item.isWatched ? "Mark as unwatched" : "Mark as watched")
            }

            Button {
                showDetails = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? "Unknown")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 28, alignment: .top)

                    HStack(spacing: 4) {
                        if item.rating > 0 {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundColor(DesignSystem.Colors.warning)
                            Text(String(format: "%.1f", item.rating))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }

                        Spacer(minLength: 0)

                        if item.isWatched {
                            Text("Watched")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.success)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button {
                toggleWatchedStatus()
            } label: {
                Label(
                    item.isWatched ? "Mark as Unwatched" : "Mark as Watched",
                    systemImage: item.isWatched ? "circle" : "checkmark.circle"
                )
            }

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
            Text("Remove \"\(item.title ?? "this item")\" from your list?")
        }
        .inkSlateSheet(isPresented: $showDetails) {
            ItemDetailView(item: item)
        }
    }

    private var posterImage: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: item.posterURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    posterPlaceholder
                case .empty:
                    posterPlaceholder
                        .overlay(ProgressView().controlSize(.mini))
                @unknown default:
                    posterPlaceholder
                }
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        item.isWatched ? DesignSystem.Colors.success.opacity(0.7) : DesignSystem.Colors.border,
                        lineWidth: item.isWatched ? 2 : 0.5
                    )
            )
            .overlay {
                if item.isWatched {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                }
            }

            Text(item.isMovie ? "Movie" : "TV")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(6)
        }
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(DesignSystem.Colors.backgroundSecondary)
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay(
                Image(systemName: item.isMovie ? "film" : "tv")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            )
    }

    private func toggleWatchedStatus() {
        withAnimation(.easeInOut(duration: 0.15)) {
            item.isWatched.toggle()
            item.modifiedDate = Date()
            item.watchedDate = item.isWatched ? Date() : nil
        }

        if !viewContext.inkSlateSave(module: "WantToWatch") {
            wantToWatchLog.error("Save watched status failed")
        }
    }

    private func deleteItem() {
        withAnimation(.easeInOut(duration: 0.2)) {
            viewContext.delete(item)
        }
        _ = viewContext.inkSlateSave(module: "WantToWatch")
    }
}

// MARK: - Search Poster Card
struct SearchPosterCard: View {
    let item: TMDBItem
    let onAdd: () -> Void
    @State private var isAdded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: item.posterURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DesignSystem.Colors.backgroundSecondary)
                            .overlay(
                                Image(systemName: item.mediaType == "movie" ? "film" : "tv")
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                            )
                    }
                }
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                )

                Button {
                    guard !isAdded else { return }
                    onAdd()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isAdded = true
                    }
                } label: {
                    Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            isAdded ? DesignSystem.Colors.success : Color.white,
                            isAdded ? Color.white : DesignSystem.Colors.info
                        )
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isAdded ? "Added" : "Add to list")
            }

            Text(item.displayTitle)
                .font(DesignSystem.Typography.caption)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 28, alignment: .top)

            HStack(spacing: 4) {
                if item.rating > 0 {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundColor(DesignSystem.Colors.warning)
                    Text(String(format: "%.1f", item.rating))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                Text(item.mediaType == "movie" ? "Movie" : "TV")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
        }
    }
}

// MARK: - Compact Category Tab
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

                if let count, count > 0 {
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
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Filter Pill
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
        .buttonStyle(.plain)
    }
}

// MARK: - Search Bar
struct SearchBarEnhanced: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .font(.system(size: 15, weight: .semibold))

            TextField("Search movies, shows…", text: $text)
                .font(DesignSystem.Typography.body)
                #if os(iOS)
                .textInputAutocapitalization(.none)
                #endif
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .focused($isFocused)
                .tint(DesignSystem.Colors.info)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
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

// MARK: - Watch Stats
struct WatchStatsView: View {
    let items: FetchedResults<WantToWatchItem>
    @Environment(\.dismiss) private var dismiss

    var watchedCount: Int { items.filter { $0.isWatched }.count }
    var notWatchedCount: Int { items.filter { !$0.isWatched }.count }
    var movieCount: Int { items.filter { $0.isMovie }.count }
    var tvCount: Int { items.filter { !$0.isMovie }.count }
    var animeLibraryCount: Int { items.filter { ($0.mediaCategory ?? "") == "anime" }.count }

    var averageRating: Double {
        let ratedItems = items.filter { $0.rating > 0 }
        guard !ratedItems.isEmpty else { return 0 }
        return ratedItems.reduce(0) { $0 + $1.rating } / Double(ratedItems.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        Text("Watch Statistics")
                            .font(DesignSystem.Typography.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        Text("Your entertainment journey")
                            .font(DesignSystem.Typography.callout)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .padding(.top, DesignSystem.Spacing.lg)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignSystem.Spacing.lg) {
                        WatchStatTile(title: "Total", value: "\(items.count)", icon: "square.stack", color: DesignSystem.Colors.accent)
                        WatchStatTile(title: "Watched", value: "\(watchedCount)", icon: "checkmark.circle", color: DesignSystem.Colors.success)
                        WatchStatTile(title: "Up Next", value: "\(notWatchedCount)", icon: "play.circle", color: DesignSystem.Colors.info)
                        WatchStatTile(title: "Movies", value: "\(movieCount)", icon: "film", color: DesignSystem.Colors.warning)
                        WatchStatTile(title: "TV Shows", value: "\(tvCount)", icon: "tv", color: DesignSystem.Colors.error)
                        WatchStatTile(title: "Anime", value: "\(animeLibraryCount)", icon: "sparkles", color: .purple)
                        WatchStatTile(title: "Avg Rating", value: String(format: "%.1f", averageRating), icon: "star.fill", color: DesignSystem.Colors.warning)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)

                    if items.count > 0 {
                        VStack(spacing: DesignSystem.Spacing.md) {
                            Text("Watch Progress")
                                .font(DesignSystem.Typography.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(DesignSystem.Colors.textPrimary)

                            ZStack {
                                Circle()
                                    .stroke(DesignSystem.Colors.border, lineWidth: 8)
                                    .frame(width: 120, height: 120)

                                Circle()
                                    .trim(from: 0, to: CGFloat(watchedCount) / CGFloat(items.count))
                                    .stroke(
                                        DesignSystem.Colors.success,
                                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                    )
                                    .frame(width: 120, height: 120)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.easeInOut(duration: 0.8), value: watchedCount)

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
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(DesignSystem.Colors.surface)
                        )
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                    }

                    Spacer(minLength: DesignSystem.Spacing.xl)
                }
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Statistics")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(DesignSystem.Colors.info)
                }
            }
        }
    }
}

private struct WatchStatTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
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
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Item Detail View
struct ItemDetailView: View {
    @ObservedObject var item: WantToWatchItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var fullDetails: TMDBFullDetails?
    @State private var isLoadingDetails = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        AsyncImage(url: item.posterURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            default:
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(DesignSystem.Colors.backgroundSecondary)
                                    .overlay(
                                        Image(systemName: item.isMovie ? "film" : "tv")
                                            .font(.system(size: 32, weight: .light))
                                            .foregroundColor(DesignSystem.Colors.textTertiary)
                                    )
                            }
                        }
                        .frame(width: 180, height: 270)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: DesignSystem.Shadows.medium, radius: 8, x: 0, y: 4)

                        VStack(spacing: DesignSystem.Spacing.md) {
                            Text(item.title ?? "Unknown")
                                .font(DesignSystem.Typography.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .multilineTextAlignment(.center)

                            if let tagline = fullDetails?.tagline, !tagline.isEmpty {
                                Text("\"\(tagline)\"")
                                    .font(DesignSystem.Typography.callout)
                                    .italic()
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                    .multilineTextAlignment(.center)
                            }

                            HStack(spacing: DesignSystem.Spacing.md) {
                                if item.rating > 0 {
                                    Label(String(format: "%.1f", item.rating), systemImage: "star.fill")
                                        .font(DesignSystem.Typography.callout)
                                        .fontWeight(.semibold)
                                        .foregroundColor(DesignSystem.Colors.warning)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(DesignSystem.Colors.warning.opacity(0.1))
                                        .cornerRadius(8)
                                }

                                if let runtime = fullDetails?.runtime, runtime > 0 {
                                    Label(formatRuntime(runtime), systemImage: "clock")
                                        .font(DesignSystem.Typography.callout)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(DesignSystem.Colors.backgroundSecondary)
                                        .cornerRadius(8)
                                }

                                if let releaseDate = item.releaseDate {
                                    Text(formatYear(releaseDate))
                                        .font(DesignSystem.Typography.callout)
                                        .fontWeight(.medium)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(DesignSystem.Colors.backgroundSecondary)
                                        .cornerRadius(8)
                                }
                            }

                            if !item.isMovie,
                               let seasons = fullDetails?.numberOfSeasons,
                               let episodes = fullDetails?.numberOfEpisodes {
                                HStack(spacing: DesignSystem.Spacing.md) {
                                    Label("\(seasons) Season\(seasons == 1 ? "" : "s")", systemImage: "tv")
                                    Label("\(episodes) Episodes", systemImage: "play.rectangle.on.rectangle")
                                }
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            }

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
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(DesignSystem.Colors.surface)
                    )
                    .padding(.horizontal, DesignSystem.Spacing.lg)

                    // Primary watched action — no competing gestures
                    Button(action: toggleWatchedStatus) {
                        HStack(spacing: 8) {
                            Image(systemName: item.isWatched ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18, weight: .semibold))
                            Text(item.isWatched ? "Mark as Unwatched" : "Mark as Watched")
                                .font(DesignSystem.Typography.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(item.isWatched ? DesignSystem.Colors.error : DesignSystem.Colors.success)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DesignSystem.Spacing.lg)

                    if let cast = fullDetails?.cast, !cast.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            Text("Cast")
                                .font(DesignSystem.Typography.title2)
                                .fontWeight(.semibold)
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

                    if let directors = fullDetails?.directors, !directors.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            Text(item.isMovie ? "Director" : "Created By")
                                .font(DesignSystem.Typography.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(DesignSystem.Colors.textPrimary)

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(directors) { person in
                                    HStack(spacing: 12) {
                                        AsyncImage(url: person.profileURL) { image in
                                            image.resizable().aspectRatio(contentMode: .fill)
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(DesignSystem.Colors.surface)
                        )
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                    }

                    if let overview = item.overview, !overview.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            Text("Overview")
                                .font(DesignSystem.Typography.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(DesignSystem.Colors.textPrimary)

                            Text(overview)
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .lineSpacing(4)
                        }
                        .padding(DesignSystem.Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(DesignSystem.Colors.surface)
                        )
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                    }

                    if isLoadingDetails {
                        ProgressView("Loading details…")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .padding()
                    }

                    if let loadError, !isLoadingDetails {
                        Text(loadError)
                            .font(DesignSystem.Typography.callout)
                            .foregroundColor(DesignSystem.Colors.error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                    }

                    Spacer(minLength: DesignSystem.Spacing.xl)
                }
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Details")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(DesignSystem.Colors.info)
                }
            }
            .task {
                await loadFullDetails()
            }
        }
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
            item.watchedDate = item.isWatched ? Date() : nil
        }

        if !viewContext.inkSlateSave(module: "WantToWatch") {
            wantToWatchLog.error("Save watched status failed")
        }
    }
}

// MARK: - Cast Member Card
struct CastMemberCard: View {
    let actor: TMDBCastMember

    var body: some View {
        VStack(spacing: 8) {
            AsyncImage(url: actor.profileURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
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

#Preview {
    WantToWatchMainView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
