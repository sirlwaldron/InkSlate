//
//  JournalViews.swift
//  InkSlate
//

import SwiftUI
import CoreData
import CloudKit
import os.log

// MARK: - JournalBook Extensions
extension JournalBook {
    var isDailyJournal: Bool {
        title?.localizedCaseInsensitiveContains("daily") == true
    }
    
    var lastWrittenDate: Date? {
        entries?
            .allObjects
            .compactMap { ($0 as? JournalEntry)?.createdDate }
            .max()
    }
    
    var currentStreak: Int {
        guard let entries = entries?.allObjects as? [JournalEntry],
              !entries.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        let entryDates = Set(entries.compactMap { entry -> Date? in
            guard let date = entry.createdDate else { return nil }
            return calendar.startOfDay(for: date)
        })
        
        guard !entryDates.isEmpty else { return 0 }
        
        var streak = 0
        var cursor = calendar.startOfDay(for: Date())
        
        if !entryDates.contains(cursor),
           let previous = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = previous
        }
        
        while entryDates.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previous
        }
        
        return streak
    }
    
    var longestStreak: Int {
        guard let entries = entries?.allObjects as? [JournalEntry],
              !entries.isEmpty else { return 0 }
        
        // Get all unique dates with entries (normalized to start of day)
        let calendar = Calendar.current
        let entryDates = Set(entries.compactMap { entry -> Date? in
            guard let date = entry.createdDate else { return nil }
            return calendar.startOfDay(for: date)
        })
        
        guard !entryDates.isEmpty else { return 0 }
        
        // Sort dates in ascending order
        let sortedDates = entryDates.sorted(by: <)
        
        // Calculate longest consecutive streak
        var longestStreak = 1
        var currentStreak = 1
        
        for i in 1..<sortedDates.count {
            let currentDate = sortedDates[i]
            let previousDate = sortedDates[i - 1]
            
            if let nextExpectedDate = calendar.date(byAdding: .day, value: 1, to: previousDate),
               calendar.isDate(currentDate, inSameDayAs: nextExpectedDate) {
                // Consecutive day
                currentStreak += 1
                longestStreak = max(longestStreak, currentStreak)
            } else {
                // Gap found, reset current streak
                currentStreak = 1
            }
        }
        
        return longestStreak
    }
    
    func updateStreak(for date: Date) {
        // Streaks are calculated dynamically from entries
        // This method is kept for potential future use if we need to cache streak values
        // For now, streaks are calculated on-demand via computed properties
    }
}

fileprivate struct JournalPromptMetadata: Codable {
    let prompt: String
    let category: String
    let type: String
}

fileprivate let promptMetadataEncoder = JSONEncoder()
fileprivate let promptMetadataDecoder = JSONDecoder()

extension JournalEntry {
    fileprivate var promptMetadata: JournalPromptMetadata? {
        guard let tags,
              let data = tags.data(using: .utf8),
              let metadata = try? promptMetadataDecoder.decode(JournalPromptMetadata.self, from: data) else {
            return nil
        }
        return metadata
    }
}

