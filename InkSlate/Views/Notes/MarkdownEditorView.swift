import SwiftUI

final class MarkdownEditorCoordinatingRef: ObservableObject {
    weak var value: (any MarkdownEditorCoordinating)?
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

    func updateUIView(_ uiView: UITextView, context: Context) {
        let column = max(60, preferredColumnWidth)
        let width = max(column, 60)
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
