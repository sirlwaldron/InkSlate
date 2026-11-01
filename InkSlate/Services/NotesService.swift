import Foundation
import Foundation

// MARK: - Enums
enum SortBy: String, CaseIterable {
    case title = "title"
    case creationDate = "creationDate"
    case modificationDate = "modificationDate"
    case pin = "pin"

    static func fromProjectSettings(_ raw: String?) -> SortBy {
        switch raw {
        case "creationDate": return .creationDate
        case "title": return .title
        case "pin": return .pin
        default: return .modificationDate
        }
    }
}

enum SortDirection: String, CaseIterable {
    case ascending = "ascending"
    case descending = "descending"
}
