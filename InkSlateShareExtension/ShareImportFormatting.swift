import Foundation
import UIKit
import UniformTypeIdentifiers

/// Converts shared rich text (Apple Notes, Safari, etc.) into the attributed-string
/// conventions InkSlate's note editor uses: literal list markers ("• ", "1. "),
/// system fonts that keep size/bold/italic, and plain link/underline/strikethrough
/// attributes that survive archiving into the app group payload.
enum ShareImportFormatting {

    static func attributedString(from data: Data, typeIdentifier: String) -> NSAttributedString? {
        let type = UTType(typeIdentifier)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = {
            if type == .rtf {
                return [.documentType: NSAttributedString.DocumentType.rtf]
            }
            if type == .rtfd || typeIdentifier == "com.apple.flat-rtfd" {
                return [.documentType: NSAttributedString.DocumentType.rtfd]
            }
            if type == .html {
                return [.documentType: NSAttributedString.DocumentType.html]
            }
            return [:]
        }()

        guard !options.isEmpty else { return nil }
        return try? NSAttributedString(data: data, options: options, documentAttributes: nil)
    }

    /// Rebuilds the shared text using only attributes InkSlate's editor understands.
    /// List paragraphs (NSTextList) become literal "• " / "1. " markers, matching how
    /// the editor stores lists. Exotic fonts and private attributes from the source
    /// app are dropped so the result archives and unarchives cleanly.
    static func editorAttributedString(from attributed: NSAttributedString) -> NSAttributedString {
        guard attributed.length > 0 else { return NSAttributedString() }

        let result = NSMutableAttributedString()
        let full = attributed.string as NSString
        var index = 0
        var orderedCounters: [Int: Int] = [:]

        while index < attributed.length {
            let paragraphRange = full.paragraphRange(for: NSRange(location: index, length: 0))
            index = paragraphRange.location + paragraphRange.length

            let style = attributed.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle
            let lists = style?.textLists ?? []
            if lists.isEmpty { orderedCounters.removeAll() }

            var marker = ""
            if let deepest = lists.last {
                let level = max(0, lists.count - 1)
                let indent = String(repeating: "    ", count: level)
                if deepest.markerFormat == .decimal {
                    let next = (orderedCounters[level] ?? 0) + 1
                    orderedCounters[level] = next
                    marker = indent + "\(next). "
                } else {
                    orderedCounters[level] = 0
                    marker = indent + bulletMarker(forLevel: level)
                }
            }

            let paragraph = sanitizedParagraph(from: attributed, range: paragraphRange)

            if !marker.isEmpty {
                let markerFont = (paragraph.length > 0 ? paragraph.attribute(.font, at: 0, effectiveRange: nil) as? UIFont : nil)
                    ?? UIFont.preferredFont(forTextStyle: .body)
                result.append(NSAttributedString(string: marker, attributes: [.font: markerFont]))
            }
            result.append(paragraph)
        }

        return result
    }

    private static func bulletMarker(forLevel level: Int) -> String {
        if level <= 0 { return "• " }
        if level == 1 { return "◦ " }
        return "▪ "
    }

    private static func sanitizedParagraph(from attributed: NSAttributedString, range: NSRange) -> NSAttributedString {
        let out = NSMutableAttributedString()
        attributed.enumerateAttributes(in: range, options: []) { attrs, runRange, _ in
            let raw = (attributed.string as NSString).substring(with: runRange)
            let text = raw.replacingOccurrences(of: "\u{FFFC}", with: "")
            guard !text.isEmpty else { return }
            out.append(NSAttributedString(string: text, attributes: sanitizedAttributes(attrs)))
        }
        return out
    }

    private static func sanitizedAttributes(_ attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var clean: [NSAttributedString.Key: Any] = [:]

        let sourceFont = attrs[.font] as? UIFont
        let size = sourceFont?.pointSize ?? UIFont.preferredFont(forTextStyle: .body).pointSize
        var font = UIFont.systemFont(ofSize: size)
        if let sourceFont {
            var symbolic: UIFontDescriptor.SymbolicTraits = []
            let traits = sourceFont.fontDescriptor.symbolicTraits
            if traits.contains(.traitBold) || sourceFont.weight >= .semibold {
                symbolic.insert(.traitBold)
            }
            if traits.contains(.traitItalic) {
                symbolic.insert(.traitItalic)
            }
            if !symbolic.isEmpty, let descriptor = font.fontDescriptor.withSymbolicTraits(symbolic) {
                font = UIFont(descriptor: descriptor, size: size)
            }
        }
        clean[.font] = font

        if let link = attrs[.link] {
            if let url = link as? URL {
                clean[.link] = url
            } else if let string = link as? String, let url = URL(string: string) {
                clean[.link] = url
            }
        }
        if let underline = attrs[.underlineStyle] as? NSNumber, underline.intValue != 0 {
            clean[.underlineStyle] = underline
        }
        if let strike = attrs[.strikethroughStyle] as? NSNumber, strike.intValue != 0 {
            clean[.strikethroughStyle] = strike
        }

        return clean
    }
}

private extension UIFont {
    var weight: UIFont.Weight {
        let traits = fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        guard let value = traits?[.weight] as? CGFloat else { return .regular }
        return UIFont.Weight(value)
    }
}
