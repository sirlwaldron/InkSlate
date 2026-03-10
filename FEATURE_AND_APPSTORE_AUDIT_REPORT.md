# InkSlate - Feature & App Store Audit Report

**Date:** March 10, 2025  
**Purpose:** Pre-App Store readiness audit - verify all features work and identify items to fix

---

## Executive Summary

This audit covers all features in InkSlate and App Store requirements. Several items need attention before submission.

**Critical:** 3 items  
**High:** 5 items  
**Medium:** 6 items  
**Low:** 4 items  

---

## Feature Audit

### Notes

| Feature | Status | Notes |
|---------|--------|-------|
| **Bold** | ✅ Works | Bold is implemented via `WysiwygActionHandler.apply(.bold)` which toggles `UIFontDescriptor.SymbolicTraits.traitBold`. Content is serialized with `MarkdownSerialization.serialize()` preserving font attributes. |
| **Italic, underline, strikethrough** | ✅ Works | Same pattern as bold - applied via font traits and paragraph styles |
| **Headers (H1, H2, H3)** | ✅ Works | `applyHeader()` in WysiwygActionHandler |
| **Bullet & numbered lists** | ✅ Works | Full list handling with Enter key continuation |
| **Indent/outdent** | ✅ Works | Tab key and toolbar buttons |
| **Links** | ✅ Works | Add link prompt, Edit/Remove link in context menu |
| **Undo/Redo** | ✅ Works | Uses UITextView undo manager (50 levels) |
| **Preview** | ✅ Works | NotePreviewScreen with MarkdownSerialization deserialization |
| **Folders, Pin, Search** | ✅ Works | Cached filtering, batch delete for trash |
| **CloudKit sync** | ✅ Works | Core Data + CloudKit |
| **Tag Editor** | ❌ **Broken** | Shows "Tag Editor - Coming Soon" placeholder. You can create tags in Tag Manager but cannot assign tags to individual notes. |

**Notes Fix Required:**
- [ ] **Implement Tag Editor** – The "Tags" button in the note editor opens a placeholder. Build a proper view to assign/remove tags from the current note (use `note.tags` and `FSTag`).

---

### Journal

| Feature | Status | Notes |
|---------|--------|-------|
| Multiple journals | ✅ Works | Create, edit, delete journals |
| Daily journal (pinned) | ✅ Works | `isDailyJournal` logic, default creation |
| Streak tracking | ✅ Works | `currentStreak`, `longestStreak` computed from entries |
| Word count | ✅ Works | In TodayQuickEntryCard |
| Writing prompts | ✅ Works | PromptPickerView with categories |
| Entry date editing | ✅ Works | DatePicker in NewEntryView |
| **Rich text (bold, bullets)** | ❌ **Mismatch** | README says "Rich Text Editing: Full text formatting with bullet points, indentation, and styling" but the Journal uses plain `TextEditor(text: $text)` - no formatting. |

**Journal Fix Options:**
- [ ] Either add rich text support (e.g. AttributedString or Markdown editor) or update the README to say "plain text" instead of "Rich Text Editing".

---

### Recipes

| Feature | Status | Notes |
|---------|--------|-------|
| Recipe CRUD | ✅ Works | Add, edit, delete recipes |
| Categories | ✅ Works | Breakfast, Lunch, Dinner, etc. |
| Shopping list | ✅ Works | ShoppingListMainView |
| Pantry | ✅ Works | PantryMainView |
| Cook mode / timers | ✅ Works | CookModeViewModel, CookModeTimerView |
| Favorites, search, filter | ✅ Works | RecipeService, FilterSortView |
| Photos | ✅ Works | RecipeImageStore, PhotosUI |

No issues found.

---

### Places

| Feature | Status | Notes |
|---------|--------|-------|
| CRUD, categories | ✅ Works | PlaceCategory, Place model |
| Ratings, photos | ✅ Works | Multiple rating criteria, CloudKitAssetService |
| Visit tracking, notes | ✅ Works | Address, cuisine, best time, etc. |

No issues found.

---

### Want to Watch / Discover

| Feature | Status | Notes |
|---------|--------|-------|
| TMDB search | ✅ Works | SearchManager, TMDBService |
| Add to watchlist | ✅ Works | WantToWatchItem Core Data |
| Filters (Up Next, Watched, All) | ✅ Works | WatchFilter enum |
| Categories (anime, tv, movie) | ✅ Works | orderedCategories |
| Stats | ✅ Works | showingStats |
| **TMDB API key** | ⚠️ **Security** | API key is hardcoded in `TMDBService.swift`. TMDB read-only keys are designed for client use, but consider moving to config for rotation. Not a blocker for App Store. |

---

### Quotes

| Feature | Status | Notes |
|---------|--------|-------|
| Add, edit, categorize | ✅ Works | Categories: Motivation, Wisdom, Love, etc. |
| Display | ✅ Works | Card-based UI |

No issues found.

---

### Todo

| Feature | Status | Notes |
|---------|--------|-------|
| Tabs, tasks | ✅ Works | TodoTab, TodoTask |
| Add, edit, delete | ✅ Works | AddTodoTaskView, EditTodoTabView |
| Recurrence | ✅ Works | createNextRecurrence |

No issues found.

---

### Budget

