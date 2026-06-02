import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif
import CoreData

// MARK: - Sort Options

// MARK: - Main Notes List View
struct NotesListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var persistence = PersistenceController.shared
    @FetchRequest private var normalNotes: FetchedResults<Notes>
    @FetchRequest private var deletedNotes: FetchedResults<Notes>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FSProject.name, ascending: true)]
    ) private var projects: FetchedResults<FSProject>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FSTag.name, ascending: true)]
    ) private var allTags: FetchedResults<FSTag>

    @StateObject private var searchDebouncer = SearchDebouncer(delay: 0.4)
    @State private var searchQuery: String = ""

    @State private var showingNewNoteSheet = false
    @State private var selectedNote: Notes?
    @State private var selectedProject: FSProject?
    @State private var showingFoldersSheet = false
    @State private var showingNewProjectSheet = false
    @State private var showingProjectSettings = false
    @State private var showingTagManager = false
    @State private var noteToMove: Notes?
    @State private var noteForDetails: Notes?
    @State private var showingNoteDetails = false
    
    @AppStorage("lastSelectedFolderID") private var lastSelectedFolderID: String?

    @State private var sortBy: SortBy = .modificationDate
    @State private var sortDirection: SortDirection = .descending
    @State private var showPinnedOnly = false

    @State private var showingDeletedNotes = false
    @State private var showingEmptyTrashAlert = false

    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isLoading = false

    @State private var filteredNoteIDs: [NSManagedObjectID] = []
    @State private var isFiltering = false
    @State private var refreshWorkItem: DispatchWorkItem?
    
    @State private var notesChromeAppeared = false
    
    init() {
        let defaultSort = [NSSortDescriptor(key: "modifiedDate", ascending: false)]
        
        let normalRequest = NSFetchRequest<Notes>(entityName: "Notes")
        normalRequest.sortDescriptors = defaultSort
        normalRequest.predicate = NSPredicate(format: "isMarkedDeleted == NO")
        normalRequest.fetchBatchSize = 50
        _normalNotes = FetchRequest(fetchRequest: normalRequest, animation: .default)
        
        let deletedRequest = NSFetchRequest<Notes>(entityName: "Notes")
        deletedRequest.sortDescriptors = defaultSort
        deletedRequest.predicate = NSPredicate(format: "isMarkedDeleted == YES")
        deletedRequest.fetchBatchSize = 50
        _deletedNotes = FetchRequest(fetchRequest: deletedRequest, animation: .default)
    }
    
    private var defaultProject: FSProject? {
        projects.first { $0.isDefault } ?? projects.first
    }
    
    private func loadLastSelectedFolder() {
        guard let folderIDString = lastSelectedFolderID,
              let folderID = UUID(uuidString: folderIDString) else {
            selectedProject = nil
            return
        }
        
        if let savedFolder = projects.first(where: { $0.id == folderID }) {
            selectedProject = savedFolder
        } else {
            selectedProject = nil
            lastSelectedFolderID = nil
        }
    }
    
    private func saveLastSelectedFolder(_ folder: FSProject?) {
        if let folder = folder {
            lastSelectedFolderID = folder.id?.uuidString
        } else {
            lastSelectedFolderID = nil
        }
    }

    private var activeNotes: FetchedResults<Notes> {
        showingDeletedNotes ? deletedNotes : normalNotes
    }

    private var tagColorByLowercasedName: [String: String] {
        var dict: [String: String] = [:]
        for tag in allTags {
            let name = (tag.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            if dict[key] == nil { dict[key] = tag.color }
        }
        return dict
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    notesHeroHeader
                    notesSearchAndFilters
                    if filteredNotes.isEmpty, !isFiltering {
                        notesEmptyState
                    } else if isFiltering {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading notes…")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        .padding(.top, 40)
                    } else {
                        notesListView
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignSystem.Colors.background, for: .navigationBar)
            .overlay { if isLoading { loadingOverlay } }
                .sheet(isPresented: $showingFoldersSheet) {
                    FoldersListView(selectedProject: $selectedProject, showingNewProjectSheet: $showingNewProjectSheet)
                }
                .sheet(isPresented: $showingNewNoteSheet) { 
                    NewNoteView(selectedProject: selectedProject)
                }
                .sheet(isPresented: $showingNewProjectSheet) {
                    NewProjectView()
                }
                .sheet(isPresented: $showingProjectSettings) {
                    if let project = selectedProject {
                        ProjectSettingsView(project: project)
                    }
                }
                .sheet(isPresented: $showingTagManager) {
                    TagManagerView()
                }
                .sheet(item: $noteToMove) { note in
                    MoveToFolderView(note: note) {
                        noteToMove = nil
                    }
                }
            .sheet(item: $selectedNote) { note in
                Group {
                    if note.isMarkedDeleted {
                        Text("This note is in Recently Deleted. Restore it from the Trash list to edit.")
                            .padding()
                    } else if note.isDeleted {
                        Text("This note is no longer available.")
                            .padding()
                    } else {
                        TextEditorView(note: note, tagColorByLowercasedName: tagColorByLowercasedName)
                    }
                }
            }
            .alert("Error", isPresented: $showingError) { Button("OK") {} } message: { Text(errorMessage) }
            .alert("Note Details", isPresented: $showingNoteDetails) {
                Button("OK", role: .cancel) {
                    noteForDetails = nil
                }
            } message: {
                let created = (noteForDetails?.createdDate ?? Date()).formatted(.dateTime.month(.abbreviated).day().year(.defaultDigits))
                let modified = (noteForDetails?.modifiedDate ?? noteForDetails?.createdDate ?? Date()).formatted(.dateTime.month(.abbreviated).day().year(.defaultDigits))
                Text("Created: \(created)\nLast edited: \(modified)")
            }
            .onAppear {
                NotesEncryptionRemoval.migrateIfNeeded(in: viewContext)
                purgeOldDeletedNotes()
                loadLastSelectedFolder()
                refreshFilteredNotes()
                withAnimation(.easeOut(duration: 0.45)) {
                    notesChromeAppeared = true
                }
            }
            .onReceive(searchDebouncer.$debouncedText) { value in
                searchQuery = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .onChange(of: selectedProject) { _, newValue in
                saveLastSelectedFolder(newValue)
            }
            .onChange(of: showingDeletedNotes) { _, _ in refreshFilteredNotes() }
            .onChange(of: selectedProject?.objectID) { _, _ in refreshFilteredNotes() }
            .onChange(of: showPinnedOnly) { _, _ in refreshFilteredNotes() }
            .onChange(of: sortBy) { _, _ in refreshFilteredNotes() }
            .onChange(of: sortDirection) { _, _ in refreshFilteredNotes() }
            .onChange(of: searchDebouncer.debouncedText) { _, _ in refreshFilteredNotes() }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: viewContext)) { _ in
                scheduleRefreshFilteredNotes(debounce: 0.35)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cloudKitDataRefreshed)) { _ in
                scheduleRefreshFilteredNotes(debounce: 0.35)
            }
        }
        }
    }

// MARK: - Folders List View (Sheet)
struct FoldersListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Notes.modifiedDate, ascending: false)],
        predicate: NSPredicate(format: "isMarkedDeleted == NO")
    ) private var normalNotes: FetchedResults<Notes>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FSProject.name, ascending: true)]
    ) private var projects: FetchedResults<FSProject>
    
    @Binding var selectedProject: FSProject?
    @Binding var showingNewProjectSheet: Bool
    
    @AppStorage("lastSelectedFolderID") private var lastSelectedFolderID: String?
    
    @State private var projectToDelete: FSProject?
    @State private var showingDeleteAlert = false
    @State private var showingFolderSaveError = false
    @State private var folderSaveErrorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        Text("Folders")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .padding(.top, DesignSystem.Spacing.sm)
                        
                        folderSelectCard(
                            title: "All notes",
                            subtitle: "\(normalNotes.count) notes",
                            isSelected: selectedProject == nil,
                            systemImage: "square.grid.2x2"
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                selectedProject = nil
                            }
                            saveFolderSelection(nil)
                            dismiss()
                        }
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        
                        if !projects.isEmpty {
                            Text("Your folders")
                                .font(DesignSystem.Typography.headline)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .padding(.horizontal, DesignSystem.Spacing.lg)
                            
                            ForEach(projects) { project in
                                folderSelectCard(
                                    title: project.name ?? "Unnamed folder",
                                    subtitle: folderNoteCount(project),
                                    isSelected: selectedProject?.id == project.id,
                                    systemImage: "folder"
                                ) {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                        selectedProject = project
                                    }
                                    saveFolderSelection(project)
                                    dismiss()
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        projectToDelete = project
                                        showingDeleteAlert = true
                                    } label: {
                                        Label("Delete folder", systemImage: "trash")
                                    }
                                }
                                .padding(.horizontal, DesignSystem.Spacing.lg)
                            }
                        }
                        
                        Button {
                            showingNewProjectSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("New folder")
                                    .font(DesignSystem.Typography.button)
                            }
                            .foregroundColor(DesignSystem.Colors.textInverse)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignSystem.Spacing.lg)
                            .background(DesignSystem.Colors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.top, DesignSystem.Spacing.sm)
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignSystem.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(DesignSystem.Typography.button)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewProjectSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                }
            }
            .alert("Delete Folder", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { projectToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let project = projectToDelete {
                        deleteProject(project)
                        projectToDelete = nil
                    }
                }
            } message: {
                Text("Are you sure you want to delete this folder? All notes in this folder will be moved to 'All Notes'.")
            }
            .sheet(isPresented: $showingNewProjectSheet) {
                NewProjectView()
            }
            .alert("Couldn’t save", isPresented: $showingFolderSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(folderSaveErrorMessage)
            }
        }
    }
    
    @ViewBuilder
    private func folderSelectCard(
        title: String,
        subtitle: String,
        isSelected: Bool,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md, style: .continuous)
                        .fill(DesignSystem.Colors.backgroundTertiary)
                        .frame(width: 44, height: 44)
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(DesignSystem.Typography.title3)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text(subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.accent)
                        .font(.system(size: 18, weight: .medium))
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                    .stroke(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func folderNoteCount(_ project: FSProject) -> String {
        guard let notes = project.notes as? Set<Notes> else { return "0 notes" }
        let n = notes.filter { !$0.isMarkedDeleted }.count
        return "\(n) notes"
    }
    
    private func deleteProject(_ project: FSProject) {
        mediumHaptic()
        
        if selectedProject?.id == project.id {
            selectedProject = nil
        }
        
        if let notes = project.notes as? Set<Notes> {
            for note in notes {
                note.project = nil
                note.modifiedDate = Date()
            }
        }
        
        viewContext.delete(project)
        
        if !viewContext.inkSlateSave(module: "Notes") {
            folderSaveErrorMessage = "Failed to delete folder."
            showingFolderSaveError = true
        }
    }
    
    private func saveFolderSelection(_ folder: FSProject?) {
        if let folder = folder {
            lastSelectedFolderID = folder.id?.uuidString
        } else {
            lastSelectedFolderID = nil
        }
    }
}

