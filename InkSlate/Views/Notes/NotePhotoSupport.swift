import Foundation
#if canImport(UIKit)
import UIKit
import os.log

extension Notification.Name {
    static let inkSlateNotePhotoCachesWarmed = Notification.Name("InkSlateNotePhotoCachesWarmed")
}
#endif

// MARK: - Note photo marker (metadata; images not stored in archived content)

extension NSAttributedString.Key {
    static let inkSlateNotePhoto = NSAttributedString.Key("InkSlateNotePhotoRef")
}

enum NotePhotoAttachment {
    static let dictRecordKey = "rk"
    static let dictWidthKey = "w"

    #if canImport(UIKit)
    static var placeholderImage: UIImage {
        let size = CGSize(width: 8, height: 8)
        let r = UIGraphicsImageRenderer(size: size)
        return r.image { ctx in
            UIColor.systemGray4.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    static func textColumnWidth(for textView: UITextView) -> CGFloat {
        let inset = textView.textContainerInset
        let pad = textView.textContainer.lineFragmentPadding
        let inner = textView.bounds.width - inset.left - inset.right - 2 * pad
        let screenCap = max(120, UIScreen.main.bounds.width - 56)
        if inner >= 80 {
            return min(inner, screenCap)
        }
        return min(320, screenCap)
    }

    static func preferredLayoutWidth(storedPoints: CGFloat?, columnWidth: CGFloat) -> CGFloat {
        let col = max(80, columnWidth)
        let cap = min(900, col)
        if let s = storedPoints, s.isFinite, s > 0 {
            return min(max(80, s), cap)
        }
        return cap
    }

    static func displaySize(for image: UIImage?, width: CGFloat) -> CGSize {
        let w = max(44, width)
        let ratio: CGFloat
        if let image, image.size.width > 1, image.size.height > 1 {
            ratio = image.size.height / image.size.width
        } else {
            ratio = 1
        }
        return CGSize(width: w, height: max(44, w * ratio))
    }

    /// Rounded-rect image for inline display (Apple Notes–like), without changing what we JPEG to disk / CloudKit
    static func displayImageForInlineEditor(_ image: UIImage) -> UIImage {
        guard image.size.width > 12, image.size.height > 12 else { return image }
        let r = min(14, min(image.size.width, image.size.height) * 0.035)
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: image.size), cornerRadius: r)
            path.addClip()
            image.draw(at: .zero)
        }
    }

    /// After unarchiving or CloudKit merge, `NSTextAttachment.bounds` can be degenerate while the image is still the 8×8 placeholder — fix using...
    static func repairAttachmentBounds(in storage: NSMutableAttributedString, columnWidth: CGFloat) {
        let col = max(80, columnWidth)
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.inkSlateNotePhoto, in: full, options: []) { value, range, _ in
            guard let d = value as? [AnyHashable: Any],
                  let att = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment
            else { return }
            let stored = (d[dictWidthKey] as? NSNumber).map { CGFloat($0.doubleValue) }
            let w = preferredLayoutWidth(storedPoints: stored, columnWidth: col)
            let sz = displaySize(for: att.image, width: w)
            att.bounds = CGRect(origin: .zero, size: sz)
        }
    }

    static func photoDict(from attributed: NSAttributedString) -> [String: CGFloat] {
        var out: [String: CGFloat] = [:]
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.inkSlateNotePhoto, in: full, options: []) { value, _, _ in
            guard let d = value as? [AnyHashable: Any],
                  let rk = d[dictRecordKey] as? String, !rk.isEmpty else { return }
            let w = (d[dictWidthKey] as? NSNumber)?.doubleValue ?? 280
            out[rk] = w
        }
        return out
    }

    /// Replaces inline images with the shared placeholder before archiving (keeps `content` CloudKit-friendly)
    static func stripHeavyImagesForPersistence(_ src: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: src)
        let full = NSRange(location: 0, length: m.length)
        m.enumerateAttribute(.inkSlateNotePhoto, in: full, options: []) { value, range, _ in
            guard value != nil, range.length > 0 else { return }
            guard let old = m.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment else { return }
            let meta = value as? [AnyHashable: Any]
            let stored = (meta?[dictWidthKey] as? NSNumber).map { CGFloat($0.doubleValue) }
            let b = old.bounds
            let fromBounds = (b.width >= 44 && b.height >= 32) ? b.width : nil
            let pseudoColumn = max(stored ?? fromBounds ?? 360, 360)
            let layoutW = preferredLayoutWidth(storedPoints: stored ?? fromBounds, columnWidth: pseudoColumn)
            let sz = displaySize(for: old.image, width: layoutW)
            let nu = NSTextAttachment()
            nu.image = placeholderImage
            nu.bounds = CGRect(origin: .zero, size: sz)
            m.addAttribute(.attachment, value: nu, range: range)
        }
        return m
    }

    static func updateWidth(in storage: NSTextStorage, range: NSRange, width: CGFloat) {
        guard range.length > 0,
              let att = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
              var d = storage.attribute(.inkSlateNotePhoto, at: range.location, effectiveRange: nil) as? [AnyHashable: Any]
        else { return }

        let w = max(80, min(width, 900))
        let sz = displaySize(for: att.image, width: w)
        att.bounds = CGRect(origin: .zero, size: sz)
        d[dictWidthKey] = NSNumber(value: Double(w))
        storage.addAttribute(.inkSlateNotePhoto, value: d, range: range)
    }
    #endif
}

