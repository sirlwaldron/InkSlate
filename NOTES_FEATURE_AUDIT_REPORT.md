# Notes Feature - Performance & Bug Audit Report

**Date:** December 10, 2025  
**Scope:** Complete notes feature including NotesViews.swift, MarkdownEditor.swift, and related services

---

## 🔴 CRITICAL BUGS

### 1. **CRITICAL - Race Condition: Async Serialization + Synchronous Core Data Access**

**Location:** `MarkdownEditor.Coordinator.textViewDidChange()` + `TextEditorView.markAsChanged()`

**Problem:** 
- `textViewDidChange()` now uses `Task.detached` for async serialization
- But `markAsChanged()` synchronously modifies `note.content` (Core Data object) on main thread
- This creates a race condition where Core Data is modified while serialization is still in progress

**Current Code (BROKEN):**
```swift
// In textViewDidChange:
Task.detached(priority: .userInitiated) { [weak self] in
    guard let self = self else { return }
    let serialized = self.serializeContent(from: attributedText)
    await MainActor.run {
        self.parent.text = serialized  // Updates binding
        self.parent.selectedRange = currentRange
    }
}

// In markAsChanged (called from onChange of note.content):
if let coordinator = coordinatorRef, let textView = coordinator.textView {
    let serialized = coordinator.serializeContent(from: textView.attributedText)
    note.content = serialized  // ⚠️ DANGER: Core Data modified while async task may still be running
}
```

**Impact:** Data corruption, lost edits, crashes

**Fix:**
```swift
// Option 1: Keep serialization synchronous (RECOMMENDED)
func textViewDidChange(_ textView: UITextView) {
    guard !isProgrammaticChange else { return }
    saveWorkItem?.cancel()

    let updateParent: () -> Void = { [weak self] in
        guard let self = self else { return }
        // Serialize synchronously on main thread
        let serialized = self.serializeContent(from: textView.attributedText)
        self.parent.text = serialized
    }

    if textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true {
        updateParent()
    } else {
        let item = DispatchWorkItem(block: updateParent)
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    parent.selectedRange = textView.selectedRange
    updateActiveStylesAsync(textView)
}

// Option 2: Make markAsChanged async-aware (COMPLEX)
// Would require significant refactoring to handle async properly
```

---

### 2. **CRITICAL - Performance: Core Data Fetch on Every SwiftUI Render**

**Location:** `NotesListView.filteredNotes` computed property

**Problem:**
- `filteredNotes` performs a Core Data fetch (`viewContext.fetch()`) on **every SwiftUI body evaluation**
- SwiftUI can evaluate body multiple times per frame
- This causes massive performance degradation with large note collections

**Current Code:**
```swift
private var filteredNotes: [Notes] {
    PerformanceLogger.measure(log: PerformanceMetrics.notesQuery, name: "FilterNotes") {
        // ... builds predicates ...
        let fetchRequest = NSFetchRequest<Notes>(entityName: "Notes")
        fetchRequest.predicate = compoundPredicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.fetchLimit = 200
        fetchRequest.fetchBatchSize = 20
        
        if let results = try? viewContext.fetch(fetchRequest) {
            return results
        }
        return []
    }
}
```

**Impact:** UI freezes, battery drain, poor user experience

**Fix:**
```swift
// Use @State to cache results and only refetch when filters change
@State private var cachedFilteredNotes: [Notes] = []
@State private var lastFilterHash: Int = 0

private var filteredNotes: [Notes] {
    let currentHash = filterHash()
    if currentHash != lastFilterHash || cachedFilteredNotes.isEmpty {
        // Only fetch when filters actually change
        let results = performFilteredFetch()
        cachedFilteredNotes = results
        lastFilterHash = currentHash
        return results
    }
    return cachedFilteredNotes
}

private func filterHash() -> Int {
    var hasher = Hasher()
    hasher.combine(showingDeletedNotes)
    hasher.combine(selectedProject?.id)
    hasher.combine(showPinnedOnly)
    hasher.combine(searchDebouncer.debouncedText)
    hasher.combine(sortBy)
    hasher.combine(sortDirection)
    return hasher.finalize()
}

private func performFilteredFetch() -> [Notes] {
    // ... existing fetch logic ...
}

// Update in onChange handlers:
.onChange(of: selectedProject) { _, _ in
    cachedFilteredNotes = []  // Invalidate cache
    saveLastSelectedFolder(newValue)
}
.onChange(of: showPinnedOnly) { _, _ in
    cachedFilteredNotes = []  // Invalidate cache
}
// etc.
```

