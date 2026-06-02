import Foundation
import CoreData
#if canImport(UIKit)
import UIKit
#endif

enum SharedImportManager {
    static let appGroupID = "group.com.lucas.InkSlateNew"
    private static let pendingPayloadFilename = "pending-share-import.json"

    struct Payload: Codable {
        var title: String?
        var content: String
        var createdAt: Date
    }
    
    struct AttachmentItem: Codable {
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
    
    struct PayloadV2: Codable {
        var title: String?
        var createdAt: Date
        var items: [AttachmentItem]
    }

    static func handleIncomingURL(_ url: URL, in context: NSManagedObjectContext) {
        guard url.scheme == "inksln" else { return }
        guard url.host == "import" else { return }
        importPendingPayload(in: context)
    }

    static func importPendingPayload(in context: NSManagedObjectContext) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return
        }

        let payloadURL = containerURL.appendingPathComponent(pendingPayloadFilename, isDirectory: false)
        guard let data = try? Data(contentsOf: payloadURL) else { return }
        
        let decoder = JSONDecoder()
        let payloadV2 = try? decoder.decode(PayloadV2.self, from: data)
        let payloadV1 = payloadV2 == nil ? (try? decoder.decode(Payload.self, from: data)) : nil
        guard payloadV2 != nil || payloadV1 != nil else { return }

        context.perform {
            let projectFetch = NSFetchRequest<FSProject>(entityName: "FSProject")
            projectFetch.fetchLimit = 1
            projectFetch.predicate = NSPredicate(format: "isDefault == YES")
            let defaultProject = (try? context.fetch(projectFetch))?.first

            let anyProjectFetch = NSFetchRequest<FSProject>(entityName: "FSProject")
            anyProjectFetch.fetchLimit = 1
            let fallbackProject = (try? context.fetch(anyProjectFetch))?.first

            let newNote = Notes(context: context)
            newNote.id = UUID()
            
            let title: String? = {
                if let v2 = payloadV2 { return v2.title }
                return payloadV1?.title
            }()
            let createdAt: Date = {
                if let v2 = payloadV2 { return v2.createdAt }
                return payloadV1?.createdAt ?? Date()
            }()
            
            newNote.title = (title?.isEmpty == false) ? title! : "Imported"

            var contentParts: [String] = []
            var attachmentMetas: [[String: String]] = []
            var attachmentFileCandidates: [(attachmentID: UUID, relativePath: String, filename: String, uti: String?, kind: String)] = []
            
            if let v2 = payloadV2 {
                for item in v2.items {
                    switch item.kind {
                    case .text:
                        if let text = item.text, !text.isEmpty {
                            contentParts.append(text)
                        }
                    case .url:
                        if let url = item.text, !url.isEmpty {
                            contentParts.append(url)
                        }
                    case .image, .file:
                        if let relativePath = item.relativePath {
                            let filename = item.filename ?? "Attachment"
                            let attachmentID = UUID()
                            contentParts.append("[Attachment: \(filename)]")
                            var meta: [String: String] = [
                                "relativePath": relativePath,
                                "filename": filename,
                                "attachmentID": attachmentID.uuidString
                            ]
                            if let uti = item.uti { meta["uti"] = uti }
                            meta["kind"] = item.kind.rawValue
                            attachmentMetas.append(meta)
                            attachmentFileCandidates.append(
                                (attachmentID: attachmentID, relativePath: relativePath, filename: filename, uti: item.uti, kind: item.kind.rawValue)
                            )
                        }
                    }
                }
            } else if let v1 = payloadV1 {
                contentParts.append(v1.content)
            }
            
            newNote.content = contentParts.joined(separator: "\n\n")
            newNote.project = defaultProject ?? fallbackProject
            newNote.isMarkedDeleted = false
            newNote.createdDate = createdAt
            newNote.modifiedDate = Date()

            if !attachmentMetas.isEmpty, let json = try? JSONSerialization.data(withJSONObject: attachmentMetas, options: []) {
                newNote.attachments = String(data: json, encoding: .utf8)
            }
            
            let plain = MarkdownSerialization.plainText(from: newNote.content ?? "")
            newNote.preview = String(plain.prefix(100))

            var didSave = false
            do {
                if context.hasChanges {
                    for object in context.insertedObjects {
                        object.ensureCloudKitMetadata()
                    }
                    try context.save()
                }
                didSave = true
            } catch {
                didSave = false
            }
            if didSave {
                try? FileManager.default.removeItem(at: payloadURL)
                
// Upload any share-import attachments to CloudKit so they sync across devices.
                if let noteID = newNote.id, !attachmentFileCandidates.isEmpty {
                    let noteObjectID = newNote.objectID
                    Task {
                        await uploadShareImportAttachments(
                            containerURL: containerURL,
                            noteObjectID: noteObjectID,
                            noteID: noteID,
                            items: attachmentFileCandidates
                        )
                    }
                }
            }
        }
    }
}