#if canImport(UIKit)
/// Persists full-resolution note images on-device (Application Support) so reopening a note does not wait on CloudKit
enum NotePhotoDiskCache {
    private static let legacySubfolder = "InkSlateNotePhotoCache"
    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("InkSlate", isDirectory: true)
            .appendingPathComponent("NotePhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var legacyDirectoryURL: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent(legacySubfolder, isDirectory: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    private static func sanitizedFileBase(recordName: String) -> String {
        recordName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    private static func fileURL(recordName: String) -> URL {
        directoryURL.appendingPathComponent(sanitizedFileBase(recordName: recordName) + ".jpg", isDirectory: false)
    }

    private static func legacyFileURL(recordName: String) -> URL? {
        legacyDirectoryURL?.appendingPathComponent(sanitizedFileBase(recordName: recordName) + ".jpg", isDirectory: false)
    }

    private static func migrateFromLegacyIfNeeded(recordName: String, primaryURL: URL) {
        guard let legacy = legacyFileURL(recordName: recordName),
              FileManager.default.fileExists(atPath: legacy.path),
              !FileManager.default.fileExists(atPath: primaryURL.path)
        else { return }
        do {
            try FileManager.default.moveItem(at: legacy, to: primaryURL)
        } catch {
            try? FileManager.default.copyItem(at: legacy, to: primaryURL)
            try? FileManager.default.removeItem(at: legacy)
        }
    }

    static func load(recordName: String) -> UIImage? {
        let url = fileURL(recordName: recordName)
        migrateFromLegacyIfNeeded(recordName: recordName, primaryURL: url)
        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            return img
        }
        guard let legacy = legacyFileURL(recordName: recordName),
              FileManager.default.fileExists(atPath: legacy.path),
              let data = try? Data(contentsOf: legacy),
              let img = UIImage(data: data)
        else { return nil }
        DispatchQueue.global(qos: .userInitiated).async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic])
            try? FileManager.default.removeItem(at: legacy)
        }
        return img
    }

    static func save(_ image: UIImage, recordName: String) {
        let url = fileURL(recordName: recordName)
        guard let data = image.jpegData(compressionQuality: 0.88) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }

    static func remove(recordName: String) {
        let url = fileURL(recordName: recordName)
        try? FileManager.default.removeItem(at: url)
        if let legacy = legacyFileURL(recordName: recordName) {
            try? FileManager.default.removeItem(at: legacy)
        }
    }
}

private final class NotePhotoHydrateTextViewRef: @unchecked Sendable {
    weak var textView: UITextView?
    init(_ textView: UITextView) { self.textView = textView }
}

/// Deduplicates concurrent CloudKit downloads for the same note photo record name
private actor NotePhotoDownloadCoordinator {
    static let shared = NotePhotoDownloadCoordinator()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    func image(for recordName: String) async -> UIImage? {
        if let existing = inFlight[recordName] {
            return await existing.value
        }
        let task = Task<UIImage?, Never> {
            if let disk = NotePhotoDiskCache.load(recordName: recordName) {
                return disk
            }
            do {
                return try await CloudKitAssetService.shared.downloadNotePhoto(recordName: recordName)
            } catch {
                return nil
            }
        }
        inFlight[recordName] = task
        let result = await task.value
        inFlight.removeValue(forKey: recordName)
        return result
    }
}

/// Loads CloudKit-backed note images into the text view (editor + preview)
enum NotePhotoCloudHydrator {
    private static let hydrateLog = Logger(subsystem: "com.lucas.InkSlateNew", category: "NotePhotoHydrate")
    private static var memoryCache: [String: UIImage] = [:]
    private static let lock = NSLock()