**OR Better - Use @FetchRequest with dynamic predicates:**
```swift
@FetchRequest private var filteredNotes: FetchedResults<Notes>

init() {
    // ... existing init code ...
    
    // Create dynamic fetch request
    let request = NSFetchRequest<Notes>(entityName: "Notes")
    request.sortDescriptors = [NSSortDescriptor(key: "modifiedDate", ascending: false)]
    request.predicate = NSPredicate(format: "isMarkedDeleted == NO")
    request.fetchLimit = 200
    request.fetchBatchSize = 20
    _filteredNotes = FetchRequest(fetchRequest: request, animation: .default)
}

// Then update predicate when filters change
private func updateFetchRequest() {
    // Rebuild predicate and update @FetchRequest
    // This is complex with SwiftUI, so caching approach above is better
}
```

---

### 3. **CRITICAL - Double Assignment Bug**

**Location:** `TextEditorView.saveNote()`

**Problem:** `isSaving = false` is set twice - once in do block, once after catch

**Current Code:**
```swift
do {
    try viewContext.save()
    hasUnsavedChanges = false
    isSaving = false  // First assignment
} catch let error as NSError {
    isSaving = false  // Second assignment
    // ... error handling ...
}
isSaving = false  // Third assignment (redundant)
```

**Impact:** Minor - just redundant code, but indicates potential logic issues

**Fix:**
```swift
do {
    try viewContext.save()
    hasUnsavedChanges = false
} catch let error as NSError {
    // ... error handling ...
} finally {
    isSaving = false  // Single assignment point
}
// OR just remove the duplicate assignments
```

---

## 🟡 HIGH PRIORITY BUGS

### 4. **Memory Leak - Task.detached Captures Strong References**

**Location:** `MarkdownEditor.Coordinator.textViewDidChange()`

**Problem:** `Task.detached` closures capture `attributedText` strongly, keeping large NSAttributedString in memory

**Current Code:**
```swift
let attributedText = textView.attributedText.copy() as! NSAttributedString  // Force cast!
let currentRange = textView.selectedRange

Task.detached(priority: .userInitiated) { [weak self] in
    guard let self = self else { return }
    let serialized = self.serializeContent(from: attributedText)  // attributedText captured strongly
    // ...
}
```

**Issues:**
1. Force cast `as!` can crash
2. `attributedText` is a large object kept in memory
3. Multiple tasks can run simultaneously, multiplying memory usage

**Fix:**
```swift
// Remove Task.detached entirely - serialization is fast enough synchronously
// OR if keeping async, use proper weak capture:
func textViewDidChange(_ textView: UITextView) {
    guard !isProgrammaticChange else { return }
    saveWorkItem?.cancel()

    let updateParent: () -> Void = { [weak self, weak textView] in
        guard let self = self, let textView = textView else { return }
        // Serialize synchronously - it's fast
        let serialized = self.serializeContent(from: textView.attributedText)
        self.parent.text = serialized
        self.parent.selectedRange = textView.selectedRange
    }

    if textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true {
        updateParent()
    } else {
        let item = DispatchWorkItem(block: updateParent)
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    parent.selectedRange = textView.selectedRange
    updateActiveStylesAsync(textView)
}
```

---

### 5. **NSCache Key/Value Type Mismatch**

**Location:** `MarkdownEditor.Coordinator.imageCache`

**Problem:** Using `NSCache<NSData, NSString>` but passing `Data` and `String` which need conversion

**Current Code:**
```swift
private let imageCache = NSCache<NSData, NSString>()

// Usage:
self.imageCache.setObject(encoded as NSString, forKey: data as NSData, totalCost: data.count)
```

**Issues:**
1. `as NSString` and `as NSData` are force casts that can fail
2. NSCache requires NSObject subclasses, but Data/String are value types
3. The conversion overhead may negate caching benefits

