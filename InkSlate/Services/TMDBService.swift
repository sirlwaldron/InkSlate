//
//  TMDBService.swift
//  InkSlate
//
//  Created by Lucas Waldron on 1/2/25.
//

import Foundation
import SwiftUI
import Combine

// MARK: - TMDb API Models
struct TMDBResponse: Codable {
    let results: [TMDBItem]
    let totalPages: Int
    let totalResults: Int
    
    enum CodingKeys: String, CodingKey {
        case results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

// MARK: - Movie/TV Details
struct TMDBMovieDetails: Codable {
    let id: Int
    let title: String?
    let overview: String?
    let runtime: Int?
    let genres: [TMDBGenre]?
    let tagline: String?
    let budget: Int?
    let revenue: Int?
    let status: String?
    let releaseDate: String?
    let voteAverage: Double?
    let posterPath: String?
    let backdropPath: String?
    
    enum CodingKeys: String, CodingKey {
        case id, title, overview, runtime, genres, tagline, budget, revenue, status
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }
}

struct TMDBTVDetails: Codable {
    let id: Int
    let name: String?
    let overview: String?
    let episodeRunTime: [Int]?
    let genres: [TMDBGenre]?
    let tagline: String?
    let status: String?
    let firstAirDate: String?
    let lastAirDate: String?
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let voteAverage: Double?
    let posterPath: String?
    let backdropPath: String?
    let networks: [TMDBNetwork]?
    
    enum CodingKeys: String, CodingKey {
        case id, name, overview, genres, tagline, status, networks
        case episodeRunTime = "episode_run_time"
        case firstAirDate = "first_air_date"
        case lastAirDate = "last_air_date"
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
        case voteAverage = "vote_average"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }
    
    var averageRuntime: Int? {
        guard let runtimes = episodeRunTime, !runtimes.isEmpty else { return nil }
        return runtimes.reduce(0, +) / runtimes.count
    }
}

struct TMDBGenre: Codable, Identifiable {
    let id: Int
    let name: String
}

struct TMDBNetwork: Codable, Identifiable {
    let id: Int
    let name: String
    let logoPath: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case logoPath = "logo_path"
    }
}

// MARK: - Credits
struct TMDBCredits: Codable {
    let id: Int
    let cast: [TMDBCastMember]
    let crew: [TMDBCrewMember]
}

struct TMDBCastMember: Codable, Identifiable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
    let order: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name, character, order
        case profilePath = "profile_path"
    }
    
    var profileURL: URL? {
        guard let profilePath = profilePath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w185\(profilePath)")
    }
}

struct TMDBCrewMember: Codable, Identifiable {
    let id: Int
    let name: String
    let job: String
    let department: String?
    let profilePath: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, job, department
        case profilePath = "profile_path"
    }
    
    var profileURL: URL? {
        guard let profilePath = profilePath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w185\(profilePath)")
    }
}

// MARK: - Combined Details Response
struct TMDBFullDetails {
    let title: String
    let overview: String?
    let tagline: String?
    let runtime: Int?
    let genres: [TMDBGenre]
    let status: String?
    let cast: [TMDBCastMember]
    let directors: [TMDBCrewMember]
    let writers: [TMDBCrewMember]
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
}

struct TMDBItem: Codable, Identifiable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let releaseDate: String?
    let firstAirDate: String?
    let mediaType: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case name
        case overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case mediaType = "media_type"
    }
    
    // Computed properties for easier access
    var displayTitle: String {
        return title ?? name ?? "Unknown"
    }
    
    var displayDate: String? {
        return releaseDate ?? firstAirDate
    }
    
    var isMovie: Bool {
        return mediaType == "movie" || (mediaType == nil && title != nil)
    }
    
    var isTVShow: Bool {
        return mediaType == "tv" || (mediaType == nil && name != nil)
    }
    
    var mediaTypeDisplay: String {
        if isMovie { return "Movie" }
        if isTVShow { return "TV Show" }
        return "Unknown"
    }
    
    var posterURL: URL? {
        guard let posterPath = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }
    
    var backdropURL: URL? {
        guard let backdropPath = backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w1280\(backdropPath)")
    }
    
    var rating: Double {
        return voteAverage ?? 0.0
    }
    
    var ratingCount: Int {
        return voteCount ?? 0
    }
}

// MARK: - TMDb Service
class TMDBService: ObservableObject {
    static let shared = TMDBService()
    
    private var apiKey: String { TMDBConfig.apiKey ?? "" }
    private let baseURL = "https://api.themoviedb.org/3"
    private let imageBaseURL = "https://image.tmdb.org/t/p"
    
