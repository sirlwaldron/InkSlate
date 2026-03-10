//
//  PerformanceMetrics.swift
//  InkSlate
//
//  Created by GPT-5 Codex on 11/11/25.
//

import Foundation
import os.signpost

enum PerformanceMetrics {
    static let subsystem = "com.lucas.InkSlateNew"
    
    static let appLaunch = OSLog(subsystem: subsystem, category: "Launch")
    static let notesQuery = OSLog(subsystem: subsystem, category: "NotesQuery")
    static let serialization = OSLog(subsystem: subsystem, category: "Serialization")
    static let persistence = OSLog(subsystem: subsystem, category: "Persistence")
}

enum PerformanceLogger {
    @discardableResult
    static func measure<T>(log: OSLog, name: StaticString, execute block: () throws -> T) rethrows -> T {
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        defer { os_signpost(.end, log: log, name: name, signpostID: signpostID) }
        return try block()
    }
}