**Fix:**
```swift
// Option 1: Use wrapper classes
private class ImageCacheKey: NSObject {
    let data: Data
    init(_ data: Data) { self.data = data }
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ImageCacheKey else { return false }
        return data == other.data
    }
    override var hash: Int { data.hashValue }
}

private class ImageCacheValue: NSObject {
    let encoded: String
    init(_ encoded: String) { self.encoded = encoded }
}

private let imageCache = NSCache<ImageCacheKey, ImageCacheValue>()

// Usage:
let key = ImageCacheKey(data)
let value = ImageCacheValue(encoded)
imageCache.setObject(value, forKey: key, totalCost: data.count)

// Option 2: Keep using Dictionary with proper locking (simpler)
private var imageCache = [Data: String]()
private let imageCacheQueue = DispatchQueue(label: "co.inkslate.imageCache", qos: .userInitiated)

func serializeContent(from attributed: NSAttributedString) -> String {
    // ... serialization ...
    mutable.enumerateAttribute(.imageData, in: NSRange(location: 0, length: mutable.length), options: []) { value, _, _ in
        if let encoded = value as? String, let data = Data(base64Encoded: encoded) {
            imageCacheQueue.async { [weak self] in
                self?.imageCache[data] = encoded
            }
        }
    }
    return serialized
}
```

---

### 6. **Performance - Unnecessary Core Data Fetch in filteredNotes**

**Location:** `NotesListView.filteredNotes`

**Problem:** Even with caching fix above, the initial implementation ignores the existing `@FetchRequest` results

**Current Code:**
```swift
@FetchRequest private var normalNotes: FetchedResults<Notes>
@FetchRequest private var deletedNotes: FetchedResults<Notes>

private var filteredNotes: [Notes] {
    // Creates NEW fetch request instead of using existing @FetchRequest results
    let fetchRequest = NSFetchRequest<Notes>(entityName: "Notes")
    // ...
}
```

**Impact:** Duplicate fetches, wasted memory, slower performance

**Fix:**
```swift
// Use the existing FetchedResults and filter in-memory (fast for reasonable sizes)
// OR use @FetchRequest with dynamic predicate (complex but optimal)

private var filteredNotes: [Notes] {
    let source = showingDeletedNotes ? deletedNotes : normalNotes
    
    // Fast in-memory filtering (Core Data already loaded these)
    var filtered = Array(source)
    
    if !showingDeletedNotes {
        if let selectedProject = selectedProject {
            filtered = filtered.filter { $0.project == selectedProject }
        }
        if showPinnedOnly {
            filtered = filtered.filter { $0.isPinned }
        }
        if !searchDebouncer.debouncedText.isEmpty {
            let searchLower = searchDebouncer.debouncedText.lowercased()
            filtered = filtered.filter { note in
                (note.title?.lowercased().contains(searchLower) ?? false) ||
                (note.content?.lowercased().contains(searchLower) ?? false) ||
                (note.preview?.lowercased().contains(searchLower) ?? false)
            }
        }
    }
    
    // Sort
    let ascending = sortDirection == .ascending
    filtered.sort { note1, note2 in
        switch sortBy {
        case .modificationDate:
            let date1 = note1.modifiedDate ?? Date.distantPast
            let date2 = note2.modifiedDate ?? Date.distantPast
            return ascending ? date1 < date2 : date1 > date2
        case .creationDate:
            let date1 = note1.createdDate ?? Date.distantPast
            let date2 = note2.createdDate ?? Date.distantPast
            return ascending ? date1 < date2 : date1 > date2
        case .title:
            let title1 = note1.title ?? ""
            let title2 = note2.title ?? ""
            return ascending ? title1 < title2 : title1 > title2
        case .pin:
            return ascending ? (note1.isPinned && !note2.isPinned) : (!note1.isPinned && note2.isPinned)
        }
    }
    
    return Array(filtered.prefix(200))  // Limit results
}
```

---

### 7. **Thread Safety - Core Data Context Access**

**Location:** `TextEditorView.markAsChanged()`

**Problem:** Modifying Core Data objects without ensuring main thread context

**Current Code:**
```swift
private func markAsChanged() {
    hasUnsavedChanges = true
    note.modifiedDate = Date()  // Core Data object modification
    
    if let coordinator = coordinatorRef, let textView = coordinator.textView {
        let serialized = coordinator.serializeContent(from: textView.attributedText)
        note.content = serialized  // Core Data modification
        note.preview = String(plain.prefix(100))  // Core Data modification
    }
}
```

