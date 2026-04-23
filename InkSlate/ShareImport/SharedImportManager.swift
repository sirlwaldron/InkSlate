import Foundation
import CoreData

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
                            contentParts.append("[Attachment: \(filename)]")
                            var meta: [String: String] = ["relativePath": relativePath, "filename": filename]
                            if let uti = item.uti { meta["uti"] = uti }
                            meta["kind"] = item.kind.rawValue
                            attachmentMetas.append(meta)
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

            do {
                try context.save()
                try? FileManager.default.removeItem(at: payloadURL)
            } catch {
                // If save fails, keep payload so user can retry.
            }
        }
    }
}