private extension SharedImportManager {
    static func uploadShareImportAttachments(
        containerURL: URL,
        noteObjectID: NSManagedObjectID,
        noteID: UUID,
        items: [(attachmentID: UUID, relativePath: String, filename: String, uti: String?, kind: String)]
    ) async {
// Upload using CloudKit; update Core Data afterwards on a background context.
        var uploaded: [[String: String]] = []
        
        for item in items {
            let sourceURL = containerURL.appendingPathComponent(item.relativePath, isDirectory: false)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            
            var uploadURL = sourceURL
            var uploadFilename = item.filename
            var tempUploadURLToDelete: URL?
            
            #if canImport(UIKit)
            if item.kind == "image" {
                let maxBytes = 5 * 1024 * 1024
                if let img = UIImage(contentsOfFile: sourceURL.path),
                   let jpeg = img.inkSlateJPEGDataFitting(maxBytes: maxBytes) {
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("jpg")
                    do {
                        try jpeg.write(to: tmp, options: .atomic)
                        uploadURL = tmp
                        tempUploadURLToDelete = tmp
                        uploadFilename = uploadFilename.isEmpty ? "Image.jpg" : uploadFilename
                        if (uploadFilename as NSString).pathExtension.isEmpty {
                            uploadFilename += ".jpg"
                        }
                    } catch {
                    }
                }
            }
            #endif
            do {
                let rk = try await CloudKitAssetService.shared.uploadNoteAttachment(
                    fileURL: uploadURL,
                    noteID: noteID,
                    attachmentID: item.attachmentID,
                    filename: uploadFilename,
                    uti: item.uti,
                    kind: item.kind
                )
                var meta: [String: String] = [
                    "recordName": rk,
                    "filename": uploadFilename,
                    "attachmentID": item.attachmentID.uuidString,
                    "kind": item.kind
                ]
                if let uti = item.uti { meta["uti"] = uti }
                uploaded.append(meta)
                
                if let tmp = tempUploadURLToDelete {
                    try? FileManager.default.removeItem(at: tmp)
                }
                try? FileManager.default.removeItem(at: sourceURL)
            } catch {
                if let tmp = tempUploadURLToDelete {
                    try? FileManager.default.removeItem(at: tmp)
                }
                continue
            }
        }
        
        guard !uploaded.isEmpty else { return }
        
        let ctx = PersistenceController.shared.backgroundContext()
        await ctx.perform {
            guard let note = try? ctx.existingObject(with: noteObjectID) as? Notes else { return }
            
            var merged: [[String: String]] = []
            if let existing = note.attachments,
               let data = existing.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
                merged.append(contentsOf: arr)
            }
            merged.append(contentsOf: uploaded)
            
            if let data = try? JSONSerialization.data(withJSONObject: merged, options: []),
               let s = String(data: data, encoding: .utf8) {
                note.attachments = s
                note.modifiedDate = Date()
                if ctx.hasChanges {
                    for object in ctx.insertedObjects {
                        object.ensureCloudKitMetadata()
                    }
                    try? ctx.save()
                }
            }
        }
    }
}