**Issue:** If called from background thread (unlikely but possible), this will crash

**Fix:**
```swift
private func markAsChanged() {
    // Ensure main thread
    guard Thread.isMainThread else {
        DispatchQueue.main.async { [weak self] in
            self?.markAsChanged()
        }
        return
    }
    
    hasUnsavedChanges = true
    note.modifiedDate = Date()
    
    if let coordinator = coordinatorRef, let textView = coordinator.textView {
        let serialized = coordinator.serializeContent(from: textView.attributedText)
        note.content = serialized
        let plain = MarkdownSerialization.plainText(from: serialized)
        note.preview = String(plain.prefix(100))
    }
    
    scheduleAutoSave()
}
```

---

## 🟠 MEDIUM PRIORITY ISSUES

### 8. **Performance - Regex Compilation in currentActiveStyles**

**Location:** `MarkdownEditor.Coordinator.currentActiveStyles()`

**Problem:** Regex patterns compiled on every call (though cached in WysiwygActionHandler)

**Current Code:**
```swift
let line = (tv as? EditorTextView)?.currentLineString() ?? ""
if line.range(of: #"^\s*• "#, options: .regularExpression) != nil { set.insert(.bulletList) }
if line.range(of: #"^\s*\d+\. "#, options: .regularExpression) != nil { set.insert(.numberedList) }
if line.range(of: #"^>+\s"#, options: .regularExpression) != nil { set.insert(.blockquote) }
```

**Fix:**
```swift
// Use the cached regex from WysiwygActionHandler
let line = (tv as? EditorTextView)?.currentLineString() ?? ""
if WysiwygActionHandler.bulletRegex.firstMatch(in: line, range: NSRange(location: 0, length: line.count)) != nil {
    set.insert(.bulletList)
} else {
    set.remove(.bulletList)
}
// Similar for numbered and blockquote
```

**OR make regexes accessible:**
```swift
// In WysiwygActionHandler:
static let bulletPattern = #"^\s*• "#
static let numberedPattern = #"^\s*\d+\. "#
static let blockquotePattern = #"^>+\s"#

// Then use in currentActiveStyles:
if line.range(of: WysiwygActionHandler.bulletPattern, options: .regularExpression) != nil {
```

---

### 9. **Memory - Font Cache Growth**

**Location:** `MarkdownEditor.Coordinator.fontCache`

**Current Code:**
```swift
private var fontCache: [String: UIFont] = [:] {
    didSet {
        if fontCache.count > 50 {
            fontCache.removeAll()  // Clears entire cache
        }
    }
}
```

**Problem:** Clears entire cache when limit reached, causing cache thrashing

**Fix:**
```swift
private var fontCache: [String: UIFont] = [:]
private let maxFontCacheSize = 50

fileprivate func applyTypingAttributes(in tv: UITextView) {
    // ... existing code ...
    
    if fontCache.count > maxFontCacheSize {
        // Remove oldest entries (simple FIFO)
        let keysToRemove = Array(fontCache.keys.prefix(maxFontCacheSize / 2))
        for key in keysToRemove {
            fontCache.removeValue(forKey: key)
        }
    }
    
    fontCache[cacheKey] = newFont
}
```

---

### 10. **Performance - Empty Trash Iteration**

**Location:** `NotesListView.emptyTrash()`

**Problem:** Iterates through all deleted notes in memory

**Current Code:**
```swift
private func emptyTrash() {
    withAnimation(.easeInOut) { isLoading = true }
    for note in deletedNotes { viewContext.delete(note) }  // Loads all into memory
    // ...
}
```

**Fix:**
```swift
private func emptyTrash() {
    withAnimation(.easeInOut) { isLoading = true }
    
    // Batch delete using Core Data batch delete (more efficient)
    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Notes")
    fetchRequest.predicate = NSPredicate(format: "isMarkedDeleted == YES")
    
    let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
    batchDelete.resultType = .resultTypeObjectIDs
    
    do {
        let result = try viewContext.execute(batchDelete) as? NSBatchDeleteResult
        let objectIDArray = result?.result as? [NSManagedObjectID]
        let changes = [NSDeletedObjectsKey: objectIDArray ?? []]
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
        
        try viewContext.save()
    } catch {
        errorMessage = "Failed to empty trash: \(error.localizedDescription)"
        showingError = true
    }
    
    withAnimation(.easeInOut) { isLoading = false }
}
```

