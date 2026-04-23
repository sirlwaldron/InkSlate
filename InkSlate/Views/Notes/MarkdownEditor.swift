//
//  MarkdownEditor.swift
//  InkSlate
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
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

    /// - Parameter recordUndo: `false` for SwiftUI/binding sync (prevents a huge “replace all” on the shared undo stack, like when Word reloads a document from disk). `true` for in-editor edits.
    func setAttributedString(_ m: NSAttributedString, recordUndo: Bool) {
        if !recordUndo, let u = undoManager {
            u.disableUndoRegistration()
        }
        defer {
            if !recordUndo, let u = undoManager { u.enableUndoRegistration() }
        }
        textStorage.beginEditing()
        textStorage.setAttributedString(m)
        textStorage.endEditing()
    }
    func setAttributedStringForBindingSync(_ m: NSAttributedString) { setAttributedString(m, recordUndo: false) }
    func setAttributedStringUndoSafe(_ m: NSAttributedString) { setAttributedString(m, recordUndo: true) }
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

        // Load text (no undo point for initial load, same as opening a file in Word)
        let attributed = context.coordinator.deserializeContent(text)
        textView.setAttributedStringForBindingSync(attributed)
        
        context.coordinator.textView = textView
        MarkdownEditor.activeCoordinator = context.coordinator

        context.coordinator.applyTypingAttributes(in: textView)
        NotificationCenter.default.post(name: .editorActiveStylesDidChange, object: nil,
                                        userInfo: ["styles": context.coordinator.currentActiveStyles(in: textView)])

        DispatchQueue.main.async { textView.becomeFirstResponder() }
        
        return textView
    }
    
    func updateUIView(_ uiView: EditorTextView, context: Context) {
        // Keep the binding reference current so `Coordinator.parent` writes always target the right note.
        context.coordinator.parent = self
        context.coordinator.textView = uiView
        guard !uiView.isFirstResponder else { return }
        let latest = context.coordinator.serializeContent(from: uiView.attributedText)
        guard latest != text else { return }

        DispatchQueue.main.async {
            let range = uiView.selectedRange
            let attributed = context.coordinator.deserializeContent(text)
            uiView.setAttributedStringForBindingSync(attributed)
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
        
        /// One toolbar or custom key action = one undo step; avoids nested group imbalance if the system already has a group open.
        private static func withUndoGroup(in tv: UITextView, _ work: () -> Void) {
            guard let um = tv.undoManager else {
                work()
                return
            }
            let startLevel = um.groupingLevel
            um.beginUndoGrouping()
            work()
            if um.groupingLevel > startLevel { um.endUndoGrouping() }
        }

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
            
            // Only clear if this instance is still the global active editor. Otherwise
            // opening another note dismisses the previous one and deinit here would
            // nil out the new editor and break the formatting toolbar and WysiwygActionHandler.
            if MarkdownEditor.activeCoordinator === self {
                MarkdownEditor.activeCoordinator = nil
            }
            
            // Post final update to clear UI state
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .editorActiveStylesDidChange,
                    object: nil,
                    userInfo: ["styles": Set<MarkdownAction>()]
                )
            }
        }

        /// Pushes the live `textView` into the SwiftUI `text` binding and cancels
        /// debounced updates. Call before save / dismiss / preview so Core Data
        /// does not lag up to 0.3s behind the UITextView.
        func flushPendingEditsToParent() {
            saveWorkItem?.cancel()
            styleCalculationWorkItem?.cancel()
            guard let textView = textView else { return }
            let serialized = serializeContent(from: textView.attributedText)
            parent.text = serialized
            parent.selectedRange = textView.selectedRange
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
                if let etv = tv as? EditorTextView {
                    var handled = false
                    Self.withUndoGroup(in: tv) { handled = WysiwygActionHandler.handleReturn(in: etv) }
                    if handled {
                        serializeAfterAttributeChange(in: tv)
                        return false
                    }
                }
            }
            if string == "\t" {
                if let etv = tv as? EditorTextView {
                    Self.withUndoGroup(in: tv) { WysiwygActionHandler.apply(.indent, to: etv) }
                    serializeAfterAttributeChange(in: tv)
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
                guard let um = tv.undoManager, um.canUndo else { return }
                isProgrammaticChange = true
                defer { isProgrammaticChange = false }
                um.undo()
                typingModes.removeAll()
                applyTypingAttributes(in: tv)
                parent.text = serializeContent(from: tv.attributedText)
                parent.selectedRange = tv.selectedRange
                NotificationCenter.default.post(name: .editorActiveStylesDidChange,
                                                object: nil,
                                                userInfo: ["styles": currentActiveStyles(in: tv)])
                return
            case .redo:
                guard let um = tv.undoManager, um.canRedo else { return }
                isProgrammaticChange = true
                defer { isProgrammaticChange = false }
                um.redo()
                typingModes.removeAll()
                applyTypingAttributes(in: tv)
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
            Self.withUndoGroup(in: tv) { WysiwygActionHandler.apply(action, to: tv) }

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
                Self.withUndoGroup(in: textView) {
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
                    strongSelf.serializeAfterAttributeChange(in: textView)
                }
                }
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
            EditorStyleState.activeStyles(
                typingModes: typingModes,
                attributedText: tv.attributedText,
                selectedRange: tv.selectedRange,
                typingAttributes: tv.typingAttributes,
                currentLine: (tv as? EditorTextView)?.currentLineString() ?? ""
            )
        }
        
        fileprivate func setTypingModesFromAttributes(_ attrs: [NSAttributedString.Key: Any], in tv: UITextView) {
            var newModes = Set<MarkdownAction>()
            if let f = (attrs[.font] as? UIFont) {
                let traits = f.fontDescriptor.symbolicTraits
                if traits.contains(.traitBold) { newModes.insert(.bold) }
                if traits.contains(.traitItalic) { newModes.insert(.italic) }
            }
            if (attrs[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue { newModes.insert(.underline) }
            if (attrs[.strikethroughStyle] as? Int) == NSUnderlineStyle.single.rawValue { newModes.insert(.strikethrough) }
            typingModes = newModes
            applyTypingAttributes(in: tv)
        }
    }
}

