//
//  NotesViews.swift
//  InkSlate
//

import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif
import CoreData

// MARK: - Sort Options (imported from NotesService)

// MARK: - Main Notes List View
struct NotesListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest private var normalNotes: FetchedResults<Notes>
    @FetchRequest private var deletedNotes: FetchedResults<Notes>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FSProject.name, ascending: true)]
    ) private var projects: FetchedResults<FSProject>

    @StateObject private var searchDebouncer = SearchDebouncer(delay: 0.4)
    @State private var searchQuery: String = ""

    @State private var showingNewNoteSheet = false
    @State private var selectedNote: Notes?
    @State private var selectedProject: FSProject?
    @State private var showingProjectSidebar = NavigationSplitViewVisibility.detailOnly
    @State private var showingFoldersSheet = false
    @State private var showingNewProjectSheet = false
    @State private var showingProjectSettings = false
    @State private var showingTagManager = false
    @State private var noteToMove: Notes?
    
    @AppStorage("lastSelectedFolderID") private var lastSelectedFolderID: String?

    @State private var sortBy: SortBy = .modificationDate
    @State private var sortDirection: SortDirection = .descending
    @State private var showPinnedOnly = false

    @State private var showingDeletedNotes = false
    @State private var showingEmptyTrashAlert = false

    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    @State private var notesChromeAppeared = false
    
    init() {
        let defaultSort = [NSSortDescriptor(key: "modifiedDate", ascending: false)]
        
        // Configure fetch request with batch size for performance.
        // Avoid hard fetch limits so users never "lose" older notes in the UI.
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
        // Start with "All Notes" (nil) if no saved preference
        guard let folderIDString = lastSelectedFolderID,
              let folderID = UUID(uuidString: folderIDString) else {
            selectedProject = nil
            return
        }
        
        // Try to find the saved folder
        if let savedFolder = projects.first(where: { $0.id == folderID }) {
            selectedProject = savedFolder
        } else {
            // Folder was deleted, reset to "All Notes"
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

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    notesHeroHeader
                    notesSearchAndFilters
                    if filteredNotes.isEmpty {
                        notesEmptyState
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
                    if note.isDeleted {
                        Text("This note is in Recently Deleted.")
                            .padding()
                    } else if note.isEncrypted {
                        DecryptionView(note: note) { success in
                            if success {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    selectedNote = note
                                }
                            } else {
                                selectedNote = nil
                            }
                        }
                    } else {
                        TextEditorView(note: note)
                    }
                }
            }
            .alert("Error", isPresented: $showingError) { Button("OK") {} } message: { Text(errorMessage) }
                .onAppear {
                    purgeOldDeletedNotes()
                    loadLastSelectedFolder()
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
        
        // Move notes to "All Notes" (remove folder assignment)
        if let notes = project.notes as? Set<Notes> {
            for note in notes {
                note.project = nil
            }
        }
        
        viewContext.delete(project)
        
        do {
            try viewContext.save()
        } catch {
            print("Failed to delete folder: \(error.localizedDescription)")
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

            ForEach(filteredNotes, id: \.id) { note in
                NoteRowView(
                    note: note,
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
                            // Lock/unlock is handled inside the editor; jump there directly.
                            selectedNote = note
                        } label: {
                            Label(note.isEncrypted ? "Unlock" : "Lock",
                                  systemImage: "lock")
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
                            Label(note.isEncrypted ? "Unlock" : "Lock",
                                  systemImage: note.isEncrypted ? "lock.open" : "lock.fill")
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
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(.easeInOut(duration: 0.2), value: filteredNotes.map { $0.id })
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
        note.modifiedDate = Date()
        
        do {
            try viewContext.save()
        } catch {
            errorMessage = "Failed to delete note: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func restoreNote(_ note: Notes) {
        lightHaptic()

        note.isMarkedDeleted = false
        note.modifiedDate = Date()

        saveOrAlert("Failed to restore note")
    }

    private func permanentlyDelete(_ note: Notes) {
        heavyHaptic()

        viewContext.delete(note)
        saveOrAlert("Failed to permanently delete note")
    }

    private func emptyTrash() {
        withAnimation(.easeInOut) { isLoading = true }

        // Use batch delete for better performance
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

    private func togglePin(_ note: Notes) {
        mediumHaptic()

        note.isPinned.toggle()
        note.modifiedDate = Date()

        saveOrAlert("Failed to toggle pin")
    }

    private func purgeOldDeletedNotes() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        
        // Use batch delete for better performance
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Notes")
        fetchRequest.predicate = NSPredicate(format: "isMarkedDeleted == YES AND modifiedDate < %@", cutoff as NSDate)
        
        let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        batchDelete.resultType = .resultTypeObjectIDs
        
        do {
            let result = try viewContext.execute(batchDelete) as? NSBatchDeleteResult
            let objectIDArray = result?.result as? [NSManagedObjectID]
            let changes = [NSDeletedObjectsKey: objectIDArray ?? []]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
            try viewContext.save()
        } catch {
            // Silently fail for background cleanup - log but don't show error
            print("Failed to purge old deleted notes: \(error.localizedDescription)")
        }
    }

    private func saveOrAlert(_ prefix: String) {
        do {
            try viewContext.save()
        } catch {
            errorMessage = "\(prefix): \(error.localizedDescription)"
            showingError = true
        }
    }
    
    /// Filtered list; must not write to `@State` here (SwiftUI forbids mutating state during view update).
    private var filteredNotes: [Notes] {
        performFilteredFilter()
    }
    
    private var rowDisplaySettings: (showCreated: Bool, showModified: Bool, showPreview: Bool, showTags: Bool) {
        guard let s = selectedProject?.settings else {
            return (true, true, true, true)
        }
        return (s.showCreatedDate, s.showModifiedDate, s.showPreview, s.showTags)
    }
    
    private func noteMatchesSearch(_ note: Notes, queryLowercased: String, scope: String) -> Bool {
        if note.isEncrypted {
            return note.title?.lowercased().contains(queryLowercased) ?? false
        }
        let inTitle = note.title?.lowercased().contains(queryLowercased) ?? false
        let inContent = (note.content ?? "").lowercased().contains(queryLowercased)
        let inPreview = (note.preview ?? "").lowercased().contains(queryLowercased)
        switch scope {
        case "title":
            return inTitle
        case "content":
            return inContent || inPreview
        default:
            return inTitle || inContent || inPreview
        }
    }
    
    private func performFilteredFilter() -> [Notes] {
        PerformanceLogger.measure(log: PerformanceMetrics.notesQuery, name: "FilterNotes") {
            // Use existing FetchedResults (already loaded by Core Data)
            let source = showingDeletedNotes ? deletedNotes : normalNotes
            var filtered = Array(source)
            
            let folderSettings = (!showingDeletedNotes) ? selectedProject?.settings : nil
            
            if let selectedProject = selectedProject, !showingDeletedNotes {
                filtered = filtered.filter { $0.project == selectedProject }
            }
            
            if !showingDeletedNotes {
                switch folderSettings?.filterBy ?? "all" {
                case "pinned":
                    filtered = filtered.filter { $0.isPinned }
                case "unpinned":
                    filtered = filtered.filter { !$0.isPinned }
                default:
                    if showPinnedOnly { filtered = filtered.filter { $0.isPinned } }
                }
            }
            
            if !searchDebouncer.debouncedText.isEmpty {
                let searchLower = searchDebouncer.debouncedText.lowercased()
                let scope = folderSettings?.searchScope ?? "titleAndContent"
                filtered = filtered.filter { noteMatchesSearch($0, queryLowercased: searchLower, scope: scope) }
            }
            
            let effectiveSortBy: SortBy = (selectedProject != nil && !showingDeletedNotes)
                ? SortBy.fromProjectSettings(folderSettings?.sortBy)
                : sortBy
            let ascending: Bool = {
                if selectedProject != nil && !showingDeletedNotes, let order = folderSettings?.sortOrder {
                    return order == "ascending"
                }
                return sortDirection == .ascending
            }()
            
            filtered.sort { note1, note2 in
                switch effectiveSortBy {
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
                    // "Ascending": unpinned first. "Descending": pinned first.
                    if note1.isPinned != note2.isPinned {
                        return ascending ? (!note1.isPinned && note2.isPinned) : (note1.isPinned && !note2.isPinned)
                    }
                    // Stable fallback within same pin group.
                    let date1 = note1.modifiedDate ?? Date.distantPast
                    let date2 = note2.modifiedDate ?? Date.distantPast
                    return date1 > date2
                }
            }
            
            return filtered
        }
    }
    
    private func deleteProject(_ project: FSProject) {
        mediumHaptic()
        
        if selectedProject?.id == project.id {
            withAnimation {
                selectedProject = nil
            }
        }
        
        // Safety: prevent Core Data cascade rules from deleting notes when a folder is removed.
        // Always move notes to "All Notes" by clearing the relationship before deleting the folder.
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

// MARK: - Note Row View
struct NoteRowView: View {
    let note: Notes
    var showCreatedDate: Bool = true
    var showModifiedDate: Bool = true
    var showPreview: Bool = true
    var showTagsRow: Bool = true
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
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
                    if note.isEncrypted {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.warning)
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
                    if note.isEncrypted {
                        Text("Locked — open to read")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .lineLimit(2)
                    } else if !(note.preview?.isEmpty ?? true) {
                        Text(note.preview ?? "")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .lineLimit(3)
                    }
                }

                HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                    if showCreatedDate || showModifiedDate {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            if showCreatedDate {
                                Text((note.createdDate ?? Date()).formatted(.dateTime.month(.abbreviated).day().year(.defaultDigits)))
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                            }
                            if showCreatedDate && showModifiedDate {
                                Text("·")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                            }
                            if showModifiedDate {
                                Text((note.modifiedDate ?? Date()).formatted(.dateTime.month(.abbreviated).day().year(.defaultDigits)))
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    if showTagsRow, !(note.tags?.isEmpty ?? true) {
                        HStack(spacing: 6) {
                            ForEach(Array(tagTokens(from: note.tags).prefix(3).enumerated()), id: \.offset) { _, trimmed in
                                Text(trimmed)
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(DesignSystem.Colors.backgroundTertiary)
                                    .clipShape(Capsule())
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
        }
        .buttonStyle(.plain)
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
    @ObservedObject var note: Notes
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingMarkdownPreview = false
    @State private var showingTagEditor = false
    @State private var showingEncryption = false
    @State private var showingDecryption = false
    @State private var showingExportOptions = false

    @State private var showingError = false
    @State private var errorMessage = ""

    @State private var hasUnsavedChanges = false
    @State private var autoSaveTimer: Timer?
    @State private var isSaving = false
    
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var coordinatorRef: MarkdownEditor.Coordinator?

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
                    contentSection
                }
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

                    Button {
                        if note.isEncrypted { showingDecryption = true } else { showingEncryption = true }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: note.isEncrypted ? "lock.fill" : "lock.open")
                            Text(note.isEncrypted ? "Decrypt" : "Encrypt")
                        }
                        .font(DesignSystem.Typography.button)
                        .foregroundColor(note.isEncrypted ? DesignSystem.Colors.warning : DesignSystem.Colors.accent)
                    }

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
            .sheet(isPresented: $showingEncryption) {
                EncryptionView(note: note) { success in
                    if success { saveNote() }
                    showingEncryption = false
                }
            }
            .sheet(isPresented: $showingDecryption) {
                DecryptionView(note: note) { success in
                    if success { saveNote() }
                    showingDecryption = false
                }
            }
            .sheet(isPresented: $showingExportOptions) { ExportOptionsView(note: note) }
            .fullScreenCoverIfAvailable(isPresented: $showingMarkdownPreview) {
                NotePreviewScreen(note: note, isPresented: $showingMarkdownPreview)
            }
            .alert("Error", isPresented: $showingError) { Button("OK") {} } message: { Text(errorMessage) }
            .onAppear { startAutoSave() }
            .onDisappear { 
                autoSaveTimer?.invalidate()
                autoSaveTimer = nil
                stopAutoSave()
                
                flushEditorToNote()
                // Save any pending changes before leaving
                if hasUnsavedChanges {
                    saveNote()
                }
            }
        }
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
                .onChange(of: note.title) { _, _ in markAsChanged() }
            
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

            MarkdownEditor(text: Binding(
                get: { note.content ?? "" },
                set: { note.content = $0 }
            ), selectedRange: $selectedRange, coordinatorRef: $coordinatorRef)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                )
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.lg)
                .onChange(of: note.content) { _, _ in markAsChanged() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func markAsChanged() {
        // Safety: encrypted notes should never be edited directly.
        guard !note.isEncrypted else { return }
        // Ensure main thread for Core Data access
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
            let plain = MarkdownSerialization.plainText(from: serialized)
            note.preview = String(plain.prefix(100))
        } else if let content = note.content {
            let plain = MarkdownSerialization.plainText(from: content)
            note.preview = String(plain.prefix(100))
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
        // Auto-save is handled by scheduleAutoSave() called from markAsChanged()
    }

    private func stopAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    private func scheduleAutoSave() {
        autoSaveTimer?.invalidate()
        // Save quickly after typing stops (1.5 seconds) - feels instant like iOS Notes
        // but still debounces to avoid saving on every single keystroke
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            if hasUnsavedChanges { saveNote() }
        }
    }

    /// Pushes the latest UITextView content into the note; matches `NewNoteView.saveNote()` and avoids
    /// the editor’s 0.3s debounce losing the last lines on Done, dismiss, or preview.
    private func flushEditorToNote() {
        #if canImport(UIKit)
        coordinatorRef?.flushPendingEditsToParent()
        #endif
    }

    private func saveNote() {
        guard !isSaving else { return }
        flushEditorToNote()
        isSaving = true
        note.modifiedDate = Date()
        
        // Capture current user edits so we can preserve them if a CloudKit/Core Data merge conflict occurs.
        let capturedTitle = note.title
        let capturedContent = note.content
        let capturedPreview = note.preview
        let capturedProject = note.project
        
        // Content already updated in markAsChanged(), just save
        // Note: Saves are already debounced (1.5s), so main thread is acceptable here
        defer { isSaving = false }  // Ensure isSaving is always reset
        
        do {
            try viewContext.save()
            hasUnsavedChanges = false
        } catch let error as NSError {
            // Handle specific Core Data errors
            if error.domain == NSCocoaErrorDomain {
                // Check for merge conflicts (error code 133020)
                if error.code == 133020 || error.userInfo[NSPersistentStoreSaveConflictsErrorKey] != nil {
                    // Conflict UX: preserve the user's edits by saving them as a separate note.
                    // This avoids silent overwrites and gives the user a recoverable copy.
                    let conflictCopy = Notes(context: viewContext)
                    conflictCopy.id = UUID()
                    conflictCopy.createdDate = Date()
                    conflictCopy.modifiedDate = Date()
                    conflictCopy.project = capturedProject
                    conflictCopy.title = ((capturedTitle?.isEmpty == false) ? capturedTitle! : "Untitled") + " (Conflict Copy)"
                    conflictCopy.content = capturedContent
                    conflictCopy.preview = capturedPreview
                    
                    // Roll back the conflicting transaction, then save the new copy.
                    viewContext.rollback()
                    viewContext.insert(conflictCopy)
                    do {
                        try viewContext.save()
                        hasUnsavedChanges = false
                        errorMessage = "Sync conflict detected. Your changes were saved as a separate note: \"\(conflictCopy.title ?? "Conflict Copy")\"."
                        showingError = true
                    } catch {
                        errorMessage = "Sync conflict detected, but saving a conflict copy failed: \(error.localizedDescription)"
                        showingError = true
                    }
                } else if error.code >= 1610 && error.code <= 1620 {
                    // Validation errors (1610-1620 range)
                    errorMessage = "Invalid data: \(error.localizedDescription)"
                    showingError = true
                } else {
                    errorMessage = "Save failed: \(error.localizedDescription)"
                    showingError = true
                }
            } else {
                errorMessage = "Failed to save: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func saveAndDismiss() {
        flushEditorToNote()
        if hasUnsavedChanges { saveNote() }
        dismiss()
    }
}

struct NotePreviewScreen: View {
    @ObservedObject var note: Notes
    @Binding var isPresented: Bool
    
    private var displayContent: String { note.content ?? "" }
    
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
        ScrollView {
            MarkdownPreviewTextView(content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignSystem.Spacing.xxl)
                .padding(.vertical, DesignSystem.Spacing.xxl)
        }
        .background(DesignSystem.Colors.background)
    }
}

#if canImport(UIKit)
private struct MarkdownPreviewTextView: UIViewRepresentable {
    let content: String
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        let width = max(uiView.bounds.width - 28, UIScreen.main.bounds.width - 48)
        if let (attributed, _) = MarkdownSerialization.deserialize(content, maxWidth: width) {
            uiView.attributedText = attributed
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
    @State private var project: FSProject?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var coordinatorRef: MarkdownEditor.Coordinator?

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
                        MarkdownEditor(text: $content, selectedRange: .constant(NSRange(location: 0, length: 0)), coordinatorRef: $coordinatorRef)
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
        
        // Capture current content (from rich editor on iOS)
        var finalContent = content
        #if canImport(UIKit)
        if let coordinator = coordinatorRef, let textView = coordinator.textView {
            finalContent = coordinator.serializeContent(from: textView.attributedText)
        }
        #endif
        let newNote = Notes(context: viewContext)
        newNote.id = UUID()  // Required for CloudKit sync
        newNote.title = title.isEmpty ? "Untitled" : title
        newNote.content = finalContent
        newNote.project = project ?? selectedProject
        newNote.isMarkedDeleted = false
        newNote.createdDate = Date()
        newNote.modifiedDate = Date()
        
        // Create preview without image markers
        let plain = MarkdownSerialization.plainText(from: finalContent)
        newNote.preview = String(plain.prefix(100))

        viewContext.insert(newNote)

        do {
            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to save note: \(error.localizedDescription)"
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
        
        // If setting as default, unset other defaults
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
        
        // Create default settings
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
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to create folder: \(error.localizedDescription)"
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
            // Create new settings
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
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to save settings: \(error.localizedDescription)"
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
        
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            errorMessage = "Failed to delete tag: \(error.localizedDescription)"
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
                                            .stroke(color == colorHex ? DesignSystem.Colors.textPrimary : Color.clear, lineWidth: 2)
                                    )
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
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to save tag: \(error.localizedDescription)"
            showingError = true
            isSaving = false
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
                        let isSelected = noteTagNames.contains(tagName)
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
        var currentTags = (note.tags ?? "").components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if isSelected {
            currentTags.removeAll { $0 == tagName }
        } else {
            if !currentTags.contains(tagName) {
                currentTags.append(tagName)
            }
        }
        note.tags = currentTags.isEmpty ? nil : currentTags.joined(separator: ",")
        note.modifiedDate = Date()
        do {
            try viewContext.save()
        } catch {
            errorMessage = "Failed to update tags: \(error.localizedDescription)"
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
                // Move to "All Notes" (no folder)
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
                
                // User Created Folders
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
        
        do {
            try viewContext.save()
            onDismiss()
            dismiss()
        } catch {
            errorMessage = "Failed to move note: \(error.localizedDescription)"
            showingError = true
        }
    }
}

// MARK: - Placeholder Views (imported from service files)