extension NotesListView {
    private var notesHeroHeader: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(showingDeletedNotes ? "Recently deleted" : "Notes")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text(notesHeroSubtitle)
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                Spacer(minLength: 0)
                if showingDeletedNotes {
                    Button {
                        lightHaptic()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            showingDeletedNotes = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.backward")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Notes")
                                .font(DesignSystem.Typography.button)
                        }
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(DesignSystem.Colors.surface)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(DesignSystem.Colors.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to notes")
                } else {
                    HStack(spacing: DesignSystem.Spacing.md) {
                        Button {
                            lightHaptic()
                            showingTagManager = true
                        } label: {
                            Image(systemName: "tag")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .frame(width: 36, height: 36)
                                .background(DesignSystem.Colors.surface)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(DesignSystem.Colors.border, lineWidth: 1))
                        }
                        .accessibilityLabel("Tags")
                        if selectedProject != nil {
                            Button {
                                lightHaptic()
                                showingProjectSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                    .frame(width: 36, height: 36)
                                    .background(DesignSystem.Colors.surface)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(DesignSystem.Colors.border, lineWidth: 1))
                            }
                            .accessibilityLabel("Folder settings")
                        }
                        Button {
                            mediumHaptic()
                            showingNewNoteSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textInverse)
                                .frame(width: 40, height: 40)
                                .background(DesignSystem.Colors.accent)
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("New note")
                    }
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.md)
        .opacity(notesChromeAppeared ? 1 : 0)
        .offset(y: notesChromeAppeared ? 0 : -10)
    }
    
    private var notesHeroSubtitle: String {
        if showingDeletedNotes {
            return "Permanently removed after 30 days"
        }
        if let p = selectedProject, let name = p.name, !name.isEmpty {
            return "Folder · \(name)"
        }
        return "Capture ideas in one place"
    }
    
    private var notesSearchAndFilters: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            SearchBar(text: $searchDebouncer.searchText)
                .padding(.horizontal, DesignSystem.Spacing.lg)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Button {
                        lightHaptic()
                        showingFoldersSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 13, weight: .medium))
                            Text(folderChipTitle)
                                .font(DesignSystem.Typography.headline)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.vertical, 10)
                        .background(DesignSystem.Colors.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(DesignSystem.Colors.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose folder")
                    if !showingDeletedNotes {
                        Button {
                            lightHaptic()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                showingDeletedNotes = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Deleted")
                                    .font(DesignSystem.Typography.headline)
                            }
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .padding(.vertical, 10)
                            .background(DesignSystem.Colors.surface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(DesignSystem.Colors.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        NotesFilterPill(
                            title: "Pinned",
                            icon: "pin.fill",
                            isOn: showPinnedOnly
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showPinnedOnly.toggle()
                            }
                        }
                        Menu {
                            Section("Sort by") {
                                Button("Modified") { sortBy = .modificationDate }
                                Button("Created") { sortBy = .creationDate }
                                Button("Title") { sortBy = .title }
                                Button("Pin") { sortBy = .pin }
                            }
                            Section("Order") {
                                Button("Ascending") { sortDirection = .ascending }
                                Button("Descending") { sortDirection = .descending }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Sort")
                                    .font(DesignSystem.Typography.headline)
                            }
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .padding(.vertical, 10)
                            .background(DesignSystem.Colors.surface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(DesignSystem.Colors.border, lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
            }
        }
        .padding(.bottom, DesignSystem.Spacing.sm)
        .opacity(notesChromeAppeared ? 1 : 0)
        .offset(y: notesChromeAppeared ? 0 : 6)
    }
    
    private var folderChipTitle: String {
        selectedProject?.name ?? "All notes"
    }
    
    private var notesEmptyState: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.backgroundSecondary)
                    .frame(width: 88, height: 88)
                Image(systemName: showingDeletedNotes ? "trash" : "note.text")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text(showingDeletedNotes ? "Trash is empty" : (searchQuery.isEmpty ? "No notes yet" : "Nothing matches"))
                    .font(DesignSystem.Typography.title2)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text(showingDeletedNotes ? "Deleted notes appear here." : (searchQuery.isEmpty ? "Start with a new note — tap the + button above." : "Try a different search or folder."))
                    .font(DesignSystem.Typography.callout)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignSystem.Spacing.xxl)
            }
            if !showingDeletedNotes && searchQuery.isEmpty {
                Button {
                    mediumHaptic()
                    showingNewNoteSheet = true
                } label: {
                    Text("New note")
                        .font(DesignSystem.Typography.button)
                        .foregroundColor(DesignSystem.Colors.textInverse)
                        .padding(.horizontal, DesignSystem.Spacing.xxl)
                        .padding(.vertical, DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    private var notesListView: some View {
        List {
            if showingDeletedNotes {
                Section { trashHeaderView }
            }

            ForEach(displayNoteSections) { section in
                if let header = section.header {
                    Section(header: Text(header)) {
                        ForEach(section.notes, id: \.id) { note in
                            noteListRow(note)
                        }
                    }
                } else {
                    ForEach(section.notes, id: \.id) { note in
                        noteListRow(note)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(persistence.isSyncing ? nil : .easeInOut(duration: 0.2), value: filteredNotes.map { $0.id })
        .padding(.bottom, 88)
    }

    private var trashHeaderView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.warning)
                Text("Notes are permanently deleted after 30 days.")
                    .font(DesignSystem.Typography.callout)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            Button(role: .destructive) {
                showingEmptyTrashAlert = true
            } label: {
                HStack {
                    Image(systemName: "trash.slash")
                    Text("Empty trash")
                }
                .font(DesignSystem.Typography.button)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.md)
            }
            .buttonStyle(.bordered)
            .tint(DesignSystem.Colors.error)
            .alert("Empty Trash", isPresented: $showingEmptyTrashAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) { emptyTrash() }
            } message: {
                Text("All notes in Recently Deleted will be permanently removed. This action cannot be undone.")
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
        .listRowInsets(EdgeInsets(
            top: 8,
            leading: DesignSystem.Spacing.lg,
            bottom: 8,
            trailing: DesignSystem.Spacing.lg
        ))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: DesignSystem.Spacing.lg) {
                ProgressView()
                    .scaleEffect(1.15)
                    .tint(DesignSystem.Colors.accent)
                Text("Working…")
                    .font(DesignSystem.Typography.callout)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.xxl)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            )
            .shadow(color: DesignSystem.Shadows.medium.opacity(0.4), radius: 20, x: 0, y: 10)
        }
    }

    private func softDelete(_ note: Notes) {
        mediumHaptic()

        if selectedNote?.id == note.id { selectedNote = nil }

        note.isMarkedDeleted = true
        note.deletedDate = Date()
        note.modifiedDate = Date()

        if !viewContext.inkSlateSave(module: "Notes") {
            note.isMarkedDeleted = false
            errorMessage = "Failed to delete note."
            showingError = true
        }
    }

    private func restoreNote(_ note: Notes) {
        lightHaptic()

        note.isMarkedDeleted = false
        note.deletedDate = nil
        note.modifiedDate = Date()

        saveOrAlert("Failed to restore note")
    }

    private func permanentlyDelete(_ note: Notes) {
        heavyHaptic()

        if selectedNote?.objectID == note.objectID {
            selectedNote = nil
        }
        let noteUUID = note.id
        viewContext.delete(note)
        if let noteUUID {
            Task {
                try? await CloudKitAssetService.shared.deleteNotePhotosForNote(noteID: noteUUID)
                try? await CloudKitAssetService.shared.deleteNoteAttachmentsForNote(noteID: noteUUID)
            }
        }
        saveOrAlert("Failed to permanently delete note")
    }

    private func emptyTrash() {
        withAnimation(.easeInOut) { isLoading = true }
        let bg = PersistenceController.shared.backgroundContext()
        bg.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Notes")
            fetchRequest.predicate = NSPredicate(format: "isMarkedDeleted == YES")

            let idFetch = NSFetchRequest<Notes>(entityName: "Notes")
            idFetch.predicate = NSPredicate(format: "isMarkedDeleted == YES")
            idFetch.propertiesToFetch = ["id"]
            let doomedIDs: [UUID]
            do {
                doomedIDs = try bg.fetch(idFetch).compactMap { $0.id }
            } catch {
                doomedIDs = []
            }
            
            let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            batchDelete.resultType = .resultTypeObjectIDs
            
            do {
                let result = try bg.execute(batchDelete) as? NSBatchDeleteResult
                let objectIDs = (result?.result as? [NSManagedObjectID]) ?? []
                for uid in doomedIDs {
                    Task {
                        try? await CloudKitAssetService.shared.deleteNotePhotosForNote(noteID: uid)
                        try? await CloudKitAssetService.shared.deleteNoteAttachmentsForNote(noteID: uid)
                    }
                }
                DispatchQueue.main.async {
                    let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: objectIDs]
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
                    selectedNote = nil
                    withAnimation(.easeInOut) { isLoading = false }
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "Failed to empty trash: \(error.localizedDescription)"
                    showingError = true
                    withAnimation(.easeInOut) { isLoading = false }
                }
            }
        }
    }

    private func togglePin(_ note: Notes) {
        mediumHaptic()

        note.isPinned.toggle()
        note.modifiedDate = Date()

        saveOrAlert("Failed to toggle pin")
    }

    private func purgeOldDeletedNotes() {
        let bg = PersistenceController.shared.backgroundContext()
        bg.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Notes")
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let deletedPred = NSPredicate(format: "isMarkedDeleted == YES AND deletedDate != nil AND deletedDate < %@", cutoffDate as NSDate)
            let legacyPred = NSPredicate(format: "isMarkedDeleted == YES AND deletedDate == nil AND modifiedDate < %@", cutoffDate as NSDate)
            fetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [deletedPred, legacyPred])

            let idFetch = NSFetchRequest<Notes>(entityName: "Notes")
            idFetch.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [deletedPred, legacyPred])
            idFetch.propertiesToFetch = ["id"]
            let doomedIDs: [UUID]
            do {
                doomedIDs = try bg.fetch(idFetch).compactMap { $0.id }
            } catch {
                doomedIDs = []
            }
            
            let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            batchDelete.resultType = .resultTypeObjectIDs
            
            do {
                let result = try bg.execute(batchDelete) as? NSBatchDeleteResult
                let objectIDs = (result?.result as? [NSManagedObjectID]) ?? []
                for uid in doomedIDs {
                    Task {
                        try? await CloudKitAssetService.shared.deleteNotePhotosForNote(noteID: uid)
                        try? await CloudKitAssetService.shared.deleteNoteAttachmentsForNote(noteID: uid)
                    }
                }
                DispatchQueue.main.async {
                    let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: objectIDs]
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
                    clearSelectedNoteIfPurgedOrInvalid()
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "Failed to remove old deleted notes: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }

    private func clearSelectedNoteIfPurgedOrInvalid() {
        guard let sn = selectedNote else { return }
        if sn.isDeleted {
            selectedNote = nil
            return
        }
        do {
            _ = try viewContext.existingObject(with: sn.objectID)
        } catch {
            selectedNote = nil
        }
    }

    private func saveOrAlert(_ prefix: String) {
        if !viewContext.inkSlateSave(module: "Notes") {
            errorMessage = "\(prefix)."
            showingError = true
        }
    }
    
    private var filteredNotes: [Notes] {
        filteredNoteIDs.compactMap { id in
            (try? viewContext.existingObject(with: id)) as? Notes
        }
    }
    
    private var rowDisplaySettings: (showCreated: Bool, showModified: Bool, showPreview: Bool, showTags: Bool) {
        guard let s = selectedProject?.settings else {
            return (true, true, true, true)
        }
        return (s.showCreatedDate, s.showModifiedDate, s.showPreview, s.showTags)
    }
    
    private func noteMatchesSearch(_ note: Notes, queryLowercased: String, scope: String) -> Bool {
        let inTitle = note.title?.lowercased().contains(queryLowercased) ?? false
        let inContent = (note.content ?? "").lowercased().contains(queryLowercased)
        let inPreview = (note.preview ?? "").lowercased().contains(queryLowercased)
        let inTags = (note.tags ?? "")
            .split(separator: ",")
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().contains(queryLowercased) }
        switch scope {
        case "title":
            return inTitle
        case "content":
            return inContent || inPreview || inTags
        default:
            return inTitle || inContent || inPreview || inTags
        }
    }
    
    private func refreshFilteredNotes() {
        let folderSettings = (!showingDeletedNotes) ? selectedProject?.settings : nil
        let query = searchDebouncer.debouncedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedProjectID = selectedProject?.objectID
        let effectiveSortBy: SortBy = (selectedProject != nil && !showingDeletedNotes)
            ? SortBy.fromProjectSettings(folderSettings?.sortBy)
            : sortBy
        let ascending: Bool = {
            if selectedProject != nil && !showingDeletedNotes, let order = folderSettings?.sortOrder {
                return order == "ascending"
            }
            return sortDirection == .ascending
        }()
        let scope = folderSettings?.searchScope ?? "titleAndContent"
        let filterBy = folderSettings?.filterBy ?? "all"
        
        isFiltering = true
        let bg = PersistenceController.shared.backgroundContext()
        bg.perform {
            let fetch = NSFetchRequest<NSManagedObjectID>(entityName: "Notes")
            fetch.resultType = .managedObjectIDResultType
            fetch.fetchBatchSize = 80
            
            var predicates: [NSPredicate] = []
            predicates.append(NSPredicate(format: "isMarkedDeleted == %@", NSNumber(value: showingDeletedNotes)))
            if let selectedProjectID, !showingDeletedNotes,
               let bgProject = try? bg.existingObject(with: selectedProjectID) as? FSProject {
                predicates.append(NSPredicate(format: "project == %@", bgProject))
            }
            if !showingDeletedNotes {
                switch filterBy {
                case "pinned":
                    predicates.append(NSPredicate(format: "isPinned == YES"))
                case "unpinned":
                    predicates.append(NSPredicate(format: "isPinned == NO"))
                default:
                    if showPinnedOnly { predicates.append(NSPredicate(format: "isPinned == YES")) }
                }
            }
            
            if !query.isEmpty {
                let q = query
                let titlePred = NSPredicate(format: "title CONTAINS[cd] %@", q)
                let contentPred = NSPredicate(format: "content CONTAINS[cd] %@", q)
                let previewPred = NSPredicate(format: "preview CONTAINS[cd] %@", q)
                let tagsPred = NSPredicate(format: "tags CONTAINS[cd] %@", q)
                
                switch scope {
                case "title":
                    predicates.append(titlePred)
                case "content":
                    predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [contentPred, previewPred, tagsPred]))
                default:
                    predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [titlePred, contentPred, previewPred, tagsPred]))
                }
            }
            
            fetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            
            switch effectiveSortBy {
            case .title:
                fetch.sortDescriptors = [NSSortDescriptor(key: "title", ascending: ascending, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))]
            case .creationDate:
                fetch.sortDescriptors = [NSSortDescriptor(key: "createdDate", ascending: ascending)]
            case .modificationDate:
                fetch.sortDescriptors = [NSSortDescriptor(key: "modifiedDate", ascending: ascending)]
            case .pin:
                fetch.sortDescriptors = [
                    NSSortDescriptor(key: "isPinned", ascending: ascending),
                    NSSortDescriptor(key: "modifiedDate", ascending: false)
                ]
            }
            
            let ids = (try? bg.fetch(fetch)) ?? []
            DispatchQueue.main.async {
                filteredNoteIDs = ids
                isFiltering = false
            }
        }
    }

    /// Debounces expensive "fetch IDs on a background context" filtering work
    @MainActor
    private func scheduleRefreshFilteredNotes(debounce: TimeInterval) {
        refreshWorkItem?.cancel()
        let item = DispatchWorkItem { refreshFilteredNotes() }
        refreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    private struct NotesListSectionModel: Identifiable {
        let id: String
        let header: String?
        let notes: [Notes]
    }

    private static let noteDaySectionFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var displayNoteSections: [NotesListSectionModel] {
        let notes = filteredNotes
        let groupBy = (!showingDeletedNotes) ? (selectedProject?.settings?.groupBy ?? "none") : "none"
        guard groupBy != "none" else {
            return [NotesListSectionModel(id: "all", header: nil, notes: notes)]
        }
        if groupBy == "tag" {
            var buckets: [String: [Notes]] = [:]
            for n in notes {
                let key = firstTagToken(from: n.tags) ?? "Untagged"
                buckets[key, default: []].append(n)
            }
            let keys = buckets.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            return keys.map { k in
                NotesListSectionModel(id: "tag:\(k)", header: k, notes: buckets[k] ?? [])
            }
        }
        if groupBy == "date" {
            let cal = Calendar.current
            var buckets: [Date: [Notes]] = [:]
            for n in notes {
                let day = cal.startOfDay(for: n.modifiedDate ?? n.createdDate ?? .distantPast)
                buckets[day, default: []].append(n)
            }
            let keys = buckets.keys.sorted(by: >)
            return keys.map { day in
                NotesListSectionModel(
                    id: "day:\(day.timeIntervalSince1970)",
                    header: Self.noteDaySectionFormatter.string(from: day),
                    notes: buckets[day] ?? []
                )
            }
        }
        return [NotesListSectionModel(id: "all", header: nil, notes: notes)]
    }

    private func firstTagToken(from raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let first = raw.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let t = first, !t.isEmpty else { return nil }
        return t
    }

    @ViewBuilder
    private func noteListRow(_ note: Notes) -> some View {
        NoteRowView(
            note: note,
            tagColorByLowercasedName: tagColorByLowercasedName,
            showCreatedDate: rowDisplaySettings.showCreated,
            showModifiedDate: rowDisplaySettings.showModified,
            showPreview: rowDisplaySettings.showPreview,
            showTagsRow: rowDisplaySettings.showTags
        ) {
            if !showingDeletedNotes { selectedNote = note }
        }
        .listRowInsets(EdgeInsets(
            top: 6,
            leading: DesignSystem.Spacing.lg,
            bottom: 6,
            trailing: DesignSystem.Spacing.lg
        ))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if showingDeletedNotes {
                Button {
                    restoreNote(note)
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .tint(.green)

                Button(role: .destructive) {
                    permanentlyDelete(note)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Button {
                    noteForDetails = note
                    showingNoteDetails = true
                } label: {
                    Label("Details", systemImage: "info.circle")
                }
                .tint(.gray)

                Button {
                    noteToMove = note
                } label: {
                    Label("Move", systemImage: "folder")
                }
                .tint(.orange)

                Button {
                    togglePin(note)
                } label: {
                    Label(note.isPinned ? "Unpin" : "Pin",
                          systemImage: note.isPinned ? "pin.slash" : "pin")
                }
                .tint(.blue)

                Button {
                    selectedNote = note
                } label: {
                    Label("Open", systemImage: "doc.text")
                }
                .tint(.orange)

                Button(role: .destructive) {
                    softDelete(note)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .contextMenu {
            if showingDeletedNotes {
                Button {
                    restoreNote(note)
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                Button(role: .destructive) {
                    permanentlyDelete(note)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Button {
                    noteToMove = note
                } label: {
                    Label("Move to Folder", systemImage: "folder")
                }
                Button {
                    selectedNote = note
                } label: {
                    Label("Open", systemImage: "doc.text")
                }
                Button {
                    togglePin(note)
                } label: {
                    Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
                Button(role: .destructive) {
                    softDelete(note)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
    
    private func deleteProject(_ project: FSProject) {
        mediumHaptic()
        
        if selectedProject?.id == project.id {
            withAnimation {
                selectedProject = nil
            }
        }
        
        if let notes = project.notes as? Set<Notes> {
            for note in notes {
                note.project = nil
                note.modifiedDate = Date()
            }
        }
        
        viewContext.delete(project)
        saveOrAlert("Failed to delete folder")
    }
}

// MARK: - Notes filter pill (minimalist)
private struct NotesFilterPill: View {
    let title: String
    let icon: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(DesignSystem.Typography.headline)
            }
            .foregroundColor(isOn ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textSecondary)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, 10)
            .background(isOn ? DesignSystem.Colors.accent : DesignSystem.Colors.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(DesignSystem.Colors.border, lineWidth: isOn ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Note list preview text
extension Notes {
    func rowPreviewLineText() -> String {
        let trimmed = (preview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let raw = (content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        return MarkdownSerialization.plainText(from: content ?? "")
    }
}

// MARK: - Tag chip quick actions (from note list / row)
private struct NoteTagChipActionToken: Identifiable {
    var id: String { name.lowercased() }
    let name: String
}

private struct NoteTagChipActionsSheet: View {
    let token: NoteTagChipActionToken
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest private var matches: FetchedResults<FSTag>
    @State private var tagToEdit: FSTag?
    @State private var showingEditTag = false
    @State private var tagForColorPick: FSTag?
    @State private var showingDeleteConfirm = false
    @State private var errorMessage = ""
    @State private var showingError = false
    
    private let palette: [String] = ["#007AFF", "#FF3B30", "#34C759", "#FF9500", "#5856D6", "#FF2D55", "#5AC8FA", "#AF52DE"]
    
    init(token: NoteTagChipActionToken) {
        self.token = token
        let trimmed = token.name.trimmingCharacters(in: .whitespacesAndNewlines)
        _matches = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \FSTag.name, ascending: true)],
            predicate: NSPredicate(format: "name ==[cd] %@", trimmed)
        )
    }
    
    private var resolvedTag: FSTag? {
        matches.first
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Edit tag") {
                        if let t = resolvedTag, !t.isSystem {
                            tagToEdit = t
                            showingEditTag = true
                        } else if resolvedTag?.isSystem == true {
                            errorMessage = "System tags can’t be edited here."
                            showingError = true
                        } else {
                            errorMessage = "No saved tag named “\(token.name)”. Create it in Tags first."
                            showingError = true
                        }
                    }
                    
                    Button("Switch color") {
                        if let t = resolvedTag, !t.isSystem {
                            tagForColorPick = t
                        } else if resolvedTag?.isSystem == true {
                            errorMessage = "System tag colors can’t be changed."
                            showingError = true
                        } else {
                            errorMessage = "No saved tag named “\(token.name)”. Create it in Tags first."
                            showingError = true
                        }
                    }
                    
                    Button("Delete tag", role: .destructive) {
                        if resolvedTag != nil {
                            showingDeleteConfirm = true
                        } else {
                            errorMessage = "No saved tag named “\(token.name)”."
                            showingError = true
                        }
                    }
                } footer: {
                    Text("Applies to the tag “\(token.name)” across your library.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            .navigationTitle(token.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showingEditTag) {
                if let t = tagToEdit {
                    EditTagView(tag: t)
                }
            }
            .sheet(isPresented: Binding(
                get: { tagForColorPick != nil },
                set: { if !$0 { tagForColorPick = nil } }
            )) {
                if let t = tagForColorPick {
                    TagColorPickSheet(tag: t, colors: palette)
                }
            }
            .alert("Delete tag?", isPresented: $showingDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let t = resolvedTag { deleteTag(t) }
                    dismiss()
                }
            } message: {
                Text("This removes the tag from all notes and deletes the tag definition.")
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func deleteTag(_ tag: FSTag) {
        let tagName = (tag.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !tagName.isEmpty {
            let request = NSFetchRequest<Notes>(entityName: "Notes")
            if let notes = try? viewContext.fetch(request) {
                for note in notes {
                    var parts = (note.tags ?? "")
                        .components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    let before = parts.count
                    parts.removeAll { $0.caseInsensitiveCompare(tagName) == .orderedSame }
                    if parts.count != before {
                        note.tags = parts.isEmpty ? nil : parts.joined(separator: ",")
                        note.modifiedDate = Date()
                    }
                }
            }
        }
        viewContext.delete(tag)
        viewContext.inkSlateSave(module: "Notes")
    }
}

private struct TagColorPickSheet: View {
    @ObservedObject var tag: FSTag
    let colors: [String]
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedHex: String = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: DesignSystem.Spacing.lg) {
                    ForEach(colors, id: \.self) { hex in
                        Button {
                            selectedHex = hex
                            tag.color = hex
                            tag.modifiedDate = Date()
                            viewContext.inkSlateSave(module: "Notes")
                            dismiss()
                        } label: {
                            Circle()
                                .fill(Color(hex: hex) ?? DesignSystem.Colors.accent)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            (selectedHex == hex || (selectedHex.isEmpty && (tag.color ?? "") == hex))
                                                ? DesignSystem.Colors.textPrimary
                                                : Color.clear,
                                            lineWidth: 3
                                        )
                                )
                                .scaleEffect((selectedHex == hex || (selectedHex.isEmpty && (tag.color ?? "") == hex)) ? 1.08 : 1.0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.background.ignoresSafeArea())
            .navigationTitle("Tag color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                selectedHex = (tag.color ?? "#007AFF").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}

// MARK: - Note Row View
struct NoteRowView: View {
    let note: Notes
    let tagColorByLowercasedName: [String: String]
    var showCreatedDate: Bool = true
    var showModifiedDate: Bool = true
    var showPreview: Bool = true
    var showTagsRow: Bool = true
    let onTap: () -> Void
    
    @State private var showingDates = false
    @State private var tagChipActionToken: NoteTagChipActionToken?
    
    @ViewBuilder
    private var previewSnippet: some View {
        let previewText = note.rowPreviewLineText()
        if !previewText.isEmpty {
            Text(previewText)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                    Text((note.title?.isEmpty ?? true) ? "Untitled" : (note.title ?? "Untitled"))
                        .font(DesignSystem.Typography.title3)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                }

                if let project = note.project, let name = project.name, !name.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .medium))
                        Text(name)
                            .font(DesignSystem.Typography.footnote)
                            .lineLimit(1)
                    }
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                }

                if showPreview {
                    previewSnippet
                }

                HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                    if showModifiedDate {
                        Text((note.modifiedDate ?? note.createdDate ?? Date()).formatted(.dateTime.month(.abbreviated).day().year(.defaultDigits)))
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }
                    Spacer(minLength: 0)
                    if showTagsRow, !(note.tags?.isEmpty ?? true) {
                        HStack(spacing: 6) {
                            ForEach(Array(tagTokens(from: note.tags).prefix(3).enumerated()), id: \.offset) { _, trimmed in
                                let colorHex = tagColorByLowercasedName[trimmed.lowercased()] ?? "#007AFF"
                                Button {
                                    tagChipActionToken = NoteTagChipActionToken(name: trimmed)
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color(hex: colorHex) ?? DesignSystem.Colors.accent)
                                            .frame(width: 8, height: 8)
                                        Text(trimmed)
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundColor(DesignSystem.Colors.textSecondary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(DesignSystem.Colors.backgroundTertiary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            if tagTokens(from: note.tags).count > 3 {
                                Text("+\(tagTokens(from: note.tags).count - 3)")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                            }
                        }
                    }
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            )
            .shadow(color: DesignSystem.Shadows.small.opacity(0.35), radius: 6, x: 0, y: 2)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                lightHaptic()
                showingDates = true
            }
        )
        .confirmationDialog("Dates", isPresented: $showingDates, titleVisibility: .visible) {
            Button("OK", role: .cancel) {}
        } message: {
            Text([
                "Created: \((note.createdDate ?? Date()).formatted(.dateTime.month(.abbreviated).day().year(.defaultDigits)))",
                "Last edited: \((note.modifiedDate ?? note.createdDate ?? Date()).formatted(.dateTime.month(.abbreviated).day().year(.defaultDigits)))"
            ].joined(separator: "\n"))
        }
        .sheet(item: $tagChipActionToken) { token in
            NoteTagChipActionsSheet(token: token)
        }
    }
    
    private func tagTokens(from raw: String?) -> [String] {
        (raw ?? "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Search Bar
struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            TextField("Search notes…", text: $text)
                .textFieldStyle(.plain)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, 12)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Note Editor View
struct TextEditorView: View {
    private static var recentConflictSignatures: [String: Date] = [:]

    @ObservedObject var note: Notes
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let tagColorByLowercasedName: [String: String]

    @State private var showingMarkdownPreview = false
    @State private var showingTagEditor = false
    @State private var showingExportOptions = false

    @State private var showingError = false
    @State private var errorMessage = ""

    @State private var hasUnsavedChanges = false
    @State private var autoSaveTimer: Timer?
    @State private var isSaving = false
    
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var coordinatorRef: MarkdownEditor.Coordinator?
    @State private var showingRemoteContentConflict = false
    @State private var pendingRemoteContent: String?
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    if let coordinator = coordinatorRef {
                        MarkdownToolbarView(coordinator: coordinator)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .background(DesignSystem.Colors.surface)
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(DesignSystem.Colors.border),
                                alignment: .bottom
                            )
                    }
                    titleSection
                    #if canImport(UIKit)
                    NoteAttachmentsSection(note: note)
                    #endif
                    contentSection
                }
            }
            .task(id: note.objectID) {
                let names = NotePhotoCloudHydrator.recordNamesForPrefetch(
                    imageUrlsJSON: note.imageUrls,
                    content: note.content
                )
                await NotePhotoCloudHydrator.prefetchToCaches(recordNames: names)
            }
            .navigationTitle((note.title?.isEmpty ?? true) ? "Note" : (note.title ?? "Note"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignSystem.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { saveAndDismiss() }
                        .font(DesignSystem.Typography.button)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.85)
                            .tint(DesignSystem.Colors.accent)
                    } else if hasUnsavedChanges {
                        Text("Unsaved")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.warning)
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        togglePin()
                    } label: {
                        Image(systemName: note.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(note.isPinned ? DesignSystem.Colors.accent : DesignSystem.Colors.textTertiary)
                    }
                    .accessibilityLabel(note.isPinned ? "Unpin" : "Pin")

                    Button("Tags") { showingTagEditor = true }
                        .font(DesignSystem.Typography.button)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Button { showingExportOptions = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                    .accessibilityLabel("Share or export")
                }
            }
            .sheet(isPresented: $showingTagEditor) {
                NoteTagEditorView(note: note, onSave: { saveNote() })
            }
            .sheet(isPresented: $showingExportOptions) { ExportOptionsView(note: note) }
            .fullScreenCoverIfAvailable(isPresented: $showingMarkdownPreview) {
                NotePreviewScreen(note: note, isPresented: $showingMarkdownPreview)
            }
            .alert("This note changed on another device", isPresented: $showingRemoteContentConflict) {
                Button("Keep My Changes", role: .destructive) {
                    overwriteRemoteWithLocalEditor()
                    pendingRemoteContent = nil
                }
                Button("Load Synced Version") {
                    if let remote = pendingRemoteContent {
                        note.content = remote
                        reloadEditorFromNoteContent()
                    }
                    pendingRemoteContent = nil
                    hasUnsavedChanges = false
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("A synced update arrived while you were editing. Choose which version to keep. Your other devices will see whichever version you keep after the next successful save.")
            }
            .alert("Error", isPresented: $showingError) { Button("OK") {} } message: { Text(errorMessage) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .inactive || phase == .background {
                    flushEditorToNote()
                    if hasUnsavedChanges { saveNote() }
                }
            }
            .onDisappear {
                stopAutoSave()
                flushEditorToNote()
                if hasUnsavedChanges, note.managedObjectContext != nil, !note.isDeleted {
                    saveNote()
                }
            }
        }
    }

    private func reloadEditorFromNoteContent() {
        #if canImport(UIKit)
        coordinatorRef?.applyExternalSerializedContent(note.content ?? "")
        hasUnsavedChanges = false
        #endif
    }

    private func overwriteRemoteWithLocalEditor() {
        #if canImport(UIKit)
        guard let coordinator = coordinatorRef, let tv = coordinator.textView else { return }
        let serialized = coordinator.serializeContent(from: tv.attributedText)
        note.content = serialized
        #if canImport(UIKit)
        if let coordinator = coordinatorRef, let tv = coordinator.textView {
            note.imageUrls = NotePhotoRefCollector.jsonIndex(for: tv.attributedText)
        } else if let (attr, _) = MarkdownSerialization.deserialize(serialized, maxWidth: 400) {
            note.imageUrls = NotePhotoRefCollector.jsonIndex(for: attr)
        } else {
            note.imageUrls = nil
        }
        #endif
        let plain = MarkdownSerialization.plainText(from: serialized)
        note.preview = String(plain.prefix(100))
        note.modifiedDate = Date()
        hasUnsavedChanges = true
        scheduleAutoSave()
        #endif
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Title")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            TextField("Note title", text: Binding(
                get: { note.title ?? "" },
                set: { note.title = $0 }
            ))
                .font(DesignSystem.Typography.title2)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .textFieldStyle(.plain)
                .onChange(of: note.title) { _, _ in
                    markAsChanged()
                }
            
            HStack {
                Text("Folder")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                ProjectPickerView(selectedProject: Binding(
                    get: { note.project },
                    set: { note.project = $0; markAsChanged() }
                ))
            }
            
            if !(note.tags?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tagTokens(from: note.tags), id: \.self) { tagName in
                            let colorHex = tagColorByLowercasedName[tagName.lowercased()] ?? "#007AFF"
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: colorHex) ?? DesignSystem.Colors.accent)
                                    .frame(width: 8, height: 8)
                                Text(tagName)
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(DesignSystem.Colors.backgroundTertiary)
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.md)
    }
    
    private struct ProjectPickerView: View {
        @Environment(\.managedObjectContext) private var viewContext
        @FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \FSProject.name, ascending: true)]
        ) private var projects: FetchedResults<FSProject>
        
        @Binding var selectedProject: FSProject?
        
        var body: some View {
            Picker("Folder", selection: $selectedProject) {
                Text("None").tag(FSProject?.none)
                ForEach(projects) { project in
                    Text(project.name ?? "Unnamed Folder").tag(FSProject?.some(project))
                }
            }
            .pickerStyle(.menu)
            .tint(DesignSystem.Colors.accent)
        }
    }
    
    private func tagTokens(from raw: String?) -> [String] {
        (raw ?? "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text("Content")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                Button("Preview") {
                    flushEditorToNote()
                    showingMarkdownPreview = true
                }
                .font(DesignSystem.Typography.button)
                .foregroundColor(DesignSystem.Colors.accent)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.md)

            MarkdownEditor(
                text: Binding(
                    get: { note.content ?? "" },
                    set: { note.content = $0 }
                ),
                selectedRange: $selectedRange,
                coordinatorRef: $coordinatorRef,
                noteCloudKitID: note.id,
                notePhotosDisabled: false,
                onPhotoIndexChanged: { json in
                    note.imageUrls = json
                    hasUnsavedChanges = true
                    note.modifiedDate = Date()
                    scheduleAutoSave()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            )
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
            .onChange(of: note.content) { _, newValue in
                handleNoteContentChanged(to: newValue ?? "")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleNoteContentChanged(to newValue: String) {
        if let coordinator = coordinatorRef, coordinator.lastPublishedSerialized == newValue {
            if coordinator.consumePendingUserEdit() {
                markAsChanged()
            }
            return
        }
        #if canImport(UIKit)
        if let coordinator = coordinatorRef, let tv = coordinator.textView {
            let local = coordinator.serializeContent(from: tv.attributedText)
            if newValue != local {
                pendingRemoteContent = newValue
                showingRemoteContentConflict = true
                return
            }
        }
        #endif
        markAsChanged()
    }

    private func markAsChanged() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [self] in
                self.markAsChanged()
            }
            return
        }

        hasUnsavedChanges = true
        note.modifiedDate = Date()

        #if canImport(UIKit)
        if let coordinator = coordinatorRef, let textView = coordinator.textView {
            let serialized = coordinator.serializeContent(from: textView.attributedText)
            note.content = serialized
            note.imageUrls = NotePhotoRefCollector.jsonIndex(for: textView.attributedText)
            let plain = MarkdownSerialization.plainText(from: serialized)
            note.preview = String(plain.prefix(100))
        } else if let content = note.content {
            let plain = MarkdownSerialization.plainText(from: content)
            note.preview = String(plain.prefix(100))
            if let (attr, _) = MarkdownSerialization.deserialize(content, maxWidth: 400) {
                note.imageUrls = NotePhotoRefCollector.jsonIndex(for: attr)
            } else {
                note.imageUrls = nil
            }
        } else {
            note.imageUrls = nil
        }
        #endif
        
        scheduleAutoSave()
    }

    private func togglePin() {
        mediumHaptic()
        note.isPinned.toggle()
        saveNote()
    }

    private func startAutoSave() {
    }

    private func stopAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    private func scheduleAutoSave() {
        autoSaveTimer?.invalidate()
        // ~1.5s debounce after typing stops.
        let timer = Timer(timeInterval: 1.5, repeats: false) { _ in
            if hasUnsavedChanges { saveNote() }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoSaveTimer = timer
    }

    /// Pushes the latest UITextView content into the note; matches `NewNoteView.saveNote()` and avoids the editor’s 0.3s debounce losing the las...
    private func flushEditorToNote() {
        #if canImport(UIKit)
        coordinatorRef?.flushPendingEditsToParent()
        if coordinatorRef?.consumePendingUserEdit() == true {
            markAsChanged()
        }
        #endif
    }

    private func saveNote() {
        guard !isSaving else { return }
        guard note.managedObjectContext != nil, !note.isDeleted else { return }
        flushEditorToNote()
        isSaving = true
        note.modifiedDate = Date()
        
        let capturedTitle = note.title
        let capturedContent = note.content
        let capturedPreview = note.preview
        let capturedProject = note.project
        
        defer { isSaving = false }
        
        do {
            try viewContext.save()
            hasUnsavedChanges = false
            #if canImport(UIKit)
            coordinatorRef?.commitPendingPhotoDeletions()
            #endif
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain {
                if error.code == 133020 || error.userInfo[NSPersistentStoreSaveConflictsErrorKey] != nil {
                    let updatedOtherThanNote = viewContext.updatedObjects.filter { $0.objectID != note.objectID }
                    let hasOtherDirty = !updatedOtherThanNote.isEmpty
                        || !viewContext.insertedObjects.isEmpty
                        || !viewContext.deletedObjects.isEmpty

                    // Throttle conflict-copy creation when auto-save races CloudKit.
                    let signature = [
                        note.objectID.uriRepresentation().absoluteString,
                        capturedTitle ?? "",
                        capturedContent ?? ""
                    ].joined(separator: "|")
                    let now = Date()
                    TextEditorView.recentConflictSignatures = TextEditorView.recentConflictSignatures
                        .filter { now.timeIntervalSince($0.value) < 120 }
                    if let last = TextEditorView.recentConflictSignatures[signature], now.timeIntervalSince(last) < 60 {
                        viewContext.rollback()
                        reloadEditorFromNoteContent()
                        hasUnsavedChanges = false
                        errorMessage = "Sync conflict detected while saving. The latest synced version was loaded to prevent duplicate conflict copies."
                        showingError = true
                        return
                    }
                    TextEditorView.recentConflictSignatures[signature] = now

                    func makeConflictCopy() -> Notes {
                        let conflictCopy = Notes(context: viewContext)
                        conflictCopy.id = UUID()
                        conflictCopy.createdDate = Date()
                        conflictCopy.modifiedDate = Date()
                        conflictCopy.project = capturedProject
                        conflictCopy.title = ((capturedTitle?.isEmpty == false) ? capturedTitle! : "Untitled") + " (Conflict Copy)"
                        conflictCopy.content = capturedContent
                        conflictCopy.preview = capturedPreview
                        return conflictCopy
                    }

                    viewContext.rollback()
                    let conflictCopy = makeConflictCopy()
                    do {
                        try viewContext.save()
                        hasUnsavedChanges = false
                        if hasOtherDirty {
                            errorMessage = "Sync conflict detected. Your text for this note was saved as \"\(conflictCopy.title ?? "Conflict Copy")\". Other unsaved changes elsewhere in the app may have been reverted—re-open those screens if something looks missing."
                        } else {
                            errorMessage = "Sync conflict detected. Your changes were saved as a separate note: \"\(conflictCopy.title ?? "Conflict Copy")\"."
                        }
                        showingError = true
                        if !PersistenceController.shared.syncStatus.isAvailable {
                            ErrorHandlingService.shared.reportSyncWarning(
                                "This note was saved as a conflict copy, but iCloud isn't available — open Settings → iCloud Sync."
                            )
                        }
                    } catch {
                        errorMessage = "Sync conflict detected, but saving a conflict copy failed: \(error.localizedDescription)"
                        showingError = true
                        ErrorHandlingService.shared.reportSaveFailure(error, module: "Notes", retry: { [self] in saveNote() })
                    }
                } else if error.code >= 1610 && error.code <= 1620 {
                    errorMessage = "Invalid data: \(error.localizedDescription)"
                    showingError = true
                    ErrorHandlingService.shared.reportSaveFailure(error, module: "Notes")
                } else {
                    errorMessage = "Save failed: \(error.localizedDescription)"
                    showingError = true
                    ErrorHandlingService.shared.reportSaveFailure(error, module: "Notes", retry: { [self] in saveNote() })
                }
            } else {
                errorMessage = "Failed to save: \(error.localizedDescription)"
                showingError = true
                ErrorHandlingService.shared.reportSaveFailure(error, module: "Notes", retry: { [self] in saveNote() })
            }
        }
    }

    private func saveAndDismiss() {
        flushEditorToNote()
        if hasUnsavedChanges {
            saveNote()
            if showingError { return }
        }
        dismiss()
    }
}