// MARK: - Bookshelf View
struct BookshelfView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \JournalBook.createdDate, ascending: true)]
    ) private var books: FetchedResults<JournalBook>
    
    @State private var showingNewJournal = false
    private let logger = Logger(subsystem: "com.lucas.InkSlateNew", category: "Journal")
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                
                if books.isEmpty {
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 44))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        Text("No Journals")
                            .font(DesignSystem.Typography.title3)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        Text("Tap + to create your first journal")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(books) { book in
                            NavigationLink {
                                EntriesListView(book: book)
                            } label: {
                                JournalBookRow(book: book)
                            }
                            .listRowBackground(DesignSystem.Colors.surface)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let book = books[index]
                                if !book.isDailyJournal {
                                    deleteBook(book)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Journals")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        lightHaptic()
                        showingNewJournal = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewJournal) {
                NewJournalView()
            }
            .onAppear {
                createDefaultDailyJournalIfNeeded()
            }
        }
    }
    
    private func deleteBook(_ book: JournalBook) {
        withAnimation {
            // Update modifiedDate before deletion for proper CloudKit sync tracking
            book.modifiedDate = Date()
            
            // Delete all entries first (cascade deletion) to ensure proper CloudKit sync
            if let entries = book.entries as? Set<JournalEntry> {
                for entry in entries {
                    entry.modifiedDate = Date()
                    viewContext.delete(entry)
                }
            }
            
            viewContext.delete(book)
            
            do {
                try viewContext.save()
                logger.info("✅ JournalBook deleted successfully: \(book.title ?? "Unknown")")
            } catch {
                logger.error("❌ Failed to delete JournalBook: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    if nsError.domain == CKErrorDomain {
                        logger.error("CloudKit error details: \(nsError.userInfo)")
                        // CloudKit errors - might be network issue or schema conflict
                        if let ckError = error as? CKError {
                            switch ckError.code {
                            case .notAuthenticated:
                                logger.warning("⚠️ Not authenticated with iCloud - deletion may not sync")
                            case .networkUnavailable:
                                logger.warning("⚠️ Network unavailable - deletion will sync when online")
                            case .serverRecordChanged:
                                logger.warning("⚠️ Record changed on server - may need to retry")
                            default:
                                break
                            }
                        }
                    }
                }
            }
            lightHaptic()
        }
    }
    
    private func createDefaultDailyJournalIfNeeded() {
        let fetchRequest: NSFetchRequest<JournalBook> = JournalBook.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "title ==[c] %@", "Daily Journal")
        fetchRequest.fetchLimit = 1
        
        if (try? viewContext.fetch(fetchRequest).first) != nil {
            return
        }
        
        guard !books.contains(where: { $0.title?.localizedCaseInsensitiveCompare("Daily Journal") == .orderedSame }) else {
            return
        }
        
        let dailyJournal = JournalBook(context: viewContext)
        dailyJournal.title = "Daily Journal"
        dailyJournal.color = "#2E7D32"
        dailyJournal.id = UUID()
        dailyJournal.createdDate = Date()
        dailyJournal.modifiedDate = Date()
        
        try? viewContext.save()
    }
}

// MARK: - Journal Book Row
struct JournalBookRow: View {
    let book: JournalBook
    
    // Use FetchRequest for reactive entry count
    @FetchRequest private var entries: FetchedResults<JournalEntry>
    
    init(book: JournalBook) {
        self.book = book
        _entries = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "book == %@", book),
            animation: .default
        )
    }
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Circle()
                .fill(Color(hex: book.color ?? "#007AFF") ?? DesignSystem.Colors.accent)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(book.title ?? "Untitled")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    if book.isDailyJournal {
                        Text("Daily")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignSystem.Colors.backgroundTertiary)
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: DesignSystem.Spacing.md) {
                    Text("\(entries.count) entries")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    if book.isDailyJournal && book.currentStreak > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("\(book.currentStreak)")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }
}

// MARK: - New Journal View
struct NewJournalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var title = ""
    @State private var selectedColor = "#2E7D32"
    @FocusState private var isTitleFocused: Bool
    
    private let colors = [
        "#2E7D32", "#1565C0", "#E65100",
        "#4A148C", "#C62828", "#F57F17",
        "#00838F", "#6A1B9A"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Journal name", text: $title)
                        .focused($isTitleFocused)
                } header: {
                    Text("Name")
                }
                
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(colors, id: \.self) { color in
                            Button {
                                selectedColor = color
                                lightHaptic()
                            } label: {
                                Circle()
                                    .fill(Color(hex: color) ?? .gray)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: selectedColor == color ? 2 : 0)
                                            .padding(-2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Color")
                }
            }
            .navigationTitle("New Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createJournal() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                isTitleFocused = true
            }
        }
    }
    
    private func createJournal() {
        let journal = JournalBook(context: viewContext)
        journal.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        journal.color = selectedColor
        journal.id = UUID()
        journal.createdDate = Date()
        journal.modifiedDate = Date()
        viewContext.insert(journal)
        try? viewContext.save()
        lightHaptic()
        dismiss()
    }
}

// MARK: - Entries List View
struct EntriesListView: View {
    let book: JournalBook
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingNewEntry = false
    @State private var newEntryTitle = ""
    @State private var newEntryText = ""
    @State private var wordCount = 0
    @State private var isRefreshing = false
    @FocusState private var isComposerFocused: Bool
    
    // Use FetchRequest for reactive updates
    @FetchRequest private var entries: FetchedResults<JournalEntry>
    
