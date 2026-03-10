//
//  MarkdownEditor.swift
//  InkSlate
//

import SwiftUI
import UIKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Theme

struct EditorTheme {
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
}

// MARK: - Editor Content Parser

struct EditorContentParser {
    static func deserialize(_ text: String, maxWidth: CGFloat) -> NSAttributedString {
        // Simple parser - just return plain text with default attributes
        return NSAttributedString(string: text, attributes: [
            .font: EditorTheme.baseFont,
            .foregroundColor: EditorTheme.textColor
        ])
    }
}

struct MarkdownSerialization {
    private static let attrPrefix = "⟪ATTR⟫"
    private static let attrSuffix = "⟪/ATTR⟫"
    
    static func serialize(_ attributed: NSAttributedString) -> String {
        let mutable = attributed as? NSMutableAttributedString ?? NSMutableAttributedString(attributedString: attributed)
        
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: mutable, requiringSecureCoding: false)
            let encoded = data.base64EncodedString()
            let plain = plainTextRepresentation(of: mutable)
            return attrPrefix + encoded + attrSuffix + plain
        } catch {
            print("⚠️ Serialization failed: \(error.localizedDescription)")
            // Fallback to plain text
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
            print("⚠️ Invalid base64 data")
            return nil
        }
        
        let allowedClasses: [AnyClass] = [
            NSAttributedString.self,
            NSMutableAttributedString.self,
            UIColor.self,
            UIFont.self,
            UIFontDescriptor.self,  // Required for fonts with symbolic traits (bold, italic, etc.)
            NSURL.self,
            NSData.self,
            NSDictionary.self,
            NSString.self,
            NSNumber.self,
            NSParagraphStyle.self,
            NSMutableParagraphStyle.self,
            NSTextTab.self,
            NSShadow.self
        ]
        
        do {
            guard let attributed = try NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: data) as? NSAttributedString else {
                print("⚠️ Failed to unarchive attributed string")
                return nil
            }
            
            let mutable = NSMutableAttributedString(attributedString: attributed)
            // Ensure font attributes are preserved (fixes CloudKit sync issues)
            restoreFontAttributes(in: mutable)
            return (mutable, plainText)
        } catch {
            print("⚠️ Deserialization failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    static func plainText(from serialized: String) -> String {
        if let components = components(from: serialized) {
            return components.plainText
        }
        let fallback = EditorContentParser.deserialize(serialized, maxWidth: 300)
        return plainTextRepresentation(of: fallback)
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
    
    private static func plainTextRepresentation(of attributed: NSAttributedString) -> String {
        return attributed.string
    }
    
    /// Restores font attributes after deserialization to ensure traits (bold, italic) are preserved
    /// This is especially important after CloudKit sync where font descriptors might be simplified
    private static func restoreFontAttributes(in mutable: NSMutableAttributedString) {
        let range = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttributes(in: range, options: []) { attrs, r, _ in
            guard let font = attrs[.font] as? UIFont else { return }
            let descriptor = font.fontDescriptor
            let traits = descriptor.symbolicTraits
            
            // Recreate font with explicit traits to ensure they're preserved
            // This fixes issues where fonts lose their traits during CloudKit sync
            if traits.rawValue != 0 {
                if let newDescriptor = descriptor.withSymbolicTraits(traits) {
                    let restoredFont = UIFont(descriptor: newDescriptor, size: font.pointSize)
                    // Update the font while preserving all other attributes
                    mutable.addAttribute(.font, value: restoredFont, range: r)
                }
            }
        }
    }
}


// MARK: - Markdown Actions

enum MarkdownAction: Int, CaseIterable, Hashable {
    case bold = 0, italic, strikethrough, underline
    case removeFormat
    case header1, header2, header3
    case bulletList, numberedList, indent, outdent
    case alignLeft, alignCenter, alignRight
    case link
    case undo, redo
}

// MARK: - Global editor state & notifications

private struct ActiveEditorCoordinator {
    static weak var instance: MarkdownEditor.Coordinator?
}

private extension MarkdownEditor {
    static var activeCoordinator: Coordinator? {
        get { ActiveEditorCoordinator.instance }
        set { ActiveEditorCoordinator.instance = newValue }
    }
}

extension Notification.Name {
    static let editorActiveStylesDidChange = Notification.Name("EditorActiveStylesDidChange")
}

// MARK: - Helpers

private extension UITextView {
    func tsBegin() { textStorage.beginEditing() }
    func tsEnd() { textStorage.endEditing() }

    func replace(range: NSRange, with attributed: NSAttributedString) {
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: range, with: attributed)
        textStorage.endEditing()
    }

    func setAttributes(_ attrs: [NSAttributedString.Key: Any], range: NSRange) {
        textStorage.beginEditing()
        textStorage.setAttributes(attrs, range: range)
        textStorage.endEditing()
    }

    func setAttributedStringUndoSafe(_ m: NSAttributedString) {
        textStorage.beginEditing()
        textStorage.setAttributedString(m)
        textStorage.endEditing()
    }
}

