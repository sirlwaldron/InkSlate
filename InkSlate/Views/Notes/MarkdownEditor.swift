import SwiftUI
import Foundation
import UniformTypeIdentifiers
import os.log

#if canImport(UIKit)
import UIKit
@preconcurrency import PhotosUI

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

struct MarkdownSerialization {
    private static let attrPrefix = "⟪ATTR⟫"
    private static let attrSuffix = "⟪/ATTR⟫"
    private static let serializationLog = Logger(subsystem: "com.lucas.InkSlateNew", category: "MarkdownSerialization")
    
    static func serialize(_ attributed: NSAttributedString) -> String {
        let mutable = attributed as? NSMutableAttributedString ?? NSMutableAttributedString(attributedString: attributed)
        let forArchive = NotePhotoAttachment.stripHeavyImagesForPersistence(mutable)

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
        
        let allowedClasses: [AnyClass] = [
            NSAttributedString.self,
            NSMutableAttributedString.self,
            UIColor.self,
            UIFont.self,
            UIFontDescriptor.self,
            NSURL.self,
            NSData.self,
            NSDictionary.self,
            NSMutableDictionary.self,
            NSString.self,
            NSNumber.self,
            NSParagraphStyle.self,
            NSMutableParagraphStyle.self,
            NSTextTab.self,
            NSShadow.self,
            NSTextAttachment.self,
            UIImage.self,
            NSValue.self,
            NSArray.self,
            NSMutableArray.self
        ]
        
        do {
            guard let attributed = try NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: data) as? NSAttributedString else {
                return (EditorContentParser.deserialize(plainText, maxWidth: maxWidth), plainText)
            }
            
            let mutable = NSMutableAttributedString(attributedString: attributed)
// Preserve font attributes after CloudKit merges.
            restoreFontAttributes(in: mutable)
            return (mutable, plainText)
        } catch {
            serializationLog.error("Rich note deserialize failed; falling back to plain text (inline photos will be missing until fixed). \(error.localizedDescription, privacy: .public)")
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
                result += rawParagraph
            }
            idx = paraRange.location + paraRange.length
        }
        return result.trimmingCharacters(in: .newlines)
    }
    
    /// Restores font attributes after deserialization to ensure traits (bold, italic) are preserved This is especially important after CloudKit...
    private static func restoreFontAttributes(in mutable: NSMutableAttributedString) {
        let range = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttributes(in: range, options: []) { attrs, r, _ in
            guard let font = attrs[.font] as? UIFont else { return }
            let descriptor = font.fontDescriptor
            let traits = descriptor.symbolicTraits
            
// Rebuild font with explicit traits (CloudKit can drop symbolic traits).
            if traits.rawValue != 0 {
                if let newDescriptor = descriptor.withSymbolicTraits(traits) {
                    let restoredFont = UIFont(descriptor: newDescriptor, size: font.pointSize)
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

    func setAttributedString(_ m: NSAttributedString, recordUndo: Bool) {
        if !recordUndo {
            textStorage.beginEditing()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.replaceCharacters(in: fullRange, with: m)
            textStorage.endEditing()
            undoManager?.removeAllActions()
            return
        }
        
        textStorage.beginEditing()
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.replaceCharacters(in: fullRange, with: m)
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
    var autoFocusOnAppear: Bool = false
    /// Stable Core Data `Notes.id` used as CloudKit `noteID` on `NotePhoto` records (draft notes should pass a fixed UUID before insert)
    var noteCloudKitID: UUID? = nil
    /// When true, inline photos are disabled (e.g
    var notePhotosDisabled: Bool = false
    var onPhotoIndexChanged: ((String?) -> Void)? = nil
    
    func makeUIView(context: Context) -> EditorTextView {
        let textView = EditorTextView()

        textView.backgroundColor = .systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 13, left: 10, bottom: 13, right: 10)
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.adjustsFontForContentSizeCategory = true
        textView.layoutManager.allowsNonContiguousLayout = true
        textView.allowsEditingTextAttributes = true
        textView.dataDetectorTypes = []
        textView.isScrollEnabled = true
        textView.isUserInteractionEnabled = true
        textView.textContainer.widthTracksTextView = true

        textView.linkTextAttributes = [
            .foregroundColor: EditorTheme.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        textView.delegate = context.coordinator
        textView.pasteDelegate = context.coordinator
        textView.owningCoordinator = context.coordinator

        let photoTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(MarkdownEditor.Coordinator.handleNotePhotoTap(_:)))
        photoTap.name = MarkdownEditor.Coordinator.notePhotoSizingTapGestureName
        photoTap.delegate = context.coordinator
        photoTap.cancelsTouchesInView = true
        textView.addGestureRecognizer(photoTap)

        context.coordinator.textView = textView

        let attributed = context.coordinator.deserializeContent(text)
        textView.setAttributedStringForBindingSync(attributed)
        context.coordinator.refreshKnownPhotoRecordNames(from: textView.attributedText)
        context.coordinator.scheduleHydrateNotePhotos()
        NotePhotoCloudHydrator.hydrate(textView: textView)

        context.coordinator.applyTypingAttributes(in: textView)
        NotificationCenter.default.post(name: .editorActiveStylesDidChange, object: context.coordinator,
                                        userInfo: ["styles": context.coordinator.currentActiveStyles(in: textView)])

        if autoFocusOnAppear {
            DispatchQueue.main.async { textView.becomeFirstResponder() }
        }
        
        return textView
    }
    
    func updateUIView(_ uiView: EditorTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.textView = uiView
        guard !uiView.isFirstResponder else { return }
        let latest = context.coordinator.serializeContent(from: uiView.attributedText)
        guard latest != text else { return }

        DispatchQueue.main.async {
            let range = uiView.selectedRange
            let attributed = context.coordinator.deserializeContent(text)
            uiView.setAttributedStringForBindingSync(attributed)
            context.coordinator.refreshKnownPhotoRecordNames(from: uiView.attributedText)
            context.coordinator.scheduleHydrateNotePhotos()
            let len = uiView.attributedText.length
            let maxR = NSMaxRange(range)
            if len == 0 {
                uiView.selectedRange = NSRange(location: 0, length: 0)
            } else if maxR <= len {
                uiView.selectedRange = range
            } else {
                let loc = min(range.location, len)
                let end = min(maxR, len)
                uiView.selectedRange = NSRange(location: loc, length: max(0, end - loc))
            }
        }
    }

    static func dismantleUIView(_ uiView: EditorTextView, coordinator: Coordinator) {
        uiView.undoManager?.removeAllActions()
    }

    func makeCoordinator() -> Coordinator { 
        let coord = Coordinator(self)
        self.coordinatorRef = coord
        return coord
    }
    
    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate, UITextPasteDelegate {
        var parent: MarkdownEditor
        weak var textView: EditorTextView?
        private var isProgrammaticChange = false
        var lastPublishedSerialized: String?

        private var hasPendingUserEdit = false

        func consumePendingUserEdit() -> Bool {
            let pending = hasPendingUserEdit
            hasPendingUserEdit = false
            return pending
        }
        
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
        /// Monotonic token guarding background serialization
        private var serializeToken = 0
        private var styleCalculationWorkItem: DispatchWorkItem?
        private var renumberListWorkItem: DispatchWorkItem?
        private var hydrateNotePhotosWorkItem: DispatchWorkItem?
        private(set) var lastKnownPhotoRecordNames: Set<String> = []
        private var pendingPhotoDeletions: Set<String> = []
        private var notePhotoCachesWarmedObserver: NSObjectProtocol?
        
        fileprivate var typingModes = Set<MarkdownAction>()

        init(_ parent: MarkdownEditor) {
            self.parent = parent
            super.init()
            notePhotoCachesWarmedObserver = NotificationCenter.default.addObserver(
                forName: .inkSlateNotePhotoCachesWarmed,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleHydrateNotePhotos()
            }
        }
        
        deinit {
            if let notePhotoCachesWarmedObserver {
                NotificationCenter.default.removeObserver(notePhotoCachesWarmedObserver)
            }
            saveWorkItem?.cancel()
            styleCalculationWorkItem?.cancel()
            renumberListWorkItem?.cancel()
            hydrateNotePhotosWorkItem?.cancel()
            fontCache.removeAll()
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                NotificationCenter.default.post(
                    name: .editorActiveStylesDidChange,
                    object: self,
                    userInfo: ["styles": Set<MarkdownAction>()]
                )
            }
        }

        func applyExternalSerializedContent(_ text: String) {
            guard let tv = textView else { return }
            renumberListWorkItem?.cancel()
            isProgrammaticChange = true
            defer { isProgrammaticChange = false }
            let attributed = deserializeContent(text)
            tv.setAttributedStringForBindingSync(attributed)
            refreshKnownPhotoRecordNames(from: tv.attributedText)
            scheduleHydrateNotePhotos()
            lastPublishedSerialized = text
            parent.text = text
            parent.selectedRange = tv.selectedRange
            applyTypingAttributes(in: tv)
            NotificationCenter.default.post(
                name: .editorActiveStylesDidChange,
                object: self,
                userInfo: ["styles": currentActiveStyles(in: tv)]
            )
        }

        /// Pushes the live `textView` into the SwiftUI `text` binding and cancels debounced updates
        func flushPendingEditsToParent() {
            saveWorkItem?.cancel()
            styleCalculationWorkItem?.cancel()
            renumberListWorkItem?.cancel()
            guard let textView = textView else { return }
            serializeToken &+= 1
            let serialized = serializeContent(from: textView.attributedText)

            lastPublishedSerialized = serialized
            parent.text = serialized
            parent.selectedRange = textView.selectedRange
        }
        
        // MARK: Serialization
        
        func serializeContent(from attributed: NSAttributedString) -> String {
            let mutable = attributed as? NSMutableAttributedString ?? NSMutableAttributedString(attributedString: attributed)
            return MarkdownSerialization.serialize(mutable)
        }
        
        func deserializeContent(_ text: String) -> NSAttributedString {
            let column: CGFloat
            if let tv = textView {
                column = NotePhotoAttachment.textColumnWidth(for: tv)
            } else {
                column = max(280, UIScreen.main.bounds.width - 48)
            }
            let availableWidth = max(column, 60)
            if let (attr, _) = MarkdownSerialization.deserialize(text, maxWidth: availableWidth) {
                let m = NSMutableAttributedString(attributedString: attr)
                NotePhotoAttachment.repairAttachmentBounds(in: m, columnWidth: column)
                return m
            }
            return EditorContentParser.deserialize(text, maxWidth: availableWidth)
        }

        // MARK: Text changes
        
        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammaticChange else { return }
            hasPendingUserEdit = true
            saveWorkItem?.cancel()

            if textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true {
                self.syncRemovedNotePhotosFromCloud(currentAttributed: textView.attributedText)
                self.serializeToken &+= 1
                let serialized = self.serializeContent(from: textView.attributedText)
                self.lastPublishedSerialized = serialized
                self.parent.text = serialized
            } else {
// Debounced typing path: snapshot the attributed string on the main thread (cheap,
                let item = DispatchWorkItem { [weak self] in
                    guard let self = self, let textView = self.textView else { return }
                    self.syncRemovedNotePhotosFromCloud(currentAttributed: textView.attributedText)
                    let snapshot = NSAttributedString(attributedString: textView.attributedText)
                    self.serializeToken &+= 1
                    let token = self.serializeToken
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        let serialized = MarkdownSerialization.serialize(snapshot)
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self, token == self.serializeToken else { return }
                            self.lastPublishedSerialized = serialized
                            self.parent.text = serialized
                        }
                    }
                }
                saveWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
            }

            parent.selectedRange = textView.selectedRange
            
// Word-style: renumber "1. / 2." lists after edits; defer for undo; cancellable work item (not raw async).
            renumberListWorkItem?.cancel()
            if textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true {
                let item = DispatchWorkItem { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    guard textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true else { return }
                    self.maybeRenumberDecimalNumberedLists(in: textView)
                }
                renumberListWorkItem = item
                DispatchQueue.main.async(execute: item)
            }
            updateActiveStylesAsync(textView)
        }

        private func updateActiveStylesAsync(_ textView: UITextView) {
            styleCalculationWorkItem?.cancel()
            styleCalculationWorkItem = DispatchWorkItem { [weak self] in
                guard let strongSelf = self else { return }
                let styles = strongSelf.currentActiveStyles(in: textView)
                NotificationCenter.default.post(name: .editorActiveStylesDidChange,
                                                object: strongSelf, userInfo: ["styles": styles])
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: styleCalculationWorkItem!)
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selectedRange = textView.selectedRange
            (textView as? EditorTextView)?.registerLinkMenuItems()
            
            let len = textView.attributedText.length
            let caret = textView.selectedRange.location
            let idx: Int
            if textView.selectedRange.length > 0 {
                idx = len == 0 ? 0 : max(0, min(caret, len - 1))
            } else {
                idx = caret >= len ? max(0, len - 1) : caret
            }
            let attrs: [NSAttributedString.Key: Any]
            if len == 0 || caret >= len {
                attrs = textView.typingAttributes
            } else {
                attrs = textView.attributedText.attributes(at: idx, effectiveRange: nil)
            }
            setTypingModesFromAttributes(attrs, in: textView)
            
            NotificationCenter.default.post(name: .editorActiveStylesDidChange, object: self,
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
                
                if range.length == 0, let etv = tv as? EditorTextView {
                    let lineR = etv.currentLineRange()
                    if isHeadingLine(tv, lineRange: lineR) {
                        Self.withUndoGroup(in: tv) {
                            tv.insertText("\n")
                            var ta = tv.typingAttributes
                            let existingAlign = (ta[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .natural
                            ta[.font] = EditorTheme.baseFont
                            ta[.foregroundColor] = EditorTheme.textColor
                            ta[.paragraphStyle] = WysiwygActionHandler.bodyParagraphStyle(preservingAlignment: existingAlign)
                            ta[.underlineStyle] = nil
                            ta[.strikethroughStyle] = nil
                            tv.typingAttributes = ta
                            setTypingModesFromAttributes(ta, in: tv)
                        }
                        serializeAfterAttributeChange(in: tv)
                        return false
                    }
                }

                if range.length == 0 {
                    let hasUnderline = (tv.typingAttributes[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue
                    let hasStrike = (tv.typingAttributes[.strikethroughStyle] as? Int) == NSUnderlineStyle.single.rawValue
                    if hasUnderline || hasStrike {
                        Self.withUndoGroup(in: tv) {
                            tv.insertText("\n")
                            var ta = tv.typingAttributes
                            ta[.underlineStyle] = nil
                            ta[.strikethroughStyle] = nil
                            tv.typingAttributes = ta
                            setTypingModesFromAttributes(ta, in: tv)
                        }
                        serializeAfterAttributeChange(in: tv)
                        return false
                    }
                }
            }
            if string == "\t" {
                if let etv = tv as? EditorTextView {
                    Self.withUndoGroup(in: tv) { WysiwygActionHandler.apply(.indent, to: etv, coordinator: self) }
                    serializeAfterAttributeChange(in: tv)
                    return false
                }
            }
            
            if string.isEmpty, range.length == 1, let etv = tv as? EditorTextView {
                let lineR = etv.currentLineRange()
                let full = tv.attributedText.string as NSString
                let raw = full.substring(with: lineR)
                let hadTrailingNewline = raw.hasSuffix("\n")
                let line = hadTrailingNewline ? String(raw.dropLast()) : raw
                
                if let pfx = WysiwygActionHandler.listMarkerPrefixUTF16Length(line) {
                    let lineStart = lineR.location
                    let contentStart = lineStart + pfx
                    if range.location == contentStart {
                        var newLine = WysiwygActionHandler.removeListMarkerForToggle(line, bullet: true)
                        if newLine == line {
                            newLine = WysiwygActionHandler.removeListMarkerForToggle(line, bullet: false)
                        }
                        let newStored = newLine + (hadTrailingNewline ? "\n" : "")
                        Self.withUndoGroup(in: tv) {
                            etv.textStorage.beginEditing()
                            etv.textStorage.replaceCharacters(in: lineR, with: newStored)
                            etv.textStorage.endEditing()
                            etv.selectedRange = NSRange(location: lineStart, length: 0)
                        }
                        serializeAfterAttributeChange(in: tv)
                        return false
                    }
                }
            }

            if string.contains("\n"), let etv = tv as? EditorTextView {
                let lineR = etv.currentLineRange()
                let full = tv.attributedText.string as NSString
                if lineR.location < full.length {
                    let raw = full.substring(with: lineR)
                    let hadTrailingNewline = raw.hasSuffix("\n")
                    let line = hadTrailingNewline ? String(raw.dropLast()) : raw
                    let r = NSRange(line.startIndex..<line.endIndex, in: line)
                    let lead = WordListLineKind.leadingPrefix(line)
                    let L = WordListLineKind.listLevel(leading: lead)
                    let afterLead = String(line.dropFirst(lead.count))

                    let isBullet = WordListLineKind.detectBullet(in: line, r) != nil
                    let afterLeadNS = afterLead as NSString
                    let decRange = afterLeadNS.range(
                        of: #"^\d+\. "#,
                        options: .regularExpression,
                        range: NSRange(afterLead.startIndex..<afterLead.endIndex, in: afterLead)
                    )
                    let isDecimal = decRange.location != NSNotFound
                    let currentDecimal: Int? = {
                        guard isDecimal else { return nil }
                        let prefix = afterLeadNS.substring(with: NSRange(location: 0, length: max(0, decRange.length)))
                        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
                        let digits = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                        return Int(digits)
                    }()

                    if isBullet || isDecimal {
                        var nextDecimal = (currentDecimal ?? 0) + 1
                        func markerForNewLine() -> String {
                            if isBullet { return WordListLineKind.bulletMark(forLevel: L) }
                            let m = "\(nextDecimal). "
                            nextDecimal += 1
                            return m
                        }
                        let parts = string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                        if parts.count > 1 {
                            var rebuilt = parts[0]
                            for i in 1..<parts.count {
                                if i == parts.count - 1, parts[i].isEmpty {
                                    rebuilt += "\n"
                                } else {
                                    rebuilt += "\n\(lead)\(markerForNewLine())\(parts[i])"
                                }
                            }
                            Self.withUndoGroup(in: tv) {
                                tv.replace(range: range, with: NSAttributedString(string: rebuilt))
                            }
                            serializeAfterAttributeChange(in: tv)
                            return false
                        }
                    }
                }
            }
            return true
        }

        // MARK: Link interaction (Word-style: tap places caret in edit mode; never opens URL)
        @available(iOS, deprecated: 17.0, message: "Use UITextViewDelegate text-item callbacks (iOS 17+) instead.")
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange) -> Bool {
            if textView.isEditable {
                textView.selectedRange = NSRange(location: characterRange.location, length: 0)
                NotificationCenter.default.post(name: .editorActiveStylesDidChange, object: self,
                                                userInfo: ["styles": currentActiveStyles(in: textView)])
                return false
            }
            return true
        }

        @available(iOS 17.0, *)
        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .link = textItem.content else { return defaultAction }

            if textView.isEditable {
                let loc = textItem.range.location
                if loc != NSNotFound {
                    textView.selectedRange = NSRange(location: loc, length: 0)
                }
                NotificationCenter.default.post(name: .editorActiveStylesDidChange, object: self,
                                                userInfo: ["styles": currentActiveStyles(in: textView)])
                return UIAction { _ in }
            }

            return defaultAction
        }

        @available(iOS 17.0, *)
        func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
            guard case .link = textItem.content else { return .init(menu: defaultMenu) }

            if textView.isEditable {
                return nil
            }
            return .init(menu: defaultMenu)
        }

        @available(iOS 16.0, *)
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard textView.isEditable,
                  let editor = textView as? EditorTextView,
                  editor.currentLinkRange() != nil else {
                return nil
            }
            let edit = UIAction(title: "Edit Link") { [weak editor] _ in editor?.editLink() }
            let remove = UIAction(title: "Remove Link", attributes: .destructive) { [weak editor] _ in editor?.removeLink() }
            var elements = suggestedActions
            elements.append(UIMenu(title: "", options: .displayInline, children: [edit, remove]))
            return UIMenu(children: elements)
        }

        // MARK: Paste sanitization
        func textPasteConfigurationSupporting(_ textPasteConfigurationSupporting: UITextPasteConfigurationSupporting, transform item: UITextPasteItem) {
            if item.itemProvider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                item.setDefaultResult()
            } else if item.itemProvider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                item.itemProvider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { obj, _ in
                    DispatchQueue.main.async {
                        if let s = obj as? String { item.setResult(string: s) } else { item.setDefaultResult() }
                    }
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
                renumberListWorkItem?.cancel()
                flushPendingEditsToParent()
                isProgrammaticChange = true
                defer { isProgrammaticChange = false }
                um.undo()
                let len = tv.attributedText.length
                let caret = tv.selectedRange.location
                let idx = len == 0 ? 0 : max(0, min(max(0, caret - 1), len - 1))
                let attrs = len == 0 ? tv.typingAttributes : tv.attributedText.attributes(at: idx, effectiveRange: nil)
                setTypingModesFromAttributes(attrs, in: tv)
                DispatchQueue.main.async {
                    self.parent.text = self.serializeContent(from: tv.attributedText)
                    self.parent.selectedRange = tv.selectedRange
                    NotificationCenter.default.post(name: .editorActiveStylesDidChange,
                                                    object: self,
                                                    userInfo: ["styles": self.currentActiveStyles(in: tv)])
                }
                return
            case .redo:
                guard let um = tv.undoManager, um.canRedo else { return }
                renumberListWorkItem?.cancel()
                flushPendingEditsToParent()
                isProgrammaticChange = true
                defer { isProgrammaticChange = false }
                um.redo()
                let len = tv.attributedText.length
                let caret = tv.selectedRange.location
                let idx = len == 0 ? 0 : max(0, min(max(0, caret - 1), len - 1))
                let attrs = len == 0 ? tv.typingAttributes : tv.attributedText.attributes(at: idx, effectiveRange: nil)
                setTypingModesFromAttributes(attrs, in: tv)
                DispatchQueue.main.async {
                    self.parent.text = self.serializeContent(from: tv.attributedText)
                    self.parent.selectedRange = tv.selectedRange
                    NotificationCenter.default.post(name: .editorActiveStylesDidChange,
                                                    object: self,
                                                    userInfo: ["styles": self.currentActiveStyles(in: tv)])
                }
                return
            default: break
            }

            if action == .removeFormat {
                typingModes.removeAll()
                applyTypingAttributes(in: tv)
            }

            isProgrammaticChange = true
            defer { isProgrammaticChange = false }
            Self.withUndoGroup(in: tv) { WysiwygActionHandler.apply(action, to: tv, coordinator: self) }

            parent.text = serializeContent(from: tv.attributedText)
            parent.selectedRange = tv.selectedRange
            NotificationCenter.default.post(name: .editorActiveStylesDidChange, object: self,
                                            userInfo: ["styles": currentActiveStyles(in: tv)])
            
            if action == .link {
                promptForLink(tv)
            }
        }
        
        // MARK: - Word parity helpers
        
        private func isHeadingLine(_ tv: UITextView, lineRange: NSRange) -> Bool {
            guard tv.attributedText.length > 0, lineRange.location < tv.attributedText.length else { return false }
            let idx = max(0, min(lineRange.location, tv.attributedText.length - 1))
            let attrs = tv.attributedText.attributes(at: idx, effectiveRange: nil)
            guard let font = attrs[.font] as? UIFont else { return false }
            let base = EditorTheme.baseFont.pointSize
            guard font.pointSize >= base * 1.08 else { return false }
            guard let p = attrs[.paragraphStyle] as? NSParagraphStyle else { return false }
            return p.paragraphSpacingBefore >= 2 && p.lineSpacing > 0
        }
        
        private func maybeRenumberDecimalNumberedLists(in tv: UITextView) {
            guard tv.undoManager?.isUndoing != true, tv.undoManager?.isRedoing != true else { return }

            let s = tv.textStorage.string
            guard s.range(of: #"(?m)^\s*\d+\. "#, options: .regularExpression) != nil else { return }

            let lines = (s as NSString).components(separatedBy: "\n")
            var nextByIndent: [String: Int] = [:]
            var inBlockByIndent: Set<String> = []

            func indentPrefix(_ line: String) -> String { String(line.prefix(while: { $0 == " " })) }

            var changes: [(range: NSRange, newMarker: String)] = []
            var currentPos = 0

            for line in lines {
                let lineLength = (line as NSString).length

                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    inBlockByIndent.removeAll()
                } else {
                    let ind = indentPrefix(line)
                    let nsLine = line as NSString
                    let markerRange = nsLine.range(of: #"^\s*\d+\. "#, options: .regularExpression)

                    if markerRange.location != NSNotFound {
                        if !inBlockByIndent.contains(ind) {
                            inBlockByIndent.insert(ind)
                            nextByIndent[ind] = 1
                        }

                        let n = nextByIndent[ind] ?? 1
                        let correctMarker = ind + "\(n). "
                        let existingMarker = nsLine.substring(with: markerRange)

                        if correctMarker != existingMarker {
                            let absoluteMarkerRange = NSRange(
                                location: currentPos + markerRange.location,
                                length: markerRange.length
                            )
                            changes.append((absoluteMarkerRange, correctMarker))
                        }
                        nextByIndent[ind] = n + 1
                    } else {
                        inBlockByIndent.remove(ind)
                    }
                }
                currentPos += lineLength + 1
            }

            guard !changes.isEmpty else { return }

            let sel = tv.selectedRange

            isProgrammaticChange = true
            defer { isProgrammaticChange = false }

            if let um = tv.undoManager {
                um.beginUndoGrouping()
                tv.textStorage.beginEditing()
                for change in changes.reversed() {
                    tv.textStorage.replaceCharacters(in: change.range, with: change.newMarker)
                }
                tv.textStorage.endEditing()
                um.endUndoGrouping()
            } else {
                tv.textStorage.beginEditing()
                for change in changes.reversed() {
                    tv.textStorage.replaceCharacters(in: change.range, with: change.newMarker)
                }
                tv.textStorage.endEditing()
            }

            var caretLoc = sel.location
            for change in changes.reversed() {
                let r = change.range
                let newLen = (change.newMarker as NSString).length
                let delta = newLen - r.length
                if r.location + r.length <= caretLoc {
                    caretLoc += delta
                } else if r.location < caretLoc {
                    caretLoc = r.location + newLen
                }
            }
            let maxLen = tv.attributedText.length
            caretLoc = max(0, min(caretLoc, maxLen))
            tv.selectedRange = NSRange(location: caretLoc, length: 0)

            parent.text = serializeContent(from: tv.attributedText)
            parent.selectedRange = tv.selectedRange
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
                    insertion.addAttributes([
                        .link: url,
                        .foregroundColor: EditorTheme.linkColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ], range: NSRange(location: 0, length: insertion.length))
                    textView.replace(range: NSRange(location: sel.location, length: 0), with: insertion)
                    textView.selectedRange = NSRange(location: sel.location + insertion.length, length: 0)
                } else {
                    textView.textStorage.beginEditing()
                    textView.textStorage.addAttribute(.link, value: url, range: sel)
                    textView.textStorage.addAttribute(.foregroundColor, value: EditorTheme.linkColor, range: sel)
                    textView.textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: sel)
                    textView.textStorage.endEditing()
                    textView.selectedRange = sel
                    strongSelf.serializeAfterAttributeChange(in: textView)
                }
                }
            })
            guard let topVC = currentTopVC() else {
                return
            }
            topVC.present(alert, animated: true)
        }


        // MARK: Helpers
        
        fileprivate func serializeAfterAttributeChange(in tv: UITextView) {
            serializeToken &+= 1
            let serialized = serializeContent(from: tv.attributedText)
            hasPendingUserEdit = true
            lastPublishedSerialized = serialized
            parent.text = serialized
            parent.selectedRange = tv.selectedRange
            NotificationCenter.default.post(
                name: .editorActiveStylesDidChange,
                object: self,
                userInfo: ["styles": currentActiveStyles(in: tv)]
            )
        }

        // MARK: - Inline note photos (CloudKit)

        var canUseNotePhotos: Bool {
            parent.noteCloudKitID != nil && !parent.notePhotosDisabled
        }

        func refreshKnownPhotoRecordNames(from attributed: NSAttributedString) {
            lastKnownPhotoRecordNames = NotePhotoRefCollector.recordNames(in: attributed)
        }

        func scheduleHydrateNotePhotos() {
            hydrateNotePhotosWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self, let tv = self.textView else { return }
                NotePhotoCloudHydrator.hydrate(textView: tv)
            }
            hydrateNotePhotosWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: item)
        }

        private func syncRemovedNotePhotosFromCloud(currentAttributed: NSAttributedString) {
            let newSet = NotePhotoRefCollector.recordNames(in: currentAttributed)
            let removed = lastKnownPhotoRecordNames.subtracting(newSet)
            lastKnownPhotoRecordNames = newSet
            // Defer CloudKit photo deletes until note save (not on every debounced keystroke).
            pendingPhotoDeletions.formUnion(removed)
            if !pendingPhotoDeletions.isEmpty {
                pendingPhotoDeletions.subtract(newSet)
            }
        }

        func commitPendingPhotoDeletions() {
            let toDelete = pendingPhotoDeletions
            pendingPhotoDeletions.removeAll()
            guard !toDelete.isEmpty else { return }
            Task {
                for rk in toDelete {
                    NotePhotoDiskCache.remove(recordName: rk)
                    try? await CloudKitAssetService.shared.deleteNotePhoto(recordName: rk)
                }
            }
        }

        func presentNotePhotoPicker() {
            guard canUseNotePhotos, let top = currentTopVC() else { return }
            var cfg = PHPickerConfiguration()
            cfg.filter = .images
            cfg.selectionLimit = 1
            let picker = PHPickerViewController(configuration: cfg)
            picker.delegate = self
            picker.modalPresentationStyle = .formSheet
            top.present(picker, animated: true)
        }

        fileprivate static let notePhotoSizingTapGestureName = "inkSlateNotePhotoSizingTap"

        private static func photoAttachmentRange(at point: CGPoint, in tv: UITextView) -> NSRange? {
            guard tv.textStorage.length > 0 else { return nil }
            let layout = tv.layoutManager
            let container = tv.textContainer
            var loc = point
            loc.x -= tv.textContainerInset.left
            loc.y -= tv.textContainerInset.top
            let glyphIndex = layout.glyphIndex(for: loc, in: container, fractionOfDistanceThroughGlyph: nil)
            let charIndex = layout.characterIndexForGlyph(at: glyphIndex)
            guard charIndex < tv.textStorage.length else { return nil }
            var eff = NSRange()
            guard tv.textStorage.attribute(.inkSlateNotePhoto, at: charIndex, effectiveRange: &eff) != nil, eff.length > 0 else { return nil }
            return eff
        }

        @objc func handleNotePhotoTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let tv = textView else { return }
            let pt = gesture.location(in: tv)
            guard let range = Self.photoAttachmentRange(at: pt, in: tv) else { return }
            presentPhotoSizeMenu(photoRange: range, in: tv)
        }

        private func presentPhotoSizeMenu(photoRange range: NSRange, in tv: UITextView) {
            guard !parent.notePhotosDisabled else { return }
            let maxW = NotePhotoAttachment.textColumnWidth(for: tv)
            let meta = tv.textStorage.attribute(.inkSlateNotePhoto, at: range.location, effectiveRange: nil) as? [AnyHashable: Any]
            let currentW = CGFloat((meta?[NotePhotoAttachment.dictWidthKey] as? NSNumber)?.doubleValue ?? 280)

            final class DismissAnchor {
                var viewController: UIViewController?
            }
            let dismissBox = DismissAnchor()

            let root = NotePhotoSizePickerSheet(
                maxLayoutWidth: maxW,
                currentWidth: currentW,
                onPick: { [weak self, weak tv] width in
                    guard let self, let tv else { return }
                    Self.withUndoGroup(in: tv) {
                        NotePhotoAttachment.updateWidth(in: tv.textStorage, range: range, width: width)
                    }
                    self.serializeAfterAttributeChange(in: tv)
                },
                onDone: {
                    dismissBox.viewController?.dismiss(animated: true)
                }
            )

            let hosting = UIHostingController(rootView: root)
            dismissBox.viewController = hosting
            hosting.modalPresentationStyle = .pageSheet
            if let sheet = hosting.sheetPresentationController {
                sheet.detents = [.medium()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = DesignSystem.CornerRadius.xxl
            }
            currentTopVC()?.present(hosting, animated: true)
        }

        @MainActor
        fileprivate func uploadAndInsertPhoto(_ image: UIImage) async {
            guard let tv = textView, let noteID = parent.noteCloudKitID else { return }
            guard !parent.notePhotosDisabled else { return }
            let attachmentID = UUID()
            let recordName: String
            do {
                recordName = try await CloudKitAssetService.shared.uploadNotePhoto(image, noteID: noteID, attachmentID: attachmentID)
            } catch {
                ErrorHandlingService.shared.reportOperationFailure(
                    module: "Notes",
                    detail: "Couldn't add the photo to your note: \(error.localizedDescription)"
                )
                return
            }
            let column = NotePhotoAttachment.textColumnWidth(for: tv)
            let width = NotePhotoAttachment.preferredLayoutWidth(storedPoints: nil, columnWidth: column)
            insertPhotoAttachment(image: image, recordName: recordName, width: width, in: tv)
        }

        private func insertPhotoAttachment(image: UIImage, recordName: String, width: CGFloat, in tv: UITextView) {
            let attachment = NSTextAttachment()
            attachment.image = NotePhotoAttachment.displayImageForInlineEditor(image)
            let sz = NotePhotoAttachment.displaySize(for: image, width: width)
            attachment.bounds = CGRect(origin: .zero, size: sz)
            let insert = NSMutableAttributedString(attachment: attachment)
            let dict: [AnyHashable: Any] = [
                NotePhotoAttachment.dictRecordKey: recordName,
                NotePhotoAttachment.dictWidthKey: NSNumber(value: Double(width))
            ]
            insert.addAttribute(.inkSlateNotePhoto, value: dict, range: NSRange(location: 0, length: insert.length))
            let ps = NSMutableParagraphStyle()
            ps.paragraphSpacing = 10
            insert.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: insert.length))

            let replaceRange = tv.selectedRange
            Self.withUndoGroup(in: tv) {
                tv.textStorage.replaceCharacters(in: replaceRange, with: insert)
                let newLoc = replaceRange.location + insert.length
                let trailing = NSAttributedString(string: "\n", attributes: [
                    .font: EditorTheme.baseFont,
                    .foregroundColor: EditorTheme.textColor
                ])
                tv.textStorage.replaceCharacters(in: NSRange(location: newLoc, length: 0), with: trailing)
            }
            tv.selectedRange = NSRange(location: replaceRange.location + insert.length + 1, length: 0)
            refreshKnownPhotoRecordNames(from: tv.attributedText)
            NotePhotoCloudHydrator.storeInMemoryCache(image, recordName: recordName)
            Task.detached(priority: .userInitiated) {
                NotePhotoDiskCache.save(image, recordName: recordName)
            }
            serializeAfterAttributeChange(in: tv)
            parent.onPhotoIndexChanged?(NotePhotoRefCollector.jsonIndex(for: tv.attributedText))
            scheduleHydrateNotePhotos()
        }

        fileprivate func setTypingMode(_ action: MarkdownAction, enabled: Bool, in tv: UITextView) {
            if enabled { typingModes.insert(action) } else { typingModes.remove(action) }
            applyTypingAttributes(in: tv)
        }

        private var fontCache: [String: UIFont] = [:]
        private var fontCacheOrder: [String] = []
        
        fileprivate func applyTypingAttributes(in tv: UITextView) {
            var attrs = tv.typingAttributes
            if attrs[.font] == nil { attrs[.font] = EditorTheme.baseFont }
            if attrs[.foregroundColor] == nil { attrs[.foregroundColor] = EditorTheme.textColor }

            let baseFont = (attrs[.font] as? UIFont) ?? EditorTheme.baseFont
            let sortedModes = typingModes.map { String($0.rawValue) }.sorted().joined(separator: ",")
            let cacheKey = "\(baseFont.pointSize)_\(sortedModes)"
            
            if let cachedFont = fontCache[cacheKey] {
                attrs[.font] = cachedFont
                if let idx = fontCacheOrder.firstIndex(of: cacheKey) {
                    fontCacheOrder.remove(at: idx)
                    fontCacheOrder.append(cacheKey)
                }
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
                if fontCache.count >= 50 {
                    let evictCount = max(1, fontCache.count - 49)
                    for _ in 0..<evictCount {
                        if let oldest = fontCacheOrder.first {
                            fontCacheOrder.removeFirst()
                            fontCache.removeValue(forKey: oldest)
                        }
                    }
                }
                fontCache[cacheKey] = newFont
                if let idx = fontCacheOrder.firstIndex(of: cacheKey) { fontCacheOrder.remove(at: idx) }
                fontCacheOrder.append(cacheKey)
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

        func toolbarAlignmentSystemImage() -> String {
            guard let tv = textView else { return "text.alignleft" }
            let styles = currentActiveStyles(in: tv)
            if styles.contains(.alignCenter) { return "text.aligncenter" }
            if styles.contains(.alignRight) { return "text.alignright" }
            return "text.alignleft"
        }

        func toolbarHeadingLevel() -> Int? {
            guard let tv = textView else { return nil }
            let len = tv.attributedText.length
            guard len > 0 else { return nil }
            let caret = min(tv.selectedRange.location, len - 1)
            let attrs = tv.attributedText.attributes(at: max(0, caret), effectiveRange: nil)
            guard let font = attrs[.font] as? UIFont else { return nil }
            let base = EditorTheme.baseFont.pointSize
            let pt = font.pointSize
            if pt >= base * 1.45 { return 1 }
            if pt >= base * 1.28 { return 2 }
            if pt >= base * 1.12 { return 3 }
            return nil
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

        if let p = attrs[.paragraphStyle] as? NSParagraphStyle {
            switch p.alignment {
            case .center:
                set.insert(.alignCenter)
                set.remove(.alignLeft)
                set.remove(.alignRight)
            case .right:
                set.insert(.alignRight)
                set.remove(.alignLeft)
                set.remove(.alignCenter)
            default:
                set.insert(.alignLeft)
                set.remove(.alignCenter)
                set.remove(.alignRight)
            }
        } else {
            set.insert(.alignLeft)
            set.remove(.alignCenter)
            set.remove(.alignRight)
        }
        
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
    weak var owningCoordinator: MarkdownEditor.Coordinator?
    
    // MARK: - Undo/Redo like a normal iOS notes app
    @objc func undo(_ sender: Any?) {
        if let owningCoordinator {
            owningCoordinator.handleMarkdownAction(.undo)
        } else {
            undoManager?.undo()
        }
    }
    
    @objc func redo(_ sender: Any?) {
        if let owningCoordinator {
            owningCoordinator.handleMarkdownAction(.redo)
        } else {
            undoManager?.redo()
        }
    }

    // MARK: - Hardware keyboard shortcuts (Word-style)
    override var keyCommands: [UIKeyCommand]? {
        guard isEditable else { return super.keyCommands }
        func cmd(_ input: String, _ flags: UIKeyModifierFlags, _ action: Selector, _ title: String) -> UIKeyCommand {
            let c = UIKeyCommand(input: input, modifierFlags: flags, action: action)
            c.discoverabilityTitle = title
            return c
        }
        return [
            cmd("b", .command, #selector(cmdBold), "Bold"),
            cmd("i", .command, #selector(cmdItalic), "Italic"),
            cmd("u", .command, #selector(cmdUnderline), "Underline"),
            cmd("k", .command, #selector(cmdLink), "Add Link"),

            cmd("8", [.command, .shift], #selector(cmdBulletList), "Bullet List"),
            cmd("7", [.command, .shift], #selector(cmdNumberedList), "Numbered List"),

            cmd("\t", [], #selector(cmdIndent), "Indent"),
            cmd("\t", .shift, #selector(cmdOutdent), "Outdent"),

            cmd("z", .command, #selector(undo(_:)), "Undo"),
            cmd("Z", [.command, .shift], #selector(redo(_:)), "Redo")
        ]
    }

    @objc private func cmdBold() { owningCoordinator?.handleMarkdownAction(.bold) }
    @objc private func cmdItalic() { owningCoordinator?.handleMarkdownAction(.italic) }
    @objc private func cmdUnderline() { owningCoordinator?.handleMarkdownAction(.underline) }
    @objc private func cmdLink() { owningCoordinator?.handleMarkdownAction(.link) }
    @objc private func cmdBulletList() { owningCoordinator?.handleMarkdownAction(.bulletList) }
    @objc private func cmdNumberedList() { owningCoordinator?.handleMarkdownAction(.numberedList) }
    @objc private func cmdIndent() { owningCoordinator?.handleMarkdownAction(.indent) }
    @objc private func cmdOutdent() { owningCoordinator?.handleMarkdownAction(.outdent) }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(editLink) || action == #selector(removeLink) { return currentLinkRange() != nil }
        if action == #selector(undo(_:)) { return undoManager?.canUndo ?? false }
        if action == #selector(redo(_:)) { return undoManager?.canRedo ?? false }
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
            if !urlString.isEmpty && !urlString.contains("://") { urlString = "https://" + urlString }
            guard !urlString.isEmpty, let newURL = URL(string: urlString), newURL.scheme != nil else { return }
            strongSelf.textStorage.beginEditing()
            strongSelf.textStorage.addAttribute(.link, value: newURL, range: r)
            strongSelf.textStorage.endEditing()
            strongSelf.owningCoordinator?.serializeAfterAttributeChange(in: strongSelf)
        })
        currentTopVC()?.present(alert, animated: true)
    }

    @objc func removeLink() {
        guard let r = currentLinkRange() else { return }
        textStorage.beginEditing()
        textStorage.removeAttribute(.link, range: r)
        textStorage.removeAttribute(.underlineStyle, range: r)
        textStorage.addAttribute(.foregroundColor, value: EditorTheme.textColor, range: r)
        textStorage.endEditing()
        owningCoordinator?.serializeAfterAttributeChange(in: self)
    }

    private static var hasRegisteredMenuItems = false
    
    func registerLinkMenuItems() {
        if #available(iOS 16.0, *) {
        } else {
            guard !Self.hasRegisteredMenuItems else { return }
            Self.hasRegisteredMenuItems = true
            UIMenuController.shared.menuItems = [
                UIMenuItem(title: "Edit Link", action: #selector(editLink)),
                UIMenuItem(title: "Remove Link", action: #selector(removeLink))
            ]
        }
    }

    func currentLinkRange() -> NSRange? {
        let len = attributedText.length
        guard len > 0 else { return nil }
        let candidates: [Int]
        if selectedRange.length > 0 {
            candidates = [min(selectedRange.location, len - 1)]
        } else {
            candidates = [min(selectedRange.location, len - 1), max(0, selectedRange.location - 1)]
        }
        for idx in candidates {
            var r = NSRange(location: 0, length: 0)
            if attributedText.attribute(.link, at: idx, effectiveRange: &r) != nil { return r }
        }
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

// MARK: - WYSIWYG Action Handler

class WysiwygActionHandler {
    private typealias AttributeRunSnapshot = [(range: NSRange, attrs: [NSAttributedString.Key: Any])]
    
    private static func snapshotAttributes(in storage: NSTextStorage, range: NSRange) -> AttributeRunSnapshot {
        guard storage.length > 0, range.length > 0, range.location < storage.length else { return [] }
        let safeLen = min(range.length, storage.length - range.location)
        let safe = NSRange(location: range.location, length: safeLen)
        var runs: AttributeRunSnapshot = []
        storage.enumerateAttributes(in: safe, options: []) { attrs, r, _ in
            if r.length > 0 { runs.append((r, attrs)) }
        }
        return runs
    }
    
    private static func unionRange(of snapshot: AttributeRunSnapshot) -> NSRange {
        guard let first = snapshot.first?.range else { return NSRange(location: 0, length: 0) }
        var minLoc = first.location
        var maxEnd = first.location + first.length
        for run in snapshot.dropFirst() {
            minLoc = min(minLoc, run.range.location)
            maxEnd = max(maxEnd, run.range.location + run.range.length)
        }
        return NSRange(location: minLoc, length: max(0, maxEnd - minLoc))
    }
    
    private static func applySnapshot(
        _ snapshot: AttributeRunSnapshot,
        to textView: UITextView,
        restoringSelection selection: NSRange
    ) {
        let storage = textView.textStorage
        let current = snapshot.isEmpty ? [] : snapshotAttributes(in: storage, range: unionRange(of: snapshot))
        if let um = textView.undoManager {
            um.registerUndo(withTarget: textView) { tv in
                applySnapshot(current, to: tv, restoringSelection: selection)
            }
        }
        
        storage.beginEditing()
        for (r, attrs) in snapshot {
            let maxLen = storage.length
            guard r.location < maxLen else { continue }
            let safeLen = min(r.length, maxLen - r.location)
            guard safeLen > 0 else { continue }
            storage.setAttributes(attrs, range: NSRange(location: r.location, length: safeLen))
        }
        storage.endEditing()
        if selection.location <= storage.length {
            textView.selectedRange = selection
        }
    }
    
    static func handleReturn(in textView: EditorTextView) -> Bool {
        let lineR = textView.currentLineRange()
        let ns = textView.attributedText.string as NSString
        let allText = String(ns)
        let line = ns.substring(with: lineR)
        let lead = WordListLineKind.leadingPrefix(line)
        let L = WordListLineKind.listLevel(leading: lead)
        let cAfter = String(line.dropFirst(lead.count))
        let lineIndex = (allText as NSString).substring(to: min(lineR.location, (allText as NSString).length))
            .filter { $0 == "\n" }.count
        let docLines = (allText as NSString).components(separatedBy: "\n")
        func clearEmptyListLine() {
            textView.textStorage.beginEditing()
            textView.textStorage.replaceCharacters(in: lineR, with: "")
            textView.textStorage.endEditing()
            textView.selectedRange = NSRange(location: lineR.location, length: 0)
        }
        if (line as NSString).range(of: "^\\s*[•◦▪] ", options: .regularExpression).location != NSNotFound,
           let match = try? NSRegularExpression(pattern: #"^[•◦▪] "#).firstMatch(in: cAfter, options: [], range: NSRange(location: 0, length: (cAfter as NSString).length)) {
            let afterB = (cAfter as NSString).substring(from: match.range.length).trimmingCharacters(in: .whitespacesAndNewlines)
            if afterB.isEmpty { clearEmptyListLine(); return true }
            let mark = WordListLineKind.bulletMark(forLevel: L)
            textView.insertText("\n\(lead)\(mark)"); return true
        }
        if (line as NSString).range(of: "^\\s*\\d+\\) ", options: .regularExpression).location != NSNotFound,
           let re = try? NSRegularExpression(pattern: #"^(\d+)\)\s"#),
           let m = re.firstMatch(in: cAfter, options: [], range: NSRange(location: 0, length: (cAfter as NSString).length)),
           let dRange = Range(m.range(at: 1), in: cAfter),
           let d = Int(String(cAfter[dRange])) {
            let after = (cAfter as NSString).substring(from: m.range.length).trimmingCharacters(in: .whitespacesAndNewlines)
            if after.isEmpty { clearEmptyListLine(); return true }
            textView.insertText("\n\(lead)\(d + 1)) ")
            return true
        }
        if (line as NSString).range(of: "^\\s*[a-z]\\) ", options: .regularExpression).location != NSNotFound,
           let re = try? NSRegularExpression(pattern: #"^([a-z])\)\s"#),
           let m = re.firstMatch(in: cAfter, options: [], range: NSRange(location: 0, length: (cAfter as NSString).length)),
           let chRange = Range(m.range(at: 1), in: cAfter) {
            let ch = cAfter[chRange].first ?? "a"
            let after = (cAfter as NSString).substring(from: m.range.length).trimmingCharacters(in: .whitespacesAndNewlines)
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
        if (line as NSString).range(of: "^\\s*\\d+\\. ", options: .regularExpression).location != NSNotFound,
           let re = try? NSRegularExpression(pattern: #"^(\d+)\.\s"#),
           let m = re.firstMatch(in: cAfter, options: [], range: NSRange(location: 0, length: (cAfter as NSString).length)),
           let dRange = Range(m.range(at: 1), in: cAfter) {
            let dStr = String(cAfter[dRange])
            let after = (cAfter as NSString).substring(from: m.range.length).trimmingCharacters(in: .whitespacesAndNewlines)
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
    
    static func apply(_ action: MarkdownAction, to textView: UITextView, coordinator coord: MarkdownEditor.Coordinator) {
        let range = textView.selectedRange
        let hasSelection = range.length > 0

        if action == .bulletList || action == .numberedList {
            applyListAction(action, tv: textView)
            return
        }

        if action == .indent || action == .outdent {
            applyIndentAction(action, tv: textView)
            return
        }

        if action == .header1 || action == .header2 || action == .header3 {
            applyHeader(action, tv: textView)
            return
        }

        if hasSelection {
            let ns = textView.textStorage.string as NSString
            let affectedRange: NSRange = {
                switch action {
                case .removeFormat:
                    return ns.paragraphRange(for: range)
                case .alignLeft, .alignCenter, .alignRight:
                    return ns.paragraphRange(for: range)
                default:
                    return range
                }
            }()
            let before = snapshotAttributes(in: textView.textStorage, range: affectedRange)
            if let um = textView.undoManager, !before.isEmpty {
                let sel = range
                um.registerUndo(withTarget: textView) { tv in
                    applySnapshot(before, to: tv, restoringSelection: sel)
                }
            }
            
            let storage = textView.textStorage
            storage.beginEditing()
            switch action {
            case .bold: toggleFontTraitWordStyle(.traitBold, in: storage, range: range)
            case .italic: toggleFontTraitWordStyle(.traitItalic, in: storage, range: range)
            case .underline: toggleKeyWordStyle(.underlineStyle, value: NSUnderlineStyle.single.rawValue, in: storage, range: range, isSet: { ($0 as? Int) == NSUnderlineStyle.single.rawValue })
            case .strikethrough: toggleKeyWordStyle(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, in: storage, range: range, isSet: { ($0 as? Int) == NSUnderlineStyle.single.rawValue })
            case .removeFormat:
                removeAllFormatting(in: storage, range: range)
                coord.typingModes.removeAll()
            case .alignLeft, .alignCenter, .alignRight:
                let a: NSTextAlignment = (action == .alignLeft) ? .left : (action == .alignCenter ? .center : .right)
                setTextAlignmentForAllLinesCovered(storage: storage, fullSelectedRange: range, alignment: a)
            default: break
            }
            storage.endEditing()
            textView.selectedRange = range
            
            let caretLocation = range.location + range.length
            let len = textView.attributedText.length
            let idx = max(0, min(max(0, caretLocation - 1), max(0, len - 1)))
            let caretAttrs = len > 0 ? textView.attributedText.attributes(at: idx, effectiveRange: nil) : textView.typingAttributes
            coord.setTypingModesFromAttributes(caretAttrs, in: textView)
        } else {
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
    
    private static func applyAlignmentToCurrentLine(_ alignment: NSTextAlignment, tv: UITextView) {
        let lineR = (tv as? EditorTextView)?.currentLineRange() ?? tv.selectedRange
        let ns = tv.textStorage.string as NSString
        let para = ns.paragraphRange(for: lineR)
        let before = snapshotAttributes(in: tv.textStorage, range: para)
        if let um = tv.undoManager, !before.isEmpty {
            let sel = tv.selectedRange
            um.registerUndo(withTarget: tv) { textView in
                applySnapshot(before, to: textView, restoringSelection: sel)
            }
        }
        
        let storage = tv.textStorage
        storage.beginEditing()
        setTextAlignment(alignment, in: storage, range: para)
        storage.endEditing()
        setCaretAlignment(alignment, in: tv)
    }
    
    // MARK: - Multiline selection (Word: apply to every selected line)
    
    private static func lineRangesCoveredBySelection(_ full: NSString, _ sel: NSRange) -> [NSRange] {
        guard full.length > 0 else { return [NSRange(location: 0, length: 0)] }
        if sel.length == 0 {
            let pos = min(max(0, sel.location), full.length)
            return [full.lineRange(for: NSRange(location: pos, length: 0))]
        }
        let endChar = min(max(0, NSMaxRange(sel) - 1), max(0, full.length - 1))
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
            if remove == 0 {
                let asNSString = line as NSString
                let r = NSRange(line.startIndex..<line.endIndex, in: line)
                let isBullet = asNSString.range(of: "^\\s*[•◦▪] ", options: .regularExpression, range: r).location != NSNotFound
                let isNumber = asNSString.range(of: "^\\s*\\d+\\. ", options: .regularExpression, range: r).location != NSNotFound
                    || asNSString.range(of: "^\\s*\\d+\\) ", options: .regularExpression, range: r).location != NSNotFound
                    || asNSString.range(of: "^\\s*[a-z]\\) ", options: .regularExpression, range: r).location != NSNotFound
                if isBullet { return removeListMarkerForToggle(line, bullet: true) }
                if isNumber { return removeListMarkerForToggle(line, bullet: false) }
                return line
            }
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
    
    private static func setTextAlignmentForAllLinesCovered(
        storage: NSTextStorage, fullSelectedRange: NSRange, alignment: NSTextAlignment
    ) {
        let ns = storage.string as NSString
        let lrs = lineRangesCoveredBySelection(ns, fullSelectedRange)
        var seen = Set<String>()
        for lr in lrs {
            let loc = min(lr.location, max(0, storage.length - 1))
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            let key = "\(pr.location)|\(pr.length)"
            if seen.insert(key).inserted {
                setTextAlignment(alignment, in: storage, range: pr)
            }
        }
    }

    // MARK: Headers (Word-style: same heading again reverts the line to body text)
    
    private static func headerSpec(_ action: MarkdownAction) -> (size: CGFloat, weight: UIFont.Weight) {
        let base = EditorTheme.baseFont.pointSize
        switch action {
        case .header1: return (round(base * 1.55), .bold)
        case .header2: return (round(base * 1.30), .semibold)
        case .header3: return (round(base * 1.10), .semibold)
        default: return (base, .regular)
        }
    }
    
    private static let headerLineSpacing: CGFloat = 6
    private static let headerParagraphBefore: CGFloat = 8
    private static let headerParagraphAfter: CGFloat = 8
    
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
    
    fileprivate static func bodyParagraphStyle(preservingAlignment align: NSTextAlignment = .natural) -> NSParagraphStyle {
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
        let storage = tv.textStorage
        let full = storage.string as NSString
        let lrs = lineRangesCoveredBySelection(full, sel)
        guard !lrs.isEmpty else { return }

        if lrs.count > 1, storage.length > 0 {
            let checkLines = lrs.filter { $0.length > 0 && $0.location < storage.length }
            let turnToBody = !checkLines.isEmpty && checkLines.allSatisfy { isSameHeadingLine(m: storage, lineR: $0, as: action) }

            storage.beginEditing()
            for lr in lrs {
                if lr.length == 0, lr.location >= storage.length { continue }
                if lr.length == 0 { continue }
                if turnToBody {
                    var align: NSTextAlignment = .natural
                    if storage.length > 0, lr.location < storage.length,
                       let p = storage.attribute(.paragraphStyle, at: lr.location, effectiveRange: nil) as? NSParagraphStyle {
                        align = p.alignment
                    }
                    storage.addAttributes([
                        .font: EditorTheme.baseFont,
                        .foregroundColor: EditorTheme.textColor,
                        .paragraphStyle: bodyParagraphStyle(preservingAlignment: align)
                    ], range: lr)
                } else {
                    let at = min(lr.location, max(0, storage.length - 1))
                    let existingAttrs = storage.attributes(at: at, effectiveRange: nil)
                    var merged = existingAttrs
                    merged[.font] = UIFont.systemFont(ofSize: spec.size, weight: spec.weight)
                    merged[.foregroundColor] = (existingAttrs[.foregroundColor] as? UIColor) ?? EditorTheme.textColor
                    let existingStyle = existingAttrs[.paragraphStyle] as? NSParagraphStyle
                    let style = (existingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                    style.lineSpacing = headerLineSpacing
                    style.paragraphSpacingBefore = headerParagraphBefore
                    style.paragraphSpacing = headerParagraphAfter
                    merged[.paragraphStyle] = style
                    storage.addAttributes(merged, range: lr)
                }
            }
            storage.endEditing()

            var ta = tv.typingAttributes
            if turnToBody {
                ta[.font] = EditorTheme.baseFont
                ta[.paragraphStyle] = bodyParagraphStyle(preservingAlignment: (ta[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .natural)
            } else {
                ta[.font] = UIFont.systemFont(ofSize: spec.size, weight: spec.weight)
            }
            tv.typingAttributes = ta

            if let br = blockRangeForLineRanges(lrs), br.location + br.length <= storage.length {
                tv.selectedRange = NSRange(location: br.location, length: br.length)
            } else {
                tv.selectedRange = NSRange(location: sel.location, length: sel.length)
            }
            return
        }

        let lineR = lrs[0]

        if storage.length > 0, lineR.length > 0, lineR.location < storage.length, isSameHeadingLine(m: storage, lineR: lineR, as: action) {
            var align: NSTextAlignment = .natural
            if let p = storage.attribute(.paragraphStyle, at: lineR.location, effectiveRange: nil) as? NSParagraphStyle {
                align = p.alignment
            }
            storage.beginEditing()
            storage.addAttributes([
                .font: EditorTheme.baseFont,
                .foregroundColor: EditorTheme.textColor,
                .paragraphStyle: bodyParagraphStyle(preservingAlignment: align)
            ], range: lineR)
            storage.endEditing()

            var ta = tv.typingAttributes
            ta[.font] = EditorTheme.baseFont
            ta[.paragraphStyle] = bodyParagraphStyle(preservingAlignment: align)
            tv.typingAttributes = ta
            tv.selectedRange = NSRange(location: lineR.location, length: 0)
            return
        }

        guard storage.length > 0, lineR.length > 0, lineR.location < storage.length else {
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

        let existingAttrs = storage.attributes(at: lineR.location, effectiveRange: nil)
        var merged = existingAttrs
        merged[.font] = UIFont.systemFont(ofSize: spec.size, weight: spec.weight)
        merged[.foregroundColor] = (existingAttrs[.foregroundColor] as? UIColor) ?? EditorTheme.textColor

        let existingStyle = existingAttrs[.paragraphStyle] as? NSParagraphStyle
        let style = (existingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.lineSpacing = headerLineSpacing
        style.paragraphSpacingBefore = headerParagraphBefore
        style.paragraphSpacing = headerParagraphAfter
        merged[.paragraphStyle] = style

        storage.beginEditing()
        storage.addAttributes(merged, range: lineR)
        storage.endEditing()

        if sel.length > 0, let br = blockRangeForLineRanges(lrs), br.location + br.length <= storage.length {
            tv.selectedRange = NSRange(location: br.location, length: br.length)
        } else {
            tv.selectedRange = NSRange(location: lineR.location, length: 0)
        }
    }

    // MARK: Lists (Word-style: same control swaps list type or toggles; never stack markers)
    
    fileprivate static func listMarkerPrefixUTF16Length(_ line: String) -> Int? {
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
    
    fileprivate static func removeListMarkerForToggle(_ line: String, bullet: Bool) -> String {
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
        let storage = tv.textStorage
        let full = storage.string as NSString
        let lrs = lineRangesCoveredBySelection(full, range)
        guard !lrs.isEmpty else { return }

        storage.beginEditing()
        defer { storage.endEditing() }
        
        if lrs.count > 1, let br = blockRangeForLineRanges(lrs) {
            let oldBlock = full.substring(with: br) as String
            let raw = stringLinesFromBlock(full, lrs)
            var newLines = raw.map { transformListLine($0, action: action) }
            
            if action == .numberedList {
                let fullText = storage.string as NSString
                let docLines = fullText.components(separatedBy: "\n")
                let startLineIdx = fullText.substring(to: min(br.location, fullText.length)).filter { $0 == "\n" }.count
                
                var nextNumberByIndent: [String: Int] = [
                    "": WordListLineKind.nextTopLevelDecimal(before: startLineIdx, lines: docLines)
                ]
                
                func renumberDecimalLineIfNeeded(_ line: String) -> String {
                    let indent = leadingSpacePrefix(line)
                    let afterIndent = String(line.dropFirst(indent.count))
                    let nsAfter = afterIndent as NSString
                    let decRange = nsAfter.range(of: #"^\d+\. "#, options: .regularExpression)
                    guard decRange.location != NSNotFound else { return line }
                    
                    let current = nextNumberByIndent[indent] ?? 1
                    nextNumberByIndent[indent] = current + 1
                    let rest = nsAfter.substring(from: decRange.location + decRange.length)
                    return indent + "\(current). " + rest
                }
                
                newLines = newLines.map(renumberDecimalLineIfNeeded)
            }
            let newBlock = newLines.joined(separator: "\n")
            guard newBlock != oldBlock else { return }
            storage.replaceCharacters(in: br, with: newBlock)
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
        storage.replaceCharacters(in: lineRange, with: newStored)
        let newCursorInLine = newCursorInLineAfterListEdit(
            oldLine: line, newLine: newCore, cursorInLine: cursorInLine, pOld: pOld, pNew: pNew
        )
        let nCore = (newCore as NSString).length
        let clamped = min(max(0, newCursorInLine), nCore)
        let off = min(clamped, (newStored as NSString).length)
        tv.selectedRange = NSRange(location: min(lineRange.location + off, storage.length), length: 0)
    }

    // MARK: Indent/Outdent (Word-style: work on any line, not only lists; 4 spaces = one level)

    private static func applyIndentAction(_ action: MarkdownAction, tv: UITextView) {
        let range = tv.selectedRange
        let storage = tv.textStorage
        let full = storage.string as NSString
        let lrs = lineRangesCoveredBySelection(full, range)
        guard !lrs.isEmpty else { return }
        let outdent = (action == .outdent)
        let str = storage.string
        let docLines = (str as NSString).components(separatedBy: "\n")
        
        storage.beginEditing()
        defer { storage.endEditing() }
        
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
            storage.replaceCharacters(in: br, with: newBlock)
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
        storage.replaceCharacters(in: lineRange, with: newStored)
        let delta = (newLine as NSString).length - (line as NSString).length
        tv.selectedRange = NSRange(
            location: min(max(0, range.location + delta), storage.length), length: 0
        )
    }

    // MARK: Alignment

    private static func setTextAlignment(_ alignment: NSTextAlignment, in m: NSMutableAttributedString, range: NSRange) {
        let ns = m.string as NSString
        let paraRange = ns.paragraphRange(for: range)
        
        let existingStyle = m.attribute(.paragraphStyle, at: paraRange.location, effectiveRange: nil) as? NSParagraphStyle
        let style = (existingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.alignment = alignment
        m.addAttribute(.paragraphStyle, value: style, range: paraRange)
    }

    private static func setTextAlignment(_ alignment: NSTextAlignment, in storage: NSTextStorage, range: NSRange) {
        let ns = storage.string as NSString
        let paraRange = ns.paragraphRange(for: range)
        
        let existingStyle = storage.attribute(.paragraphStyle, at: paraRange.location, effectiveRange: nil) as? NSParagraphStyle
        let style = (existingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.alignment = alignment
        storage.addAttribute(.paragraphStyle, value: style, range: paraRange)
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
    
    private static func toggleFontTraitWordStyle(
        _ trait: UIFontDescriptor.SymbolicTraits,
        in storage: NSTextStorage,
        range: NSRange
    ) {
        let allHave = allRunsInRangeHaveFontTrait(storage, range: range, trait: trait)
        let enable = !allHave
        storage.enumerateAttribute(.font, in: range, options: []) { f, r, _ in
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
            storage.addAttribute(.font, value: newFont, range: r)
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
    
    private static func toggleKeyWordStyle(
        _ key: NSAttributedString.Key,
        value: Int,
        in storage: NSTextStorage,
        range: NSRange,
        isSet: (Any?) -> Bool
    ) {
        var all = true
        storage.enumerateAttribute(key, in: range, options: []) { existing, r, _ in
            if r.length == 0 { return }
            if !isSet(existing) { all = false }
        }
        if all {
            storage.removeAttribute(key, range: range)
        } else {
            storage.addAttribute(key, value: value, range: range)
        }
    }


    private static func removeAllFormatting(in m: NSMutableAttributedString, range: NSRange) {
        let ns = m.string as NSString
        let paraRange = ns.paragraphRange(for: range)
        
        m.setAttributes([
            .font: EditorTheme.baseFont,
            .foregroundColor: EditorTheme.textColor
        ], range: paraRange)
        
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 0
        style.paragraphSpacingBefore = 0
        style.paragraphSpacing = 0
        style.alignment = .natural
        m.addAttribute(.paragraphStyle, value: style, range: paraRange)
    }
    
    private static func removeAllFormatting(in storage: NSTextStorage, range: NSRange) {
        let ns = storage.string as NSString
        let paraRange = ns.paragraphRange(for: range)
        
        storage.setAttributes([
            .font: EditorTheme.baseFont,
            .foregroundColor: EditorTheme.textColor
        ], range: paraRange)
        
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 0
        style.paragraphSpacingBefore = 0
        style.paragraphSpacing = 0
        style.alignment = .natural
        storage.addAttribute(.paragraphStyle, value: style, range: paraRange)
    }

}

// MARK: - SwiftUI Toolbar (Cleaner Layout)

struct MarkdownToolbarView: View {
    var coordinator: MarkdownEditor.Coordinator?
    @State private var alignmentMenuIcon = "text.alignleft"
    @State private var headingMenuTitle = "H"

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    toolbarButton("B", .bold, label: "Bold", hint: "Toggles bold on the selection or next typing")
                    toolbarButton("I", .italic, label: "Italic", hint: "Toggles italic on the selection or next typing")
                    toolbarButton("U", .underline, label: "Underline", hint: "Toggles underline on the selection or next typing")
                    toolbarButton("S", .strikethrough, label: "Strikethrough", hint: "Toggles strikethrough on the selection or next typing")
                    toolbarButton("⦸", .removeFormat, label: "Remove formatting", hint: "Clears character styles in the selection")
                }
                
                Rectangle()
                    .fill(DesignSystem.Colors.border)
                    .frame(width: 1, height: 24)
                
                Menu {
                    Button {
                        coordinator?.handleMarkdownAction(.header1)
                    } label: {
                        Label("Header 1", systemImage: coordinator?.toolbarHeadingLevel() == 1 ? "checkmark.circle.fill" : "circle")
                    }
                    Button {
                        coordinator?.handleMarkdownAction(.header2)
                    } label: {
                        Label("Header 2", systemImage: coordinator?.toolbarHeadingLevel() == 2 ? "checkmark.circle.fill" : "circle")
                    }
                    Button {
                        coordinator?.handleMarkdownAction(.header3)
                    } label: {
                        Label("Header 3", systemImage: coordinator?.toolbarHeadingLevel() == 3 ? "checkmark.circle.fill" : "circle")
                    }
                } label: {
                    Text(headingMenuTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .background(DesignSystem.Colors.backgroundTertiary)
                        .cornerRadius(DesignSystem.CornerRadius.sm)
                }
                .accessibilityLabel("Headings")
                .accessibilityHint("Choose heading level for the current line")
                
                Rectangle()
                    .fill(DesignSystem.Colors.border)
                    .frame(width: 1, height: 24)
                
                HStack(spacing: 6) {
                    toolbarButton("•", .bulletList, label: "Bullet list", hint: "Starts or continues a bullet list")
                    toolbarButton("1.", .numberedList, label: "Numbered list", hint: "Starts or continues a numbered list")
                    toolbarButton("→", .indent, label: "Indent", hint: "Indents the current list item")
                    toolbarButton("←", .outdent, label: "Outdent", hint: "Outdents the current list item")
                }
                
                Rectangle()
                    .fill(DesignSystem.Colors.border)
                    .frame(width: 1, height: 24)
                
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
                    Image(systemName: alignmentMenuIcon)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 32, height: 32)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .background(DesignSystem.Colors.backgroundTertiary)
                        .cornerRadius(DesignSystem.CornerRadius.sm)
                }
                .accessibilityLabel("Text alignment")
                .accessibilityHint("Opens alignment options for the current paragraph")
                
                Rectangle()
                    .fill(DesignSystem.Colors.border)
                    .frame(width: 1, height: 24)
                
                Menu {
                    if coordinator?.canUseNotePhotos == true {
                        Button(action: { coordinator?.presentNotePhotoPicker() }) {
                            Label("Photo", systemImage: "photo")
                        }
                    }
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
                
                HStack(spacing: 6) {
                    toolbarButton("↶", .undo, label: "Undo", hint: "Undoes the last edit")
                    toolbarButton("↷", .redo, label: "Redo", hint: "Redoes the last undo")
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
        .onAppear { refreshToolbarChrome() }
        .onReceive(NotificationCenter.default.publisher(for: .editorActiveStylesDidChange)) { output in
            guard let c = coordinator, (output.object as AnyObject?) === (c as AnyObject?) else { return }
            refreshToolbarChrome()
        }
    }

    private func refreshToolbarChrome() {
        alignmentMenuIcon = coordinator?.toolbarAlignmentSystemImage() ?? "text.alignleft"
        if let level = coordinator?.toolbarHeadingLevel() {
            headingMenuTitle = "H\(level)"
        } else {
            headingMenuTitle = "H"
        }
    }
    
    private func toolbarButton(_ title: String, _ action: MarkdownAction, label: String, hint: String) -> some View {
        ToolbarButton(title: title, action: action, coordinator: coordinator, accessibilityLabel: label, accessibilityHint: hint)
    }
}

struct ToolbarButton: View {
    let title: String
    let action: MarkdownAction
    var coordinator: MarkdownEditor.Coordinator?
    @State private var isSelected = false
    @State private var isEnabled = true
    var accessibilityLabel: String
    var accessibilityHint: String?

    private var combinedAccessibilityLabel: String {
        if let hint = accessibilityHint, !hint.isEmpty {
            return "\(accessibilityLabel). \(hint)"
        }
        return accessibilityLabel
    }
    
    var body: some View {
        Button {
            coordinator?.handleMarkdownAction(action)  
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 32, height: 32)
                .foregroundColor(foregroundColor)
                .background(backgroundColor)
                .cornerRadius(DesignSystem.CornerRadius.sm)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(combinedAccessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .onAppear { refreshEnabledState() }
        .onReceive(NotificationCenter.default.publisher(for: .editorActiveStylesDidChange)) { output in
            guard let c = coordinator, (output.object as AnyObject?) === (c as AnyObject?) else { return }
            if let set = output.userInfo?["styles"] as? Set<MarkdownAction> {
                isSelected = set.contains(action)
            } else if action != .undo && action != .redo {
                isSelected = false
            }
            refreshEnabledState()
        }
    }

    private var foregroundColor: Color {
        if isSelected { return DesignSystem.Colors.textInverse }
        return DesignSystem.Colors.textPrimary
    }

    private var backgroundColor: Color {
        if isSelected { return DesignSystem.Colors.accent }
        return DesignSystem.Colors.backgroundTertiary
    }

    private func refreshEnabledState() {
        guard action == .undo || action == .redo else {
            isEnabled = true
            return
        }
        guard let tv = coordinator?.textView, let um = tv.undoManager else {
            isEnabled = false
            return
        }
        isEnabled = (action == .undo) ? um.canUndo : um.canRedo
    }
}

// MARK: - PHPicker (note photos)

extension MarkdownEditor.Coordinator: PHPickerViewControllerDelegate, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer.name == Self.notePhotoSizingTapGestureName, let tv = textView else { return true }
        let pt = touch.location(in: tv)
        return Self.photoAttachmentRange(at: pt, in: tv) != nil
    }

    nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let coord = self
        let firstResult = results.first
        DispatchQueue.main.async {
            picker.dismiss(animated: true)
            guard let r = firstResult else { return }
            if r.itemProvider.canLoadObject(ofClass: UIImage.self) {
                r.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    guard let image = object as? UIImage else { return }
                    Task { @MainActor in
                        await coord.uploadAndInsertPhoto(image)
                    }
                }
            }
        }
    }
}

#endif
