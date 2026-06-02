import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let appGroupID = "group.com.lucas.InkSlateNew"
    private let pendingPayloadFilename = "pending-share-import.json"
    private let attachmentsFolderName = "share-import-attachments"

    private struct AttachmentItem: Codable {
        enum Kind: String, Codable {
            case text
            case url
            case file
            case image
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

        let providers = extensionItems.flatMap { $0.attachments ?? [] }

        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            finish()
            return
        }
        
        var items: [AttachmentItem] = []
        
        if let text = await loadFirstRichText(from: providers) {
            items.append(AttachmentItem(kind: .text, text: text, relativePath: nil, filename: nil, uti: UTType.rtf.identifier))
        } else if let text = await loadFirstText(from: providers) {
            items.append(AttachmentItem(kind: .text, text: text, relativePath: nil, filename: nil, uti: UTType.plainText.identifier))
        } else if let urlString = await loadFirstURLString(from: providers) {
            items.append(AttachmentItem(kind: .url, text: urlString, relativePath: nil, filename: nil, uti: UTType.url.identifier))
        }
        
        if items.isEmpty {
            if let saved = await saveFirstImage(from: providers, containerURL: containerURL) {
                items.append(saved)
            } else if let saved = await saveFirstFile(from: providers, containerURL: containerURL) {
                items.append(saved)
            }
        }
        
        if !items.isEmpty {
            await writePayloadAndOpenApp(containerURL: containerURL, title: nil, items: items)
            return
        }

        finish()
    }

    private func loadFirstRichText(from providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.rtf.identifier) {
                if let s = await loadAttributedString(from: provider, typeIdentifier: UTType.rtf.identifier) {
                    return s
                }
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.rtfd.identifier) {
                if let s = await loadAttributedString(from: provider, typeIdentifier: UTType.rtfd.identifier) {
                    return s
                }
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.html.identifier) {
                if let s = await loadAttributedString(from: provider, typeIdentifier: UTType.html.identifier) {
                    return s
                }
            }
        }
        return nil
    }

    private func loadAttributedString(from provider: NSItemProvider, typeIdentifier: String) async -> String? {
        do {
            let item = try await provider.loadItem(forTypeIdentifier: typeIdentifier)

            if let data = item as? Data {
                return attributedStringPlainText(from: data, typeIdentifier: typeIdentifier)
            }

            if let url = item as? URL {
                if let data = try? Data(contentsOf: url) {
                    if let s = attributedStringPlainText(from: data, typeIdentifier: typeIdentifier) {
                        return s
                    }
                }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                if let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
                    let plain = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    return plain.isEmpty ? nil : plain
                }
            }

            if let s = item as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        } catch {
            return nil
        }
        return nil
    }

    private func attributedStringPlainText(from data: Data, typeIdentifier: String) -> String? {
        let type = UTType(typeIdentifier)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = {
            if type == .rtf {
                return [.documentType: NSAttributedString.DocumentType.rtf]
            }
            if type == .rtfd {
                return [.documentType: NSAttributedString.DocumentType.rtfd]
            }
            if type == .html {
                return [.documentType: NSAttributedString.DocumentType.html]
            }
            return [:]
        }()
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            let plain = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return plain.isEmpty ? nil : plain
        }
        return nil
    }

    private func loadFirstText(from providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                do {
                    let item = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
                    if let s = item as? String { return s }
                    if let url = item as? URL, let s = try? String(contentsOf: url, encoding: .utf8) { return s }
                } catch {
                    continue
                }
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                do {
                    let item = try await provider.loadItem(forTypeIdentifier: UTType.text.identifier)
                    if let s = item as? String { return s }
                    if let url = item as? URL, let s = try? String(contentsOf: url, encoding: .utf8) { return s }
                } catch {
                    continue
                }
            }
        }
        return nil
    }

    private func loadFirstURLString(from providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                do {
                    let item = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
                    if let url = item as? URL { return url.absoluteString }
                    if let s = item as? String { return s }
                } catch {
                    continue
                }
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
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
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
    private func writePayloadAndOpenApp(containerURL: URL, title: String?, items: [AttachmentItem]) async {
        let payload = PayloadV2(title: title, createdAt: Date(), items: items)
        let payloadURL = containerURL.appendingPathComponent(pendingPayloadFilename, isDirectory: false)

        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: payloadURL, options: [.atomic])
        } catch {
            finish()
            return
        }

        if let url = URL(string: "inksln://import") {
            _ = await withCheckedContinuation { continuation in
                extensionContext?.open(url, completionHandler: { _ in
                    continuation.resume()
                })
            }
            finish()
        } else {
            finish()
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