#if canImport(UIKit)
private struct NoteAttachmentEntry: Identifiable {
    let id: String  // CloudKit record name
    let filename: String
    let kind: String
}

/// Lists a note's synced share-import attachments and downloads them on demand
private struct NoteAttachmentsSection: View {
    @ObservedObject var note: Notes
    @State private var downloadingIDs: Set<String> = []
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private var entries: [NoteAttachmentEntry] {
        Self.parse(note.attachments)
    }

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Attachments")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                ForEach(entries) { entry in
                    Button {
                        open(entry)
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Image(systemName: entry.kind == "image" ? "photo" : "doc")
                                .foregroundColor(DesignSystem.Colors.accent)
                            Text(entry.filename)
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            if downloadingIDs.contains(entry.id) {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.sm)
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: shareItems)
            }
            .alert("Attachment", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Couldn't open this attachment.")
            }
        }
    }

    private func open(_ entry: NoteAttachmentEntry) {
        let cached = CloudKitAssetService.cachedNoteAttachmentURL(recordName: entry.id, filename: entry.filename)
        if FileManager.default.fileExists(atPath: cached.path) {
            shareItems = [cached]
            showingShareSheet = true
            return
        }
        guard !downloadingIDs.contains(entry.id) else { return }
        downloadingIDs.insert(entry.id)
        Task {
            do {
                let url = try await CloudKitAssetService.shared.downloadNoteAttachment(recordName: entry.id)
                await MainActor.run {
                    downloadingIDs.remove(entry.id)
                    if let url {
                        shareItems = [url]
                        showingShareSheet = true
                    } else {
                        errorMessage = "This attachment couldn't be found in iCloud."
                        showingError = true
                    }
                }
            } catch {
                await MainActor.run {
                    downloadingIDs.remove(entry.id)
                    errorMessage = "Couldn't download attachment: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }

    static func parse(_ json: String?) -> [NoteAttachmentEntry] {
        guard let json, let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return []
        }
        var seen = Set<String>()
        var result: [NoteAttachmentEntry] = []
        for dict in arr {
            guard let recordName = dict["recordName"], !recordName.isEmpty, !seen.contains(recordName) else { continue }
            seen.insert(recordName)
            result.append(NoteAttachmentEntry(
                id: recordName,
                filename: dict["filename"] ?? "Attachment",
                kind: dict["kind"] ?? "file"
            ))
        }
        return result
    }
}
#endif

struct NotePreviewScreen: View {
    @ObservedObject var note: Notes
    @Binding var isPresented: Bool
    
    private var displayContent: String {
        note.content ?? ""
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                MarkdownPreviewContainer(content: displayContent)
            }
            .navigationTitle((note.title?.isEmpty ?? true) ? "Preview" : (note.title ?? "Preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignSystem.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                        .font(DesignSystem.Typography.button)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
            }
        }
    }
}

private struct MarkdownPreviewContainer: View {
    let content: String

    var body: some View {
        GeometryReader { geo in
            let horizontalPad = DesignSystem.Spacing.xxl * 2
            let column = max(80, geo.size.width - horizontalPad)
            ScrollView {
                MarkdownPreviewTextView(content: content, preferredColumnWidth: column)
                    .frame(width: column, alignment: .leading)
                    .padding(.vertical, DesignSystem.Spacing.xxl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, DesignSystem.Spacing.xxl)
        }
        .background(DesignSystem.Colors.background)
    }
}

#if canImport(UIKit)
private struct MarkdownPreviewTextView: UIViewRepresentable {
    let content: String
    var preferredColumnWidth: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let column = max(60, preferredColumnWidth)
        let width = max(column, 60)
        if let (attributed, _) = MarkdownSerialization.deserialize(content, maxWidth: width) {
            let m = NSMutableAttributedString(attributedString: attributed)
            NotePhotoAttachment.repairAttachmentBounds(in: m, columnWidth: column)
            uiView.attributedText = m
            uiView.layoutIfNeeded()
            NotePhotoCloudHydrator.hydrate(textView: uiView, overrideColumnWidth: column)
            DispatchQueue.main.async {
                NotePhotoCloudHydrator.hydrate(textView: uiView, overrideColumnWidth: column)
            }
        } else {
            uiView.attributedText = EditorContentParser.deserialize(content, maxWidth: width)
        }
    }
}
#endif

// MARK: - New Note View
struct NewNoteView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FSProject.name, ascending: true)]
    ) private var projects: FetchedResults<FSProject>
    
    let selectedProject: FSProject?

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var draftNoteCloudID = UUID()
    @State private var project: FSProject?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var coordinatorRef: MarkdownEditor.Coordinator?
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    if let coordinator = coordinatorRef {
                        MarkdownToolbarView(coordinator: coordinator)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .background(DesignSystem.Colors.surface)
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(DesignSystem.Colors.border),
                                alignment: .bottom
                            )
                    }
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Title")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                            .textCase(.uppercase)
                            .tracking(0.6)
                        TextField("Note title", text: $title)
                            .font(DesignSystem.Typography.title2)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .textFieldStyle(.plain)
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.top, DesignSystem.Spacing.md)
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Folder")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                            .textCase(.uppercase)
                            .tracking(0.6)
                        Picker("Folder", selection: $project) {
                            Text("None").tag(FSProject?.none)
                            ForEach(projects) { proj in
                                Text(proj.name ?? "Unnamed Folder").tag(FSProject?.some(proj))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(DesignSystem.Colors.accent)
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.top, DesignSystem.Spacing.md)
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Content")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .padding(.top, DesignSystem.Spacing.md)
                        MarkdownEditor(text: $content, selectedRange: $selectedRange, coordinatorRef: $coordinatorRef, autoFocusOnAppear: true, noteCloudKitID: draftNoteCloudID, notePhotosDisabled: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(DesignSystem.Colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
                            )
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .padding(.bottom, DesignSystem.Spacing.lg)
                    }
                }
            }
            .navigationTitle("New note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignSystem.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(DesignSystem.Typography.button)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveNote() }
                        .font(DesignSystem.Typography.button)
                        .foregroundColor(DesignSystem.Colors.accent)
                        .disabled(isSaving || (title.isEmpty && content.isEmpty))
                }
            }
            .alert("Error", isPresented: $showingError) { Button("OK") {} } message: { Text(errorMessage) }
            .onAppear {
                project = selectedProject
            }
        }
    }

    private func saveNote() {
        guard !isSaving else { return }
        guard !title.isEmpty || !content.isEmpty else { dismiss(); return }

        isSaving = true
        
        var finalContent = content
        #if canImport(UIKit)
        if let coordinator = coordinatorRef, let textView = coordinator.textView {
            finalContent = coordinator.serializeContent(from: textView.attributedText)
        }
        #endif
        let newNote = Notes(context: viewContext)
        newNote.id = draftNoteCloudID
        newNote.title = title.isEmpty ? "Untitled" : title
        newNote.content = finalContent
        #if canImport(UIKit)
        if let coordinator = coordinatorRef, let textView = coordinator.textView {
            newNote.imageUrls = NotePhotoRefCollector.jsonIndex(for: textView.attributedText)
        } else if let (attr, _) = MarkdownSerialization.deserialize(finalContent, maxWidth: 400) {
            newNote.imageUrls = NotePhotoRefCollector.jsonIndex(for: attr)
        } else {
            newNote.imageUrls = nil
        }
        #endif
        
        newNote.isMarkedDeleted = false
        newNote.createdDate = Date()
        newNote.modifiedDate = Date()
        newNote.project = project ?? selectedProject
        
        let plain = MarkdownSerialization.plainText(from: finalContent)
        newNote.preview = String(plain.prefix(100))

        viewContext.insert(newNote)

        if viewContext.inkSlateSave(module: "Notes") {
            #if canImport(UIKit)
            coordinatorRef?.commitPendingPhotoDeletions()
            #endif
            dismiss()
        } else {
            errorMessage = "Failed to save note."
            showingError = true
            isSaving = false
        }
    }
}