private extension UIViewController {
    func topMostViewController() -> UIViewController {
        if let presented = presentedViewController { return presented.topMostViewController() }
        if let nav = self as? UINavigationController { return nav.visibleViewController?.topMostViewController() ?? self }
        if let tab = self as? UITabBarController { return tab.selectedViewController?.topMostViewController() ?? self }
        return self
    }
}

private func currentTopVC() -> UIViewController? {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let win = scene.windows.first(where: { $0.isKeyWindow }) else { return nil }
    return win.rootViewController?.topMostViewController()
}

// MARK: - UIViewRepresentable

struct MarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var coordinatorRef: Coordinator?
    
    func makeUIView(context: Context) -> EditorTextView {
        let textView = EditorTextView()

        textView.backgroundColor = .systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 13, left: 10, bottom: 13, right: 10)
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.adjustsFontForContentSizeCategory = true
        textView.layoutManager.allowsNonContiguousLayout = true
        textView.allowsEditingTextAttributes = true
        textView.dataDetectorTypes = [.link]
        textView.isScrollEnabled = true
        textView.isUserInteractionEnabled = true

        textView.linkTextAttributes = [
            .foregroundColor: EditorTheme.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        textView.delegate = context.coordinator
        textView.pasteDelegate = context.coordinator
        textView.undoManager?.levelsOfUndo = 50

        // Load text
        let attributed = context.coordinator.deserializeContent(text)
        textView.attributedText = attributed
        
        context.coordinator.textView = textView
        MarkdownEditor.activeCoordinator = context.coordinator

        context.coordinator.applyTypingAttributes(in: textView)
        NotificationCenter.default.post(name: .editorActiveStylesDidChange, object: nil,
                                        userInfo: ["styles": context.coordinator.currentActiveStyles(in: textView)])

        DispatchQueue.main.async { textView.becomeFirstResponder() }
        
        return textView
    }
    
    func updateUIView(_ uiView: EditorTextView, context: Context) {
        guard !uiView.isFirstResponder else { return }

        context.coordinator.textView = uiView
        let latest = context.coordinator.serializeContent(from: uiView.attributedText)
        guard latest != text else { return }

        DispatchQueue.main.async {
            let range = uiView.selectedRange
            let attributed = context.coordinator.deserializeContent(text)
            uiView.setAttributedStringUndoSafe(attributed)
            if range.location <= uiView.attributedText.length {
                uiView.selectedRange = range
            }
        }
    }

    func makeCoordinator() -> Coordinator { 
        let coord = Coordinator(self)
        DispatchQueue.main.async {
            self.coordinatorRef = coord
        }
        return coord
    }
    
    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate, UITextPasteDelegate {
        var parent: MarkdownEditor
        weak var textView: EditorTextView?
        private var isProgrammaticChange = false

        private var saveWorkItem: DispatchWorkItem?
        private var styleCalculationWorkItem: DispatchWorkItem?
        
        fileprivate var typingModes = Set<MarkdownAction>()

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }
        
        deinit {
            saveWorkItem?.cancel()
            styleCalculationWorkItem?.cancel()
            fontCache.removeAll()
            
            // Clear active coordinator reference
            MarkdownEditor.activeCoordinator = nil
            
            // Post final update to clear UI state
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .editorActiveStylesDidChange,
                    object: nil,
                    userInfo: ["styles": Set<MarkdownAction>()]
                )
            }
        }

        // MARK: Serialization
        
        func serializeContent(from attributed: NSAttributedString) -> String {
            let mutable = attributed as? NSMutableAttributedString ?? NSMutableAttributedString(attributedString: attributed)
            return MarkdownSerialization.serialize(mutable)
        }
        
        func deserializeContent(_ text: String) -> NSAttributedString {
            let availableWidth = max((textView?.bounds.width ?? 300) - 28, 60)
            if let (attr, _) = MarkdownSerialization.deserialize(text, maxWidth: availableWidth) {
                return attr
            }
            return EditorContentParser.deserialize(text, maxWidth: availableWidth)
        }

        // MARK: Text changes
        
        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammaticChange else { return }
            saveWorkItem?.cancel()

            let updateParent: () -> Void = { [weak self] in
                guard let self = self else { return }
                // Serialize synchronously on main thread (fast enough, avoids race conditions)
                let serialized = self.serializeContent(from: textView.attributedText)
                self.parent.text = serialized
            }

            if textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true {
                updateParent()
            } else {
                let item = DispatchWorkItem(block: updateParent)
                saveWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
            }

            parent.selectedRange = textView.selectedRange
            updateActiveStylesAsync(textView)
        }

        private func updateActiveStylesAsync(_ textView: UITextView) {
            styleCalculationWorkItem?.cancel()
            styleCalculationWorkItem = DispatchWorkItem { [weak self] in
                guard let strongSelf = self else { return }
                let styles = strongSelf.currentActiveStyles(in: textView)
                NotificationCenter.default.post(name: .editorActiveStylesDidChange,
                                                object: nil, userInfo: ["styles": styles])
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: styleCalculationWorkItem!)
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selectedRange = textView.selectedRange
            (textView as? EditorTextView)?.registerLinkMenuItems()
            NotificationCenter.default.post(name: .editorActiveStylesDidChange, object: nil,
                                            userInfo: ["styles": currentActiveStyles(in: textView)])
        }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText string: String) -> Bool {
            if string == "\n" {
                if let etv = tv as? EditorTextView, WysiwygActionHandler.handleReturn(in: etv) {
                    return false
                }
            }
            // Handle Tab key for indenting lists
            if string == "\t" {
                if let etv = tv as? EditorTextView {
                    WysiwygActionHandler.apply(.indent, to: etv)
                    return false
                }
            }
            return true
        }

        // MARK: Paste sanitization + image paste
        func textPasteConfigurationSupporting(_ textPasteConfigurationSupporting: UITextPasteConfigurationSupporting, transform item: UITextPasteItem) {
            if item.itemProvider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                item.setDefaultResult()
            } else if item.itemProvider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                item.itemProvider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { obj, _ in
                    if let s = obj as? String { item.setResult(string: s) } else { item.setDefaultResult() }
                }
            } else {
                item.setDefaultResult()
            }
        }

        // MARK: Actions routing
        
        func handleMarkdownAction(_ action: MarkdownAction) {
            guard let tv = textView else { return }

            switch action {
            case .undo:
                tv.undoManager?.undo()
                // Recalculate typing modes based on current cursor position
                typingModes.removeAll()
                applyTypingAttributes(in: tv)
                // Direct serialization instead of serializeAndPublishContent
                parent.text = serializeContent(from: tv.attributedText)
                parent.selectedRange = tv.selectedRange
                NotificationCenter.default.post(name: .editorActiveStylesDidChange,
                                                object: nil,
                                                userInfo: ["styles": currentActiveStyles(in: tv)])
                return
            case .redo:
                tv.undoManager?.redo()
                // Recalculate typing modes based on current cursor position
                typingModes.removeAll()
                applyTypingAttributes(in: tv)
                // Direct serialization instead of serializeAndPublishContent
                parent.text = serializeContent(from: tv.attributedText)
                parent.selectedRange = tv.selectedRange
                NotificationCenter.default.post(name: .editorActiveStylesDidChange,
                                                object: nil,
                                                userInfo: ["styles": currentActiveStyles(in: tv)])
                return
            default: break
            }

            if action == .removeFormat {
                typingModes.removeAll()
                applyTypingAttributes(in: tv)
            }

            isProgrammaticChange = true
            defer { isProgrammaticChange = false }  // Ensures cleanup even if error occurs
            
            tv.undoManager?.beginUndoGrouping()
            
            WysiwygActionHandler.apply(action, to: tv)
            
            tv.undoManager?.endUndoGrouping()

            // Direct serialization instead of serializeAndPublishContent
            parent.text = serializeContent(from: tv.attributedText)
            parent.selectedRange = tv.selectedRange
            NotificationCenter.default.post(name: .editorActiveStylesDidChange, object: nil,
                                            userInfo: ["styles": currentActiveStyles(in: tv)])
            
            if action == .link {
                promptForLink(tv)
            }
        }
        
        func topViewController() -> UIViewController? { currentTopVC() }

        // MARK: Link prompt

        func promptForLink(_ textView: UITextView) {
            let alert = UIAlertController(title: "Add Link", message: nil, preferredStyle: .alert)
            alert.addTextField {
                $0.placeholder = "https://example.com"
                $0.keyboardType = .URL
                $0.autocorrectionType = .no
                $0.autocapitalizationType = .none
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                guard let strongSelf = self else { return }
                var urlString = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !urlString.isEmpty && !urlString.contains("://") { urlString = "https://" + urlString }
                guard !urlString.isEmpty, let url = URL(string: urlString), url.scheme != nil else { return }
                
                let sel = textView.selectedRange
                textView.undoManager?.beginUndoGrouping()
                if sel.length == 0 {
                    let linkText = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host ?? urlString
                    let insertion = NSMutableAttributedString(string: linkText)
                    insertion.addAttributes([.link: url], range: NSRange(location: 0, length: insertion.length))
                    textView.replace(range: NSRange(location: sel.location, length: 0), with: insertion)
                    textView.selectedRange = NSRange(location: sel.location + insertion.length, length: 0)
                } else {
                    textView.textStorage.beginEditing()
                    textView.textStorage.addAttribute(.link, value: url, range: sel)
                    textView.textStorage.endEditing()
                    textView.selectedRange = sel
                    // Serialize after attribute-only change
                    strongSelf.serializeAfterAttributeChange(in: textView)
                }
                textView.undoManager?.endUndoGrouping()
            })
            guard let topVC = currentTopVC() else {
                print("Warning: Unable to present alert - no view controller available")
                return
            }
            topVC.present(alert, animated: true)
        }


        // MARK: Helpers
        
        /// Serializes content after attribute-only changes that don't trigger textViewDidChange
        fileprivate func serializeAfterAttributeChange(in tv: UITextView) {
            guard let coord = MarkdownEditor.activeCoordinator,
                  coord === self else { return }
            parent.text = serializeContent(from: tv.attributedText)
            parent.selectedRange = tv.selectedRange
            NotificationCenter.default.post(
                name: .editorActiveStylesDidChange,
                object: nil,
                userInfo: ["styles": currentActiveStyles(in: tv)]
            )
        }

        fileprivate func setTypingMode(_ action: MarkdownAction, enabled: Bool, in tv: UITextView) {
            if enabled { typingModes.insert(action) } else { typingModes.remove(action) }
            applyTypingAttributes(in: tv)
        }

        private var fontCache: [String: UIFont] = [:] {
            didSet {
                // Limit cache size to prevent unbounded growth
                if fontCache.count > 50 {
                    // Remove half the cache using LRU would be ideal, but simple clear works
                    fontCache.removeAll()
                }
            }
        }
        
        fileprivate func applyTypingAttributes(in tv: UITextView) {
            var attrs = tv.typingAttributes
            if attrs[.font] == nil { attrs[.font] = EditorTheme.baseFont }
            if attrs[.foregroundColor] == nil { attrs[.foregroundColor] = EditorTheme.textColor }

            let baseFont = (attrs[.font] as? UIFont) ?? EditorTheme.baseFont
            let cacheKey = "\(baseFont.pointSize)_\(typingModes.hashValue)"
            
            if let cachedFont = fontCache[cacheKey] {
                attrs[.font] = cachedFont
            } else {
                var traits: UIFontDescriptor.SymbolicTraits = []
                if typingModes.contains(.bold) { traits.insert(.traitBold) }
                if typingModes.contains(.italic) { traits.insert(.traitItalic) }
                
                let newFont: UIFont
                if traits.isEmpty {
                    newFont = baseFont
                } else if let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) {
                    newFont = UIFont(descriptor: descriptor, size: baseFont.pointSize)
                    } else {
                        newFont = baseFont
                }
                fontCache[cacheKey] = newFont
                attrs[.font] = newFont
            }

            attrs[.underlineStyle] = typingModes.contains(.underline) ? NSUnderlineStyle.single.rawValue : nil
            attrs[.strikethroughStyle] = typingModes.contains(.strikethrough) ? NSUnderlineStyle.single.rawValue : nil

            attrs[.backgroundColor] = nil

            tv.typingAttributes = attrs
        }
        

        fileprivate func currentActiveStyles(in tv: UITextView) -> Set<MarkdownAction> {
            var set = typingModes
            let idx = max(0, min(tv.selectedRange.location, max(0, tv.attributedText.length - 1)))
            let attrs = tv.attributedText.length > 0 ? tv.attributedText.attributes(at: idx, effectiveRange: nil) : tv.typingAttributes

            if let f = (attrs[.font] as? UIFont) {
                let traits = f.fontDescriptor.symbolicTraits
                if traits.contains(.traitBold) { set.insert(.bold) } else { set.remove(.bold) }
                if traits.contains(.traitItalic) { set.insert(.italic) } else { set.remove(.italic) }
            }
            if (attrs[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue { set.insert(.underline) } else { set.remove(.underline) }
            if (attrs[.strikethroughStyle] as? Int) == NSUnderlineStyle.single.rawValue { set.insert(.strikethrough) } else { set.remove(.strikethrough) }

            // Use cached regex patterns for better performance
            let line = (tv as? EditorTextView)?.currentLineString() ?? ""
            let lineRange = NSRange(line.startIndex..., in: line)
            if WysiwygActionHandler.bulletRegex.firstMatch(in: line, range: lineRange) != nil {
                set.insert(.bulletList)
            } else {
                set.remove(.bulletList)
            }
            if WysiwygActionHandler.numberedRegex.firstMatch(in: line, range: lineRange) != nil {
                set.insert(.numberedList)
            } else {
                set.remove(.numberedList)
            }

            return set
        }
    }
}

