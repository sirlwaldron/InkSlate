//
//  TMDBConfig.swift
//  InkSlate
//
//  TMDB API configuration. For key rotation, update here or use Info.plist key TMDB_API_KEY.
//

import Foundation

enum TMDBConfig {
    /// API key for The Movie Database. Read-only keys are designed for client use.
    /// To use a custom key: add TMDB_API_KEY to Info.plist, or replace the default below.
    static var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String
            ?? "c2ed76e24aa7e68be5549011ee9d3947"
    }
}