    init(book: JournalBook) {
        self.book = book
        _entries = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \JournalEntry.createdDate, ascending: false)],
            predicate: NSPredicate(format: "book == %@", book),
            animation: .default
        )
    }
    
    var accentColor: Color { Color(hex: book.color ?? "#007AFF") ?? DesignSystem.Colors.accent }
    
    var sortedEntries: [JournalEntry] {
        Array(entries)
    }
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()
            
            ScrollView {
                RefreshControl(isRefreshing: $isRefreshing) {
                    refreshData()
                }
                VStack(spacing: DesignSystem.Spacing.md) {
                    if book.isDailyJournal {
                        TodayQuickEntryCard(
                            title: $newEntryTitle,
                            text: $newEntryText,
                            wordCount: $wordCount,
                            accentColor: accentColor,
                            onCommit: saveInlineEntry
                        )
                        .focused($isComposerFocused)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.top, DesignSystem.Spacing.md)
                    }
                    
                    if sortedEntries.isEmpty && !book.isDailyJournal {
                        EmptyEntriesState(accentColor: accentColor)
                            .padding(DesignSystem.Spacing.lg)
                    } else if !sortedEntries.isEmpty {
                        VStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(sortedEntries) { entry in
                                NavigationLink {
                                    EditEntryView(book: book, entry: entry)
                                } label: {
                                    EntryRow(entry: entry)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        delete(entry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.top, DesignSystem.Spacing.sm)
                    }
                }
                .padding(.bottom, DesignSystem.Spacing.xl)
            }
        }
        .navigationTitle(book.title ?? "Journal")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    lightHaptic()
                    showingNewEntry = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewEntry) {
            NewEntryView(book: book)
        }
    }
    
    private func saveInlineEntry() {
        guard !newEntryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let entry = JournalEntry(context: viewContext)
        entry.title = newEntryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newEntryTitle
        entry.content = newEntryText
        entry.createdDate = Date()
        entry.modifiedDate = Date()
        entry.id = UUID()
        entry.book = book
        viewContext.insert(entry)
        withAnimation(.spring) { try? viewContext.save() }
        newEntryTitle = ""
        newEntryText = ""
        wordCount = 0
        isComposerFocused = false
        lightHaptic()
    }
    
    private func delete(_ entry: JournalEntry) {
        withAnimation {
            viewContext.delete(entry)
            try? viewContext.save()
            lightHaptic()
        }
    }
    
    private func refreshData() {
        viewContext.refreshAllObjects()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isRefreshing = false
        }
    }
}

// MARK: - Today Quick Entry Card
struct TodayQuickEntryCard: View {
    @Binding var title: String
    @Binding var text: String
    @Binding var wordCount: Int
    var accentColor: Color
    var onCommit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Today's Entry")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Spacer()
                Text("\(wordCount) words")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            TextField("Title (optional)", text: $title)
                .font(DesignSystem.Typography.body)
                .padding(DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.backgroundSecondary)
                .cornerRadius(DesignSystem.CornerRadius.sm)
            
            TextEditor(text: $text)
                .font(DesignSystem.Typography.body)
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .background(DesignSystem.Colors.backgroundSecondary)
                .cornerRadius(DesignSystem.CornerRadius.sm)
                .onChange(of: text) { _, newValue in
                    wordCount = newValue
                        .components(separatedBy: .whitespacesAndNewlines)
                        .filter { !$0.isEmpty }
                        .count
                }
            
            Button {
                onCommit()
            } label: {
                Text("Save Entry")
                    .font(DesignSystem.Typography.button)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .background(text.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : accentColor)
                    .cornerRadius(DesignSystem.CornerRadius.md)
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.lg)
    }
}

// MARK: - Entry Row
struct EntryRow: View {
    let entry: JournalEntry
    
    private var displayTitle: String {
        if let title = entry.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        // Use first line of content as fallback title
        let content = entry.content ?? ""
        let firstLine = content.components(separatedBy: .newlines).first ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(50))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            // Date
            Text(entry.createdDate ?? Date(), style: .date)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            // Title
            Text(displayTitle)
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
            
            // Content Preview
            if let content = entry.content, !content.isEmpty {
                Text(content.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.md)
        .padding(.horizontal, DesignSystem.Spacing.lg)
    }
}

// MARK: - Empty Entries State
struct EmptyEntriesState: View {
    var accentColor: Color
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 48))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            Text("No Entries Yet")
                .font(DesignSystem.Typography.title2)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            Text("Start writing your first entry.")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

// MARK: - New Entry View
struct NewEntryView: View {
    let book: JournalBook
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var title = ""
    @State private var text = ""
    @State private var date = Date()
    @FocusState private var focusedField: Field?
    
    enum Field { case title, content }
    
