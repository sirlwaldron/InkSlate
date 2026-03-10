//
//  DiscoverViews.swift
//  InkSlate
//
//  Created by Lucas Waldron on 1/2/25.
//

import SwiftUI
import CoreData

// MARK: - Discover Main View
struct DiscoverMainView: View {
    @StateObject private var searchManager = SearchManager()
    @State private var searchText = ""
    @State private var selectedItem: TMDBItem?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                DiscoverSearchBar(text: $searchText)
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                // Results
                if searchManager.isLoading {
                    Spacer()
                    VStack(spacing: DesignSystem.Spacing.md) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Searching...")
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    Spacer()
                } else if searchManager.results.isEmpty && !searchText.isEmpty {
                    Spacer()
                    VStack(spacing: DesignSystem.Spacing.xl) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        Text("No results found")
                            .font(DesignSystem.Typography.title3)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        Text("Try a different search term")
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }
                    Spacer()
                } else if searchManager.results.isEmpty && searchText.isEmpty {
                    Spacer()
                    VStack(spacing: DesignSystem.Spacing.xl) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        Text("What to Watch")
                            .font(DesignSystem.Typography.title3)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        Text("Start typing to search for movies and TV shows")
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: DesignSystem.Spacing.md) {
                            ForEach(searchManager.results) { item in
                                DiscoverItemCard(item: item) {
                                    selectedItem = item
                                }
                            }
                        }
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.top, DesignSystem.Spacing.sm)
                    }
                }
            }
            .navigationTitle("What to Watch")
            .onChange(of: searchText) { _, newValue in
                searchManager.search(query: newValue)
            }
            .sheet(item: $selectedItem) { item in
                DiscoverDetailView(item: item)
            }
        }
    }
}

// MARK: - Discover Search Bar
struct DiscoverSearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DesignSystem.Colors.accent)
            
            TextField("Search movies and TV shows...", text: $text)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !text.isEmpty {
                Button("Clear") {
                    text = ""
                }
                .font(DesignSystem.Typography.caption)
                .fontWeight(.medium)
                .foregroundColor(DesignSystem.Colors.accent)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .stroke(DesignSystem.Colors.accent.opacity(0.3), lineWidth: 1)
        )
        .shadow(
            color: DesignSystem.Shadows.small,
            radius: 2,
            x: 0,
            y: 1
        )
    }
}

// MARK: - Discover Item Card
struct DiscoverItemCard: View {
    let item: TMDBItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Poster Image
                AsyncImage(url: item.posterURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(DesignSystem.Colors.backgroundSecondary)
                        .overlay(
                            Image(systemName: item.isMovie ? "film" : "tv")
                                .font(.system(size: 16))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        )
                }
                .frame(width: 50, height: 75)
                .cornerRadius(DesignSystem.CornerRadius.sm)
                .clipped()
                
                // Content
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    HStack {
                        Text(item.displayTitle)
                            .font(DesignSystem.Typography.title3)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .lineLimit(2)
                        
                        Spacer()
                        
                        // Type Badge
                        Text(item.mediaTypeDisplay)
                            .font(DesignSystem.Typography.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .background(item.isMovie ? DesignSystem.Colors.info : DesignSystem.Colors.success)
                            .foregroundColor(DesignSystem.Colors.textInverse)
                            .cornerRadius(DesignSystem.CornerRadius.xs)
                    }
                    
                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .lineLimit(2)
                    }
                    
                    HStack {
                        // Rating
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "star.fill")
                                .foregroundColor(DesignSystem.Colors.warning)
                                .font(.system(size: 10))
                            Text(String(format: "%.1f", item.rating))
                                .font(DesignSystem.Typography.caption)
                                .fontWeight(.medium)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        
                        Spacer()
                        
                        // Release Date
                        if let dateString = item.displayDate {
                            Text(TMDBService.shared.formatDisplayDate(dateString) ?? dateString)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
        .buttonStyle(PlainButtonStyle())
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
}

// MARK: - Discover Detail View
struct DiscoverDetailView: View {
    let item: TMDBItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var isAdded = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Backdrop Image
                    AsyncImage(url: item.backdropURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .overlay(
                                Image(systemName: item.isMovie ? "film" : "tv")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                            )
                    }
                    .frame(height: 200)
                    .clipped()
                    
                    VStack(alignment: .leading, spacing: 16) {
                        // Title and Type
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.displayTitle)
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                
                                Text(item.mediaTypeDisplay)
                                    .font(.headline)
                                    .foregroundColor(item.isMovie ? .blue : .green)
                            }
                            
                            Spacer()
                            
                            // Rating
                            VStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                    Text(String(format: "%.1f", item.rating))
                                        .fontWeight(.bold)
                                }
                                .font(.title2)
                                
                                Text("Rating")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Release Date
                        if let dateString = item.displayDate {
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundColor(.secondary)
                                Text(TMDBService.shared.formatDisplayDate(dateString) ?? dateString)
                                    .font(.subheadline)
                            }
                        }
                        
                        // Overview
                        if let overview = item.overview, !overview.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Overview")
                                    .font(.headline)
                                
                                Text(overview)
                                    .font(.body)
                                    .lineSpacing(4)
                            }
                        }
                        
                        // Add to Want to Watch Button
                        Button(action: addToWantToWatch) {
                            HStack {
                                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                                Text(isAdded ? "Added to Want to Watch" : "Add to Want to Watch")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isAdded ? Color.green : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isAdded)
                    }
                    .padding(.horizontal)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            checkIfAdded()
        }
        .alert("Success", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func checkIfAdded() {
        let request: NSFetchRequest<WantToWatchItem> = WantToWatchItem.fetchRequest()
        request.predicate = NSPredicate(format: "tmdbId == %d", item.id)
        
        do {
            let results = try viewContext.fetch(request)
            isAdded = !results.isEmpty
        } catch {
        }
    }
    
    private func addToWantToWatch() {
        let newItem = WantToWatchItem(context: viewContext)
        newItem.id = UUID()
        newItem.tmdbId = Int32(item.id)
        newItem.title = item.displayTitle
        newItem.overview = item.overview
        newItem.posterPath = item.posterPath
        newItem.backdropPath = item.backdropPath
        newItem.rating = item.rating
        newItem.isMovie = item.isMovie
        newItem.isWatched = false
        newItem.createdDate = Date()
        newItem.modifiedDate = Date()
        
        // Set default category based on isMovie
        newItem.mediaCategory = item.isMovie ? "movie" : "tv"
        
        // Parse and set release date
        if let dateString = item.displayDate {
            newItem.releaseDate = TMDBService.shared.parseDate(dateString)
        }
        
        // Fetch details to determine if anime (async, will update category if needed)
        Task {
            await determineAndSetCategory(for: newItem)
        }
        
        do {
            try viewContext.save()
            isAdded = true
            alertMessage = "\(item.displayTitle) added to Want to Watch!"
            showingAlert = true
        } catch {
            alertMessage = "Failed to add item. Please try again."
            showingAlert = true
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

// MARK: - Search Manager
class SearchManager: ObservableObject {
    @Published var results: [TMDBItem] = []
    @Published var isLoading = false
    
    private let tmdbService = TMDBService.shared
    private var searchTask: Task<Void, Never>?
    
    func search(query: String) {
        searchTask?.cancel()
        
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            return
        }
        
        searchTask = Task {
            await MainActor.run {
                isLoading = true
            }
            
            do {
                let searchResults = try await tmdbService.searchMulti(query: query)
                
                await MainActor.run {
                    self.results = searchResults
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.results = []
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    DiscoverMainView()
}
