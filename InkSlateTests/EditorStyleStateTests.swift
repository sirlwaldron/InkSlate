//
//  EditorStyleStateTests.swift
//  InkSlateTests
//

import Testing
@testable import InkSlate

#if canImport(UIKit)
import UIKit

struct EditorStyleStateTests {
    @Test func activeStyles_caretAtEnd_usesTypingAttributesNotLastCharacter() async throws {
        let boldFont = UIFont.systemFont(ofSize: 17, weight: .bold)
        let regularFont = UIFont.systemFont(ofSize: 17, weight: .regular)
        
        let attributed = NSAttributedString(string: "A", attributes: [.font: boldFont])
        let selectedRange = NSRange(location: 1, length: 0) // caret at end
        let typingAttributes: [NSAttributedString.Key: Any] = [.font: regularFont]
        
        let styles = EditorStyleState.activeStyles(
            typingModes: [],
            attributedText: attributed,
            selectedRange: selectedRange,
            typingAttributes: typingAttributes,
            currentLine: ""
        )
        
        #expect(!styles.contains(.bold))
    }
}
#endif