// MARK: - Custom UITextView

final class EditorTextView: UITextView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        undoManager?.levelsOfUndo = 50
    }
 

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(editLink) || action == #selector(removeLink) { return currentLinkRange() != nil }
        return super.canPerformAction(action, withSender: sender)
    }

    @objc func editLink() {
        guard let r = currentLinkRange(),
              let url = attributedText.attribute(.link, at: r.location, effectiveRange: nil) as? URL else { return }
        let alert = UIAlertController(title: "Edit Link", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = url.absoluteString
            tf.keyboardType = .URL
            tf.autocorrectionType = .no
            tf.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let strongSelf = self else { return }
            var urlString = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Auto-add https:// if no protocol specified
            if !urlString.isEmpty && !urlString.contains("://") { urlString = "https://" + urlString }
            guard !urlString.isEmpty, let newURL = URL(string: urlString), newURL.scheme != nil else { return }
            strongSelf.textStorage.beginEditing()
            strongSelf.textStorage.addAttribute(.link, value: newURL, range: r)
            strongSelf.textStorage.endEditing()
            // Serialize after attribute-only change
            if let coord = MarkdownEditor.activeCoordinator {
                coord.serializeAfterAttributeChange(in: strongSelf)
            }
        })
        currentTopVC()?.present(alert, animated: true)
    }

    @objc func removeLink() {
        guard let r = currentLinkRange() else { return }
        textStorage.beginEditing()
        textStorage.removeAttribute(.link, range: r)
        textStorage.removeAttribute(.underlineStyle, range: r)
        textStorage.endEditing()
        // Serialize after attribute-only change
        if let coord = MarkdownEditor.activeCoordinator {
            coord.serializeAfterAttributeChange(in: self)
        }
    }

    private static var hasRegisteredMenuItems = false
    
    func registerLinkMenuItems() {
        if #available(iOS 16.0, *) {
            // System edit menu
        } else {
            // Only register once to avoid repeatedly creating menu items
            guard !Self.hasRegisteredMenuItems else { return }
            Self.hasRegisteredMenuItems = true
            UIMenuController.shared.menuItems = [
                UIMenuItem(title: "Edit Link", action: #selector(editLink)),
                UIMenuItem(title: "Remove Link", action: #selector(removeLink))
            ]
        }
    }

    private func currentLinkRange() -> NSRange? {
        guard attributedText.length > 0 else { return nil }
        let idx = max(0, min(selectedRange.location, attributedText.length - 1))
        var r = NSRange(location: 0, length: 0)
        if attributedText.attribute(.link, at: idx, effectiveRange: &r) != nil { return r }
        return nil
    }

    func currentLineRange() -> NSRange {
        let ns = attributedText.string as NSString
        let idx = min(selectedRange.location, ns.length)
        return ns.lineRange(for: NSRange(location: idx, length: 0))
    }
    func currentLineString() -> String {
        let ns = attributedText.string as NSString
        return ns.substring(with: currentLineRange())
    }
}

