import Foundation
import os.log

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum EditorTheme {
    #if canImport(UIKit)
    static var baseFont: UIFont { UIFont.preferredFont(forTextStyle: .body) }
    static func font(size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont {
        var f = UIFont.systemFont(ofSize: size, weight: weight)
        if italic, let d = f.fontDescriptor.withSymbolicTraits(.traitItalic) {
            f = UIFont(descriptor: d, size: size)
        }
        return f
    }
    static var textColor: UIColor { .label }
    static var linkColor: UIColor { .systemBlue }
    #elseif canImport(AppKit)
    static var baseFont: NSFont { NSFont.preferredFont(forTextStyle: .body) }
    static func font(size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
        var f = NSFont.systemFont(ofSize: size, weight: weight)
        if italic {
            let descriptor = f.fontDescriptor.withSymbolicTraits(.italic)
            f = NSFont(descriptor: descriptor, size: size) ?? f
        }
        return f
    }
    static var textColor: NSColor { .labelColor }
    static var linkColor: NSColor { .linkColor }
    #endif
}

struct EditorContentParser {
    static func deserialize(_ text: String, maxWidth: CGFloat) -> NSAttributedString {
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: EditorTheme.baseFont,
            .foregroundColor: EditorTheme.textColor
        ]
        let m = NSMutableAttributedString(string: text, attributes: baseAttrs)

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let ns = text as NSString
            let full = NSRange(location: 0, length: ns.length)
            detector.enumerateMatches(in: text, options: [], range: full) { result, _, _ in
                guard let result, let url = result.url, result.range.length > 0 else { return }
                m.addAttribute(.link, value: url, range: result.range)
                m.addAttribute(.foregroundColor, value: EditorTheme.linkColor, range: result.range)
                m.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: result.range)
            }
        }

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        m.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: m.length))
        return m
    }
}


extension NSAttributedString.Key {
    static let inkSlateFontTraits = NSAttributedString.Key("inkSlateFontTraits")
    static let inkSlateFontSize = NSAttributedString.Key("inkSlateFontSize")
    static let inkSlateFontWeight = NSAttributedString.Key("inkSlateFontWeight")
}

struct MarkdownSerialization {
    private static let attrPrefix = "⟪ATTR⟫"
    private static let attrSuffix = "⟪/ATTR⟫"
    private static let serializationLog = Logger(subsystem: "com.lucas.InkSlateNew", category: "MarkdownSerialization")

    static var allowedUnarchiveClasses: [AnyClass] {
        var classes: [AnyClass] = [
            NSAttributedString.self,
            NSMutableAttributedString.self,
            NSURL.self,
            NSData.self,
            NSDictionary.self,
            NSMutableDictionary.self,
            NSString.self,
            NSNumber.self,
            NSParagraphStyle.self,
            NSMutableParagraphStyle.self,
            NSTextTab.self,
            NSTextList.self,
            NSShadow.self,
            NSTextAttachment.self,
            NSValue.self,
            NSArray.self,
            NSMutableArray.self
        ]
        #if canImport(UIKit)
        classes += [UIColor.self, UIFont.self, UIFontDescriptor.self, UIImage.self]
        #elseif canImport(AppKit)
        classes += [NSColor.self, NSFont.self, NSFontDescriptor.self, NSImage.self]
        #endif
        return classes
    }

