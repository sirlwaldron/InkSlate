import SwiftUI

final class MarkdownEditorCoordinatingRef: ObservableObject {
    weak var value: (any MarkdownEditorCoordinating)? {
        didSet {
            let previous = oldValue as AnyObject?
            let current = value as AnyObject?
            guard previous !== current else { return }
            // makeCoordinator assigns this during the first layout pass. Publish
            // on the next turn so the formatting bar can bind without waiting
            // for the user to type.
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }
}

struct MarkdownEditorView: View {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @ObservedObject var coordinatorRef: MarkdownEditorCoordinatingRef
    var autoFocusOnAppear: Bool = false
    var noteCloudKitID: UUID? = nil
    var notePhotosDisabled: Bool = false
    var onPhotoIndexChanged: ((String?) -> Void)? = nil

    var body: some View {
        #if os(iOS)
        MarkdownEditor(
            text: $text,
            selectedRange: $selectedRange,
            coordinatorRef: Binding(
                get: { coordinatorRef.value as? MarkdownEditor.Coordinator },
                set: { coordinatorRef.value = $0 }
            ),
            autoFocusOnAppear: autoFocusOnAppear,
            noteCloudKitID: noteCloudKitID,
            notePhotosDisabled: notePhotosDisabled,
            onPhotoIndexChanged: onPhotoIndexChanged
        )
        #elseif os(macOS)
        MarkdownEditorMac(
            text: $text,
            selectedRange: $selectedRange,
            coordinatorRef: Binding(
                get: { coordinatorRef.value as? MarkdownEditorMac.Coordinator },
                set: { coordinatorRef.value = $0 }
            ),
            autoFocusOnAppear: autoFocusOnAppear,
            noteCloudKitID: noteCloudKitID,
            notePhotosDisabled: notePhotosDisabled,
            onPhotoIndexChanged: onPhotoIndexChanged
        )
        #endif
    }
}

struct MarkdownPreviewView: View {
    let content: String
    var preferredColumnWidth: CGFloat

    var body: some View {
        #if os(iOS)
        MarkdownPreviewTextView(content: content, preferredColumnWidth: preferredColumnWidth)
        #elseif os(macOS)
        MarkdownPreviewTextViewMac(content: content, preferredColumnWidth: preferredColumnWidth)
        #endif
    }
}

#if os(iOS)
import UIKit

private struct MarkdownPreviewTextView: UIViewRepresentable {
    let content: String
    var preferredColumnWidth: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    /// Remembers what is currently shown so unrelated SwiftUI updates don't re-deserialize and re-layout the note.
    final class Coordinator {
        var lastContent: String?
        var lastColumn: CGFloat = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let column = max(60, preferredColumnWidth)
        let width = max(column, 60)
        if context.coordinator.lastContent == content, context.coordinator.lastColumn == column {
            // Same text and width: keep the existing attributed text; just let pending photos hydrate.
            NotePhotoCloudHydrator.hydrate(textView: uiView, overrideColumnWidth: column)
            return
        }
        context.coordinator.lastContent = content
        context.coordinator.lastColumn = column
        if let (attributed, _) = MarkdownSerialization.deserialize(content, maxWidth: width) {
            let m = NSMutableAttributedString(attributedString: attributed)
            NotePhotoAttachment.repairAttachmentBounds(in: m, columnWidth: column)
            uiView.attributedText = m
            uiView.layoutIfNeeded()
            NotePhotoCloudHydrator.hydrate(textView: uiView, overrideColumnWidth: column)
            DispatchQueue.main.async {
                NotePhotoCloudHydrator.hydrate(textView: uiView, overrideColumnWidth: column)
            }
        } else {
            uiView.attributedText = EditorContentParser.deserialize(content, maxWidth: width)
        }
    }
}
#endif
