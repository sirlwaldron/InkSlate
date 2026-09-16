#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MarkdownEditorMac: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var coordinatorRef: Coordinator?
    var autoFocusOnAppear: Bool = false
    var noteCloudKitID: UUID? = nil
    var notePhotosDisabled: Bool = false
    var onPhotoIndexChanged: ((String?) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = MacEditorTextView()
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 10, height: 13)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.delegate = context.coordinator
        textView.owningCoordinator = context.coordinator

        scrollView.documentView = textView
        context.coordinator.textView = textView

        let attributed = context.coordinator.deserializeContent(text)
        textView.textStorage?.setAttributedString(attributed)
        context.coordinator.refreshKnownPhotoRecordNames(from: textView.attributedString())
        context.coordinator.lastPublishedSerialized = text
        NotePhotoCloudHydrator.hydrate(textView: textView)
        context.coordinator.applyTypingAttributes(in: textView)

        if autoFocusOnAppear {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MacEditorTextView else { return }
        context.coordinator.parent = self
        context.coordinator.textView = textView
        guard textView.window?.firstResponder !== textView else { return }

        if context.coordinator.lastPublishedSerialized == text {
            return
        }

        let latest = context.coordinator.serializeContent(from: textView.attributedString())
        if latest == text {
            context.coordinator.lastPublishedSerialized = text
            return
        }

        if NotePhotoAttachment.hasHydratedPhotos(in: textView.attributedString()) {
            let incomingPlain = MarkdownSerialization.searchablePlainText(from: text)
            let currentPlain = MarkdownSerialization.searchablePlainText(from: latest)
            let incomingPhotos = Set(NotePhotoRefCollector.recordNames(fromSerialized: text))
            let currentPhotos = NotePhotoRefCollector.recordNames(in: textView.attributedString())
            if incomingPlain == currentPlain && incomingPhotos == currentPhotos {
                context.coordinator.lastPublishedSerialized = text
                return
            }
        }

        DispatchQueue.main.async {
            guard textView.window?.firstResponder !== textView else { return }
            if context.coordinator.lastPublishedSerialized == text { return }
            let range = textView.selectedRange()
            let attributed = context.coordinator.deserializeContent(text)
            textView.textStorage?.setAttributedString(attributed)
            context.coordinator.refreshKnownPhotoRecordNames(from: textView.attributedString())
            context.coordinator.lastPublishedSerialized = text
            NotePhotoCloudHydrator.hydrate(textView: textView)
            let len = textView.attributedString().length
            if len == 0 {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            } else {
                let maxR = NSMaxRange(range)
                if maxR <= len {
                    textView.setSelectedRange(range)
                } else {
                    let loc = min(range.location, len)
                    let end = min(maxR, len)
                    textView.setSelectedRange(NSRange(location: loc, length: max(0, end - loc)))
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        let coord = Coordinator(self)
        coordinatorRef = coord
        return coord
    }

    final class Coordinator: NSObject, NSTextViewDelegate, MarkdownEditorCoordinating {
        var parent: MarkdownEditorMac
        weak var textView: MacEditorTextView?
        private var isProgrammaticChange = false
        var lastPublishedSerialized: String?
        private var hasPendingUserEdit = false
        private(set) var lastKnownPhotoRecordNames: Set<String> = []
        private var pendingPhotoDeletions: Set<String> = []
        fileprivate var typingModes = Set<MarkdownAction>()

        init(_ parent: MarkdownEditorMac) {
            self.parent = parent
        }

        var editorUndoManager: UndoManager? { textView?.undoManager }

        var canUseNotePhotos: Bool {
            parent.noteCloudKitID != nil && !parent.notePhotosDisabled
        }

        func deserializeContent(_ text: String) -> NSAttributedString {
            let width = textView.map { NotePhotoAttachment.textColumnWidth(for: $0) } ?? 320
            if let (attr, _) = MarkdownSerialization.deserialize(text, maxWidth: width) {
                let mutable = NSMutableAttributedString(attributedString: attr)
                NotePhotoAttachment.repairAttachmentBounds(in: mutable, columnWidth: width)
                return mutable
            }
            return EditorContentParser.deserialize(text, maxWidth: width)
        }

        func serializeContent(from attributed: NSAttributedString) -> String {
            MarkdownSerialization.serialize(attributed)
        }

        func refreshKnownPhotoRecordNames(from attributed: NSAttributedString) {
            lastKnownPhotoRecordNames = NotePhotoRefCollector.recordNames(in: attributed)
        }

        func consumePendingUserEdit() -> Bool {
            let pending = hasPendingUserEdit
            hasPendingUserEdit = false
            return pending
        }

        func flushPendingEditsToParent() {
            guard let tv = textView else { return }
            let serialized = serializeContent(from: tv.attributedString())
            lastPublishedSerialized = serialized
            parent.text = serialized
            parent.selectedRange = tv.selectedRange()
        }

        func applyExternalSerializedContent(_ text: String) {
            guard let tv = textView else { return }
            isProgrammaticChange = true
            defer { isProgrammaticChange = false }
            let attributed = deserializeContent(text)
            tv.textStorage?.setAttributedString(attributed)
            refreshKnownPhotoRecordNames(from: tv.attributedString())
            applyTypingAttributes(in: tv)
            postStyleChange(in: tv)
        }

        func commitPendingPhotoDeletions() {
            let pending = pendingPhotoDeletions
            pendingPhotoDeletions.removeAll()
            guard !pending.isEmpty else { return }
            Task {
                for name in pending {
                    NotePhotoDiskCache.remove(recordName: name)
                    NotePhotoSync.dequeuePending(recordName: name)
                    try? await CloudKitAssetService.shared.deleteNotePhoto(recordName: name)
                }
            }
        }

        func currentSerializedContent() -> String? {
            guard let tv = textView else { return nil }
            return serializeContent(from: tv.attributedString())
        }

        func currentImageUrlsJSON() -> String? {
            guard let tv = textView else { return nil }
            return NotePhotoRefCollector.jsonIndex(for: tv.attributedString())
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticChange, let tv = textView, !NotePhotoCloudHydrator.isHydrating(tv) else { return }
            hasPendingUserEdit = true
            let serialized = serializeContent(from: tv.attributedString())
            lastPublishedSerialized = serialized
            parent.text = serialized
            parent.selectedRange = tv.selectedRange()
            refreshKnownPhotoRecordNames(from: tv.attributedString())
            postStyleChange(in: tv)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.selectedRange = tv.selectedRange()
            postStyleChange(in: tv)
        }

        func handleMarkdownAction(_ action: MarkdownAction) {
            guard let tv = textView else { return }

            switch action {
            case .undo:
                tv.undoManager?.undo()
                syncFromTextView(tv)
                return
            case .redo:
                tv.undoManager?.redo()
                syncFromTextView(tv)
                return
            default:
                break
            }

            isProgrammaticChange = true
            defer { isProgrammaticChange = false }
            MacWysiwygActionHandler.apply(action, to: tv, coordinator: self)
            syncFromTextView(tv)

            if action == .link {
                promptForLink(tv)
            }
        }
        
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let string = replacementString else { return true }
            
            if string == " ", affectedCharRange.length == 0 {
                let full = textView.attributedString().string as NSString
                if affectedCharRange.location <= full.length {
                    let lineR = full.lineRange(for: NSRange(location: affectedCharRange.location, length: 0))
                    let textBeforeCursor = full.substring(with: NSRange(location: lineR.location, length: affectedCharRange.location - lineR.location))
                    if textBeforeCursor.range(of: "^[ \t]*[-*+]$", options: .regularExpression) != nil {
                        let action: MarkdownAction = .bulletList
                        isProgrammaticChange = true
                        defer { isProgrammaticChange = false }
                        textView.textStorage?.replaceCharacters(in: NSRange(location: lineR.location, length: affectedCharRange.location - lineR.location), with: "")
                        let newRange = NSRange(location: lineR.location, length: 0)
                        textView.setSelectedRange(newRange)
                        MacWysiwygActionHandler.apply(action, to: textView, coordinator: self)
                        syncFromTextView(textView)
                        return false
                    } else if textBeforeCursor.range(of: "^[ \t]*\\d+\\.$", options: .regularExpression) != nil {
                        let action: MarkdownAction = .numberedList
                        isProgrammaticChange = true
                        defer { isProgrammaticChange = false }
                        textView.textStorage?.replaceCharacters(in: NSRange(location: lineR.location, length: affectedCharRange.location - lineR.location), with: "")
                        let newRange = NSRange(location: lineR.location, length: 0)
                        textView.setSelectedRange(newRange)
                        MacWysiwygActionHandler.apply(action, to: textView, coordinator: self)
                        syncFromTextView(textView)
                        return false
                    }
                }
            }
            return true
        }

        private func syncFromTextView(_ tv: NSTextView) {
            parent.text = serializeContent(from: tv.attributedString())
            parent.selectedRange = tv.selectedRange()
            postStyleChange(in: tv)
        }

        private func postStyleChange(in tv: NSTextView) {
            NotificationCenter.default.post(
                name: .editorActiveStylesDidChange,
                object: self,
                userInfo: ["styles": currentActiveStyles(in: tv)]
            )
        }

        func currentActiveStyles(in tv: NSTextView) -> Set<MarkdownAction> {
            var styles = typingModes
            let range = tv.selectedRange()
            guard tv.attributedString().length > 0 else { return styles }
            let idx = max(0, min(range.location, tv.attributedString().length - 1))
            let attrs = tv.attributedString().attributes(at: idx, effectiveRange: nil)
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.bold) { styles.insert(.bold) }
                if traits.contains(.italic) { styles.insert(.italic) }
            }
            if let ul = attrs[.underlineStyle] as? Int, ul == NSUnderlineStyle.single.rawValue {
                styles.insert(.underline)
            }
            if let st = attrs[.strikethroughStyle] as? Int, st == NSUnderlineStyle.single.rawValue {
                styles.insert(.strikethrough)
            }
            return styles
        }

        func toggleTypingMode(_ action: MarkdownAction) {
            typingModes.formSymmetricDifference([action])
            if let tv = textView { applyTypingAttributes(in: tv) }
        }

        func clearTypingModes() {
            typingModes.removeAll()
            if let tv = textView { applyTypingAttributes(in: tv) }
        }

        func applyTypingAttributes(in tv: NSTextView) {
            var attrs: [NSAttributedString.Key: Any] = [
                .font: EditorTheme.baseFont,
                .foregroundColor: EditorTheme.textColor
            ]
            if typingModes.contains(.bold) {
                attrs[.font] = EditorTheme.font(size: EditorTheme.baseFont.pointSize, weight: .bold)
            }
            if typingModes.contains(.italic), let f = attrs[.font] as? NSFont {
                let d = f.fontDescriptor.withSymbolicTraits([.italic])
                attrs[.font] = NSFont(descriptor: d, size: f.pointSize) ?? f
            }
            if typingModes.contains(.underline) {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if typingModes.contains(.strikethrough) {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            tv.typingAttributes = attrs
        }

        func toolbarAlignmentSystemImage() -> String {
            guard let tv = textView else { return "text.alignleft" }
            let range = tv.selectedRange()
            guard tv.attributedString().length > 0 else { return "text.alignleft" }
            let idx = max(0, min(range.location, tv.attributedString().length - 1))
            let ps = tv.attributedString().attribute(.paragraphStyle, at: idx, effectiveRange: nil) as? NSParagraphStyle
            switch ps?.alignment {
            case .center: return "text.aligncenter"
            case .right: return "text.alignright"
            default: return "text.alignleft"
            }
        }

        func toolbarHeadingLevel() -> Int? {
            guard let tv = textView else { return nil }
            let range = tv.selectedRange()
            guard tv.attributedString().length > 0 else { return nil }
            let idx = max(0, min(range.location, tv.attributedString().length - 1))
            guard let font = tv.attributedString().attribute(.font, at: idx, effectiveRange: nil) as? NSFont else { return nil }
            let base = EditorTheme.baseFont.pointSize
            let size = font.pointSize
            if size >= base * 1.45 { return 1 }
            if size >= base * 1.25 { return 2 }
            if size >= base * 1.1 { return 3 }
            return nil
        }

        func presentNotePhotoPicker() {
            guard canUseNotePhotos, let tv = textView else { return }
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.begin { response in
                guard response == .OK, let url = panel.url,
                      let image = NSImage(contentsOf: url) else { return }
                Task { @MainActor in
                    await self.uploadAndInsertPhoto(image, in: tv)
                }
            }
        }

        @MainActor
        private func uploadAndInsertPhoto(_ image: NSImage, in tv: NSTextView) async {
            guard let noteID = parent.noteCloudKitID else { return }

            let uploadImage: NSImage
            if let data = image.inkSlateJPEGDataFitting(maxBytes: 5 * 1024 * 1024),
               let normalized = NSImage(data: data) {
                uploadImage = normalized
            } else {
                uploadImage = image
            }

            let attachmentID = UUID()
            let recordName = "NotePhoto-\(attachmentID.uuidString)"
            NotePhotoDiskCache.save(uploadImage, recordName: recordName)

            let width = NotePhotoAttachment.textColumnWidth(for: tv)
            let sz = NotePhotoAttachment.displaySize(for: uploadImage, width: width)
            let att = NSTextAttachment()
            att.image = NotePhotoAttachment.displayImageForInlineEditor(uploadImage)
            att.bounds = CGRect(origin: .zero, size: sz)
            let meta: [AnyHashable: Any] = [
                NotePhotoAttachment.dictRecordKey: recordName,
                NotePhotoAttachment.dictWidthKey: NSNumber(value: Double(width))
            ]
            let attachmentString = NSAttributedString(attachment: att)
            let mutable = NSMutableAttributedString(attributedString: attachmentString)
            mutable.addAttribute(.inkSlateNotePhoto, value: meta, range: NSRange(location: 0, length: mutable.length))
            tv.textStorage?.insert(mutable, at: tv.selectedRange().location)
            syncFromTextView(tv)

            do {
                _ = try await CloudKitAssetService.shared.uploadNotePhoto(
                    uploadImage,
                    noteID: noteID,
                    attachmentID: attachmentID
                )
                NotePhotoSync.dequeuePending(recordName: recordName)
            } catch {
                NotePhotoSync.enqueuePending(recordName: recordName, noteID: noteID)
                ErrorHandlingService.shared.reportOperationFailure(
                    module: "Notes",
                    detail: "Photo added on this device, but iCloud sync failed. It will retry automatically."
                )
            }
        }

        private func promptForLink(_ tv: NSTextView) {
            let alert = NSAlert()
            alert.messageText = "Add Link"
            alert.informativeText = "Enter a URL"
            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            input.placeholderString = "https://example.com"
            alert.accessoryView = input
            alert.addButton(withTitle: "Add")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                var urlString = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !urlString.isEmpty && !urlString.contains("://") { urlString = "https://" + urlString }
                guard !urlString.isEmpty, let url = URL(string: urlString), url.scheme != nil else { return }
                let range = tv.selectedRange()
                let linkAttributes: [NSAttributedString.Key: Any] = [
                    .link: url,
                    .foregroundColor: EditorTheme.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
                if range.length > 0 {
                    tv.textStorage?.addAttributes(linkAttributes, range: range)
                } else {
                    // No selection: insert the host (or the URL itself) as linked text, like iOS.
                    let linkText = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host ?? urlString
                    let insertion = NSAttributedString(string: linkText, attributes: linkAttributes)
                    tv.textStorage?.insert(insertion, at: min(range.location, tv.textStorage?.length ?? 0))
                    tv.setSelectedRange(NSRange(location: range.location + insertion.length, length: 0))
                }
                syncFromTextView(tv)
            }
        }
    }
}

final class MacEditorTextView: NSTextView {
    weak var owningCoordinator: MarkdownEditorMac.Coordinator?
}

enum MacWysiwygActionHandler {
    static func apply(_ action: MarkdownAction, to textView: NSTextView, coordinator: MarkdownEditorMac.Coordinator) {
        let range = textView.selectedRange()
        let storage = textView.textStorage
        guard let storage else { return }

        switch action {
        case .bold, .italic, .underline, .strikethrough:
            guard range.length > 0 else {
                coordinator.toggleTypingMode(action)
                return
            }
            storage.beginEditing()
            storage.enumerateAttributes(in: range, options: []) { attrs, r, _ in
                var newAttrs = attrs
                switch action {
                case .bold:
                    if let font = attrs[.font] as? NSFont {
                        var traits = font.fontDescriptor.symbolicTraits
                        if traits.contains(.bold) { traits.remove(.bold) } else { traits.insert(.bold) }
                        let d = font.fontDescriptor.withSymbolicTraits(traits)
                        newAttrs[.font] = NSFont(descriptor: d, size: font.pointSize) ?? font
                    }
                case .italic:
                    if let font = attrs[.font] as? NSFont {
                        var traits = font.fontDescriptor.symbolicTraits
                        if traits.contains(.italic) { traits.remove(.italic) } else { traits.insert(.italic) }
                        let d = font.fontDescriptor.withSymbolicTraits(traits)
                        newAttrs[.font] = NSFont(descriptor: d, size: font.pointSize) ?? font
                    }
                case .underline:
                    let current = (attrs[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue
                    newAttrs[.underlineStyle] = current ? 0 : NSUnderlineStyle.single.rawValue
                case .strikethrough:
                    let current = (attrs[.strikethroughStyle] as? Int) == NSUnderlineStyle.single.rawValue
                    newAttrs[.strikethroughStyle] = current ? 0 : NSUnderlineStyle.single.rawValue
                default: break
                }
                storage.setAttributes(newAttrs, range: r)
            }
            storage.endEditing()
        case .removeFormat:
            // With no selection, only reset typing attributes (matches iOS; never wipe the whole note).
            if range.length > 0 {
                storage.setAttributes([
                    .font: EditorTheme.baseFont,
                    .foregroundColor: EditorTheme.textColor
                ], range: range)
            }
            coordinator.clearTypingModes()
        case .header1, .header2, .header3:
            let size: CGFloat
            switch action {
            case .header1: size = EditorTheme.baseFont.pointSize * 1.5
            case .header2: size = EditorTheme.baseFont.pointSize * 1.3
            case .header3: size = EditorTheme.baseFont.pointSize * 1.15
            default: size = EditorTheme.baseFont.pointSize
            }
            let para = (storage.string as NSString).paragraphRange(for: range)
            storage.addAttribute(.font, value: EditorTheme.font(size: size, weight: .bold), range: para)
        case .alignLeft, .alignCenter, .alignRight:
            let para = (storage.string as NSString).paragraphRange(for: range)
            let style = NSMutableParagraphStyle()
            style.alignment = action == .alignLeft ? .left : (action == .alignCenter ? .center : .right)
            storage.addAttribute(.paragraphStyle, value: style, range: para)
        case .bulletList, .numberedList:
            let full = storage.string as NSString
            let lrs = WysiwygActionHandler.lineRangesCoveredBySelection(full, range)
            guard !lrs.isEmpty else { return }

            storage.beginEditing()
            if lrs.count > 1, let br = WysiwygActionHandler.blockRangeForLineRanges(lrs) {
                let raw = WysiwygActionHandler.stringLinesFromBlock(full, lrs)
                var newLines = raw.map { WysiwygActionHandler.transformListLine($0, action: action) }
                if action == .numberedList {
                    let docLines = full.components(separatedBy: "\n")
                    let startLineIdx = full.substring(to: min(br.location, full.length)).filter { $0 == "\n" }.count
                    var nextNumberByIndent: [String: Int] = [
                        "": WysiwygActionHandler.nextTopLevelDecimal(before: startLineIdx, lines: docLines)
                    ]
                    func renumberDecimalLineIfNeeded(_ line: String) -> String {
                        let indent = WysiwygActionHandler.leadingSpacePrefix(line)
                        let afterIndent = String(line.dropFirst(indent.count))
                        let nsAfter = afterIndent as NSString
                        let decRange = nsAfter.range(of: "^\\d+\\. ", options: .regularExpression)
                        guard decRange.location != NSNotFound else { return line }
                        let current = nextNumberByIndent[indent] ?? 1
                        nextNumberByIndent[indent] = current + 1
                        let rest = nsAfter.substring(from: decRange.location + decRange.length)
                        return indent + "\(current). " + rest
                    }
                    newLines = newLines.map(renumberDecimalLineIfNeeded)
                }
                let newBlock = newLines.joined(separator: "\n")
                if newBlock != full.substring(with: br) {
                    storage.replaceCharacters(in: br, with: newBlock)
                    let newLen = (newBlock as NSString).length
                    textView.setSelectedRange(NSRange(location: br.location, length: newLen))
                }
            } else {
                let lineRange = lrs[0]
                let raw = full.substring(with: lineRange) as String
                let hadTrailingNewline = raw.hasSuffix("\n")
                let line = hadTrailingNewline ? String(raw.dropLast()) : raw
                var cursorInLine = max(0, range.location - lineRange.location)
                cursorInLine = min(cursorInLine, (line as NSString).length)
                if hadTrailingNewline, range.location >= lineRange.location + (line as NSString).length {
                    cursorInLine = (line as NSString).length
                }
                let newCore = WysiwygActionHandler.transformListLine(line, action: action)
                if newCore != line {
                    let newStored = newCore + (hadTrailingNewline ? "\n" : "")
                    let pOld = WysiwygActionHandler.listMarkerPrefixUTF16Length(line) ?? 0
                    let pNew = WysiwygActionHandler.listMarkerPrefixUTF16Length(newCore) ?? 0
                    storage.replaceCharacters(in: lineRange, with: newStored)
                    let newCursorInLine = WysiwygActionHandler.newCursorInLineAfterListEdit(
                        oldLine: line, newLine: newCore, cursorInLine: cursorInLine, pOld: pOld, pNew: pNew
                    )
                    let nCore = (newCore as NSString).length
                    let clamped = min(max(0, newCursorInLine), nCore)
                    let off = min(clamped, (newStored as NSString).length)
                    textView.setSelectedRange(NSRange(location: min(lineRange.location + off, storage.length), length: 0))
                }
            }
            storage.endEditing()
        default:
            break
        }
    }
}

struct MarkdownPreviewTextViewMac: NSViewRepresentable {
    let content: String
    var preferredColumnWidth: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainer?.containerSize = NSSize(width: preferredColumnWidth, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        if let (attr, _) = MarkdownSerialization.deserialize(content, maxWidth: preferredColumnWidth) {
            textView.textStorage?.setAttributedString(attr)
        } else {
            textView.string = content
        }
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if let (attr, _) = MarkdownSerialization.deserialize(content, maxWidth: preferredColumnWidth) {
            textView.textStorage?.setAttributedString(attr)
        } else {
            textView.string = content
        }
    }
}

enum WysiwygActionHandler {
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

    static func lineRangesCoveredBySelection(_ full: NSString, _ sel: NSRange) -> [NSRange] {
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

    static func blockRangeForLineRanges(_ lrs: [NSRange]) -> NSRange? {
        guard let f = lrs.first, let l = lrs.last else { return nil }
        return NSRange(location: f.location, length: NSMaxRange(l) - f.location)
    }

    static func stringLinesFromBlock(_ full: NSString, _ lrs: [NSRange]) -> [String] {
        lrs.map { r in
            var s = full.substring(with: r) as String
            if s.hasSuffix("\n") { s = String(s.dropLast()) }
            return s
        }
    }

    static func convertNumberedLineToBulletLine(_ line: String) -> String {
        let n = line as NSString
        let r1 = n.range(of: "^\\s*\\d+\\. ", options: .regularExpression)
        if r1.location != NSNotFound { return n.replacingCharacters(in: r1, with: leadingSpacePrefix(line) + "• ") }
        let r2 = n.range(of: "^\\s*\\d+\\) ", options: .regularExpression)
        if r2.location != NSNotFound { return n.replacingCharacters(in: r2, with: leadingSpacePrefix(line) + "• ") }
        let r3 = n.range(of: "^\\s*[a-z]\\) ", options: .regularExpression)
        if r3.location != NSNotFound { return n.replacingCharacters(in: r3, with: leadingSpacePrefix(line) + "◦ ") }
        return line
    }

    static func convertBulletLineToNumberedLine(_ line: String) -> String {
        let n = line as NSString
        let r1 = n.range(of: "^\\s*• ", options: .regularExpression)
        if r1.location != NSNotFound { return n.replacingCharacters(in: r1, with: leadingSpacePrefix(line) + "1. ") }
        let r2 = n.range(of: "^\\s*◦ ", options: .regularExpression)
        if r2.location != NSNotFound { return n.replacingCharacters(in: r2, with: leadingSpacePrefix(line) + "a) ") }
        let r3 = n.range(of: "^\\s*▪ ", options: .regularExpression)
        if r3.location != NSNotFound { return n.replacingCharacters(in: r3, with: leadingSpacePrefix(line) + "1) ") }
        return line
    }

    static func addListMarkerToPlainLine(_ line: String, numbered: Bool) -> String {
        let sp = leadingSpacePrefix(line)
        let core = String(line.dropFirst(sp.count))
        if numbered { return sp + "1. " + core }
        return sp + "• " + core
    }

    static func transformListLine(_ line: String, action: MarkdownAction) -> String {
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

    static func listMarkerPrefixUTF16Length(_ line: String) -> Int? {
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

    static func leadingSpacePrefix(_ line: String) -> String {
        String(line.prefix(while: { $0 == " " }))
    }

    static func removeListMarkerForToggle(_ line: String, bullet: Bool) -> String {
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

    static func newCursorInLineAfterListEdit(oldLine: String, newLine: String, cursorInLine: Int, pOld: Int, pNew: Int) -> Int {
        if cursorInLine < pOld {
            return min(cursorInLine, pNew)
        }
        let diff = pNew - pOld
        return cursorInLine + diff
    }
}
#endif