    static func prepareForArchiving(_ mutable: NSMutableAttributedString) {
        let range = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttributes(in: range, options: []) { attrs, r, _ in
            #if canImport(UIKit)
            if let font = attrs[.font] as? UIFont {
                let traits = font.fontDescriptor.symbolicTraits.rawValue
                mutable.addAttribute(.inkSlateFontTraits, value: NSNumber(value: traits), range: r)
                mutable.addAttribute(.inkSlateFontSize, value: NSNumber(value: Float(font.pointSize)), range: r)
                let traitsDict = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
                if let weight = traitsDict?[.weight] as? CGFloat, weight != 0 {
                    mutable.addAttribute(.inkSlateFontWeight, value: NSNumber(value: Double(weight)), range: r)
                }
                mutable.removeAttribute(.font, range: r)
            }
            if attrs[.foregroundColor] is UIColor {
                mutable.removeAttribute(.foregroundColor, range: r)
            }
            #elseif canImport(AppKit)
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits.rawValue
                mutable.addAttribute(.inkSlateFontTraits, value: NSNumber(value: traits), range: r)
                mutable.addAttribute(.inkSlateFontSize, value: NSNumber(value: Float(font.pointSize)), range: r)
                let traitsDict = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
                if let weight = traitsDict?[.weight] as? CGFloat, weight != 0 {
                    mutable.addAttribute(.inkSlateFontWeight, value: NSNumber(value: Double(weight)), range: r)
                }
                mutable.removeAttribute(.font, range: r)
            }
            if attrs[.foregroundColor] is NSColor {
                mutable.removeAttribute(.foregroundColor, range: r)
            }
            #endif
        }
    }

    static func serialize(_ attributed: NSAttributedString) -> String {
        let mutable = attributed as? NSMutableAttributedString ?? NSMutableAttributedString(attributedString: attributed)
        let forArchive = NSMutableAttributedString(attributedString: NotePhotoAttachment.stripHeavyImagesForPersistence(mutable))
        prepareForArchiving(forArchive)

        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: forArchive, requiringSecureCoding: false)
            let encoded = data.base64EncodedString()
            let plain = plainTextRepresentation(of: mutable)
            return attrPrefix + encoded + attrSuffix + plain
        } catch {
            return plainTextRepresentation(of: mutable)
        }
    }

    static func deserialize(_ text: String, maxWidth: CGFloat) -> (NSAttributedString, String)? {
        guard let components = components(from: text) else {
            return nil
        }

        let base64 = components.base64
        let plainText = components.plainText
        guard let data = Data(base64Encoded: base64) else {
            return (EditorContentParser.deserialize(plainText, maxWidth: maxWidth), plainText)
        }

        do {
            guard let attributed = try NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedUnarchiveClasses, from: data) as? NSAttributedString else {
                return (EditorContentParser.deserialize(plainText, maxWidth: maxWidth), plainText)
            }

            let mutable = NSMutableAttributedString(attributedString: attributed)
            restoreFontAttributes(in: mutable)
            return (mutable, plainText)
        } catch {
            serializationLog.error("Rich note deserialize failed; falling back to plain text. \(error.localizedDescription, privacy: .public)")
            return (EditorContentParser.deserialize(plainText, maxWidth: maxWidth), plainText)
        }
    }

    static func plainText(from serialized: String) -> String {
        if let components = components(from: serialized) {
            return components.plainText
        }
        let fallback = EditorContentParser.deserialize(serialized, maxWidth: 300)
        return plainTextRepresentation(of: fallback)
    }

    /// Cheap plain-text extraction for search: skips the base64 archive so queries
    /// never match encoded formatting data. Legacy (unserialized) content is returned as-is.
    static func searchablePlainText(from serialized: String) -> String {
        components(from: serialized)?.plainText ?? serialized
    }

    private static func components(from text: String) -> (base64: String, plainText: String)? {
        guard
            let prefixRange = text.range(of: attrPrefix),
            let suffixRange = text.range(of: attrSuffix, range: prefixRange.upperBound..<text.endIndex)
        else { return nil }

        let base64 = String(text[prefixRange.upperBound..<suffixRange.lowerBound])
        let plain = String(text[suffixRange.upperBound...])
        return (base64, plain)
    }

    static func plainTextRepresentation(of attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }
        let full = attributed.string as NSString
        var result = ""
        var idx = 0
        var orderedCounter = 0
        while idx < attributed.length {
            let paraRange = full.paragraphRange(for: NSRange(location: idx, length: 0))
            let rawParagraph = full.substring(with: paraRange)
            let lineContent = rawParagraph
                .replacingOccurrences(of: "\u{FFFC}", with: " ")
                .trimmingCharacters(in: .newlines)
            let ps = attributed.attribute(.paragraphStyle, at: paraRange.location, effectiveRange: nil) as? NSParagraphStyle
            if let lists = ps?.textLists, let deepest = lists.last {
                let isOrdered = deepest.markerFormat == .decimal
                if isOrdered {
                    orderedCounter += 1
                    result += "\(orderedCounter). " + lineContent + "\n"
                } else {
                    orderedCounter = 0
                    result += "• " + lineContent + "\n"
                }
            } else {
                orderedCounter = 0
                result += rawParagraph.replacingOccurrences(of: "\u{FFFC}", with: " ")
            }
            idx = paraRange.location + paraRange.length
        }
        return result.trimmingCharacters(in: .newlines)
    }

    private static func restoreFontAttributes(in mutable: NSMutableAttributedString) {
        let range = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttributes(in: range, options: []) { attrs, r, _ in
            var restoredFont: Any? = nil
            var restoredColor: Any? = EditorTheme.textColor
            
            if let _ = attrs[.link] {
                restoredColor = EditorTheme.linkColor
            }
            
            #if canImport(UIKit)
            if let sizeNum = attrs[.inkSlateFontSize] as? NSNumber {
                let size = CGFloat(sizeNum.floatValue)
                var font: UIFont
                if let weightNum = attrs[.inkSlateFontWeight] as? NSNumber {
                    font = UIFont.systemFont(ofSize: size, weight: UIFont.Weight(rawValue: CGFloat(weightNum.doubleValue)))
                } else {
                    font = UIFont.systemFont(ofSize: size)
                }
                if let traitsNum = attrs[.inkSlateFontTraits] as? NSNumber {
                    let traits = UIFontDescriptor.SymbolicTraits(rawValue: traitsNum.uint32Value)
                    if let d = font.fontDescriptor.withSymbolicTraits(traits) {
                        font = UIFont(descriptor: d, size: size)
                    }
                }
                restoredFont = font
            }
            #elseif canImport(AppKit)
            if let sizeNum = attrs[.inkSlateFontSize] as? NSNumber {
                let size = CGFloat(sizeNum.floatValue)
                var font: NSFont
                if let weightNum = attrs[.inkSlateFontWeight] as? NSNumber {
                    font = NSFont.systemFont(ofSize: size, weight: NSFont.Weight(rawValue: CGFloat(weightNum.doubleValue)))
                } else {
                    font = NSFont.systemFont(ofSize: size)
                }
                if let traitsNum = attrs[.inkSlateFontTraits] as? NSNumber {
                    let traits = NSFontDescriptor.SymbolicTraits(rawValue: traitsNum.uint32Value)
                    let d = font.fontDescriptor.withSymbolicTraits(traits)
                    font = NSFont(descriptor: d, size: size) ?? font
                }
                restoredFont = font
            }
            #endif
            
            if let rf = restoredFont {
                mutable.addAttribute(.font, value: rf, range: r)
                mutable.removeAttribute(.inkSlateFontTraits, range: r)
                mutable.removeAttribute(.inkSlateFontSize, range: r)
                mutable.removeAttribute(.inkSlateFontWeight, range: r)
            } else {
                #if canImport(UIKit)
                if attrs[.font] as? UIFont == nil {
                    mutable.addAttribute(.font, value: EditorTheme.baseFont, range: r)
                }
                #elseif canImport(AppKit)
                if attrs[.font] as? NSFont == nil {
                    mutable.addAttribute(.font, value: EditorTheme.baseFont, range: r)
                }
                #endif
            }
            
            if let rc = restoredColor {
                mutable.addAttribute(.foregroundColor, value: rc, range: r)
            }
        }
    }
}
