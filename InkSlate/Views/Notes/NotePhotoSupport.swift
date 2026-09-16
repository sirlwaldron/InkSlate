import Foundation

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

extension Notification.Name {
    static let inkSlateNotePhotoCachesWarmed = Notification.Name("InkSlateNotePhotoCachesWarmed")
}

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

    /// Replaces inline images with the shared placeholder before archiving (keeps `content` CloudKit-friendly).
    /// Prefer existing layout bounds so hydrate → serialize does not churn the archive and fight SwiftUI.
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
            let sz: CGSize
            if b.width >= 44, b.height >= 32 {
                let ratio = b.height / max(b.width, 1)
                sz = CGSize(width: layoutW, height: max(44, layoutW * ratio))
            } else {
                sz = displaySize(for: old.image, width: layoutW)
            }
            let nu = NSTextAttachment()
            nu.image = placeholderImage
            nu.bounds = CGRect(origin: .zero, size: sz)
            m.addAttribute(.attachment, value: nu, range: range)
        }
        return m
    }

    /// True when at least one note photo attachment already shows a real bitmap (not the 8×8 placeholder).
    static func hasHydratedPhotos(in attributed: NSAttributedString) -> Bool {
        let full = NSRange(location: 0, length: attributed.length)
        var found = false
        attributed.enumerateAttribute(.inkSlateNotePhoto, in: full, options: []) { value, range, stop in
            guard value != nil else { return }
            guard let att = attributed.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
                  let img = att.image else { return }
            if img.size.width > 12, img.size.height > 12 {
                found = true
                stop.pointee = true
            }
        }
        return found
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
    #elseif canImport(AppKit)
    static var placeholderImage: NSImage {
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.separatorColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    static func textColumnWidth(for textView: NSTextView) -> CGFloat {
        let inset = textView.textContainerInset
        let pad = textView.textContainer?.lineFragmentPadding ?? 0
        let inner = textView.bounds.width - inset.width - 2 * pad
        let screenCap = max(120, (NSScreen.main?.visibleFrame.width ?? 800) - 56)
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

    static func displaySize(for image: NSImage?, width: CGFloat) -> CGSize {
        let w = max(44, width)
        let ratio: CGFloat
        if let image, image.size.width > 1, image.size.height > 1 {
            ratio = image.size.height / image.size.width
        } else {
            ratio = 1
        }
        return CGSize(width: w, height: max(44, w * ratio))
    }

    static func displayImageForInlineEditor(_ image: NSImage) -> NSImage {
        image
    }

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
            let sz: CGSize
            if b.width >= 44, b.height >= 32 {
                let ratio = b.height / max(b.width, 1)
                sz = CGSize(width: layoutW, height: max(44, layoutW * ratio))
            } else {
                sz = displaySize(for: old.image, width: layoutW)
            }
            let nu = NSTextAttachment()
            nu.image = placeholderImage
            nu.bounds = CGRect(origin: .zero, size: sz)
            m.addAttribute(.attachment, value: nu, range: range)
        }
        return m
    }

    static func hasHydratedPhotos(in attributed: NSAttributedString) -> Bool {
        let full = NSRange(location: 0, length: attributed.length)
        var found = false
        attributed.enumerateAttribute(.inkSlateNotePhoto, in: full, options: []) { value, range, stop in
            guard value != nil else { return }
            guard let att = attributed.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
                  let img = att.image else { return }
            if img.size.width > 12, img.size.height > 12 {
                found = true
                stop.pointee = true
            }
        }
        return found
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

    static func load(recordName: String) -> PlatformImage? {
        let url = fileURL(recordName: recordName)
        migrateFromLegacyIfNeeded(recordName: recordName, primaryURL: url)
        if let data = try? Data(contentsOf: url), let img = platformImage(from: data) {
            return img
        }
        guard let legacy = legacyFileURL(recordName: recordName),
              FileManager.default.fileExists(atPath: legacy.path),
              let data = try? Data(contentsOf: legacy),
              let img = platformImage(from: data)
        else { return nil }
        DispatchQueue.global(qos: .userInitiated).async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic])
            try? FileManager.default.removeItem(at: legacy)
        }
        return img
    }

    static func save(_ image: PlatformImage, recordName: String) {
        let url = fileURL(recordName: recordName)
        let data = image.inkSlateJPEGDataFitting(maxBytes: 5 * 1024 * 1024)
            ?? image.jpegData(compressionQuality: 0.88)
        guard let data else { return }
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

/// Tracks note photos that were saved locally but still need a CloudKit upload.
enum NotePhotoSync {
    private static let defaultsKey = "InkSlate.PendingNotePhotoUploads"

    private struct PendingItem: Codable, Equatable {
        let recordName: String
        let noteID: String
    }

    static func isCloudRecordName(_ name: String) -> Bool {
        name.hasPrefix("NotePhoto-")
    }

    static func attachmentID(from recordName: String) -> UUID? {
        guard recordName.hasPrefix("NotePhoto-") else { return nil }
        return UUID(uuidString: String(recordName.dropFirst("NotePhoto-".count)))
    }

    static func enqueuePending(recordName: String, noteID: UUID) {
        var items = loadPending()
        items.removeAll { $0.recordName == recordName }
        items.append(PendingItem(recordName: recordName, noteID: noteID.uuidString))
        savePending(items)
    }

    static func dequeuePending(recordName: String) {
        var items = loadPending()
        items.removeAll { $0.recordName == recordName }
        savePending(items)
    }

    @MainActor
    static func flushPendingUploads() async {
        let items = loadPending()
        guard !items.isEmpty else { return }

        for item in items {
            guard let noteID = UUID(uuidString: item.noteID),
                  let attachmentID = attachmentID(from: item.recordName),
                  let image = NotePhotoDiskCache.load(recordName: item.recordName)
            else {
                dequeuePending(recordName: item.recordName)
                continue
            }

            do {
                _ = try await CloudKitAssetService.shared.uploadNotePhoto(
                    image,
                    noteID: noteID,
                    attachmentID: attachmentID
                )
                dequeuePending(recordName: item.recordName)
            } catch {
                // Keep pending for a later retry.
            }
        }
    }

    private static func loadPending() -> [PendingItem] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let items = try? JSONDecoder().decode([PendingItem].self, from: data)
        else { return [] }
        return items
    }

    private static func savePending(_ items: [PendingItem]) {
        if items.isEmpty {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return
        }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

#if canImport(UIKit) || canImport(AppKit)
/// Deduplicates concurrent CloudKit downloads for the same note photo record name
private actor NotePhotoDownloadCoordinator {
    static let shared = NotePhotoDownloadCoordinator()
    private var inFlight: [String: Task<PlatformImage?, Never>] = [:]

    func image(for recordName: String) async -> PlatformImage? {
        if let existing = inFlight[recordName] {
            return await existing.value
        }
        let task = Task<PlatformImage?, Never> {
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
    private static var memoryCache: [String: PlatformImage] = [:]
    private static let lock = NSLock()
    /// Text views currently swapping placeholder bitmaps — edits from those must not mark dirty.
    private static let hydratingViews = NSHashTable<AnyObject>.weakObjects()

    /// True while any text view is hydrating (legacy callers). Prefer `isHydrating(_:)`.
    static var isHydrating: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hydratingViews.count > 0
    }

    static func isHydrating(_ view: AnyObject) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return hydratingViews.contains(view)
    }

    private static func beginHydrating(_ view: AnyObject) {
        lock.lock()
        hydratingViews.add(view)
        lock.unlock()
    }

    private static func endHydrating(_ view: AnyObject) {
        lock.lock()
        hydratingViews.remove(view)
        lock.unlock()
    }

    static func cachedImage(recordName: String) -> PlatformImage? {
        lock.lock()
        defer { lock.unlock() }
        return memoryCache[recordName]
    }

    static func storeInMemoryCache(_ image: PlatformImage, recordName: String) {
        lock.lock()
        defer { lock.unlock() }
        memoryCache[recordName] = image
    }

    static func recordNames(fromImageUrlsJSON json: String?) -> [String] {
        NotePhotoRefCollector.recordNames(fromImageUrlsJSON: json)
    }

    static func recordNamesForPrefetch(imageUrlsJSON: String?, content: String?) -> [String] {
        NotePhotoRefCollector.recordNamesForPrefetch(imageUrlsJSON: imageUrlsJSON, content: content)
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

    #if canImport(UIKit)
    private final class TextViewRef: @unchecked Sendable {
        weak var textView: UITextView?
        init(_ textView: UITextView) { self.textView = textView }
    }

    static func hydrate(textView: UITextView, overrideColumnWidth: CGFloat? = nil) {
        let tvRef = TextViewRef(textView)
        guard let storage = optionalStorage(textView.textStorage) else { return }
        let column = overrideColumnWidth ?? NotePhotoAttachment.textColumnWidth(for: textView)
        beginHydrating(textView)
        defer { endHydrating(textView) }
        hydrate(storage: storage, columnWidth: column) { range, rk, w in
            Task {
                if let img = await NotePhotoDownloadCoordinator.shared.image(for: rk) {
                    NotePhotoDiskCache.save(img, recordName: rk)
                    await MainActor.run {
                        guard let tv = tvRef.textView else { return }
                        storeInMemoryCache(img, recordName: rk)
                        beginHydrating(tv)
                        apply(image: img, range: range, width: w, recordName: rk, in: tv.textStorage)
                        endHydrating(tv)
                        tv.setNeedsLayout()
                        tv.layoutIfNeeded()
                    }
                }
            }
        }
    }
    #endif

    #if canImport(AppKit) && !canImport(UIKit)
    private final class MacTextViewRef: @unchecked Sendable {
        weak var textView: NSTextView?
        init(_ textView: NSTextView) { self.textView = textView }
    }

    static func hydrate(textView: NSTextView, overrideColumnWidth: CGFloat? = nil) {
        let tvRef = MacTextViewRef(textView)
        guard let storage = textView.textStorage else { return }
        let column = overrideColumnWidth ?? NotePhotoAttachment.textColumnWidth(for: textView)
        beginHydrating(textView)
        defer { endHydrating(textView) }
        hydrate(storage: storage, columnWidth: column) { range, rk, w in
            Task {
                if let img = await NotePhotoDownloadCoordinator.shared.image(for: rk) {
                    NotePhotoDiskCache.save(img, recordName: rk)
                    await MainActor.run {
                        guard let tv = tvRef.textView, let storage = tv.textStorage else { return }
                        storeInMemoryCache(img, recordName: rk)
                        beginHydrating(tv)
                        apply(image: img, range: range, width: w, recordName: rk, in: storage)
                        endHydrating(tv)
                        tv.needsLayout = true
                        tv.layoutSubtreeIfNeeded()
                    }
                }
            }
        }
    }
    #endif

    private static func optionalStorage(_ storage: NSTextStorage?) -> NSTextStorage? { storage }

    private static func hydrate(
        storage: NSTextStorage,
        columnWidth: CGFloat,
        onMiss: (_ range: NSRange, _ recordName: String, _ width: CGFloat) -> Void
    ) {
        let len = storage.length
        guard len > 0 else { return }
        var work: [(range: NSRange, recordName: String, width: CGFloat)] = []
        storage.enumerateAttribute(.inkSlateNotePhoto, in: NSRange(location: 0, length: len), options: []) { value, range, _ in
            guard let d = value as? [AnyHashable: Any],
                  let rk = d[NotePhotoAttachment.dictRecordKey] as? String, !rk.isEmpty else { return }
            let stored = (d[NotePhotoAttachment.dictWidthKey] as? NSNumber).map { CGFloat($0.doubleValue) }
            let w = NotePhotoAttachment.preferredLayoutWidth(storedPoints: stored, columnWidth: columnWidth)
            work.append((range, rk, w))
        }

        for item in work {
            if let cached = cachedImage(recordName: item.recordName) {
                apply(image: cached, range: item.range, width: item.width, recordName: item.recordName, in: storage)
                continue
            }
            if let disk = NotePhotoDiskCache.load(recordName: item.recordName) {
                storeInMemoryCache(disk, recordName: item.recordName)
                apply(image: disk, range: item.range, width: item.width, recordName: item.recordName, in: storage)
                continue
            }
            onMiss(item.range, item.recordName, item.width)
        }
    }

    private static func rangeOfPhoto(recordName: String, in storage: NSTextStorage) -> NSRange? {
        let len = storage.length
        guard len > 0 else { return nil }
        var found: NSRange?
        storage.enumerateAttribute(.inkSlateNotePhoto, in: NSRange(location: 0, length: len), options: []) { value, range, stop in
            guard let d = value as? [AnyHashable: Any],
                  let rk = d[NotePhotoAttachment.dictRecordKey] as? String,
                  rk == recordName else { return }
            found = range
            stop.pointee = true
        }
        return found
    }

    private static func apply(image: PlatformImage, range: NSRange, width: CGFloat, recordName: String, in storage: NSTextStorage) {
        let targetRange: NSRange
        if range.location + range.length <= storage.length,
           let d = storage.attribute(.inkSlateNotePhoto, at: range.location, effectiveRange: nil) as? [AnyHashable: Any],
           (d[NotePhotoAttachment.dictRecordKey] as? String) == recordName {
            targetRange = range
        } else if let found = rangeOfPhoto(recordName: recordName, in: storage) {
            targetRange = found
        } else {
            return
        }

        guard let att = storage.attribute(.attachment, at: targetRange.location, effectiveRange: nil) as? NSTextAttachment else { return }
        let sz = NotePhotoAttachment.displaySize(for: image, width: width)
        #if canImport(UIKit)
        let imageSize = att.image?.size ?? .zero
        #else
        let imageSize = att.image?.size ?? .zero
        #endif
        let tiny = imageSize.width <= 12 && imageSize.height <= 12
        if !tiny,
           abs(att.bounds.width - sz.width) < 1.5,
           abs(att.bounds.height - sz.height) < 1.5,
           imageSize.width > 12 {
            return
        }
        storage.beginEditing()
        att.image = NotePhotoAttachment.displayImageForInlineEditor(image)
        att.bounds = CGRect(origin: .zero, size: sz)
        storage.endEditing()
    }
}
#endif


enum NotePhotoRefCollector {
    static func recordNames(fromImageUrlsJSON json: String?) -> [String] {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr.filter { !$0.isEmpty }
    }

    static func recordNamesForPrefetch(imageUrlsJSON: String?, content: String?) -> [String] {
        var names = Set(recordNames(fromImageUrlsJSON: imageUrlsJSON))
        if let content, !content.isEmpty,
           let (attr, _) = MarkdownSerialization.deserialize(content, maxWidth: 400) {
            names.formUnion(recordNames(in: attr))
        }
        return Array(names).sorted()
    }

    static func recordNames(in attributed: NSAttributedString) -> Set<String> {
        Set(NotePhotoAttachment.photoDict(from: attributed).keys)
    }

    static func recordNames(fromSerialized content: String?) -> [String] {
        guard let content, !content.isEmpty,
              let (attr, _) = MarkdownSerialization.deserialize(content, maxWidth: 400) else { return [] }
        return Array(recordNames(in: attr))
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
