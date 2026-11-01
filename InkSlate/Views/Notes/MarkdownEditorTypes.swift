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
    /// Record names of every note photo this editor knows about (in the text or removed but not yet purged).
    func allTrackedPhotoRecordNames() -> Set<String>
    func serializeContent(from attributed: NSAttributedString) -> String
    func currentSerializedContent() -> String?
    func currentImageUrlsJSON() -> String?
}
