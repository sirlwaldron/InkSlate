import Foundation

enum TMDBConfig {
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
