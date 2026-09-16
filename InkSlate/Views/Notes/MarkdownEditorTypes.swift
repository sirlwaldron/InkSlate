import Foundation

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

protocol MarkdownEditorCoordinating: AnyObject {
    func handleMarkdownAction(_ action: MarkdownAction)
    func toolbarAlignmentSystemImage() -> String
    func toolbarHeadingLevel() -> Int?
    var canUseNotePhotos: Bool { get }
    func presentNotePhotoPicker()
    var editorUndoManager: UndoManager? { get }
    var lastPublishedSerialized: String? { get }
    func consumePendingUserEdit() -> Bool
    func flushPendingEditsToParent()
    func applyExternalSerializedContent(_ text: String)
    func commitPendingPhotoDeletions()
    func serializeContent(from attributed: NSAttributedString) -> String
    func currentSerializedContent() -> String?
    func currentImageUrlsJSON() -> String?
}