    var accentColor: Color { Color(hex: book.color ?? "#007AFF") ?? DesignSystem.Colors.accent }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    // Title Field
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text("Title")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        TextField("Entry title (optional)", text: $title)
                            .font(DesignSystem.Typography.title3)
                            .focused($focusedField, equals: .title)
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                    
                    // Date Picker
                    HStack {
                        Text("Date")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        Spacer()
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                    
                    // Content Field
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text("Content")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        TextEditor(text: $text)
                            .font(DesignSystem.Typography.body)
                            .frame(minHeight: 200)
                            .focused($focusedField, equals: .content)
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEntry() }
                        .fontWeight(.semibold)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                focusedField = .title
            }
        }
    }
    
    private func saveEntry() {
        let entry = JournalEntry(context: viewContext)
        entry.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title
        entry.content = text
        entry.createdDate = date
        entry.modifiedDate = Date()
        entry.id = UUID()
        entry.book = book
        viewContext.insert(entry)
        try? viewContext.save()
        lightHaptic()
        dismiss()
    }
}

// MARK: - Edit Entry View
struct EditEntryView: View {
    let book: JournalBook
    let entry: JournalEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var title: String
    @State private var text: String
    @FocusState private var focusedField: Field?
    
    enum Field { case title, content }
    
    init(book: JournalBook, entry: JournalEntry) {
        self.book = book
        self.entry = entry
        _title = State(initialValue: entry.title ?? "")
        _text = State(initialValue: entry.content ?? "")
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Title Field
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Title")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    TextField("Entry title (optional)", text: $title)
                        .font(DesignSystem.Typography.title3)
                        .focused($focusedField, equals: .title)
                }
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.surface)
                .cornerRadius(DesignSystem.CornerRadius.md)
                
                // Date Display
                HStack {
                    Text("Created")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Spacer()
                    Text(entry.createdDate ?? Date(), style: .date)
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.surface)
                .cornerRadius(DesignSystem.CornerRadius.md)
                
                // Content Field
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Content")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    TextEditor(text: $text)
                        .font(DesignSystem.Typography.body)
                        .frame(minHeight: 300)
                        .focused($focusedField, equals: .content)
                }
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.surface)
                .cornerRadius(DesignSystem.CornerRadius.md)
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(DesignSystem.Colors.background)
        .navigationTitle("Edit Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveEntry() }
                    .fontWeight(.semibold)
            }
        }
    }
    
    private func saveEntry() {
        entry.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title
        entry.content = text
        entry.modifiedDate = Date()
        try? viewContext.save()
        lightHaptic()
        dismiss()
    }
}

// MARK: - Prompt Picker View
struct PromptPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedPrompt: String
    @Binding var selectedPromptCategory: String
    @Binding var selectedPromptType: PromptType
    
    @State private var selectedCategory: PromptCategory = .reflection
    @State private var showingPrompts = false
    
    private let promptData = JournalPromptData.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xxl) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        Text("Choose a Category")
                            .font(DesignSystem.Typography.title3)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: DesignSystem.Spacing.lg) {
                            ForEach(PromptCategory.allCases, id: \.self) { category in
                                Button {
                                    withAnimation(.spring) {
                                        selectedCategory = category
                                        showingPrompts = true
                                        lightHaptic()
                                    }
                                } label: {
                                    VStack(spacing: DesignSystem.Spacing.sm) {
                                        Image(systemName: category.icon)
                                            .font(.title3)
                                            .foregroundColor(Color(hex: category.color) ?? .blue)
                                        Text(category.displayName)
                                            .font(DesignSystem.Typography.body)
                                            .foregroundColor(DesignSystem.Colors.textPrimary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 80)
                                    .padding(DesignSystem.Spacing.lg)
                                    .background(DesignSystem.Colors.surface)
                                    .cornerRadius(DesignSystem.CornerRadius.lg)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                                            .stroke(Color(hex: category.color) ?? DesignSystem.Colors.border, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    Button {
                        let prompt = promptData.getRandomPrompt(category: selectedCategory, type: .reflection)
                        selectedPrompt = prompt
                        selectedPromptCategory = selectedCategory.rawValue
                        selectedPromptType = .reflection
                        lightHaptic()
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Get Random Prompt")
                                .fontWeight(.medium)
                        }
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textInverse)
                        .padding(.vertical, DesignSystem.Spacing.lg)
                        .frame(maxWidth: .infinity)
                        .background(DesignSystem.Colors.accent)
                        .cornerRadius(DesignSystem.CornerRadius.md)
                    }
                    .buttonStyle(.plain)
                }
                .padding(DesignSystem.Spacing.xl)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Writing Prompts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(DesignSystem.Colors.accent)
                }
            }
        }
        .sheet(isPresented: $showingPrompts) {
            PromptCategoryView(
                category: selectedCategory,
                selectedPrompt: $selectedPrompt,
                selectedPromptCategory: $selectedPromptCategory,
                selectedPromptType: $selectedPromptType
            )
            .presentationDetents([.fraction(0.5), .large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Prompt Category View
struct PromptCategoryView: View {
    let category: PromptCategory
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedPrompt: String
    @Binding var selectedPromptCategory: String
    @Binding var selectedPromptType: PromptType
    
    private let promptData = JournalPromptData.shared
    
    var prompts: [String] {
        promptData.getAllPrompts(for: category, type: .reflection)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.md) {
                ForEach(prompts, id: \.self) { prompt in
                        Button {
                        selectedPrompt = prompt
                        selectedPromptCategory = category.rawValue
                        selectedPromptType = .reflection
                            lightHaptic()
                        dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text(prompt)
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                .multilineTextAlignment(.leading)
                            
                                HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: category.icon)
                                    .font(.caption)
                                    .foregroundColor(Color(hex: category.color) ?? .blue)
                                    Text(category.displayName)
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                Spacer()
                                }
                            }
                            .padding(DesignSystem.Spacing.md)
                            .background(DesignSystem.Colors.surface)
                            .cornerRadius(DesignSystem.CornerRadius.sm)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                                    .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle(category.displayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                        .foregroundColor(DesignSystem.Colors.accent)
                }
            }
        }
    }
}

