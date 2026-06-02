import SwiftUI
import CoreData
import CloudKit
import Combine

enum JournalPromptKind {
    case dailyReflection
    case deepExistential
}

// MARK: - JournalBook Extensions
extension JournalBook {
    var lastWrittenDate: Date? {
        guard let viewContext = managedObjectContext else { return nil }
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "book == %@", self)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdDate, ascending: false)]
        request.fetchLimit = 1
        request.returnsObjectsAsFaults = true
        request.includesPropertyValues = true

        return (try? viewContext.fetch(request))?.first?.createdDate
    }
    
    func updateStreak(for date: Date) {
        guard let viewContext = managedObjectContext else { return }
        let calendar = Calendar.current
        let newDay = calendar.startOfDay(for: date)

        let latestDay = lastWrittenDate.map { calendar.startOfDay(for: $0) }
        if let latestDay, newDay < latestDay {
            recomputeStreaks(in: viewContext)
            return
        }

        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "book == %@ AND createdDate < %@", self, newDay as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdDate, ascending: false)]
        request.fetchLimit = 1
        request.returnsObjectsAsFaults = true
        request.includesPropertyValues = true

        let previousDay = (try? viewContext.fetch(request))?.first?.createdDate.map { calendar.startOfDay(for: $0) }

        if let nextDay = calendar.date(byAdding: .day, value: 1, to: newDay) {
            let countReq = NSFetchRequest<NSNumber>(entityName: "JournalEntry")
            countReq.predicate = NSPredicate(
                format: "book == %@ AND createdDate >= %@ AND createdDate < %@",
                self,
                newDay as NSDate,
                nextDay as NSDate
            )
            countReq.resultType = .countResultType
            let entriesToday = (try? viewContext.count(for: countReq)) ?? 0
            if entriesToday > 1 {
                return
            }
        }

        if let previousDay,
           let expected = calendar.date(byAdding: .day, value: -1, to: newDay),
           calendar.isDate(previousDay, inSameDayAs: expected) {
            currentStreak += 1
        } else {
            currentStreak = 1
        }

        if currentStreak > longestStreak {
            longestStreak = currentStreak
        }

        modifiedDate = Date()
        viewContext.saveQuietly(module: "Journal")
    }

    fileprivate func recomputeStreaks(in viewContext: NSManagedObjectContext) {
        let calendar = Calendar.current
        let request = NSFetchRequest<NSDictionary>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "book == %@", self)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["createdDate"]
        request.sortDescriptors = [NSSortDescriptor(key: "createdDate", ascending: true)]

        let rows = (try? viewContext.fetch(request)) ?? []
        let days = rows.compactMap { dict -> Date? in
            guard let date = dict["createdDate"] as? Date else { return nil }
            return calendar.startOfDay(for: date)
        }

        let uniqueDays = Array(Set(days)).sorted()
        guard !uniqueDays.isEmpty else {
            currentStreak = 0
            longestStreak = 0
            modifiedDate = Date()
            viewContext.saveQuietly(module: "Journal")
            return
        }

        var longest = 1
        var running = 1
        for i in 1..<uniqueDays.count {
            let prev = uniqueDays[i - 1]
            let cur = uniqueDays[i]
            if let expected = calendar.date(byAdding: .day, value: 1, to: prev),
               calendar.isDate(cur, inSameDayAs: expected) {
                running += 1
                longest = max(longest, running)
            } else {
                running = 1
            }
        }

        var cursor = calendar.startOfDay(for: Date())
        let daySet = Set(uniqueDays)
        if !daySet.contains(cursor),
           let prev = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = prev
        }
        var current = 0
        while daySet.contains(cursor) {
            current += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        currentStreak = Int32(current)
        longestStreak = Int32(longest)
        modifiedDate = Date()
        viewContext.saveQuietly(module: "Journal")
    }
}