// MARK: - New Folder View
struct NewProjectView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var isDefault: Bool = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                Form {
                    Section {
                        TextField("Folder name", text: $name)
                            #if os(iOS)
                            .textInputAutocapitalization(.words)
                            #endif
                    } header: {
                        Text("Folder Details")
                    }
                    
                    Section {
                        Toggle("Set as default folder", isOn: $isDefault)
                    } footer: {
                        Text("Default folder will be selected automatically when viewing notes.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignSystem.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(DesignSystem.Typography.button)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { saveProject() }
                        .font(DesignSystem.Typography.button)
                        .foregroundColor(DesignSystem.Colors.accent)
                        .disabled(isSaving || name.isEmpty)
                }
            }
            .alert("Error", isPresented: $showingError) { Button("OK") {} } message: { Text(errorMessage) }
        }
    }
    
    private func saveProject() {
        guard !isSaving else { return }
        guard !name.isEmpty else { return }
        
        isSaving = true
        
        if isDefault {
            let fetchRequest = NSFetchRequest<FSProject>(entityName: "FSProject")
            if let existingProjects = try? viewContext.fetch(fetchRequest) {
                for project in existingProjects {
                    project.isDefault = false
                }
            }
        }
        
        let newProject = FSProject(context: viewContext)
        newProject.name = name
        newProject.isDefault = isDefault
        newProject.id = UUID()
        newProject.createdDate = Date()
        newProject.modifiedDate = Date()
        
        let settings = ProjectSettings(context: viewContext)
        settings.id = UUID()
        settings.project = newProject
        settings.filterBy = "all"
        settings.groupBy = "none"
        settings.searchScope = "titleAndContent"
        settings.sortBy = "modifiedDate"
        settings.sortOrder = "descending"
        settings.showCreatedDate = true
        settings.showModifiedDate = true
        settings.showPreview = true
        settings.showTags = true
        
        viewContext.insert(newProject)
        viewContext.insert(settings)
        
        if viewContext.inkSlateSave(module: "Notes") {
            dismiss()
        } else {
            errorMessage = "Failed to create folder."
            showingError = true
            isSaving = false
        }
    }
}

