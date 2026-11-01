import Foundation

// Platform-neutral list-editing logic shared by the iOS and macOS note editors.
// (WordListLineKind used to live in the UIKit-only MarkdownEditor.swift.)

// MARK: - Word-style multi-level list (•/◦/▪, 1., a), 1) …)

enum WordListLineKind {
    private static let indentU = 4
    static func listLevel(leading: String) -> Int { leading.count / indentU }
    static func leadingPrefix(_ line: String) -> String { String(line.prefix(while: { $0 == " " })) }
    static func detectBullet(in line: String, _ r: NSRange) -> NSRange? {
        let m = (line as NSString).range(of: "^\\s*[•◦▪] ", options: .regularExpression, range: r)
        return m.location != NSNotFound ? m : nil
    }
    static func detectNumbered(in line: String, _ r: NSRange) -> NSRange? {
        let n = line as NSString
        if n.range(of: "^\\s*\\d+\\. ", options: .regularExpression, range: r).location != NSNotFound { return r }
        if n.range(of: "^\\s*[a-z]\\) ", options: .regularExpression, range: r).location != NSNotFound { return r }
        if n.range(of: "^\\s*\\d+\\) ", options: .regularExpression, range: r).location != NSNotFound { return r }
        return nil
    }
    static func bulletMark(forLevel l: Int) -> String {
        if l <= 0 { return "• " }
        if l == 1 { return "◦ " }
        return "▪ "
    }
    static func nextTopLevelDecimal(before lineIndex: Int, lines: [String]) -> Int {
        let upper = min(lineIndex - 1, lines.count - 1)
        guard upper >= 0 else { return 1 }
        for i in stride(from: upper, through: 0, by: -1) {
            let raw = lines[i]
            if raw.first == " " { continue }
            if let r = raw.range(of: "^\\d+\\. ", options: .regularExpression) {
                if let n = Int(String(raw[r].dropLast(2))) { return n + 1 }
            }
        }
        return 1
    }
    static func relevelLineAfterIndent(_ line: String) -> String? {
        let sp = leadingPrefix(line)
        let L = listLevel(leading: sp)
        if L == 0 { return nil }
        let c = String(line.dropFirst(sp.count))
        if let r = c.range(of: "^\\d+\\. ", options: .regularExpression) {
            if L == 1, Int(String(c[r].dropLast(2))) != nil { return sp + "a) " + String(c[r.upperBound...]) }
            if L >= 2, Int(String(c[r].dropLast(2))) != nil { return sp + "1) " + String(c[r.upperBound...]) }
        }
        if L >= 2, let r = c.range(of: "^[a-z]\\) ", options: .regularExpression) { return sp + "1) " + String(c[r.upperBound...]) }
        if L == 1, c.hasPrefix("• ") { return sp + "◦ " + String(c.dropFirst(2)) }
        if L == 1, c.hasPrefix("◦ ") { return sp + "▪ " + String(c.dropFirst(2)) }
        if L >= 2, c.hasPrefix("• ") { return sp + "▪ " + String(c.dropFirst(2)) }
        if L >= 2, c.hasPrefix("◦ ") { return sp + "▪ " + String(c.dropFirst(2)) }
        return nil
    }
    static func relevelLineAfterOutdent(_ line: String, allLines: [String], myIndex: Int) -> String? {
        let sp = leadingPrefix(line)
        let c = String(line.dropFirst(sp.count))
        if sp.isEmpty, let r = c.range(of: "^[a-z]\\) ", options: .regularExpression) {
            return "\(nextTopLevelDecimal(before: myIndex, lines: allLines)). " + String(c[r.upperBound...]) }
        if !sp.isEmpty, let r = c.range(of: "^[a-z]\\) ", options: .regularExpression) {
            let n = nextTopLevelDecimal(before: myIndex, lines: allLines)
            if sp.isEmpty { return "\(n). " + String(c[r.upperBound...]) }
            return sp + "\(n). " + String(c[r.upperBound...]) }
        if !sp.isEmpty, let r = c.range(of: "^\\d+\\) ", options: .regularExpression) {
            if sp.isEmpty {
                let n = nextTopLevelDecimal(before: myIndex, lines: allLines)
                return "\(n). " + String(c[r.upperBound...]) }
            return sp + "a) " + String(c[r.upperBound...]) }
        if sp.isEmpty, c.hasPrefix("◦ ") { return "• " + String(c.dropFirst(2)) }
        if !sp.isEmpty, c.hasPrefix("◦ ") { return sp + "• " + String(c.dropFirst(2)) }
        if !sp.isEmpty, c.hasPrefix("▪ ") { return sp + "◦ " + String(c.dropFirst(2)) }
        return nil
    }
}

// MARK: - Pure list-editing decisions (used by the macOS editor; string in, decision out)

enum ListEditingLogic {
    enum ReturnOutcome: Equatable {
        /// Not a list line (or caret not after the marker): let the text view insert a normal newline.
        case defaultBehavior
        /// Empty list item: remove the marker/indent, keep the line break.
        case clearMarker
        /// Insert this text (starts with "\n") instead of a plain newline.
        case insert(String)
    }