---

### 11. **Bug - Duplicate isSaving Flag**

**Location:** `TextEditorView.saveNote()`

**Already identified in #3, but worth emphasizing**

---

### 12. **Performance - Preview Generation on Every Change**

**Location:** `TextEditorView.markAsChanged()`

**Problem:** Generates preview on every keystroke (though debounced)

**Current Code:**
```swift
let plain = MarkdownSerialization.plainText(from: serialized)
note.preview = String(plain.prefix(100))
```

**Optimization:**
```swift
// Only update preview if content actually changed significantly
private var lastPreviewContent: String = ""

private func markAsChanged() {
    // ... existing code ...
    
    if let coordinator = coordinatorRef, let textView = coordinator.textView {
        let serialized = coordinator.serializeContent(from: textView.attributedText)
        note.content = serialized
        
        // Only regenerate preview if content changed significantly
        let plain = MarkdownSerialization.plainText(from: serialized)
        let newPreview = String(plain.prefix(100))
        if newPreview != lastPreviewContent {
            note.preview = newPreview
            lastPreviewContent = newPreview
        }
    }
}
```

---

## 🟢 LOW PRIORITY / OPTIMIZATIONS

### 13. **Code Quality - Unused Methods**

**Location:** `NotesListView`

**Found:**
- `buildSortDescriptors()` - defined but never used
- `buildSearchPredicate()` - defined but never used

**Action:** Remove or implement

---

### 14. **Performance - Note Count Calculation**

**Location:** `FoldersListView` and `MoveToFolderView`

**Problem:** Calculates note count by filtering Set on every render

**Current Code:**
```swift
if let notes = project.notes as? Set<Notes> {
    let count = notes.filter { !$0.isMarkedDeleted }.count
    Text("\(count) notes")
}
```

**Fix:** Cache counts or use Core Data fetch with count

---

### 15. **UI - Missing Loading States**

**Location:** Various save operations

**Problem:** Some operations don't show loading indicators

**Example:** `moveNoteToFolder()` doesn't show loading state

---

### 16. **Error Handling - Silent Failures**

**Location:** Multiple places

**Examples:**
- `purgeOldDeletedNotes()` uses `try?` and silently fails
- `moveNoteToFolder()` prints error but doesn't show to user
- `deleteTag()` prints error but doesn't show to user

**Fix:** Show user-friendly error messages

---

## 📊 PERFORMANCE METRICS

### Current Issues:
1. **Core Data Fetches:** `filteredNotes` performs fetch on every SwiftUI render
2. **Memory Usage:** Large NSAttributedString objects kept in Task closures
3. **Cache Thrashing:** Font cache clears entirely when limit reached
4. **Unnecessary Work:** Preview regenerated even when content unchanged

### Recommended Optimizations:
1. ✅ Cache filtered results (already partially addressed)
2. ✅ Use batch deletes for trash operations
3. ✅ Optimize preview generation
4. ✅ Fix async serialization race condition

---

## 🔧 RECOMMENDED FIXES PRIORITY

### Immediate (Critical):
1. **Fix #1** - Remove async serialization or make it properly thread-safe
2. **Fix #2** - Cache filteredNotes results
3. **Fix #3** - Remove duplicate isSaving assignment

### High Priority:
4. **Fix #4** - Remove Task.detached or fix memory capture
5. **Fix #5** - Fix NSCache type usage
6. **Fix #6** - Use existing @FetchRequest results

### Medium Priority:
7. **Fix #7** - Add main thread checks
8. **Fix #8** - Use cached regex patterns
9. **Fix #10** - Use batch delete for empty trash

### Low Priority:
10. Remove unused methods
11. Improve error handling
12. Add loading states

---

## 📝 SUMMARY

**Total Issues Found:** 16
- **Critical:** 3
- **High Priority:** 3
- **Medium Priority:** 6
- **Low Priority:** 4

**Most Critical:** The async serialization race condition (#1) can cause data loss and corruption. This must be fixed immediately.

**Performance Impact:** The filteredNotes fetch-on-render issue (#2) will cause severe performance degradation with large note collections.