// MARK: - Folder Settings View
struct ProjectSettingsView: View {
    @ObservedObject var project: FSProject
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var settings: ProjectSettings?
    @State private var filterBy: String = "all"
    @State private var groupBy: String = "none"
    @State private var searchScope: String = "titleAndContent"
    @State private var sortBy: String = "modifiedDate"
    @State private var sortOrder: String = "descending"
    @State private var showCreatedDate: Bool = true
    @State private var showModifiedDate: Bool = true
    @State private var showPreview: Bool = true
    @State private var showTags: Bool = true
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                Form {
                    Section("Display Options") {
                        Toggle("Show Created Date", isOn: $showCreatedDate)
                        Toggle("Show Modified Date", isOn: $showModifiedDate)
                        Toggle("Show Preview", isOn: $showPreview)
                        Toggle("Show Tags", isOn: $showTags)
                    }
                    
                    Section("Sorting") {
                        Picker("Sort By", selection: $sortBy) {
                            Text("Modified Date").tag("modifiedDate")
                            Text("Created Date").tag("createdDate")
                            Text("Title").tag("title")
                            Text("Pin Status").tag("pin")
                        }
                        
                        Picker("Sort Order", selection: $sortOrder) {
                            Text("Ascending").tag("ascending")
                            Text("Descending").tag("descending")
                        }
                    }
                    
                    Section("Search") {
                        Picker("Search Scope", selection: $searchScope) {
                            Text("Title & Content").tag("titleAndContent")
                            Text("Title Only").tag("title")
                            Text("Content Only").tag("content")
                        }
                    }
                    
                    Section("Filtering") {
                        Picker("Filter By", selection: $filterBy) {
                            Text("All").tag("all")
                            Text("Pinned").tag("pinned")
                            Text("Unpinned").tag("unpinned")
                        }
                        
                        Picker("Group By", selection: $groupBy) {
                            Text("None").tag("none")
                            Text("Date").tag("date")
                            Text("Tag").tag("tag")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Folder settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignSystem.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(DesignSystem.Typography.button)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveSettings() }
                        .font(DesignSystem.Typography.button)
                        .foregroundColor(DesignSystem.Colors.accent)
                }
            }
            .alert("Error", isPresented: $showingError) { Button("OK") {} } message: { Text(errorMessage) }
            .onAppear {
                loadSettings()
            }
        }
    }
    
    private func loadSettings() {
        if let existingSettings = project.settings {
            settings = existingSettings
            filterBy = existingSettings.filterBy ?? "all"
            groupBy = existingSettings.groupBy ?? "none"
            searchScope = existingSettings.searchScope ?? "titleAndContent"
            sortBy = existingSettings.sortBy ?? "modifiedDate"
            sortOrder = existingSettings.sortOrder ?? "descending"
            showCreatedDate = existingSettings.showCreatedDate
            showModifiedDate = existingSettings.showModifiedDate
            showPreview = existingSettings.showPreview
            showTags = existingSettings.showTags
        } else {
            let newSettings = ProjectSettings(context: viewContext)
            newSettings.id = UUID()
            newSettings.project = project
            settings = newSettings
        }
    }
    
    private func saveSettings() {
        guard let settings = settings else { return }
        
        settings.filterBy = filterBy
        settings.groupBy = groupBy
        settings.searchScope = searchScope
        settings.sortBy = sortBy
        settings.sortOrder = sortOrder
        settings.showCreatedDate = showCreatedDate
        settings.showModifiedDate = showModifiedDate
        settings.showPreview = showPreview
        settings.showTags = showTags
        
        if viewContext.inkSlateSave(module: "Notes") {
            dismiss()
        } else {
            errorMessage = "Failed to save settings."
            showingError = true
        }
    }
}

