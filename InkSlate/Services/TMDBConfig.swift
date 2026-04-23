//
//  TMDBConfig.swift
//  InkSlate
//
//  TMDB API configuration. For key rotation, update here or use Info.plist key TMDB_API_KEY.
//

import Foundation

enum TMDBConfig {
    /// API key for The Movie Database. Override order:
    /// 1) Process environment `TMDB_API_KEY` (Xcode scheme)
    /// 2) `TMDB_API_KEY` in the merged Info.plist (build setting `$(TMDB_API_KEY)`)
    /// 3) Default read-only v3 key from the initial app import (public in git history; replace via 1/2 to rotate)
    private static let defaultReadOnlyV3Key = "c2ed76e24aa7e68be5549011ee9d3947"

    static var apiKey: String? {
        if let raw = ProcessInfo.processInfo.environment["TMDB_API_KEY"] {
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { return v }
        }
        if let plist = (Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !plist.isEmpty
        { return plist }
        return defaultReadOnlyV3Key
    }
}