    static func cachedImage(recordName: String) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return memoryCache[recordName]
    }

    static func storeInMemoryCache(_ image: UIImage, recordName: String) {
        lock.lock()
        defer { lock.unlock() }
        memoryCache[recordName] = image
    }

    /// Decodes `Notes.imageUrls` (JSON array of CloudKit record names) for prefetch
    static func recordNames(fromImageUrlsJSON json: String?) -> [String] {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr.filter { !$0.isEmpty }
    }

    static func recordNamesForPrefetch(imageUrlsJSON: String?, content: String?) -> [String] {
        var names = Set(recordNames(fromImageUrlsJSON: imageUrlsJSON))
        if let content, !content.isEmpty,
           let (attr, _) = MarkdownSerialization.deserialize(content, maxWidth: 400) {
            names.formUnion(NotePhotoRefCollector.recordNames(in: attr))
        }
        return Array(names).sorted()
    }

    static func prefetchToCaches(recordNames: [String]) async {
        let names = recordNames.filter { !$0.isEmpty }
        guard !names.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for rk in names {
                group.addTask {
                    if cachedImage(recordName: rk) != nil { return }
                    if let disk = NotePhotoDiskCache.load(recordName: rk) {
                        await MainActor.run { storeInMemoryCache(disk, recordName: rk) }
                        return
                    }
                    if let img = await NotePhotoDownloadCoordinator.shared.image(for: rk) {
                        NotePhotoDiskCache.save(img, recordName: rk)
                        await MainActor.run { storeInMemoryCache(img, recordName: rk) }
                    }
                }
            }
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .inkSlateNotePhotoCachesWarmed, object: nil)
        }
    }

    static func hydrate(textView: UITextView, overrideColumnWidth: CGFloat? = nil) {
        let tvRef = NotePhotoHydrateTextViewRef(textView)
        let storage = textView.textStorage
        let len = storage.length
        guard len > 0 else { return }

        let column = overrideColumnWidth ?? NotePhotoAttachment.textColumnWidth(for: textView)
        var work: [(range: NSRange, recordName: String, width: CGFloat)] = []
        storage.enumerateAttribute(.inkSlateNotePhoto, in: NSRange(location: 0, length: len), options: []) { value, range, _ in
            guard let d = value as? [AnyHashable: Any],
                  let rk = d[NotePhotoAttachment.dictRecordKey] as? String, !rk.isEmpty else { return }
            let stored = (d[NotePhotoAttachment.dictWidthKey] as? NSNumber).map { CGFloat($0.doubleValue) }
            let w = NotePhotoAttachment.preferredLayoutWidth(storedPoints: stored, columnWidth: column)
            work.append((range, rk, w))
        }

        for item in work {
            if let cached = cachedImage(recordName: item.recordName) {
                apply(image: cached, range: item.range, width: item.width, in: storage)
                continue
            }
            if let disk = NotePhotoDiskCache.load(recordName: item.recordName) {
                storeInMemoryCache(disk, recordName: item.recordName)
                apply(image: disk, range: item.range, width: item.width, in: storage)
                continue
            }
            let range = item.range
            let rk = item.recordName
            let w = item.width
            Task {
                if let img = await NotePhotoDownloadCoordinator.shared.image(for: rk) {
                    NotePhotoDiskCache.save(img, recordName: rk)
                    await MainActor.run {
                        guard let tv = tvRef.textView else { return }
                        storeInMemoryCache(img, recordName: rk)
                        apply(image: img, range: range, width: w, in: tv.textStorage)
                        tv.setNeedsLayout()
                        tv.layoutIfNeeded()
                    }
                }
            }
        }
    }

    private static func apply(image: UIImage, range: NSRange, width: CGFloat, in storage: NSTextStorage) {
        guard range.location + range.length <= storage.length else { return }
        guard let att = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment else { return }
        let sz = NotePhotoAttachment.displaySize(for: image, width: width)
        let tiny = (att.image?.size.width ?? 0) <= 12 && (att.image?.size.height ?? 0) <= 12
        if !tiny,
           abs(att.bounds.width - sz.width) < 1.5,
           abs(att.bounds.height - sz.height) < 1.5 {
            return
        }
        att.image = NotePhotoAttachment.displayImageForInlineEditor(image)
        att.bounds = CGRect(origin: .zero, size: sz)
    }
}
#endif


#if canImport(UIKit)
enum NotePhotoRefCollector {
    static func recordNames(in attributed: NSAttributedString) -> Set<String> {
        Set(NotePhotoAttachment.photoDict(from: attributed).keys)
    }

    static func jsonIndex(for attributed: NSAttributedString) -> String? {
        let names = Array(NotePhotoAttachment.photoDict(from: attributed).keys).sorted()
        guard !names.isEmpty else { return nil }
        if let data = try? JSONEncoder().encode(names),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return nil
    }

    static func hasAnyPhotoReferences(inSerializedContent content: String?) -> Bool {
        guard let content, !content.isEmpty else { return false }
        if let (attr, _) = MarkdownSerialization.deserialize(content, maxWidth: 400) {
            return !recordNames(in: attr).isEmpty
        }
        return false
    }
}
#endif