// MARK: - Tag Manager View
struct TagManagerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \FSTag.isSystem, ascending: false),
            NSSortDescriptor(keyPath: \FSTag.name, ascending: true)
        ]
    ) private var tags: FetchedResults<FSTag>
    
    @State private var showingNewTag = false
    @State private var selectedTag: FSTag?
    @State private var showingEditTag = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                List {
                if tags.isEmpty {
                    Section {
                        VStack(spacing: DesignSystem.Spacing.lg) {
                            Image(systemName: "tag")
                                .font(.system(size: 40, weight: .light))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                            Text("No tags yet")
                                .font(DesignSystem.Typography.title2)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            Text("Create tags to organize your notes")
                                .font(DesignSystem.Typography.callout)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    }
                } else {
                    let systemTags = tags.filter { $0.isSystem }
                    let customTags = tags.filter { !$0.isSystem }
                    
                    if !systemTags.isEmpty {
                        Section("System Tags") {
                            ForEach(systemTags) { tag in
                                TagRowView(tag: tag)
                            }
                        }
                    }
                    
                    if !customTags.isEmpty {
                        Section("Custom Tags") {
                            ForEach(customTags) { tag in
                                TagRowView(tag: tag)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedTag = tag
                                        showingEditTag = true
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            deleteTag(tag)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            deleteTag(tag)
                                        } label: {
                                            Label("Delete Tag", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignSystem.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(DesignSystem.Typography.button)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewTag = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                }
            }
            .sheet(isPresented: $showingNewTag) {
                NewTagView()
            }
            .sheet(isPresented: $showingEditTag) {
                if let selectedTag {
                    EditTagView(tag: selectedTag)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func deleteTag(_ tag: FSTag) {
        mediumHaptic()
        
        let tagName = (tag.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !tagName.isEmpty {
            let request = NSFetchRequest<Notes>(entityName: "Notes")
            if let notes = try? viewContext.fetch(request) {
                for note in notes {
                    var parts = (note.tags ?? "")
                        .components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    let before = parts.count
                    parts.removeAll { $0.caseInsensitiveCompare(tagName) == .orderedSame }
                    if parts.count != before {
                        note.tags = parts.isEmpty ? nil : parts.joined(separator: ",")
                        note.modifiedDate = Date()
                    }
                }
            }
        }
        
        viewContext.delete(tag)
        
        if !viewContext.inkSlateSave(module: "Notes") {
            viewContext.rollback()
            errorMessage = "Failed to delete tag."
            showingError = true
        }
    }
}

// MARK: - Tag Row View
struct TagRowView: View {
    @ObservedObject var tag: FSTag
    
    var body: some View {
        HStack {
            Circle()
                .fill(Color(hex: tag.color ?? "#007AFF") ?? .blue)
                .frame(width: 12, height: 12)
            
            Text(tag.name ?? "Unnamed Tag")
                .font(.body)
            
            if tag.isSystem {
                Spacer()
                Text("System")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.adaptiveSystemGray)
                    .cornerRadius(4)
            }
        }
    }
}

// MARK: - New Tag View
struct NewTagView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FSTag.name, ascending: true)]
    ) private var allTags: FetchedResults<FSTag>
    
    @State private var name: String = ""
    @State private var color: String = "#007AFF"
    @State private var parentTag: FSTag?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    
    let colors: [String] = ["#007AFF", "#FF3B30", "#34C759", "#FF9500", "#5856D6", "#FF2D55", "#5AC8FA", "#AF52DE"]
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                Form {
                Section {
                    TextField("Tag name", text: $name)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                } header: {
                    Text("Tag details")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: DesignSystem.Spacing.lg) {
                        ForEach(colors, id: \.self) { colorHex in
                            Button {
                                color = colorHex
                            } label: {
                                Circle()
                                    .fill(Color(hex: colorHex) ?? DesignSystem.Colors.accent)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Circle()
                                            .stroke(color == colorHex ? DesignSystem.Colors.textPrimary : Color.clear, lineWidth: 3)
                                    )
                                    .scaleEffect(color == colorHex ? 1.08 : 1.0)
                            }
                        }
                    }
                } header: {
                    Text("Color")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                Section {
                    Picker("Parent tag", selection: $parentTag) {
                        Text("None").tag(FSTag?.none)
                        ForEach(allTags) { tag in
                            Text(tag.name ?? "Unnamed").tag(FSTag?.some(tag))
                        }
                    }
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                } header: {
                    Text("Parent tag")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                } footer: {
                    Text("Select a parent tag to create a hierarchical tag structure.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }
            .scrollContentBackground(.hidden)
            }
            .navigationTitle("New tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignSystem.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(DesignSystem.Typography.button)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTag() }
                        .font(DesignSystem.Typography.button)
                        .foregroundColor(DesignSystem.Colors.accent)
                        .disabled(isSaving || name.isEmpty)
                }
            }
            .alert("Error", isPresented: $showingError) { Button("OK") {} } message: { Text(errorMessage) }
        }
    }
    
    private func saveTag() {
        guard !isSaving else { return }
        guard !name.isEmpty else { return }
        
        isSaving = true
        
        let newTag = FSTag(context: viewContext)
        newTag.name = name
        newTag.color = color
        newTag.parentTag = parentTag
        newTag.isSystem = false
        newTag.id = UUID()
        newTag.createdDate = Date()
        newTag.modifiedDate = Date()
        
        viewContext.insert(newTag)
        
        if viewContext.inkSlateSave(module: "Notes") {
            dismiss()
        } else {
            errorMessage = "Failed to save tag."
            showingError = true
            isSaving = false
        }
    }
}