    // Date formatter for TMDb API dates
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    // Display date formatter
    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale.current
        return formatter
    }()
    
    private init() {}
    
    // MARK: - Search Methods
    
    func searchMulti(query: String) async throws -> [TMDBItem] {
        guard TMDBConfig.apiKey != nil else {
            throw TMDBError.missingAPIKey
        }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "\(baseURL)/search/multi?api_key=\(apiKey)&query=\(encodedQuery)"
        
        guard let url = URL(string: urlString) else {
            throw TMDBError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMDBError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw TMDBError.httpStatus(httpResponse.statusCode)
        }
        
        let tmdbResponse = try JSONDecoder().decode(TMDBResponse.self, from: data)
        
        // Only allow movie/tv results (exclude "person" and others).
        return tmdbResponse.results.filter { item in
            item.mediaType == "movie" || item.mediaType == "tv"
        }
    }
    
    // MARK: - Fetch Details
    
    func fetchMovieDetails(id: Int) async throws -> TMDBMovieDetails {
        guard TMDBConfig.apiKey != nil else {
            throw TMDBError.missingAPIKey
        }
        let urlString = "\(baseURL)/movie/\(id)?api_key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw TMDBError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TMDBError.invalidResponse
        }
        
        return try JSONDecoder().decode(TMDBMovieDetails.self, from: data)
    }
    
    func fetchTVDetails(id: Int) async throws -> TMDBTVDetails {
        guard TMDBConfig.apiKey != nil else {
            throw TMDBError.missingAPIKey
        }
        let urlString = "\(baseURL)/tv/\(id)?api_key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw TMDBError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TMDBError.invalidResponse
        }
        
        return try JSONDecoder().decode(TMDBTVDetails.self, from: data)
    }
    
    func fetchCredits(id: Int, isMovie: Bool) async throws -> TMDBCredits {
        guard TMDBConfig.apiKey != nil else {
            throw TMDBError.missingAPIKey
        }
        let mediaType = isMovie ? "movie" : "tv"
        let urlString = "\(baseURL)/\(mediaType)/\(id)/credits?api_key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw TMDBError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TMDBError.invalidResponse
        }
        
        return try JSONDecoder().decode(TMDBCredits.self, from: data)
    }
    
    /// Fetch full details including cast and crew
    func fetchFullDetails(id: Int, isMovie: Bool) async throws -> TMDBFullDetails {
        async let creditsTask = fetchCredits(id: id, isMovie: isMovie)
        
        if isMovie {
            async let detailsTask = fetchMovieDetails(id: id)
            let (details, credits) = try await (detailsTask, creditsTask)
            
            let directors = credits.crew.filter { $0.job == "Director" }
            let writers = credits.crew.filter { $0.job == "Screenplay" || $0.job == "Writer" }
            
            return TMDBFullDetails(
                title: details.title ?? "Unknown",
                overview: details.overview,
                tagline: details.tagline,
                runtime: details.runtime,
                genres: details.genres ?? [],
                status: details.status,
                cast: Array(credits.cast.prefix(15)),
                directors: directors,
                writers: Array(writers.prefix(3)),
                numberOfSeasons: nil,
                numberOfEpisodes: nil
            )
        } else {
            async let detailsTask = fetchTVDetails(id: id)
            let (details, credits) = try await (detailsTask, creditsTask)
            
            let creators = credits.crew.filter { $0.job == "Creator" || $0.job == "Executive Producer" }
            
            return TMDBFullDetails(
                title: details.name ?? "Unknown",
                overview: details.overview,
                tagline: details.tagline,
                runtime: details.averageRuntime,
                genres: details.genres ?? [],
                status: details.status,
                cast: Array(credits.cast.prefix(15)),
                directors: Array(creators.prefix(3)),
                writers: [],
                numberOfSeasons: details.numberOfSeasons,
                numberOfEpisodes: details.numberOfEpisodes
            )
        }
    }
    
    // MARK: - Date Parsing
    
    func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString, !dateString.isEmpty else { return nil }
        return dateFormatter.date(from: dateString)
    }
    
    func formatDisplayDate(_ dateString: String?) -> String? {
        guard let date = parseDate(dateString) else { return nil }
        return displayDateFormatter.string(from: date)
    }
}

// MARK: - TMDb Errors
enum TMDBError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case noData
    case decodingError
    case missingAPIKey
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpStatus(let code):
            if code == 401 { return "TMDB authorization failed (check TMDB_API_KEY)" }
            if code == 429 { return "TMDB rate limit exceeded. Try again in a moment." }
            return "TMDB returned HTTP \(code)"
        case .noData:
            return "No data received"
        case .decodingError:
            return "Failed to decode response"
        case .missingAPIKey:
            return "TMDB API key is missing. Provide TMDB_API_KEY in Info.plist/build settings."
        }
    }
}