// MARK: - Active style calculation (shared + testable)
enum EditorStyleState {
    static func activeStyles(
        typingModes: Set<MarkdownAction>,
        attributedText: NSAttributedString,
        selectedRange: NSRange,
        typingAttributes: [NSAttributedString.Key: Any],
        currentLine: String
    ) -> Set<MarkdownAction> {
        var set = typingModes
        
        let attrs: [NSAttributedString.Key: Any] = {
            if attributedText.length == 0 {
                return typingAttributes
            }
            
            // If there's no selection and the caret is at the end, reflect the next-typed state.
            if selectedRange.length == 0, selectedRange.location >= attributedText.length {
                return typingAttributes
            }
            
            let idx = max(0, min(selectedRange.location, attributedText.length - 1))
            return attributedText.attributes(at: idx, effectiveRange: nil)
        }()
        
        if let f = (attrs[.font] as? UIFont) {
            let traits = f.fontDescriptor.symbolicTraits
            if traits.contains(.traitBold) { set.insert(.bold) } else { set.remove(.bold) }
            if traits.contains(.traitItalic) { set.insert(.italic) } else { set.remove(.italic) }
        }
        if (attrs[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue { set.insert(.underline) } else { set.remove(.underline) }
        if (attrs[.strikethroughStyle] as? Int) == NSUnderlineStyle.single.rawValue { set.insert(.strikethrough) } else { set.remove(.strikethrough) }
        
        // List state from current line (Word-style: •/◦/▪, 1., a), 1) …)
        let lineRange = NSRange(currentLine.startIndex..., in: currentLine)
        if WordListLineKind.detectBullet(in: currentLine, lineRange) != nil {
            set.insert(.bulletList)
        } else {
            set.remove(.bulletList)
        }
        if WordListLineKind.detectNumbered(in: currentLine, lineRange) != nil {
            set.insert(.numberedList)
        } else {
            set.remove(.numberedList)
        }
        
        return set
    }
}

// MARK: - Custom UITextView

final class EditorTextView: UITextView {
    /// Document-only undo, like Word—avoids sharing the window’s undo stack with other controls, which can corrupt undo/redo.
    private let documentUndoManager: UndoManager = {
        let m = UndoManager()
        m.levelsOfUndo = 50
        m.groupsByEvent = true
        return m
    }()
    override var undoManager: UndoManager? { documentUndoManager }
    
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

// MARK: - Word-style multi-level list (•/◦/▪, 1., a), 1) …)

private enum WordListLineKind {
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
        var m = 0
        for i in 0..<min(lineIndex, lines.count) {
            var line = lines[i]
            let sp = String(line.prefix(while: { $0 == " " }))
            if !sp.isEmpty { continue }
            line = String(line.dropFirst(sp.count))
            if let r = line.range(of: "^\\d+\\. ", options: .regularExpression) {
                if let n = Int(String(line[r].dropLast(2))) { m = max(m, n) }
            }
        }
        return m + 1
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
            let nsp = String(sp.dropLast(4))
            let n = nextTopLevelDecimal(before: myIndex, lines: allLines)
            if nsp.isEmpty { return "\(n). " + String(c[r.upperBound...]) }
            return nsp + "\(n). " + String(c[r.upperBound...]) }
        if !sp.isEmpty, let r = c.range(of: "^\\d+\\) ", options: .regularExpression) {
            let nsp = String(sp.dropLast(4))
            if nsp.isEmpty {
                let n = nextTopLevelDecimal(before: myIndex, lines: allLines)
                return "\(n). " + String(c[r.upperBound...]) }
            return nsp + "a) " + String(c[r.upperBound...]) }
        if !sp.isEmpty, c.hasPrefix("◦ ") { return (String(sp.dropLast(4))) + "• " + String(c.dropFirst(2)) }
        if !sp.isEmpty, c.hasPrefix("▪ ") { return (String(sp.dropLast(4))) + "◦ " + String(c.dropFirst(2)) }
        return nil
    }
}

// MARK: - WYSIWYG Action Handler

class WysiwygActionHandler {
    // Lazy static initialization with error handling
    static let bulletRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"^(\s*)[•◦▪] "#)
        } catch {
            fatalError("Invalid regex pattern for bullet: \(error)")
        }
    }()
    
    static let numberedRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: #"^(\s*)((\d+\.\s+)|([a-z]\)\s+)|(\d+\)\s+))"#
            )
        } catch {
            fatalError("Invalid regex pattern for numbered list: \(error)")
        }
    }()
    
    static func handleReturn(in textView: EditorTextView) -> Bool {
        let lineR = textView.currentLineRange()
        let ns = textView.attributedText.string as NSString
        let allText = String(ns)
        let line = ns.substring(with: lineR)
        let R = NSRange(line.startIndex..., in: line)
        let lead = WordListLineKind.leadingPrefix(line)
        let L = WordListLineKind.listLevel(leading: lead)
        let cAfter = String(line.dropFirst(lead.count))
        let lineIndex = (allText as NSString).substring(to: min(lineR.location, (allText as NSString).length))
            .filter { $0 == "\n" }.count
        let docLines = (allText as NSString).components(separatedBy: "\n")
        func clearEmptyListLine() {
            let m = NSMutableAttributedString(attributedString: textView.attributedText)
            m.replaceCharacters(in: lineR, with: "")
            textView.setAttributedStringUndoSafe(m)
            textView.selectedRange = NSRange(location: lineR.location, length: 0)
        }
        if (line as NSString).range(of: "^\\s*[•◦▪] ", options: .regularExpression, range: R).location != NSNotFound,
           let b = cAfter.range(of: "^[•◦▪] ", options: .regularExpression) {
            let afterB = String(cAfter[b.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if afterB.isEmpty { clearEmptyListLine(); return true }
            let mark = WordListLineKind.bulletMark(forLevel: L)
            textView.insertText("\n\(lead)\(mark)"); return true
        }
        if (line as NSString).range(of: "^\\s*\\d+\\) ", options: .regularExpression, range: R).location != NSNotFound,
           let r = cAfter.range(of: "^\\d+\\) ", options: .regularExpression),
           let d = Int(String(cAfter[r].dropLast(2))) {
            let after = String(cAfter[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if after.isEmpty { clearEmptyListLine(); return true }
            textView.insertText("\n\(lead)\(d + 1)) ")
            return true
        }
        if (line as NSString).range(of: "^\\s*[a-z]\\) ", options: .regularExpression, range: R).location != NSNotFound,
           let r = cAfter.range(of: "^[a-z]\\) ", options: .regularExpression) {
            let ch = cAfter[r.lowerBound]
            let after = String(cAfter[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if after.isEmpty { clearEmptyListLine(); return true }
            if L == 0 {
                let n = WordListLineKind.nextTopLevelDecimal(before: lineIndex, lines: docLines)
                textView.insertText("\n\(n). ")
                return true
            }
            let nch: Character
            if ch < "z" {
                nch = Character(UnicodeScalar(UInt32(ch.asciiValue! + 1))!)
            } else {
                nch = "a"
            }
            textView.insertText("\n\(lead)\(String(nch))" + ") ")
            return true
        }
        if (line as NSString).range(of: "^\\s*\\d+\\. ", options: .regularExpression, range: R).location != NSNotFound,
           let r0 = cAfter.range(of: "^\\d+\\. ", options: .regularExpression) {
            let dStr = String(cAfter[r0].dropLast(2))
            let after = String(cAfter[r0.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if L == 0, let n = Int(dStr) {
                if after.isEmpty { clearEmptyListLine(); return true }
                textView.insertText("\n\(lead)\(n + 1). ")
                return true
            }
            if L > 0, after.isEmpty { clearEmptyListLine(); return true }
            if L > 0, let n0 = Int(dStr) {
                let u = (n0 - 1) % 26
                let nextCode = 97 + (u + 1) % 26
                let nextCh = Character(UnicodeScalar(nextCode)!)
                textView.insertText("\n\(lead)\(nextCh)) ")
                return true
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
            case .bold: toggleFontTraitWordStyle(.traitBold, in: m, range: range)
            case .italic: toggleFontTraitWordStyle(.traitItalic, in: m, range: range)
            case .underline: toggleKeyWordStyle(.underlineStyle, value: NSUnderlineStyle.single.rawValue, in: m, range: range, isSet: { ($0 as? Int) == NSUnderlineStyle.single.rawValue })
            case .strikethrough: toggleKeyWordStyle(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, in: m, range: range, isSet: { ($0 as? Int) == NSUnderlineStyle.single.rawValue })
            case .removeFormat: removeAllFormatting(in: m, range: range)
            case .alignLeft, .alignCenter, .alignRight:
                let a: NSTextAlignment = (action == .alignLeft) ? .left : (action == .alignCenter ? .center : .right)
                setTextAlignmentForAllLinesCovered(m: m, fullSelectedRange: range, alignment: a)
            default: break
            }
            textView.setAttributedStringUndoSafe(m)
            textView.selectedRange = range
            
            // Ensure "next typed" attributes and toolbar state reflect the caret context
            // rather than stale typingModes after selection-only formatting.
            let caretLocation = range.location + range.length
            let idx = max(0, min(max(0, caretLocation - 1), max(0, m.length - 1)))
            let caretAttrs = m.length > 0 ? m.attributes(at: idx, effectiveRange: nil) : textView.typingAttributes
            coord.setTypingModesFromAttributes(caretAttrs, in: textView)
        } else {
            // Typing mode
            switch action {
            case .bold, .italic, .underline, .strikethrough:
                let shouldEnable = !coord.typingModes.contains(action)
                coord.setTypingMode(action, enabled: shouldEnable, in: textView)
            case .alignLeft: applyAlignmentToCurrentLine(.left, tv: textView)
            case .alignCenter: applyAlignmentToCurrentLine(.center, tv: textView)
            case .alignRight: applyAlignmentToCurrentLine(.right, tv: textView)
            default: break
            }
        }
    }
    
    /// Word-style: alignment applies to the current paragraph, not just future typing.
    private static func applyAlignmentToCurrentLine(_ alignment: NSTextAlignment, tv: UITextView) {
        let lineR = (tv as? EditorTextView)?.currentLineRange() ?? tv.selectedRange
        let m = NSMutableAttributedString(attributedString: tv.attributedText)
        if m.length > 0, lineR.location < m.length {
            setTextAlignment(alignment, in: m, range: lineR)
        }
        setCaretAlignment(alignment, in: tv)
        tv.setAttributedStringUndoSafe(m)
    }
    
    // MARK: - Multiline selection (Word: apply to every selected line)
    
    /// `NSString` line ranges from the first line the selection touches through the last (inclusive).
    private static func lineRangesCoveredBySelection(_ full: NSString, _ sel: NSRange) -> [NSRange] {
        guard full.length > 0 else { return [] }
        if sel.length == 0 {
            let pos = min(max(0, sel.location), full.length - 1)
            return [full.lineRange(for: NSRange(location: pos, length: 0))]
        }
        let endChar = min(NSMaxRange(sel) - 1, full.length - 1)
        let a = min(max(0, sel.location), endChar)
        let firstL = full.lineRange(for: NSRange(location: a, length: 0))
        let lastL = full.lineRange(for: NSRange(location: endChar, length: 0))
        let endBound = NSMaxRange(lastL)
        var r: [NSRange] = []
        var c = firstL.location
        var safety = 0
        while c < endBound, safety < 20_000 {
            safety += 1
            let lr = full.lineRange(for: NSRange(location: c, length: 0))
            r.append(lr)
            let n = NSMaxRange(lr)
            if n <= c { break }
            c = n
        }
        return r
    }
    
    private static func blockRangeForLineRanges(_ lrs: [NSRange]) -> NSRange? {
        guard let f = lrs.first, let l = lrs.last else { return nil }
        return NSRange(location: f.location, length: NSMaxRange(l) - f.location)
    }
    
    private static func stringLinesFromBlock(_ full: NSString, _ lrs: [NSRange]) -> [String] {
        lrs.map { r in
            var s = full.substring(with: r) as String
            if s.hasSuffix("\n") { s = String(s.dropLast()) }
            return s
        }
    }
    
    private static func transformListLine(_ line: String, action: MarkdownAction) -> String {
        let n = line as NSString
        let r = line.startIndex..<line.endIndex
        let rNS = NSRange(r, in: line)
        let hasNumber = n.range(of: "^\\s*\\d+\\. ", options: .regularExpression, range: rNS).location != NSNotFound
            || n.range(of: "^\\s*\\d+\\) ", options: .regularExpression, range: rNS).location != NSNotFound
            || n.range(of: "^\\s*[a-z]\\) ", options: .regularExpression, range: rNS).location != NSNotFound
        let hasBullet = n.range(of: "^\\s*[•◦▪] ", options: .regularExpression, range: rNS).location != NSNotFound
        switch action {
        case .bulletList:
            if hasNumber { return convertNumberedLineToBulletLine(line) }
            if hasBullet { return removeListMarkerForToggle(line, bullet: true) }
            return addListMarkerToPlainLine(line, numbered: false)
        case .numberedList:
            if hasNumber { return removeListMarkerForToggle(line, bullet: false) }
            if hasBullet { return convertBulletLineToNumberedLine(line) }
            return addListMarkerToPlainLine(line, numbered: true)
        default: return line
        }
    }
    
    private static func indentOrOutdentLineString(
        _ line: String, outdent: Bool, allDocumentLines: [String], lineIndex: Int
    ) -> String {
        if outdent {
            let lead = line.prefix(while: { $0 == " " })
            let remove = min(4, lead.count)
            if remove == 0 { return line }
            let t = String(line.dropFirst(remove))
            return WordListLineKind.relevelLineAfterOutdent(t, allLines: allDocumentLines, myIndex: lineIndex) ?? t
        }
        let t = String(repeating: " ", count: 4) + line
        return WordListLineKind.relevelLineAfterIndent(t) ?? t
    }
    
    private static func setTextAlignmentForAllLinesCovered(
        m: NSMutableAttributedString, fullSelectedRange: NSRange, alignment: NSTextAlignment
    ) {
        let ns = m.string as NSString
        let lrs = lineRangesCoveredBySelection(ns, fullSelectedRange)
        var seen = Set<String>()
        for lr in lrs {
            let loc = min(lr.location, max(0, m.length - 1))
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            let key = "\(pr.location)|\(pr.length)"
            if seen.insert(key).inserted {
                setTextAlignment(alignment, in: m, range: pr)
            }
        }
    }

    // MARK: Headers (Word-style: same heading again reverts the line to body text)
    
    private static func headerSpec(_ action: MarkdownAction) -> (size: CGFloat, weight: UIFont.Weight) {
        switch action {
        case .header1: return (28, .bold)
        case .header2: return (22, .semibold)
        case .header3: return (18, .semibold)
        default: return (EditorTheme.baseFont.pointSize, .regular)
        }
    }
    
    private static let headerLineSpacing: CGFloat = 6
    private static let headerParagraphBefore: CGFloat = 8
    private static let headerParagraphAfter: CGFloat = 8
    
    /// True when this line is already that heading: font size + heading-style paragraph (avoids 18pt body / H3 false positives).
    private static func isSameHeadingLine(
        m: NSAttributedString,
        lineR: NSRange,
        as action: MarkdownAction
    ) -> Bool {
        guard lineR.length > 0, lineR.location + lineR.length <= m.length else { return false }
        let s = headerSpec(action)
        guard let font = m.attribute(.font, at: lineR.location, effectiveRange: nil) as? UIFont,
              abs(font.pointSize - s.size) < 0.85
        else { return false }
        guard let p = m.attribute(.paragraphStyle, at: lineR.location, effectiveRange: nil) as? NSParagraphStyle,
              p.paragraphSpacingBefore >= 2, p.lineSpacing > 0
        else { return false }
        return true
    }
    
    private static func bodyParagraphStyle(preservingAlignment align: NSTextAlignment = .natural) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 0
        style.paragraphSpacingBefore = 0
        style.paragraphSpacing = 0
        style.alignment = align
        return style
    }

    // MARK: Headers (implementation)

    private static func applyHeader(_ action: MarkdownAction, tv: UITextView) {
        let spec = headerSpec(action)
        let sel = tv.selectedRange
        let m = NSMutableAttributedString(attributedString: tv.attributedText)
        let full = m.string as NSString
        let lrs = lineRangesCoveredBySelection(full, sel)
        guard !lrs.isEmpty else { return }
        var lineR = lrs[0]
        
        // Many lines: revert to body only if every non-empty line is already this heading; otherwise make each line that heading.
        if lrs.count > 1, m.length > 0 {
            let checkLines = lrs.filter { $0.length > 0 && $0.location < m.length }
            let turnToBody = !checkLines.isEmpty && checkLines.allSatisfy { isSameHeadingLine(m: m, lineR: $0, as: action) }
            for lr in lrs {
                if lr.length == 0, lr.location >= m.length { continue }
                if lr.length == 0 { continue }
                if turnToBody {
                    var align: NSTextAlignment = .natural
                    if m.length > 0, lr.location < m.length,
                       let p = m.attribute(.paragraphStyle, at: lr.location, effectiveRange: nil) as? NSParagraphStyle {
                        align = p.alignment
                    }
                    m.addAttributes([
                        .font: EditorTheme.baseFont,
                        .foregroundColor: EditorTheme.textColor,
                        .paragraphStyle: bodyParagraphStyle(preservingAlignment: align)
                    ], range: lr)
                } else {
                    let at = min(lr.location, max(0, m.length - 1))
                    let existingAttrs = m.attributes(at: at, effectiveRange: nil)
                    var merged = existingAttrs
                    merged[.font] = UIFont.systemFont(ofSize: spec.size, weight: spec.weight)
                    merged[.foregroundColor] = (existingAttrs[.foregroundColor] as? UIColor) ?? EditorTheme.textColor
                    let existingStyle = existingAttrs[.paragraphStyle] as? NSParagraphStyle
                    let style = (existingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                    style.lineSpacing = headerLineSpacing
                    style.paragraphSpacingBefore = headerParagraphBefore
                    style.paragraphSpacing = headerParagraphAfter
                    merged[.paragraphStyle] = style
                    m.addAttributes(merged, range: lr)
                }
            }
            var ta = tv.typingAttributes
            if turnToBody {
                ta[.font] = EditorTheme.baseFont
                ta[.paragraphStyle] = bodyParagraphStyle(preservingAlignment: (ta[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .natural)
            } else {
                ta[.font] = UIFont.systemFont(ofSize: spec.size, weight: spec.weight)
            }
            tv.typingAttributes = ta
            tv.setAttributedStringUndoSafe(m)
            if let br = blockRangeForLineRanges(lrs), br.location + br.length <= m.length {
                tv.selectedRange = NSRange(location: br.location, length: br.length)
            } else {
                tv.selectedRange = NSRange(location: sel.location, length: sel.length)
            }
            return
        }
        
        lineR = lrs[0]
        
        // Word: the same style control again reverts the line to Normal (body).
        if m.length > 0, lineR.length > 0, lineR.location < m.length, isSameHeadingLine(m: m, lineR: lineR, as: action) {
            var align: NSTextAlignment = .natural
            if let p = m.attribute(.paragraphStyle, at: lineR.location, effectiveRange: nil) as? NSParagraphStyle {
                align = p.alignment
            }
            m.addAttributes([
                .font: EditorTheme.baseFont,
                .foregroundColor: EditorTheme.textColor,
                .paragraphStyle: bodyParagraphStyle(preservingAlignment: align)
            ], range: lineR)
            var ta = tv.typingAttributes
            ta[.font] = EditorTheme.baseFont
            ta[.paragraphStyle] = bodyParagraphStyle(preservingAlignment: align)
            tv.typingAttributes = ta
            tv.setAttributedStringUndoSafe(m)
            tv.selectedRange = NSRange(location: lineR.location, length: 0)
            return
        }
        
        // Handle empty text or invalid range
        guard m.length > 0, lineR.length > 0, lineR.location < m.length else {
            // For empty text, just set typing attributes for the header
            var attrs = tv.typingAttributes
            attrs[.font] = UIFont.systemFont(ofSize: spec.size, weight: spec.weight)
            let style = NSMutableParagraphStyle()
            style.lineSpacing = headerLineSpacing
            style.paragraphSpacingBefore = headerParagraphBefore
            style.paragraphSpacing = headerParagraphAfter
            attrs[.paragraphStyle] = style
            tv.typingAttributes = attrs
            return
        }
        
        let existingAttrs = m.attributes(at: lineR.location, effectiveRange: nil)
        var merged = existingAttrs
        merged[.font] = UIFont.systemFont(ofSize: spec.size, weight: spec.weight)
        merged[.foregroundColor] = (existingAttrs[.foregroundColor] as? UIColor) ?? EditorTheme.textColor
        
        let existingStyle = existingAttrs[.paragraphStyle] as? NSParagraphStyle
        let style = (existingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.lineSpacing = headerLineSpacing
        style.paragraphSpacingBefore = headerParagraphBefore
        style.paragraphSpacing = headerParagraphAfter
        merged[.paragraphStyle] = style
        m.addAttributes(merged, range: lineR)
        
        tv.setAttributedStringUndoSafe(m)
        if sel.length > 0, let br = blockRangeForLineRanges(lrs), br.location + br.length <= m.length {
            tv.selectedRange = NSRange(location: br.location, length: br.length)
        } else {
            tv.selectedRange = NSRange(location: lineR.location, length: 0)
        }
    }

    // MARK: Lists (Word-style: same control swaps list type or toggles; never stack markers)
    
    /// End offset in the line of leading spaces + list marker (• or N. ), in UTF-16. Nil if the line is not a list line.
    private static func listMarkerPrefixUTF16Length(_ line: String) -> Int? {
        let n = line as NSString
        let paren = n.range(of: "^\\s*\\d+\\) ", options: .regularExpression)
        if paren.location != NSNotFound { return paren.length }
        let letter = n.range(of: "^\\s*[a-z]\\) ", options: .regularExpression)
        if letter.location != NSNotFound { return letter.length }
        let numbered = n.range(of: "^\\s*\\d+\\. ", options: .regularExpression)
        if numbered.location != NSNotFound { return numbered.length }
        let bullet = n.range(of: "^\\s*[•◦▪] ", options: .regularExpression)
        if bullet.location != NSNotFound { return bullet.length }
        return nil
    }
    
    private static func leadingSpacePrefix(_ line: String) -> String {
        String(line.prefix(while: { $0 == " " }))
    }
    
    private static func removeListMarkerForToggle(_ line: String, bullet: Bool) -> String {
        let n = line as NSString
        if bullet {
            for p in ["^\\s*• ", "^\\s*◦ ", "^\\s*▪ "] {
                let r = n.range(of: p, options: .regularExpression)
                if r.location != NSNotFound { return n.replacingCharacters(in: r, with: "") }
            }
            return line
        } else {
            for p in ["^\\s*\\d+\\. ", "^\\s*\\d+\\) ", "^\\s*[a-z]\\) "] {
                let r = n.range(of: p, options: .regularExpression)
                if r.location != NSNotFound { return n.replacingCharacters(in: r, with: "") }
            }
            return line
        }
    }
    
    /// Plain line or paragraph → "• a" / "1. a" (leading spaces = indent; does not double-insert a second indent).
    private static func addListMarkerToPlainLine(_ line: String, numbered: Bool) -> String {
        let indent = leadingSpacePrefix(line)
        let indLen = indent.count
        let rest = indLen > 0 ? String(line.dropFirst(indLen)) : line
        let marker = numbered ? "1. " : "• "
        if rest.isEmpty { return indent + marker }
        return indent + marker + rest
    }
    
    private static func convertNumberedLineToBulletLine(_ line: String) -> String {
        let indent = leadingSpacePrefix(line)
        let indLen = indent.count
        let after = indLen > 0 ? String(line.dropFirst(indLen)) : line
        let a = after as NSString
        for p in ["^\\d+\\. ", "^\\d+\\) ", "^[a-z]\\) "] {
            let m = a.range(of: p, options: .regularExpression)
            if m.location != NSNotFound { return indent + "• " + a.substring(from: m.location + m.length) }
        }
        return line
    }
    
    private static func convertBulletLineToNumberedLine(_ line: String) -> String {
        let indent = leadingSpacePrefix(line)
        let indLen = indent.count
        let rest = indLen > 0 ? String(line.dropFirst(indLen)) : line
        if let b = rest.range(of: "^[•◦▪] ", options: .regularExpression) {
            return indent + "1. " + String(rest[b.upperBound...])
        }
        return line
    }
    
    private static func newCursorInLineAfterListEdit(
        oldLine: String,
        newLine: String,
        cursorInLine: Int,
        pOld: Int,
        pNew: Int
    ) -> Int {
        let oLen = (oldLine as NSString).length
        let nLen = (newLine as NSString).length
        if cursorInLine <= pOld {
            return pNew
        }
        return cursorInLine + (nLen - oLen)
    }

    private static func applyListAction(_ action: MarkdownAction, tv: UITextView) {
        let range = tv.selectedRange
        let m = NSMutableAttributedString(attributedString: tv.attributedText)
        let full = m.string as NSString
        let lrs = lineRangesCoveredBySelection(full, range)
        guard !lrs.isEmpty else { return }
        
        if lrs.count > 1, let br = blockRangeForLineRanges(lrs) {
            let oldBlock = full.substring(with: br) as String
            let raw = stringLinesFromBlock(full, lrs)
            let newLines = raw.map { transformListLine($0, action: action) }
            let newBlock = newLines.joined(separator: "\n")
            guard newBlock != oldBlock else { return }
            m.replaceCharacters(in: br, with: newBlock)
            tv.setAttributedStringUndoSafe(m)
            let newLen = (newBlock as NSString).length
            tv.selectedRange = NSRange(location: br.location, length: newLen)
            return
        }
        
        let lineRange = lrs[0]
        let raw = full.substring(with: lineRange) as String
        let hadTrailingNewline = raw.hasSuffix("\n")
        let line = hadTrailingNewline ? String(raw.dropLast()) : raw
        var cursorInLine = max(0, range.location - lineRange.location)
        cursorInLine = min(cursorInLine, (line as NSString).length)
        if hadTrailingNewline, range.location >= lineRange.location + (line as NSString).length {
            cursorInLine = (line as NSString).length
        }
        let newCore = transformListLine(line, action: action)
        guard newCore != line else { return }
        let newStored = newCore + (hadTrailingNewline ? "\n" : "")
        let pOld = listMarkerPrefixUTF16Length(line) ?? 0
        let pNew = listMarkerPrefixUTF16Length(newCore) ?? 0
        m.replaceCharacters(in: lineRange, with: newStored)
        let newCursorInLine = newCursorInLineAfterListEdit(
            oldLine: line, newLine: newCore, cursorInLine: cursorInLine, pOld: pOld, pNew: pNew
        )
        let nCore = (newCore as NSString).length
        let clamped = min(max(0, newCursorInLine), nCore)
        tv.setAttributedStringUndoSafe(m)
        let off = min(clamped, (newStored as NSString).length)
        tv.selectedRange = NSRange(location: min(lineRange.location + off, m.length), length: 0)
    }

    // MARK: Indent/Outdent (Word-style: work on any line, not only lists; 4 spaces = one level)

    private static func applyIndentAction(_ action: MarkdownAction, tv: UITextView) {
        let range = tv.selectedRange
        let m = NSMutableAttributedString(attributedString: tv.attributedText)
        let full = m.string as NSString
        let lrs = lineRangesCoveredBySelection(full, range)
        guard !lrs.isEmpty else { return }
        let outdent = (action == .outdent)
        let str = m.string
        let docLines = (str as NSString).components(separatedBy: "\n")
        
        if lrs.count > 1, let br = blockRangeForLineRanges(lrs) {
            let raw = stringLinesFromBlock(full, lrs)
            let startIdx = (str as NSString).substring(to: br.location).filter { $0 == "\n" }.count
            let newLines = raw.enumerated().map { (i, line) in
                indentOrOutdentLineString(
                    line, outdent: outdent, allDocumentLines: docLines, lineIndex: startIdx + i
                )
            }
            let newBlock = newLines.joined(separator: "\n")
            if newBlock == full.substring(with: br) { return }
            m.replaceCharacters(in: br, with: newBlock)
            tv.setAttributedStringUndoSafe(m)
            tv.selectedRange = NSRange(location: br.location, length: (newBlock as NSString).length)
            return
        }
        
        let lineRange = lrs[0]
        let raw0 = full.substring(with: lineRange) as String
        let hadTrailing = raw0.hasSuffix("\n")
        let line = hadTrailing ? String(raw0.dropLast()) : raw0
        let lineIdx = (str as NSString).substring(to: min(lineRange.location, full.length)).filter { $0 == "\n" }.count
        let newLine = indentOrOutdentLineString(
            line, outdent: outdent, allDocumentLines: docLines, lineIndex: lineIdx
        )
        if newLine == line { return }
        let newStored = newLine + (hadTrailing ? "\n" : "")
        m.replaceCharacters(in: lineRange, with: newStored)
        let delta = (newLine as NSString).length - (line as NSString).length
        tv.setAttributedStringUndoSafe(m)
        tv.selectedRange = NSRange(
            location: min(max(0, range.location + delta), m.length), length: 0
        )
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

    // MARK: Font traits (Word: whole selection is bold or not; not per-run flips on mixed)

    private static func allRunsInRangeHaveFontTrait(
        _ m: NSAttributedString, range: NSRange, trait: UIFontDescriptor.SymbolicTraits
    ) -> Bool {
        var all = true
        var saw = false
        m.enumerateAttribute(.font, in: range, options: []) { f, r, _ in
            if r.length == 0 { return }
            saw = true
            let uif = (f as? UIFont) ?? EditorTheme.baseFont
            if !uif.fontDescriptor.symbolicTraits.contains(trait) { all = false }
        }
        return saw && all
    }

    private static func toggleFontTraitWordStyle(
        _ trait: UIFontDescriptor.SymbolicTraits, in m: NSMutableAttributedString, range: NSRange
    ) {
        let allHave = allRunsInRangeHaveFontTrait(m, range: range, trait: trait)
        let enable = !allHave
        m.enumerateAttribute(.font, in: range, options: []) { f, r, _ in
            if r.length == 0 { return }
            let base = (f as? UIFont) ?? EditorTheme.baseFont
            var t = base.fontDescriptor.symbolicTraits
            if enable { t.insert(trait) } else { t.remove(trait) }
            let newFont: UIFont
            if let descriptor = base.fontDescriptor.withSymbolicTraits(t) {
                newFont = UIFont(descriptor: descriptor, size: base.pointSize)
            } else {
                newFont = base
            }
            m.addAttribute(.font, value: newFont, range: r)
        }
    }

    private static func toggleKeyWordStyle(
        _ key: NSAttributedString.Key,
        value: Int,
        in m: NSMutableAttributedString,
        range: NSRange,
        isSet: (Any?) -> Bool
    ) {
        var all = true
        m.enumerateAttribute(key, in: range, options: []) { existing, r, _ in
            if r.length == 0 { return }
            if !isSet(existing) { all = false }
        }
        if all { m.removeAttribute(key, range: range) } else { m.addAttribute(key, value: value, range: range) }
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
                
                Rectangle()
                    .fill(DesignSystem.Colors.border)
                    .frame(width: 1, height: 24)
                
                // Headers menu
                Menu {
                    Button("Header 1") { coordinator?.handleMarkdownAction(.header1) }
                    Button("Header 2") { coordinator?.handleMarkdownAction(.header2) }
                    Button("Header 3") { coordinator?.handleMarkdownAction(.header3) }
                } label: {
                    Text("H")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .background(DesignSystem.Colors.backgroundTertiary)
                        .cornerRadius(DesignSystem.CornerRadius.sm)
                }
                
                Rectangle()
                    .fill(DesignSystem.Colors.border)
                    .frame(width: 1, height: 24)
                
                // Lists
                HStack(spacing: 6) {
                    toolbarButton("•", .bulletList, hint: "Bullet List")
                    toolbarButton("1.", .numberedList, hint: "Numbered List")
                    toolbarButton("→", .indent, hint: "Indent")
                    toolbarButton("←", .outdent, hint: "Outdent")
                }
                
                Rectangle()
                    .fill(DesignSystem.Colors.border)
                    .frame(width: 1, height: 24)
                
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
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 32, height: 32)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .background(DesignSystem.Colors.backgroundTertiary)
                        .cornerRadius(DesignSystem.CornerRadius.sm)
                }
                
                Rectangle()
                    .fill(DesignSystem.Colors.border)
                    .frame(width: 1, height: 24)
                
                // Insert menu
                Menu {
                    Button(action: { coordinator?.handleMarkdownAction(.link) }) {
                        Label("Link", systemImage: "link")
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 32, height: 32)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .background(DesignSystem.Colors.backgroundTertiary)
                        .cornerRadius(DesignSystem.CornerRadius.sm)
                }
                
                Rectangle()
                    .fill(DesignSystem.Colors.border)
                    .frame(width: 1, height: 24)
                
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
        .background(DesignSystem.Colors.surface)
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
                .foregroundColor(isSelected ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textPrimary)
                .background(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.backgroundTertiary)
                .cornerRadius(DesignSystem.CornerRadius.sm)
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