// MARK: - Edit Tag View
struct EditTagView: View {
    @ObservedObject var tag: FSTag
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var selectedColorHex: String = "#007AFF"
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let colors: [String] = ["#007AFF", "#FF3B30", "#34C759", "#FF9500", "#5856D6", "#FF2D55", "#5AC8FA", "#AF52DE"]
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                Form {
                    Section("Tag details") {
                        TextField("Tag name", text: $name)
                            .disabled(tag.isSystem)
                    }
                    
                    Section {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: DesignSystem.Spacing.lg) {
                            ForEach(colors, id: \.self) { colorHex in
                                Button {
                                    selectedColorHex = colorHex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: colorHex) ?? DesignSystem.Colors.accent)
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    selectedColorHex.caseInsensitiveCompare(colorHex) == .orderedSame
                                                        ? DesignSystem.Colors.textPrimary
                                                        : Color.clear,
                                                    lineWidth: 3
                                                )
                                        )
                                        .scaleEffect(selectedColorHex.caseInsensitiveCompare(colorHex) == .orderedSame ? 1.08 : 1.0)
                                }
                                .buttonStyle(.plain)
                                .disabled(tag.isSystem)
                            }
                        }
                    } header: {
                        Text("Color")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    if tag.isSystem {
                        Section {
                            Text("System tags can’t be edited.")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignSystem.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(DesignSystem.Typography.button)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(DesignSystem.Typography.button)
                        .foregroundColor(DesignSystem.Colors.accent)
                        .disabled(tag.isSystem || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                name = (tag.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                selectedColorHex = (tag.color ?? "#007AFF").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .alert("Error", isPresented: $showingError) { Button("OK") {} } message: { Text(errorMessage) }
        }
    }
    
    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        tag.name = trimmed
        tag.color = selectedColorHex
        tag.modifiedDate = Date()
        
        if viewContext.inkSlateSave(module: "Notes") {
            dismiss()
        } else {
            viewContext.rollback()
            errorMessage = "Failed to update tag."
            showingError = true
        }
    }
}

// MARK: - Note Tag Editor View
struct NoteTagEditorView: View {
    @ObservedObject var note: Notes
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \FSTag.isSystem, ascending: false),
            NSSortDescriptor(keyPath: \FSTag.name, ascending: true)
        ]
    ) private var allTags: FetchedResults<FSTag>
    
    @State private var showingError = false
    @State private var errorMessage = ""
    
    let onSave: () -> Void
    
    private var noteTagNames: Set<String> {
        let names = (note.tags ?? "").components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Set(names)
    }
    
    private var noteTagNamesLowercased: Set<String> {
        Set(noteTagNames.map { $0.lowercased() })
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                List {
                if allTags.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("No tags")
                                .font(DesignSystem.Typography.title2)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                        } icon: {
                            Image(systemName: "tag")
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                    } description: {
                        Text("Create tags in the Tags manager to organize your notes.")
                            .font(DesignSystem.Typography.callout)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(allTags) { tag in
                        let tagName = tag.name ?? "Unnamed"
                        let isSelected = noteTagNamesLowercased.contains(tagName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                        Button {
                            toggleTag(tagName, isSelected: isSelected)
                        } label: {
                            HStack(spacing: DesignSystem.Spacing.md) {
                                Circle()
                                    .fill(Color(hex: tag.color ?? "#007AFF") ?? DesignSystem.Colors.accent)
                                    .frame(width: 12, height: 12)
                                Text(tagName)
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(DesignSystem.Colors.accent)
                                        .font(.system(size: 18))
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignSystem.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onSave()
                        dismiss()
                    }
                    .font(DesignSystem.Typography.button)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func toggleTag(_ tagName: String, isSelected: Bool) {
        let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        var currentTags = (note.tags ?? "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        if isSelected {
            currentTags.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        } else {
            let exists = currentTags.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
            if !exists { currentTags.append(trimmed) }
        }
        
        note.tags = currentTags.isEmpty ? nil : currentTags.joined(separator: ",")
        note.modifiedDate = Date()
        if !viewContext.inkSlateSave(module: "Notes") {
            errorMessage = "Failed to update tags."
            showingError = true
        }
    }
}

// MARK: - Move to Folder View
struct MoveToFolderView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject var note: Notes
    let onDismiss: () -> Void
    
    @State private var showingError = false
    @State private var errorMessage = ""
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FSProject.name, ascending: true)]
    ) private var projects: FetchedResults<FSProject>
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                Form {
                Section {
                    Button {
                        moveNoteToFolder(nil)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 20))
                                .foregroundColor(DesignSystem.Colors.accent)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("All Notes")
                                    .font(DesignSystem.Typography.title3)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                Text("Remove from folder")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            
                            Spacer()
                            
                            if note.project == nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(DesignSystem.Colors.accent)
                                    .font(.system(size: 18))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                
                Section("Folders") {
                    if projects.isEmpty {
                        VStack(spacing: DesignSystem.Spacing.lg) {
                            Image(systemName: "folder")
                                .font(.system(size: 40, weight: .light))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                            Text("No folders yet")
                                .font(DesignSystem.Typography.title2)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            Text("Create a folder to organize your notes")
                                .font(DesignSystem.Typography.callout)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(projects) { project in
                            Button {
                                moveNoteToFolder(project)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(DesignSystem.Colors.accent)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.name ?? "Unnamed Folder")
                                            .font(DesignSystem.Typography.title3)
                                            .foregroundColor(DesignSystem.Colors.textPrimary)
                                        if let notes = project.notes as? Set<Notes> {
                                            let count = notes.filter { !$0.isMarkedDeleted }.count
                                            Text("\(count) notes")
                                                .font(DesignSystem.Typography.caption)
                                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if note.project?.id == project.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(DesignSystem.Colors.accent)
                                            .font(.system(size: 18))
                                    }
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            }
            .navigationTitle("Move to folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignSystem.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                    .font(DesignSystem.Typography.button)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func moveNoteToFolder(_ folder: FSProject?) {
        lightHaptic()
        
        note.project = folder
        note.modifiedDate = Date()
        
        if viewContext.inkSlateSave(module: "Notes") {
            onDismiss()
            dismiss()
        } else {
            errorMessage = "Failed to move note."
            showingError = true
        }
    }
}

// MARK: - Placeholder Views