// MARK: - Journal Prompt Types
enum PromptType: String, CaseIterable {
    case reflection = "reflection"
    case gratitude = "gratitude"
    case goal = "goal"
    case memory = "memory"
    case creative = "creative"
    
    var displayName: String {
        switch self {
        case .reflection: return "Reflection"
        case .gratitude: return "Gratitude"
        case .goal: return "Goal Setting"
        case .memory: return "Memory"
        case .creative: return "Creative Writing"
        }
    }
}

enum PromptCategory: String, CaseIterable {
    case reflection = "reflection"
    case gratitude = "gratitude"
    case goal = "goal"
    case memory = "memory"
    case creative = "creative"
    
    var displayName: String {
        switch self {
        case .reflection: return "Reflection"
        case .gratitude: return "Gratitude"
        case .goal: return "Goal Setting"
        case .memory: return "Memory"
        case .creative: return "Creative Writing"
        }
    }
    
    var icon: String {
        switch self {
        case .reflection: return "brain.head.profile"
        case .gratitude: return "heart.fill"
        case .goal: return "target"
        case .memory: return "photo"
        case .creative: return "paintbrush.fill"
        }
    }
    
    var color: String {
        switch self {
        case .reflection: return "#4A90E2"
        case .gratitude: return "#7ED321"
        case .goal: return "#F5A623"
        case .memory: return "#9013FE"
        case .creative: return "#D0021B"
        }
    }
    
    var prompts: [String] {
        switch self {
        case .reflection:
            return [
                "What was the most challenging part of your day?",
                "What did you learn about yourself today?",
                "How did you grow today?",
                "What would you do differently if you could relive today?",
                "What patterns do you notice in your thoughts today?"
            ]
        case .gratitude:
            return [
                "What are three things you're grateful for today?",
                "Who made a positive impact on your day?",
                "What small moment brought you joy today?",
                "What are you grateful for about yourself?",
                "What in nature are you grateful for today?"
            ]
        case .goal:
            return [
                "What is one goal you want to achieve this week?",
                "What steps did you take toward your goals today?",
                "What obstacles are preventing you from reaching your goals?",
                "How do you define success for yourself?",
                "What new skill would you like to learn?"
            ]
        case .memory:
            return [
                "Describe a favorite childhood memory.",
                "What was the best day you had this month?",
                "Write about a person who influenced you.",
                "What tradition from your family do you cherish?",
                "Describe a place that holds special meaning for you."
            ]
        case .creative:
            return [
                "Write a short story about a character who finds a mysterious key.",
                "Describe your ideal day in detail.",
                "Write a letter to your future self.",
                "Create a poem about the changing seasons.",
                "Imagine you could have dinner with anyone, living or dead. Who would it be and why?"
            ]
        }
    }
}

class JournalPromptData: ObservableObject {
    static let shared = JournalPromptData()
    
    private init() {}
    
    func getRandomPrompt(for category: PromptCategory) -> String {
        let prompts = category.prompts
        return prompts.randomElement() ?? "Write about your day."
    }
    
    func getAllPrompts() -> [PromptCategory: [String]] {
        var allPrompts: [PromptCategory: [String]] = [:]
        for category in PromptCategory.allCases {
            allPrompts[category] = category.prompts
        }
        return allPrompts
    }
    
    func getRandomPrompt(category: PromptCategory, type: PromptType) -> String {
        return getRandomPrompt(for: category)
    }
    
    func getAllPrompts(for category: PromptCategory, type: PromptType) -> [String] {
        return category.prompts
    }
}