| Feature | Status | Notes |
|---------|--------|-------|
| Budget tracking | ✅ Works | BudgetManager, BudgetViews |

No issues found.

---

### Calendar

| Feature | Status | Notes |
|---------|--------|-------|
| Events | ✅ Works | CalendarViews, EventKit integration |
| Location field | ✅ Works | TextField for optional location |

No issues found.

---

### Mind Maps

| Feature | Status | Notes |
|---------|--------|-------|
| Create, edit nodes | ✅ Works | MindMapViews |
| Hierarchy | ✅ Works | MindMapNode parent/child |

No issues found.

---

### Settings & Profile

| Feature | Status | Notes |
|---------|--------|-------|
| Profile customization | ✅ Works | ProfileCustomizationView |
| Privacy settings | ✅ Works | PrivacySettingsView |
| iCloud troubleshooting | ✅ Works | CloudKitTroubleshootingView |
| Factory Reset | ✅ Works | Deletes all Core Data entities |
| Menu reorder | ✅ Works | MenuReorderView |

No issues found.

---

## App Store Requirements Checklist

### Required Before Submission

| Requirement | Status | Action |
|-------------|--------|--------|
| **Privacy manifest (PrivacyInfo.xcprivacy)** | ❌ Missing | Required since May 1, 2024. Add `PrivacyInfo.xcprivacy` with NSPrivacyAccessedAPITypes and NSPrivacyCollectedDataTypes. Create via File > New File > App Privacy. |
| **Privacy policy URL** | ⚠️ Unknown | App Store Connect requires a privacy policy URL if you collect any user data. Add in App Store Connect metadata. |
| **Replace placeholder content** | ⚠️ One placeholder | "Tag Editor - Coming Soon" is a placeholder; implement or remove the Tags button until ready. |
| **ITSAppUsesNonExemptEncryption** | ✅ Set | `false` in Info.plist - good for export compliance. |
| **Account / data deletion** | ✅ Covered | Factory Reset deletes all data. If you add accounts later, ensure in-app deletion is available. |

### Permissions (Info.plist)

| Permission | Status |
|------------|--------|
| NSCalendarsFullAccessUsageDescription | ✅ |
| NSPhotoLibraryUsageDescription | ✅ |
| NSPhotoLibraryAddUsageDescription | ✅ |
| NSCameraUsageDescription | In project.pbxproj, not Info.plist – ensure it's in final build |

### Other Recommendations

- [ ] **App Store screenshots** – README says "Screenshots coming soon". Prepare 6.7", 6.5", 5.5" for iPhone.
- [ ] **Metadata** – Ensure app name, subtitle, keywords, and description match the actual features.
- [ ] **Age rating** – Complete questionnaire in App Store Connect.
- [ ] **Test on real device** – Simulator is not sufficient for final validation.
- [ ] **Remove or replace** – No "Coming Soon" or placeholder screens in production builds.

---

## Summary: Items to Fix

### Critical (fix before submission)

1. ~~**Add Privacy manifest**~~ ✅ DONE – Added `InkSlate/PrivacyInfo.xcprivacy`.
2. ~~**Implement or hide Tag Editor**~~ ✅ DONE – Implemented `NoteTagEditorView`.
3. **Ensure Privacy Policy** – Update `AppLegalURLs.privacyPolicy` in SettingsViews.swift with your URL, then add it in App Store Connect.

### High priority

4. **Journal rich text vs README** – Either add rich text to Journal entries or update README to "plain text".
5. **Move TMDB API key** – Prefer config/env over hardcoded key for maintainability.
6. **Show user errors for silent failures** – e.g. `moveNoteToFolder` prints to console but doesn't show an alert; add `@State` error handling.

### Medium priority (from existing NOTES_FEATURE_AUDIT_REPORT)

7. **Review filter cache invalidation** – `performFilteredFilter` uses `searchDebouncer.debouncedText`; ensure cache invalidates when debounced value updates (currently `onReceive` clears cache).
8. **Error handling** – Several `try?` usages (e.g. `purgeOldDeletedNotes`, tag delete) – consider user-facing errors where appropriate.
9. **ProjectSettingsView** – Folder settings (filterBy, groupBy, etc.) don't appear to be used by NotesListView; either wire them up or simplify the settings.

### Low priority

10. **Remove duplicate/invalid menu items** – Ensure Discover/What to Watch is accessible if it's in the menu.
11. **Accessibility** – Verify VoiceOver labels on key controls (e.g. Markdown toolbar).
12. **README** – Update "Screenshots coming soon" once screenshots are added.

---

## Notes on Bold & Formatting

**Does bold work?** Yes. Flow:

1. User taps Bold → `handleMarkdownAction(.bold)` → `WysiwygActionHandler.apply(.bold, to: textView)`
2. For selection: `toggleFontTrait(.traitBold, in: m, range: range)` toggles bold on the selected range.
3. For no selection: `coord.setTypingMode(.bold, enabled: shouldEnable, in: textView)` sets typing attributes.
4. On change: `serializeContent(from: attributedText)` uses `MarkdownSerialization.serialize()` which archives the NSAttributedString (including font traits) and stores base64 + plain text.
5. On load: `MarkdownSerialization.deserialize()` unarchives and restores font attributes, including bold.

Bold, italic, underline, strikethrough, links, headers, and lists are all handled and persisted correctly.