// MARK: - Bookshelf View
struct BookshelfView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \JournalBook.createdDate, ascending: true)]
    ) private var books: FetchedResults<JournalBook>
    
    @State private var showingNewJournal = false
    
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
                            .deleteDisabled(book.isDailyJournal)
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
                ToolbarItem(placement: .primaryAction) {
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
        guard !book.isDailyJournal else { return }
        withAnimation {
            book.modifiedDate = Date()
            
            viewContext.delete(book)

            if !viewContext.inkSlateSave(module: "Journal") {
                viewContext.rollback()
            }
            lightHaptic()
        }
    }
    
    private func createDefaultDailyJournalIfNeeded() {
        PersistenceController.shared.ensureDailyJournalBooksConfiguredFromBookshelf()
    }
}

// MARK: - Journal Book Row
struct JournalBookRow: View {
    let book: JournalBook

    private var entryCount: Int { book.entries?.count ?? 0 }
    
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
                    Text("\(entryCount) entries")
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
            .inlineNavigationTitle()
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
        journal.isDailyJournal = false
        viewContext.insert(journal)
        viewContext.inkSlateSave(module: "Journal")
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
    @FocusState private var isComposerFocused: Bool
    @State private var searchText: String = ""
    @State private var promptDraftForNewEntry: String? = nil
    
    var accentColor: Color { Color(hex: book.color ?? "#007AFF") ?? DesignSystem.Colors.accent }
    
    var body: some View {
        List {
            Section {
                JournalPromptCard(
                    kind: book.isDailyJournal ? .dailyReflection : .deepExistential,
                    accentColor: accentColor,
                    onUsePrompt: { prompt in
                        lightHaptic()
                        if book.isDailyJournal {
                            if newEntryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                newEntryText = prompt
                            } else {
                                newEntryText += "\n\n" + prompt
                            }
                            isComposerFocused = true
                        } else {
                            promptDraftForNewEntry = prompt
                            showingNewEntry = true
                        }
                    }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: DesignSystem.Spacing.lg, bottom: 8, trailing: DesignSystem.Spacing.lg))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if book.isDailyJournal {
                    TodayQuickEntryCard(
                        title: $newEntryTitle,
                        text: $newEntryText,
                        accentColor: accentColor,
                        onCommit: saveInlineEntry
                    )
                    .focused($isComposerFocused)
                    .listRowInsets(EdgeInsets(top: 4, leading: DesignSystem.Spacing.lg, bottom: 8, trailing: DesignSystem.Spacing.lg))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            Section {
                EntriesResultsSection(book: book, searchText: searchText)
            }
            .listSectionSeparator(.hidden, edges: .all)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DesignSystem.Colors.background)
        .refreshable {
            await refreshDataAsync()
        }
        .navigationTitle(book.title ?? "Journal")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    lightHaptic()
                    showingNewEntry = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewEntry) {
            NewEntryView(book: book, initialText: promptDraftForNewEntry)
                .onDisappear {
                    promptDraftForNewEntry = nil
                }
        }
    }
    
    private func saveInlineEntry() {
        guard !newEntryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let entryDate = Date()
        let entry = JournalEntry(context: viewContext)
        entry.title = newEntryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newEntryTitle
        entry.content = newEntryText
        entry.createdDate = entryDate
        entry.modifiedDate = Date()
        entry.id = UUID()
        entry.book = book
        viewContext.insert(entry)
        withAnimation(.spring) { _ = viewContext.inkSlateSave(module: "Journal") }

        if book.isDailyJournal {
            book.updateStreak(for: entryDate)
        }

        newEntryTitle = ""
        newEntryText = ""
        isComposerFocused = false
        lightHaptic()
    }
    
    private func refreshDataAsync() async {
        await MainActor.run {
            viewContext.refreshAllObjects()
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
    }
}

private struct EntriesResultsSection: View {
    let book: JournalBook
    let searchText: String
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest private var entries: FetchedResults<JournalEntry>