// MARK: - WYSIWYG Action Handler

class WysiwygActionHandler {
    // Lazy static initialization with error handling
    static let bulletRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"^(\s*)• "#)
        } catch {
            fatalError("Invalid regex pattern for bullet: \(error)")
        }
    }()
    
    static let numberedRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"^(\s*)(\d+)\. "#)
        } catch {
            fatalError("Invalid regex pattern for numbered list: \(error)")
        }
    }()
    
    static func handleReturn(in textView: EditorTextView) -> Bool {
        let lineR = textView.currentLineRange()
        let ns = textView.attributedText.string as NSString
        let line = ns.substring(with: lineR)

        // Check for indented bullets (with leading spaces)
        let fullRange = NSRange(line.startIndex..., in: line)
        if let match = WysiwygActionHandler.bulletRegex.firstMatch(in: line, range: fullRange) {
            let matchRange = match.range
            if let range = Range(matchRange, in: line) {
                let indent = String(line[range]).dropLast(2) // Remove "• "
                let afterBullet = String(line.dropFirst(indent.count + 2))
                if afterBullet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let m = NSMutableAttributedString(attributedString: textView.attributedText)
                    m.replaceCharacters(in: lineR, with: "")
                    textView.setAttributedStringUndoSafe(m)
                    textView.selectedRange = NSRange(location: lineR.location, length: 0)
                    return true
                } else {
                    textView.insertText("\n\(indent)• ")
                    return true
                }
            }
        }

        // Numbered list
        if let match = WysiwygActionHandler.numberedRegex.firstMatch(in: line, range: fullRange) {
            let nsLine = line as NSString
            let matchRange = match.range
            let prefix = nsLine.substring(with: matchRange)
            
            // Extract indent and number
            if let numMatch = prefix.range(of: #"\d+"#, options: .regularExpression) {
                let numStr = String(prefix[numMatch])
                let indent = String(prefix.prefix(while: { $0 == " " }))
                let after = String(line.dropFirst(prefix.count))
                
                if after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let m = NSMutableAttributedString(attributedString: textView.attributedText)
                    m.replaceCharacters(in: lineR, with: "")
                    textView.setAttributedStringUndoSafe(m)
                    textView.selectedRange = NSRange(location: lineR.location, length: 0)
                    return true
                } else if let n = Int(numStr) {
                    textView.insertText("\n\(indent)\(n + 1). ")
                    return true
                }
            }
        }

        return false
    }
    
    static func apply(_ action: MarkdownAction, to textView: UITextView) {
        guard let coord = MarkdownEditor.activeCoordinator else { return }
        let range = textView.selectedRange
        let hasSelection = range.length > 0

        // List actions
        if action == .bulletList || action == .numberedList {
            applyListAction(action, tv: textView)
            return
        }

        // Indent/outdent
        if action == .indent || action == .outdent {
            applyIndentAction(action, tv: textView)
            return
        }

        // Headers
        if action == .header1 || action == .header2 || action == .header3 {
            applyHeader(action, tv: textView)
            return
        }

        // Style toggles
        if hasSelection {
            let m = NSMutableAttributedString(attributedString: textView.attributedText)
            switch action {
            case .bold: toggleFontTrait(.traitBold, in: m, range: range)
            case .italic: toggleFontTrait(.traitItalic, in: m, range: range)
            case .underline: toggleSimple(.underlineStyle, value: NSUnderlineStyle.single.rawValue, in: m, range: range)
            case .strikethrough: toggleSimple(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, in: m, range: range)
            case .removeFormat: removeAllFormatting(in: m, range: range)
            case .alignLeft: setTextAlignment(.left, in: m, range: range)
            case .alignCenter: setTextAlignment(.center, in: m, range: range)
            case .alignRight: setTextAlignment(.right, in: m, range: range)
            default: break
            }
            textView.setAttributedStringUndoSafe(m)
            textView.selectedRange = range
            coord.applyTypingAttributes(in: textView)
        } else {
            // Typing mode
            switch action {
            case .bold, .italic, .underline, .strikethrough:
                let shouldEnable = !coord.typingModes.contains(action)
                coord.setTypingMode(action, enabled: shouldEnable, in: textView)
            case .alignLeft: setCaretAlignment(.left, in: textView)
            case .alignCenter: setCaretAlignment(.center, in: textView)
            case .alignRight: setCaretAlignment(.right, in: textView)
            default: break
            }
        }
    }

    // MARK: Headers

    private static func applyHeader(_ action: MarkdownAction, tv: UITextView) {
        let sizes: (CGFloat, UIFont.Weight) = {
            switch action {
            case .header1: return (28, .bold)
            case .header2: return (22, .semibold)
            case .header3: return (18, .semibold)
            default: return (EditorTheme.baseFont.pointSize, .regular)
            }
        }()
        
        let lineR = (tv as? EditorTextView)?.currentLineRange() ?? tv.selectedRange
        let m = NSMutableAttributedString(attributedString: tv.attributedText)
        
        // Handle empty text or invalid range
        guard m.length > 0, lineR.location < m.length else {
            // For empty text, just set typing attributes for the header
            var attrs = tv.typingAttributes
            attrs[.font] = UIFont.systemFont(ofSize: sizes.0, weight: sizes.1)
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 6
            style.paragraphSpacingBefore = 8
            style.paragraphSpacing = 8
            attrs[.paragraphStyle] = style
            tv.typingAttributes = attrs
            return
        }
        
        let existingAttrs = m.attributes(at: lineR.location, effectiveRange: nil)
        var merged = existingAttrs
        merged[.font] = UIFont.systemFont(ofSize: sizes.0, weight: sizes.1)
        
        // Preserve existing paragraph style properties and just update spacing
        let existingStyle = existingAttrs[.paragraphStyle] as? NSParagraphStyle
        let style = (existingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.lineSpacing = 6
        style.paragraphSpacingBefore = 8
        style.paragraphSpacing = 8
        merged[.paragraphStyle] = style
        m.addAttributes(merged, range: lineR)
        
        tv.setAttributedStringUndoSafe(m)
        tv.selectedRange = NSRange(location: lineR.location, length: 0)
    }

    // MARK: Lists with proper indentation

    private static func applyListAction(_ action: MarkdownAction, tv: UITextView) {
        let range = tv.selectedRange
        let m = NSMutableAttributedString(attributedString: tv.attributedText)
        let ns = m.string as NSString
        let lineRange = ns.lineRange(for: range)
        let line = ns.substring(with: lineRange)
        
        // Get current indent level
        let currentIndent = line.prefix(while: { $0 == " " })
        
        // Track cursor adjustment
        var newCursorLocation = range.location
        
        switch action {
        case .bulletList:
            if line.range(of: #"^\s*• "#, options: .regularExpression) != nil {
                // Remove bullet
                if let bulletRange = line.range(of: #"^\s*• "#, options: .regularExpression) {
                    let nsRange = NSRange(bulletRange, in: line)
                    m.replaceCharacters(in: NSRange(location: lineRange.location + nsRange.location, 
                                                   length: nsRange.length), with: "")
                    // Adjust cursor - move back by the removed prefix length
                    newCursorLocation = max(lineRange.location, range.location - nsRange.length)
                }
            } else {
                // Add bullet with current indent
                let prefix = "\(currentIndent)• "
                m.insert(NSAttributedString(string: prefix), at: lineRange.location)
                // Position cursor after the bullet point
                newCursorLocation = lineRange.location + prefix.count
            }
            
        case .numberedList:
            if line.range(of: #"^\s*\d+\. "#, options: .regularExpression) != nil {
                // Remove number
                if let numRange = line.range(of: #"^\s*\d+\. "#, options: .regularExpression) {
                    let nsRange = NSRange(numRange, in: line)
                    m.replaceCharacters(in: NSRange(location: lineRange.location + nsRange.location,
                                                   length: nsRange.length), with: "")
                    // Adjust cursor - move back by the removed prefix length
                    newCursorLocation = max(lineRange.location, range.location - nsRange.length)
                }
            } else {
                // Add number with current indent
                let prefix = "\(currentIndent)1. "
                m.insert(NSAttributedString(string: prefix), at: lineRange.location)
                // Position cursor after the number
                newCursorLocation = lineRange.location + prefix.count
            }
            
        default: break
        }
        
        tv.setAttributedStringUndoSafe(m)
        tv.selectedRange = NSRange(location: newCursorLocation, length: 0)
    }

    // MARK: Indent/Outdent with sub-bullets

    private static func applyIndentAction(_ action: MarkdownAction, tv: UITextView) {
        let range = tv.selectedRange
        let m = NSMutableAttributedString(attributedString: tv.attributedText)
        let ns = m.string as NSString
        let lineRange = ns.lineRange(for: range)
        let line = ns.substring(with: lineRange)
        
        let indentUnit = "    " // 4 spaces for sub-level
        
        if action == .indent {
            // Add indent
            if line.range(of: #"^\s*[•\d]"#, options: .regularExpression) != nil {
                // It's a list item, add indent at the start
                m.insert(NSAttributedString(string: indentUnit), at: lineRange.location)
                tv.setAttributedStringUndoSafe(m)
                tv.selectedRange = NSRange(location: range.location + indentUnit.count, length: 0)
            }
        } else if action == .outdent {
            // Remove indent
            let leadingSpaces = line.prefix(while: { $0 == " " })
            if leadingSpaces.count >= indentUnit.count {
                m.replaceCharacters(in: NSRange(location: lineRange.location, length: indentUnit.count), with: "")
                tv.setAttributedStringUndoSafe(m)
                tv.selectedRange = NSRange(location: max(0, range.location - indentUnit.count), length: 0)
            }
        }
    }

    // MARK: Alignment

    private static func setTextAlignment(_ alignment: NSTextAlignment, in m: NSMutableAttributedString, range: NSRange) {
        let ns = m.string as NSString
        let paraRange = ns.paragraphRange(for: range)
        
        // Get existing paragraph style or create new one
        let existingStyle = m.attribute(.paragraphStyle, at: paraRange.location, effectiveRange: nil) as? NSParagraphStyle
        let style = (existingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.alignment = alignment
        m.addAttribute(.paragraphStyle, value: style, range: paraRange)

        if let tv = MarkdownEditor.activeCoordinator?.textView {
            var attrs = tv.typingAttributes
            let existingTypingStyle = attrs[.paragraphStyle] as? NSParagraphStyle
            let typingStyle = (existingTypingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            typingStyle.alignment = alignment
            attrs[.paragraphStyle] = typingStyle
            tv.typingAttributes = attrs
        }
    }
    
    private static func setCaretAlignment(_ alignment: NSTextAlignment, in tv: UITextView) {
        var attrs = tv.typingAttributes
        let existingStyle = attrs[.paragraphStyle] as? NSParagraphStyle
        let style = (existingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.alignment = alignment
        attrs[.paragraphStyle] = style
        tv.typingAttributes = attrs
    }

    // MARK: Font traits

    private static func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits, 
                                       in m: NSMutableAttributedString, 
                                       range: NSRange) {
        m.enumerateAttribute(.font, in: range, options: []) { value, r, _ in
            let base = (value as? UIFont) ?? EditorTheme.baseFont
            var traits = base.fontDescriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
            
            let newFont: UIFont
            if let descriptor = base.fontDescriptor.withSymbolicTraits(traits) {
                newFont = UIFont(descriptor: descriptor, size: base.pointSize)
            } else {
                newFont = base
            }
            m.addAttribute(.font, value: newFont, range: r)
        }
    }

    private static func toggleSimple(_ key: NSAttributedString.Key, value: Any, in m: NSMutableAttributedString, range: NSRange) {
        m.enumerateAttribute(key, in: range, options: []) { existing, r, _ in
            if existing != nil { m.removeAttribute(key, range: r) }
            else { m.addAttribute(key, value: value, range: r) }
        }
    }


    private static func removeAllFormatting(in m: NSMutableAttributedString, range: NSRange) {
        m.setAttributes([
            .font: EditorTheme.baseFont,
            .foregroundColor: EditorTheme.textColor
        ], range: range)
    }

}

// MARK: - SwiftUI Toolbar (Cleaner Layout)

struct MarkdownToolbarView: View {
    var coordinator: MarkdownEditor.Coordinator?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Basic formatting
                HStack(spacing: 6) {
                    toolbarButton("B", .bold, hint: "Bold")
                    toolbarButton("I", .italic, hint: "Italic")
                    toolbarButton("U", .underline, hint: "Underline")
                    toolbarButton("S", .strikethrough, hint: "Strikethrough")
                }
                
                Divider().frame(height: 24)
                
                // Headers menu
                Menu {
                    Button("Header 1") { coordinator?.handleMarkdownAction(.header1) }
                    Button("Header 2") { coordinator?.handleMarkdownAction(.header2) }
                    Button("Header 3") { coordinator?.handleMarkdownAction(.header3) }
                } label: {
                    Text("H")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray5))
                        .cornerRadius(6)
                }
                
                Divider().frame(height: 24)
                
                // Lists
                HStack(spacing: 6) {
                    toolbarButton("•", .bulletList, hint: "Bullet List")
                    toolbarButton("1.", .numberedList, hint: "Numbered List")
                    toolbarButton("→", .indent, hint: "Indent")
                    toolbarButton("←", .outdent, hint: "Outdent")
                }
                
                Divider().frame(height: 24)
                
                // Alignment menu
                Menu {
                    Button(action: { coordinator?.handleMarkdownAction(.alignLeft) }) {
                        Label("Align Left", systemImage: "text.alignleft")
                    }
                    Button(action: { coordinator?.handleMarkdownAction(.alignCenter) }) {
                        Label("Align Center", systemImage: "text.aligncenter")
                    }
                    Button(action: { coordinator?.handleMarkdownAction(.alignRight) }) {
                        Label("Align Right", systemImage: "text.alignright")
                    }
                } label: {
                    Image(systemName: "text.alignleft")
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray5))
                        .cornerRadius(6)
                }
                
                Divider().frame(height: 24)
                
                // Insert menu
                Menu {
                    Button(action: { coordinator?.handleMarkdownAction(.link) }) {
                        Label("Link", systemImage: "link")
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray5))
                        .cornerRadius(6)
                }
                
                Divider().frame(height: 24)
                
                // Tools
                HStack(spacing: 6) {
                    toolbarButton("↶", .undo, hint: "Undo")
                    toolbarButton("↷", .redo, hint: "Redo")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .frame(height: 44)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatting toolbar")
        .accessibilityHint("Use to format text with bold, italic, lists, and more")
    }
    
    private func toolbarButton(_ title: String, _ action: MarkdownAction, hint: String) -> some View {
        ToolbarButton(title: title, action: action, coordinator: coordinator, accessibilityHint: hint)
    }
}

struct ToolbarButton: View {
    let title: String
    let action: MarkdownAction
    var coordinator: MarkdownEditor.Coordinator?
    @State private var isSelected = false
    var accessibilityHint: String?
    
    var body: some View {
        Button {
            coordinator?.handleMarkdownAction(action)  
        } label: {
            Text(title)
        .font(.system(size: 16, weight: .medium))
                .frame(width: 32, height: 32)
                .foregroundColor(isSelected ? .white : .primary)
                .background(isSelected ? Color.blue : Color(.systemGray5))
        .cornerRadius(6)
        }
        .accessibilityLabel(accessibilityHint ?? title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(.isButton)
        .dynamicTypeSize(.large ... .xxxLarge)
        .onReceive(NotificationCenter.default.publisher(for: .editorActiveStylesDidChange)) { note in
            if let set = note.userInfo?["styles"] as? Set<MarkdownAction> { 
                isSelected = set.contains(action) 
            }
        }
    }
}