    /// Port of the iOS Return behavior. `line` is the caret's line (a trailing "\n" is ignored),
    /// `caretInLine` is the caret offset in UTF-16 units from the line start.
    static func returnOutcome(line rawLine: String, caretInLine: Int, lineIndex: Int, docLines: [String]) -> ReturnOutcome {
        let line = rawLine.hasSuffix("\n") ? String(rawLine.dropLast()) : rawLine
        let ns = line as NSString
        // Caret at the line start or inside the marker: plain newline (else the marker would double up).
        let markerMatch = ns.range(of: #"^\s*([•◦▪] |\d+\. |\d+\) |[a-z]\) )"#, options: .regularExpression)
        guard markerMatch.location != NSNotFound else { return .defaultBehavior }
        if caretInLine < NSMaxRange(markerMatch) { return .defaultBehavior }

        let lead = WordListLineKind.leadingPrefix(line)
        let level = WordListLineKind.listLevel(leading: lead)
        let after = String(line.dropFirst(lead.count))
        let afterNS = after as NSString

        func rest(_ m: NSTextCheckingResult) -> String {
            afterNS.substring(from: m.range.length).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func match(_ pattern: String) -> NSTextCheckingResult? {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            return re.firstMatch(in: after, options: [], range: NSRange(location: 0, length: afterNS.length))
        }

        if let m = match(#"^[•◦▪] "#) {
            if rest(m).isEmpty { return .clearMarker }
            return .insert("\n\(lead)\(WordListLineKind.bulletMark(forLevel: level))")
        }
        if let m = match(#"^(\d+)\)\s"#), let d = Int(afterNS.substring(with: m.range(at: 1))) {
            if rest(m).isEmpty { return .clearMarker }
            return .insert("\n\(lead)\(d + 1)) ")
        }
        if let m = match(#"^([a-z])\)\s"#) {
            if rest(m).isEmpty { return .clearMarker }
            if level == 0 {
                let n = WordListLineKind.nextTopLevelDecimal(before: lineIndex, lines: docLines)
                return .insert("\n\(n). ")
            }
            let ch = afterNS.substring(with: m.range(at: 1)).unicodeScalars.first?.value ?? 97
            let next = ch < 122 ? ch + 1 : 97
            let nextCh = Character(UnicodeScalar(next) ?? "a")
            return .insert("\n\(lead)\(nextCh)) ")
        }
        if let m = match(#"^(\d+)\.\s"#), let n0 = Int(afterNS.substring(with: m.range(at: 1))) {
            if rest(m).isEmpty { return .clearMarker }
            if level == 0 { return .insert("\n\(lead)\(n0 + 1). ") }
            let u = (n0 - 1) % 26
            let nextCode = 97 + (u + 1) % 26
            let nextCh = Character(UnicodeScalar(UInt8(nextCode)))
            return .insert("\n\(lead)\(nextCh)) ")
        }
        return .defaultBehavior
    }

    /// Removes the leading indent and list marker (any kind), or returns the line unchanged.
    static func removingListMarker(from line: String) -> String {
        let n = line as NSString
        for p in ["^\\s*[•◦▪] ", "^\\s*\\d+\\. ", "^\\s*\\d+\\) ", "^\\s*[a-z]\\) "] {
            let r = n.range(of: p, options: .regularExpression)
            if r.location != NSNotFound { return n.replacingCharacters(in: r, with: "") }
        }
        return line
    }

    static func isListLine(_ line: String) -> Bool {
        line.range(of: #"^\s*([•◦▪] |\d+\. |\d+\) |[a-z]\) )"#, options: .regularExpression) != nil
    }

    /// One indent level = 4 spaces. Outdenting a non-indented list line removes its marker.
    static func indentOrOutdent(_ line: String, outdent: Bool, allDocumentLines: [String], lineIndex: Int) -> String {
        if outdent {
            let lead = line.prefix(while: { $0 == " " })
            let remove = min(4, lead.count)
            if remove == 0 {
                return isListLine(line) ? removingListMarker(from: line) : line
            }
            let t = String(line.dropFirst(remove))
            return WordListLineKind.relevelLineAfterOutdent(t, allLines: allDocumentLines, myIndex: lineIndex) ?? t
        }
        let t = String(repeating: " ", count: 4) + line
        return WordListLineKind.relevelLineAfterIndent(t) ?? t
    }

    /// Marker rewrites needed so every "N. " block counts 1, 2, 3 … per indent level (blank lines and
    /// non-list lines end a block). Ranges are absolute UTF-16 ranges in `text`.
    static func decimalRenumberChanges(in text: String) -> [(range: NSRange, newMarker: String)] {
        guard text.range(of: #"(?m)^\s*\d+\. "#, options: .regularExpression) != nil else { return [] }
        let lines = (text as NSString).components(separatedBy: "\n")
        var nextByIndent: [String: Int] = [:]
        var inBlock: Set<String> = []
        var changes: [(range: NSRange, newMarker: String)] = []
        var pos = 0
        for line in lines {
            let len = (line as NSString).length
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                inBlock.removeAll()
            } else {
                let ind = WordListLineKind.leadingPrefix(line)
                let nsLine = line as NSString
                let markerRange = nsLine.range(of: #"^\s*\d+\. "#, options: .regularExpression)
                if markerRange.location != NSNotFound {
                    if !inBlock.contains(ind) {
                        inBlock.insert(ind)
                        nextByIndent[ind] = 1
                    }
                    let n = nextByIndent[ind] ?? 1
                    let correct = ind + "\(n). "
                    if correct != nsLine.substring(with: markerRange) {
                        changes.append((NSRange(location: pos + markerRange.location, length: markerRange.length), correct))
                    }
                    nextByIndent[ind] = n + 1
                } else {
                    inBlock.remove(ind)
                }
            }
            pos += len + 1
        }
        return changes
    }
}