    init(book: JournalBook, searchText: String) {
        self.book = book
        self.searchText = searchText

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let predicate: NSPredicate
        if trimmed.isEmpty {
            predicate = NSPredicate(format: "book == %@", book)
        } else {
            predicate = NSPredicate(
                format: "book == %@ AND ((title CONTAINS[cd] %@) OR (content CONTAINS[cd] %@))",
                book,
                trimmed,
                trimmed
            )
        }

        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.createdDate, ascending: false)]
        request.predicate = predicate
        _entries = FetchRequest(fetchRequest: request, animation: .default)
    }

    var body: some View {
        let rows = Array(entries)
        if rows.isEmpty && !book.isDailyJournal {
            EmptyEntriesState(accentColor: Color(hex: book.color ?? "#007AFF") ?? DesignSystem.Colors.accent)
                .padding(DesignSystem.Spacing.lg)
                .listRowInsets(EdgeInsets(top: 8, leading: DesignSystem.Spacing.lg, bottom: 8, trailing: DesignSystem.Spacing.lg))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            ForEach(rows) { entry in
                NavigationLink {
                    EditEntryView(book: book, entry: entry)
                } label: {
                    EntryRow(entry: entry)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 6, leading: DesignSystem.Spacing.lg, bottom: 6, trailing: DesignSystem.Spacing.lg))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        delete(entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        delete(entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func delete(_ entry: JournalEntry) {
        withAnimation {
            viewContext.delete(entry)
            if book.isDailyJournal {
                book.recomputeStreaks(in: viewContext)
            }
            _ = viewContext.inkSlateSave(module: "Journal")
            lightHaptic()
        }
    }
}

private struct JournalPromptCard: View {
    typealias Kind = JournalPromptKind

    let kind: Kind
    let accentColor: Color
    let onUsePrompt: (String) -> Void

    @State private var prompt: String = ""

    private var title: String {
        switch kind {
        case .dailyReflection: return "Daily Prompt"
        case .deepExistential: return "Writing Prompt"
        }
    }

    private var subtitle: String {
        switch kind {
        case .dailyReflection: return "Optional — tap to start writing"
        case .deepExistential: return "Optional — if you want inspiration"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text(subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                Button {
                    withAnimation(.spring) {
                        prompt = JournalPromptLibrary.randomPrompt(for: kind)
                    }
                    lightHaptic()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundColor(accentColor)
                        .padding(8)
                        .background(DesignSystem.Colors.backgroundSecondary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Text(prompt)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onUsePrompt(prompt)
            } label: {
                Text("Use Prompt")
                    .font(DesignSystem.Typography.button)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .background(accentColor)
                    .cornerRadius(DesignSystem.CornerRadius.md)
            }
            .buttonStyle(.plain)
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.lg)
        .onAppear {
            if prompt.isEmpty {
                prompt = JournalPromptLibrary.randomPrompt(for: kind)
            }
        }
    }
}

// MARK: - Today Quick Entry Card
struct TodayQuickEntryCard: View {
    @Binding var title: String
    @Binding var text: String
    var accentColor: Color
    var onCommit: () -> Void

    @State private var wordCount: Int = 0
    
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
                    wordCount = newValue.split(whereSeparator: \.isWhitespace).count
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
        .onAppear {
            wordCount = text.split(whereSeparator: \.isWhitespace).count
        }
    }
}

// MARK: - Entry Row
struct EntryRow: View {
    let entry: JournalEntry
    
    private var displayTitle: String {
        if let title = entry.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        let content = entry.content ?? ""
        let firstLine = content.components(separatedBy: .newlines).first ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(50))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(entry.createdDate ?? Date(), style: .date)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Text(displayTitle)
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
            
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

    init(book: JournalBook, initialText: String? = nil) {
        self.book = book
        _text = State(initialValue: initialText ?? "")
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
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
            .inlineNavigationTitle()
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
                focusedField = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .title : .content
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
        _ = viewContext.inkSlateSave(module: "Journal")

        if book.isDailyJournal {
            book.updateStreak(for: date)
        }

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
        .inlineNavigationTitle()
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
        _ = viewContext.inkSlateSave(module: "Journal")
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
