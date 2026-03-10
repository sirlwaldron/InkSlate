//
//  PerformanceTests.swift
//  InkSlateTests
//
//  Created by GPT-5 Codex on 11/11/25.
//

import XCTest
@testable import InkSlate

final class PerformanceTests: XCTestCase {
    
    func testMarkdownSerializationPerformance() throws {
        let content = String(repeating: "InkSlate performance serialization test.\n", count: 1500)
        let attributed = NSMutableAttributedString(string: content)
        
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            _ = PerformanceLogger.measure(log: PerformanceMetrics.serialization, name: "TestSerialize") {
                MarkdownSerialization.serialize(attributed)
            }
        }
    }
}

