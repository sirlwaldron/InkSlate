import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let appGroupID = "group.com.lucas.InkSlateNew"
    private let pendingPayloadDirectoryName = "pending-share-imports"
    private let attachmentsFolderName = "share-import-attachments"

    struct AttachmentItem: Codable {
        enum Kind: String, Codable {
            case text
            case url
            case file
            case image
            case rich
        }

        var kind: Kind
        var text: String?
        var relativePath: String?
        var filename: String?
        var uti: String?
    }

    private struct PayloadV2: Codable {
        var title: String?
        var createdAt: Date
        var items: [AttachmentItem]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        Task { @MainActor in
            await handleShare()
        }
    }

    @MainActor
    private func handleShare() async {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish()
            return
        }

        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            finish()
            return
        }

        var title = extensionTitle(from: extensionItems)

        let providers = extensionItems.flatMap { $0.attachments ?? [] }

        // Prefer the rich attributed content so formatting (bullets, bold, headings)
        // survives all the way into InkSlate's editor.
        var richSource = extensionItems.compactMap(\.attributedContentText).first { $0.length > 0 }
        if richSource == nil {
            richSource = await loadFirstAttributedContent(from: providers)
        }

        var editorBody: NSAttributedString? = richSource.map { ShareImportFormatting.editorAttributedString(from: $0) }
        if let converted = editorBody, converted.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            editorBody = nil
        }

        var body: String? = editorBody?.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if body == nil {
            if let text = await loadFirstText(from: providers) {
                body = text
            } else if let urlString = await loadFirstURLString(from: providers) {
                body = urlString
            }
        }

        if body == nil {
            if let saved = await saveFirstImage(from: providers, containerURL: containerURL) {
                await presentSharePreview(containerURL: containerURL, title: title, items: [saved], richBody: nil)
                return
            }
            if let saved = await saveFirstFile(from: providers, containerURL: containerURL) {
                await presentSharePreview(containerURL: containerURL, title: title, items: [saved], richBody: nil)
                return
            }
            finish()
            return
        }

        if title == nil {
            title = inferredTitle(from: body!)
        } else if let title, bodyHasLeadingTitle(title, in: body!) {
            if let rich = editorBody {
                let stripped = strippingLeadingTitle(title, from: rich)
                editorBody = stripped
                body = stripped.string.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                body = stripLeadingTitle(title, from: body!)
            }
        }

        let item = AttachmentItem(
            kind: .text,
            text: body,
            relativePath: nil,
            filename: nil,
            uti: UTType.plainText.identifier
        )
        await presentSharePreview(containerURL: containerURL, title: title, items: [item], richBody: editorBody)
    }

    private func extensionTitle(from items: [NSExtensionItem]) -> String? {
        for item in items {
            if let title = item.attributedTitle?.string.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                return title
            }
        }
        return nil
    }

    private func inferredTitle(from body: String) -> String? {
        let lines = body.components(separatedBy: .newlines)
        guard let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty else {
            return nil
        }
        guard first.count <= 120, !first.contains("\n") else { return nil }
        if first.hasPrefix("#") { return first.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
        return first
    }

    private func bodyHasLeadingTitle(_ title: String, in body: String) -> Bool {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedBody.hasPrefix(title)
    }

    private func stripLeadingTitle(_ title: String, from body: String) -> String {
        var remainder = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if remainder.hasPrefix(title) {
            remainder.removeFirst(title.count)
            remainder = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            if remainder.hasPrefix("\n") {
                remainder.removeFirst()
            }
        }
        return remainder
    }

    private func strippingLeadingTitle(_ title: String, from attributed: NSAttributedString) -> NSAttributedString {
        let full = attributed.string as NSString
        guard full.length > 0 else { return attributed }
        let firstParagraphRange = full.paragraphRange(for: NSRange(location: 0, length: 0))
        let firstLine = full.substring(with: firstParagraphRange).trimmingCharacters(in: .whitespacesAndNewlines)
        guard firstLine == title.trimmingCharacters(in: .whitespacesAndNewlines) else { return attributed }

        let mutable = NSMutableAttributedString(attributedString: attributed)
        mutable.deleteCharacters(in: firstParagraphRange)
        while mutable.string.hasPrefix("\n") {
            mutable.deleteCharacters(in: NSRange(location: 0, length: 1))
        }
        return mutable
    }

    private func loadFirstAttributedContent(from providers: [NSItemProvider]) async -> NSAttributedString? {
        let richTypes: [UTType] = [
            .rtf,
            .rtfd,
            .html,
            UTType("com.apple.flat-rtfd") ?? .rtfd
        ]

        for provider in providers {
            for type in richTypes {
                guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { continue }
                if let attributed = await loadAttributedItem(from: provider, typeIdentifier: type.identifier) {
                    return attributed
                }
            }
        }
        return nil
    }

    private func loadAttributedItem(from provider: NSItemProvider, typeIdentifier: String) async -> NSAttributedString? {
        do {
            let item = try await provider.loadItem(forTypeIdentifier: typeIdentifier)

            if let data = item as? Data,
               let attributed = ShareImportFormatting.attributedString(from: data, typeIdentifier: typeIdentifier) {
                return attributed
            }

            if let url = item as? URL {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

                if let data = try? Data(contentsOf: url),
                   let attributed = ShareImportFormatting.attributedString(from: data, typeIdentifier: typeIdentifier) {
                    return attributed
                }
                if let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil),
                   attributed.length > 0 {
                    return attributed
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func loadFirstText(from providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            for type in [UTType.plainText, UTType.text] {
                guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { continue }
                do {
                    let item = try await provider.loadItem(forTypeIdentifier: type.identifier)
                    if let string = item as? String {
                        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { return trimmed }
                    }
                    if let url = item as? URL,
                       let string = try? String(contentsOf: url, encoding: .utf8) {
                        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { return trimmed }
                    }
                } catch {
                    continue
                }
            }
        }
        return nil
    }

    private func loadFirstURLString(from providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { continue }
            do {
                let item = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
                if let url = item as? URL { return url.absoluteString }
                if let string = item as? String { return string }
            } catch {
                continue
            }
        }
        return nil
    }

    private func safeFilename(_ filename: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return UUID().uuidString }
        return trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func ensureAttachmentsDirectory(containerURL: URL) throws -> URL {
        let dir = containerURL.appendingPathComponent(attachmentsFolderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func uniqueAttachmentFilename(base: String, fileExtension: String?) -> String {
        let id = UUID().uuidString
        let baseName = safeFilename(base)
        if let fileExtension, !fileExtension.isEmpty {
            return "\(baseName)-\(id).\(fileExtension)"
        }
        return "\(baseName)-\(id)"
    }

    private func saveDataToAttachments(
        data: Data,
        preferredFilename: String,
        fileExtension: String?,
        containerURL: URL
    ) throws -> (relativePath: String, filename: String) {
        let attachmentsDir = try ensureAttachmentsDirectory(containerURL: containerURL)
        let filename = uniqueAttachmentFilename(base: preferredFilename, fileExtension: fileExtension)
        let fileURL = attachmentsDir.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: fileURL, options: [.atomic])
        return (relativePath: "\(attachmentsFolderName)/\(filename)", filename: filename)
    }

    private func saveFileToAttachments(
        fileURL: URL,
        containerURL: URL
    ) throws -> (relativePath: String, filename: String) {
        let attachmentsDir = try ensureAttachmentsDirectory(containerURL: containerURL)
        let ext = fileURL.pathExtension.isEmpty ? nil : fileURL.pathExtension
        let filename = uniqueAttachmentFilename(base: fileURL.deletingPathExtension().lastPathComponent, fileExtension: ext)
        let destURL = attachmentsDir.appendingPathComponent(filename, isDirectory: false)
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { fileURL.stopAccessingSecurityScopedResource() }
        }
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.copyItem(at: fileURL, to: destURL)
        return (relativePath: "\(attachmentsFolderName)/\(filename)", filename: filename)
    }

    private func saveFirstImage(from providers: [NSItemProvider], containerURL: URL) async -> AttachmentItem? {
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { continue }
            do {
                let item = try await provider.loadItem(forTypeIdentifier: UTType.image.identifier)
                if let url = item as? URL {
                    let saved = try saveFileToAttachments(fileURL: url, containerURL: containerURL)
                    return AttachmentItem(kind: .image, text: nil, relativePath: saved.relativePath, filename: saved.filename, uti: UTType.image.identifier)
                }
                if let image = item as? UIImage, let data = image.jpegData(compressionQuality: 0.92) {
                    let saved = try saveDataToAttachments(data: data, preferredFilename: "Image", fileExtension: "jpg", containerURL: containerURL)
                    return AttachmentItem(kind: .image, text: nil, relativePath: saved.relativePath, filename: saved.filename, uti: UTType.jpeg.identifier)
                }
                if let data = item as? Data {
                    let saved = try saveDataToAttachments(data: data, preferredFilename: "Image", fileExtension: "img", containerURL: containerURL)
                    return AttachmentItem(kind: .image, text: nil, relativePath: saved.relativePath, filename: saved.filename, uti: UTType.image.identifier)
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func saveFirstFile(from providers: [NSItemProvider], containerURL: URL) async -> AttachmentItem? {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                do {
                    let item = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
                    if let url = item as? URL {
                        let saved = try saveFileToAttachments(fileURL: url, containerURL: containerURL)
                        return AttachmentItem(kind: .file, text: nil, relativePath: saved.relativePath, filename: saved.filename, uti: UTType.fileURL.identifier)
                    }
                } catch {
                    continue
                }
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                do {
                    let item = try await provider.loadItem(forTypeIdentifier: UTType.pdf.identifier)
                    if let url = item as? URL {
                        let saved = try saveFileToAttachments(fileURL: url, containerURL: containerURL)
                        return AttachmentItem(kind: .file, text: nil, relativePath: saved.relativePath, filename: saved.filename, uti: UTType.pdf.identifier)
                    }
                    if let data = item as? Data {
                        let saved = try saveDataToAttachments(data: data, preferredFilename: "Document", fileExtension: "pdf", containerURL: containerURL)
                        return AttachmentItem(kind: .file, text: nil, relativePath: saved.relativePath, filename: saved.filename, uti: UTType.pdf.identifier)
                    }
                } catch {
                    continue
                }
            }
        }
        return nil
    }

    @MainActor
    private func presentSharePreview(containerURL: URL, title: String?, items: [AttachmentItem], richBody: NSAttributedString?) async {
        let initialContent = items.first(where: { $0.kind == .text })?.text ?? ""
        let view = SharePreviewView(
            initialTitle: title ?? "",
            initialContent: initialContent,
            containerURL: containerURL,
            items: items,
            onSave: { [weak self] finalTitle, finalContent in
                guard let self else { return }

                // If the user didn't edit the body, keep the rich version so
                // formatting survives. Otherwise fall back to their edited text.
                var finalItems = items
                var content: String? = finalContent
                if let richBody,
                   finalContent.trimmingCharacters(in: .whitespacesAndNewlines) == initialContent.trimmingCharacters(in: .whitespacesAndNewlines),
                   let saved = try? self.archiveRichBody(richBody, containerURL: containerURL) {
                    finalItems.removeAll { $0.kind == .text }
                    finalItems.insert(
                        AttachmentItem(kind: .rich, text: finalContent, relativePath: saved.relativePath, filename: saved.filename, uti: nil),
                        at: 0
                    )
                    content = nil
                }
                self.writePayloadAndFinish(containerURL: containerURL, title: finalTitle, content: content, items: finalItems)
            },
            onCancel: { [weak self] in
                self?.finish()
            }
        )
        
        let hostingController = UIHostingController(rootView: view)
        hostingController.view.backgroundColor = .clear
        
        self.addChild(hostingController)
        hostingController.view.frame = self.view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
    }

    private func archiveRichBody(_ attributed: NSAttributedString, containerURL: URL) throws -> (relativePath: String, filename: String) {
        let data = try NSKeyedArchiver.archivedData(withRootObject: attributed, requiringSecureCoding: false)
        return try saveDataToAttachments(data: data, preferredFilename: "RichNote", fileExtension: "richnote", containerURL: containerURL)
    }

    private func writePayloadAndFinish(containerURL: URL, title: String?, content: String?, items: [AttachmentItem]) {
        var finalItems = items
        if let textIndex = finalItems.firstIndex(where: { $0.kind == .text }) {
            finalItems[textIndex].text = content
        } else if let content = content, !content.isEmpty {
            finalItems.append(AttachmentItem(kind: .text, text: content, relativePath: nil, filename: nil, uti: UTType.plainText.identifier))
        }
        
        let payload = PayloadV2(title: title, createdAt: Date(), items: finalItems)
        let dir = containerURL.appendingPathComponent(pendingPayloadDirectoryName, isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        let payloadURL = dir.appendingPathComponent(UUID().uuidString + ".json", isDirectory: false)

        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: payloadURL, options: [.atomic])
        } catch {
            print("Failed to save pending import: \(error)")
            finish()
            return
        }

        openHostAppAndFinish()
    }

    /// Opens the main InkSlate app so the shared note appears immediately.
    /// `NSExtensionContext.open` is only officially supported from Today widgets,
    /// so fall back to walking the responder chain and performing `openURL:`.
    private func openHostAppAndFinish() {
        guard let url = URL(string: "inksln://import") else {
            finish()
            return
        }

        if let context = extensionContext {
            context.open(url) { [weak self] success in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if success {
                        self.finish()
                    } else {
                        self.openViaResponderChain(url)
                        // Give the openURL: call a moment before tearing down the extension.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            self.finish()
                        }
                    }
                }
            }
        } else {
            openViaResponderChain(url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.finish()
            }
        }
    }

    private func openViaResponderChain(_ url: URL) {
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector), !(current is UIViewController) {
                current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
import SwiftUI

struct SharePreviewView: View {
    @State var initialTitle: String
    @State var initialContent: String
    let containerURL: URL
    let items: [ShareViewController.AttachmentItem]
    
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Title")) {
                    TextField("Optional title", text: $initialTitle)
                        .font(.headline)
                }
                
                Section(header: Text("Note Content")) {
                    TextEditor(text: $initialContent)
                        .frame(minHeight: 200)
                        .font(.body)
                }
                
                if items.contains(where: { $0.kind == .image || $0.kind == .file }) {
                    Section(header: Text("Attachments")) {
                        ForEach(items.filter { $0.kind == .image || $0.kind == .file }, id: \.filename) { item in
                            HStack {
                                Image(systemName: item.kind == .image ? "photo" : "doc")
                                Text(item.filename ?? "Attachment")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Save to InkSlate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(initialTitle, initialContent)
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}
