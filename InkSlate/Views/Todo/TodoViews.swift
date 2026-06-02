import SwiftUI
import CoreData

// MARK: - Recurrence Helper

struct RecurrenceRule: Codable {
    var type: String
    var interval: Int?
    var weekdays: [Int]?

    private static let decoder: JSONDecoder = {
        JSONDecoder()
    }()

    static func decode(from ruleString: String?) -> RecurrenceRule? {
        guard let ruleString,
              let ruleData = ruleString.data(using: .utf8) else {
            return nil
        }
        return try? decoder.decode(RecurrenceRule.self, from: ruleData)
    }
    
    func nextDueDate(from currentDate: Date) -> Date? {
        let calendar = Calendar.current
        
        switch type {
        case "daily":
            return calendar.date(byAdding: .day, value: 1, to: currentDate)
            
        case "weekly":
            guard let weekdays = weekdays, !weekdays.isEmpty else {
                return calendar.date(byAdding: .weekOfYear, value: 1, to: currentDate)
            }
            let currentWeekday = calendar.component(.weekday, from: currentDate)
            let sortedWeekdays = weekdays.sorted()
            
            if let next = sortedWeekdays.first(where: { $0 > currentWeekday }) {
                let daysToAdd = next - currentWeekday
                return calendar.date(byAdding: .day, value: daysToAdd, to: currentDate)
            }
            if let first = sortedWeekdays.first {
                let daysToAdd = 7 - currentWeekday + first
                return calendar.date(byAdding: .day, value: daysToAdd, to: currentDate)
            }
            return calendar.date(byAdding: .weekOfYear, value: 1, to: currentDate)
            
        case "monthly":
            return calendar.date(byAdding: .month, value: 1, to: currentDate)
            
        case "custom":
            let intervalDays = interval ?? 1
            return calendar.date(byAdding: .day, value: intervalDays, to: currentDate)
            
        default:
            return nil
        }
    }
}

// MARK: - Color Conversion Extension
extension TodoTab {
    var colorValue: Color {
        guard let colorName = color else { return DesignSystem.Colors.accent }
        switch colorName.lowercased() {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "pink": return .pink
        case "cyan": return .cyan
        case "mint": return .mint
        case "indigo": return .indigo
        case "brown": return .brown
        default: return DesignSystem.Colors.accent
        }
    }
}

// MARK: - Todo Main View

struct TodoMainView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var sharedState: SharedStateManager
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \TodoTab.createdDate, ascending: true)]) private var tabs: FetchedResults<TodoTab>
    
    @State private var selectedTab: TodoTab?
    @State private var showingAddTask = false
    @State private var showingAddTab = false
    @State private var showingEditTab = false
    @State private var editingTab: TodoTab?
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if !tabs.isEmpty {
                        TabSelectorView(
                            tabs: Array(tabs),
                            selectedTab: $selectedTab,
                            onAddTab: { showingAddTab = true },
                            onEditTab: { tab in
                                editingTab = tab
                                showingEditTab = true
                            },
                            onDeleteTab: deleteTab
                        )
                        .padding(.bottom, DesignSystem.Spacing.md)
                    }
                    
                    if tabs.isEmpty {
                        EmptyTodoStateView {
                            showingAddTab = true
                        }
                    } else if let selectedTab {
                        TodoTaskListView(
                            selectedTab: selectedTab,
                            onAddTask: { showingAddTask = true }
                        )
                        .id(selectedTab.objectID)
                    }
                }
            }
            .navigationTitle(selectedTab?.name ?? "To-Do")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            showingAddTab = true
                            lightHaptic()
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .tint(selectedTab?.colorValue ?? DesignSystem.Colors.accent)
                        
                        Button {
                            showingAddTask = true
                            lightHaptic()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .tint(selectedTab?.colorValue ?? DesignSystem.Colors.accent)
                        .disabled(tabs.isEmpty)
                    }
                }
            }
            .onAppear {
                if selectedTab == nil && !tabs.isEmpty {
                    selectedTab = tabs.first
                }
            }
            .onChange(of: tabs.count) { _, _ in
                reconcileSelectedTab()
            }
            .onChange(of: tabs.first?.objectID) { _, _ in
                reconcileSelectedTab()
            }
            .sheet(isPresented: $showingAddTask) {
                AddTodoTaskView(selectedTab: selectedTab, availableTabs: Array(tabs))
                    .presentationDetents([.fraction(0.5), .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingAddTab) {
                AddTodoTabView()
                    .presentationDetents([.fraction(0.5)])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingEditTab) {
                if let tab = editingTab {
                    EditTodoTabView(tab: tab)
                        .presentationDetents([.fraction(0.5)])
                        .presentationDragIndicator(.visible)
                }
            }
        }
    }
    
    private func reconcileSelectedTab() {
        guard !tabs.isEmpty else {
            selectedTab = nil
            return
        }

        if let current = selectedTab,
           tabs.contains(where: { $0.objectID == current.objectID }) {
            return
        }

        selectedTab = tabs.first
    }
    
    private func deleteTab(_ tab: TodoTab) {
        withAnimation {
            viewContext.delete(tab)
            viewContext.inkSlateSave(module: "To-Do")
            if selectedTab === tab {
                selectedTab = tabs.first
            }
        }
    }
}

// MARK: - Task List (predicate-scoped fetch)

private struct TodoTaskListView: View {
    @Environment(\.managedObjectContext) private var viewContext

    private let selectedTab: TodoTab
    private let onAddTask: () -> Void

    @FetchRequest private var tasks: FetchedResults<TodoTask>

    init(selectedTab: TodoTab, onAddTask: @escaping () -> Void) {
        self.selectedTab = selectedTab
        self.onAddTask = onAddTask

        let request: NSFetchRequest<TodoTask> = TodoTask.fetchRequest()
        request.predicate = NSPredicate(format: "tab == %@", selectedTab)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \TodoTask.isCompleted, ascending: true),
            NSSortDescriptor(keyPath: \TodoTask.title, ascending: true)
        ]
        request.fetchBatchSize = 40

        _tasks = FetchRequest(fetchRequest: request, animation: .default)
    }

    var body: some View {
        List {
            if tasks.isEmpty {
                EmptyTaskStateView(selectedTab: selectedTab, onCreate: onAddTask)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 40, leading: DesignSystem.Spacing.lg, bottom: 8, trailing: DesignSystem.Spacing.lg))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(tasks) { task in
                    TodoTaskRow(task: task)
                        .id(task.objectID)
                        .listRowInsets(EdgeInsets(top: 4, leading: DesignSystem.Spacing.lg, bottom: 4, trailing: DesignSystem.Spacing.lg))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DesignSystem.Colors.background)
        .refreshable {
            PersistenceController.shared.refreshFromCloud()
        }
    }
}

// MARK: - Empty States

struct EmptyTodoStateView: View {
    let onCreate: () -> Void
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 44))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            
            Text("No To-Do Lists")
                .font(DesignSystem.Typography.title2)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Text("Create your first list to get started.")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Button("Create List", action: onCreate)
                .minimalistButton(variant: .primary, size: .medium)
        }
        .padding(.horizontal, DesignSystem.Spacing.xxl)
    }
}

struct EmptyTaskStateView: View {
    let selectedTab: TodoTab
    let onCreate: () -> Void
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            
            Text("No tasks in \"\(selectedTab.name ?? "List")\"")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Text("Tap below to add your first task.")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Button("Add Task", action: onCreate)
                .minimalistButton(variant: .secondary, size: .medium)
        }
    }
}

// MARK: - Tab Selector View

struct TabSelectorView: View {
    let tabs: [TodoTab]
    @Binding var selectedTab: TodoTab?
    let onAddTab: () -> Void
    let onEditTab: (TodoTab) -> Void
    let onDeleteTab: (TodoTab) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(tabs) { tab in
                    TabButtonView(
                        tab: tab,
                        isSelected: selectedTab === tab,
                        onTap: {
                            withAnimation(.easeInOut) {
                                selectedTab = tab
                                lightHaptic()
                            }
                        },
                        onEdit: { onEditTab(tab) },
                        onDelete: { onDeleteTab(tab) }
                    )
                }
                
                Button(action: onAddTab) {
                    Label("New List", systemImage: "plus.circle")
                        .labelStyle(.titleAndIcon)
                            .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.backgroundSecondary)
    }
}

// MARK: - Tab Button View

struct TabButtonView: View {
    let tab: TodoTab
    let isSelected: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Circle()
                    .fill(tab.colorValue)
                    .frame(width: 8, height: 8)
                
                Text(tab.name ?? "Unknown")
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.medium)
                
                Text("\(tab.tasks?.count ?? 0)")
                    .font(DesignSystem.Typography.caption)
                    .padding(.horizontal, DesignSystem.Spacing.xs)
                    .background(DesignSystem.Colors.backgroundTertiary)
                    .cornerRadius(DesignSystem.CornerRadius.xs)
            }
            .foregroundColor(isSelected ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textPrimary)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(isSelected ? tab.colorValue : DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.md)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit Name") { onEdit() }
            Button("Delete List", role: .destructive) {
                onDelete()
            }
            .disabled((tab.tasks?.count ?? 0) > 0)
        }
    }
}

// MARK: - Todo Task Row

struct TodoTaskRow: View {
    @ObservedObject var task: TodoTask
    @Environment(\.managedObjectContext) private var viewContext
    
    private var hasRecurrence: Bool {
        guard let recurrenceType = task.recurrenceType, !recurrenceType.isEmpty else {
            return false
        }
        return recurrenceType != "none"
    }
    
    private var nextDueDateString: String? {
        guard let nextDue = task.nextDueDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: nextDue)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Button {
                toggleTaskCompletion(animation: .spring(response: 0.25, dampingFraction: 0.8))
                lightHaptic()
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(task.isCompleted ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(task.title ?? "Untitled")
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(task.isCompleted ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.textPrimary)
                    .strikethrough(task.isCompleted)
                
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineLimit(3)
                }
                
                if let dueDate = task.dueDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                        Text(formatDate(dueDate))
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                } else if hasRecurrence, let nextDue = nextDueDateString {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("Next: \(nextDue)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                }
            }
            
            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .minimalistCard(.outlined)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteTask()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            Button {
                withAnimation {
                    toggleTaskCompletion(animation: nil)
                    lightHaptic()
                }
            } label: {
                Label("Complete", systemImage: "checkmark")
            }
            .tint(DesignSystem.Colors.success)
        }
        .contextMenu {
            Button {
                withAnimation {
                    toggleTaskCompletion(animation: nil)
                    lightHaptic()
                }
            } label: {
                Label("Mark Complete", systemImage: "checkmark")
            }
            Button(role: .destructive) {
                deleteTask()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func toggleTaskCompletion(animation: Animation?) {
        let ruleString = task.recurrenceRule
        let recurrenceRule = (task.isCompleted == false) ? RecurrenceRule.decode(from: ruleString) : nil

        let applyToggle = {
            task.isCompleted.toggle()
            task.completedDate = task.isCompleted ? Date() : nil
            task.modifiedDate = Date()  // Critical for CloudKit sync
        }

        if let animation {
            withAnimation(animation) { applyToggle() }
        } else {
            applyToggle()
        }

        if task.isCompleted, hasRecurrence, let recurrenceRule, let ruleString {
            createNextRecurrenceIfNeeded(from: task, rule: recurrenceRule, ruleString: ruleString)
        }

        viewContext.inkSlateSave(module: "To-Do")
    }
    
    private func createNextRecurrenceIfNeeded(from originalTask: TodoTask, rule: RecurrenceRule, ruleString: String) {
        guard let baseDate = originalTask.dueDate ?? originalTask.createdDate,
              let nextDue = rule.nextDueDate(from: baseDate) else { return }

        if nextRecurrenceAlreadyExists(in: originalTask, ruleString: ruleString, nextDue: nextDue) {
            return
        }
        
        let now = Date()
        let newTask = TodoTask(context: viewContext)
        newTask.id = UUID()
        newTask.title = originalTask.title
        newTask.notes = originalTask.notes
        newTask.tab = originalTask.tab
        newTask.createdDate = now
        newTask.modifiedDate = now  // Critical for CloudKit sync
        newTask.dueDate = nextDue
        newTask.isCompleted = false
        newTask.recurrenceType = originalTask.recurrenceType
        newTask.recurrenceRule = originalTask.recurrenceRule
        newTask.nextDueDate = rule.nextDueDate(from: nextDue)
        newTask.priority = originalTask.priority
        
    }

    private func nextRecurrenceAlreadyExists(in originalTask: TodoTask, ruleString: String, nextDue: Date) -> Bool {
        guard let tab = originalTask.tab else { return false }

        let request: NSFetchRequest<TodoTask> = TodoTask.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(
            format: "tab == %@ AND isCompleted == NO AND recurrenceRule == %@ AND dueDate == %@",
            tab,
            ruleString,
            nextDue as NSDate
        )

        guard let count = try? viewContext.count(for: request) else { return true }
        return count > 0
    }
    
    private func deleteTask() {
        viewContext.delete(task)
        viewContext.inkSlateSave(module: "To-Do")
    }
}


// MARK: - Add Task View

struct AddTodoTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let selectedTab: TodoTab?
    let availableTabs: [TodoTab]
    @State private var title = ""
    @State private var notes = ""
    @State private var selectedTabID: NSManagedObjectID?
    @State private var showingError = false
    @State private var errorMessage = ""
    
    @State private var dueDate: Date = Date()
    @State private var hasDueDate = false
    @State private var hasRecurrence = false
    @State private var recurrenceType = "daily"
    @State private var selectedWeekdays: Set<Int> = []
    @State private var customInterval = 1
    
    private var trimmedAddTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Task Details")
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        VStack(spacing: DesignSystem.Spacing.lg) {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                                Text("Title")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                
                                TextField("Enter task title", text: $title)
                                    .font(DesignSystem.Typography.body)
                                    .padding(DesignSystem.Spacing.md)
                                    .background(DesignSystem.Colors.surface)
                                    .cornerRadius(DesignSystem.CornerRadius.sm)
                            }
                            
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                                Text("Notes")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                
                                TextField("Add notes (optional)", text: $notes, axis: .vertical)
                                    .font(DesignSystem.Typography.body)
                                    .lineLimit(3...6)
                                    .padding(DesignSystem.Spacing.md)
                                    .background(DesignSystem.Colors.surface)
                                    .cornerRadius(DesignSystem.CornerRadius.sm)
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                    
                    if availableTabs.isEmpty {
                        VStack(spacing: DesignSystem.Spacing.md) {
                            Text("No lists available")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            Text("Create a to-do list before adding tasks.")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                        .padding(DesignSystem.Spacing.lg)
                        .frame(maxWidth: .infinity)
                        .background(DesignSystem.Colors.backgroundSecondary)
                        .cornerRadius(DesignSystem.CornerRadius.md)
                    } else {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            Text("List")
                                .font(DesignSystem.Typography.headline)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            Picker("List", selection: $selectedTabID) {
                                ForEach(availableTabs, id: \.objectID) { tab in
                                    Text(tab.name ?? "Untitled List")
                                        .tag(Optional(tab.objectID))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        .padding(DesignSystem.Spacing.lg)
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(DesignSystem.CornerRadius.md)
                    }
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        HStack {
                            Text("Due Date")
                                .font(DesignSystem.Typography.headline)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            Spacer()
                            Toggle("", isOn: $hasDueDate)
                                .labelsHidden()
                        }
                        
                        if hasDueDate {
                            DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date])
                                .datePickerStyle(.compact)
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        HStack {
                            Text("Recurrence")
                                .font(DesignSystem.Typography.headline)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            Spacer()
                            Toggle("", isOn: $hasRecurrence)
                                .labelsHidden()
                        }
                        
                        if hasRecurrence {
                            VStack(spacing: DesignSystem.Spacing.md) {
                                Picker("Recurrence Type", selection: $recurrenceType) {
                                    Text("Daily").tag("daily")
                                    Text("Weekly").tag("weekly")
                                    Text("Monthly").tag("monthly")
                                    Text("Custom").tag("custom")
                                }
                                .pickerStyle(.segmented)
                                
                                if recurrenceType == "weekly" {
                                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                                        Text("Select Days")
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundColor(DesignSystem.Colors.textSecondary)
                                        HStack(spacing: DesignSystem.Spacing.sm) {
                                            ForEach(1...7, id: \.self) { weekday in
                                                Button {
                                                    if selectedWeekdays.contains(weekday) {
                                                        selectedWeekdays.remove(weekday)
                                                    } else {
                                                        selectedWeekdays.insert(weekday)
                                                    }
                                                } label: {
                                                    Text(weekdayNames[weekday - 1])
                                                        .font(DesignSystem.Typography.caption)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(selectedWeekdays.contains(weekday) ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textPrimary)
                                                        .frame(width: 40, height: 40)
                                                        .background(selectedWeekdays.contains(weekday) ? DesignSystem.Colors.accent : DesignSystem.Colors.surface)
                                                        .cornerRadius(DesignSystem.CornerRadius.sm)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                                
                                if recurrenceType == "custom" {
                                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                                        Text("Every \(customInterval) day\(customInterval == 1 ? "" : "s")")
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundColor(DesignSystem.Colors.textSecondary)
                                        Stepper("", value: $customInterval, in: 1...365)
                                    }
                                }
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                    
                    Button {
                        addTask()
                    } label: {
                        Text("Add Task")
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.textInverse)
                            .frame(maxWidth: .infinity)
                            .padding(DesignSystem.Spacing.lg)
                            .background(trimmedAddTitle.isEmpty ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.accent)
                            .cornerRadius(DesignSystem.CornerRadius.md)
                    }
                    .disabled(trimmedAddTitle.isEmpty || availableTabs.isEmpty)
                    .padding(.bottom, DesignSystem.Spacing.lg)
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .navigationTitle("Add Task")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.accent)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            selectedTabID = selectedTab?.objectID ?? availableTabs.first?.objectID
        }
    }
    
    private func addTask() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        
        guard !availableTabs.isEmpty else {
            errorMessage = "Create a list before adding tasks."
            showingError = true
            return
        }
        
        if hasRecurrence && recurrenceType == "weekly" && selectedWeekdays.isEmpty {
            errorMessage = "Select at least one weekday for a weekly recurrence."
            showingError = true
            return
        }
        
        let resolvedTabID = selectedTabID ?? availableTabs.first?.objectID
        guard let tabID = resolvedTabID,
              let tab = availableTabs.first(where: { $0.objectID == tabID }) else {
            errorMessage = "No list available to add task to"
            showingError = true
            return
        }
        
        let now = Date()
        let newTask = TodoTask(context: viewContext)
        newTask.title = trimmedTitle
        newTask.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        newTask.tab = tab
        newTask.id = UUID()
        newTask.createdDate = now
        newTask.modifiedDate = now  // Critical for CloudKit sync
        newTask.isCompleted = false
        
        if hasDueDate {
            newTask.dueDate = dueDate
        }
        
        if hasRecurrence {
            newTask.recurrenceType = recurrenceType
            
            var rule = RecurrenceRule(type: recurrenceType)
            if recurrenceType == "weekly" {
                rule.weekdays = Array(selectedWeekdays).sorted()
            } else if recurrenceType == "custom" {
                rule.interval = customInterval
            }
            
            if let ruleData = try? JSONEncoder().encode(rule),
               let ruleString = String(data: ruleData, encoding: .utf8) {
                newTask.recurrenceRule = ruleString
            }
            
// Use a stable baseline for recurring tasks so instances are deterministic and dedupe-safe.
            if newTask.dueDate == nil {
                newTask.dueDate = Date()
            }
            if let due = newTask.dueDate, let nextDue = rule.nextDueDate(from: due) {
                newTask.nextDueDate = nextDue
            }
        } else {
            newTask.recurrenceType = "none"
        }
        
        
        if viewContext.inkSlateSave(module: "To-Do", retry: { addTask() }) {
            dismiss()
        } else if errorMessage.isEmpty {
            errorMessage = "Failed to save task."
            showingError = true
        }
    }
}

// MARK: - Add Todo Tab View

struct AddTodoTabView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var tabName = ""
    @State private var selectedColor: Color = .blue
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private let availableColors: [Color] = [
        .blue, .green, .orange, .red, .purple, .pink, .cyan, .mint, .indigo, .brown
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: DesignSystem.Spacing.xl) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("List Name")
                        .font(DesignSystem.Typography.callout)
                        .fontWeight(.medium)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    TextField("Enter list name", text: $tabName)
                        .font(DesignSystem.Typography.body)
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(DesignSystem.CornerRadius.sm)
                }
                
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Color")
                        .font(DesignSystem.Typography.callout)
                        .fontWeight(.medium)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: DesignSystem.Spacing.md) {
                        ForEach(availableColors, id: \.self) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: selectedColor == color ? 3 : 1)
                                    )
                                    .scaleEffect(selectedColor == color ? 1.1 : 1.0)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                Spacer()
                
                Button {
                    createTab()
                } label: {
                    Text("Create List")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textInverse)
                        .frame(maxWidth: .infinity)
                        .padding(DesignSystem.Spacing.lg)
                        .background(tabName.isEmpty ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.accent)
                        .cornerRadius(DesignSystem.CornerRadius.md)
                }
                .disabled(tabName.isEmpty)
            }
            .padding(DesignSystem.Spacing.lg)
            .navigationTitle("New List")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func createTab() {
        let newTab = TodoTab(context: viewContext)
        newTab.name = tabName.trimmingCharacters(in: .whitespacesAndNewlines)
        newTab.color = getColorString(from: selectedColor)
        newTab.id = UUID()
        newTab.createdDate = Date()
        newTab.modifiedDate = Date()
        viewContext.insert(newTab)
        if viewContext.inkSlateSave(module: "To-Do", retry: { createTab() }) {
            dismiss()
        } else if errorMessage.isEmpty {
            errorMessage = "Failed to create list."
            showingError = true
        }
    }
    
    private func getColorString(from color: Color) -> String {
        if color == .blue { return "blue" }
        if color == .green { return "green" }
        if color == .orange { return "orange" }
        if color == .red { return "red" }
        if color == .purple { return "purple" }
        if color == .pink { return "pink" }
        if color == .cyan { return "cyan" }
        if color == .mint { return "mint" }
        if color == .indigo { return "indigo" }
        if color == .brown { return "brown" }
        return "blue"
    }
}

// MARK: - Edit Todo Tab View

struct EditTodoTabView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let tab: TodoTab
    @State private var tabName: String
    @State private var selectedColor: Color
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingDeleteConfirmation = false
    
    private let availableColors: [Color] = [
        .blue, .green, .orange, .red, .purple, .pink, .cyan, .mint, .indigo, .brown
    ]
    
    init(tab: TodoTab) {
        self.tab = tab
        self._tabName = State(initialValue: tab.name ?? "")
        self._selectedColor = State(initialValue: tab.colorValue)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: DesignSystem.Spacing.xl) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("List Name")
                        .font(DesignSystem.Typography.callout)
                        .fontWeight(.medium)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    TextField("Enter list name", text: $tabName)
                        .font(DesignSystem.Typography.body)
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(DesignSystem.CornerRadius.sm)
                }
                
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Color")
                        .font(DesignSystem.Typography.callout)
                        .fontWeight(.medium)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: DesignSystem.Spacing.md) {
                        ForEach(availableColors, id: \.self) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: selectedColor == color ? 3 : 1)
                                    )
                                    .scaleEffect(selectedColor == color ? 1.1 : 1.0)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                if (tab.tasks?.count ?? 0) == 0 {
                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        Text("Delete List")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(DesignSystem.Spacing.md)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(DesignSystem.CornerRadius.sm)
                    }
                }
                
                Spacer()
                
                Button {
                    saveChanges()
                } label: {
                    Text("Save Changes")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textInverse)
                        .frame(maxWidth: .infinity)
                        .padding(DesignSystem.Spacing.lg)
                        .background(tabName.isEmpty ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.accent)
                        .cornerRadius(DesignSystem.CornerRadius.md)
                }
                .disabled(tabName.isEmpty)
            }
            .padding(DesignSystem.Spacing.lg)
            .navigationTitle("Edit List")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .alert("Delete List", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteTab()
                }
            } message: {
                Text("Are you sure you want to delete '\(tab.name ?? "Unknown")'? This action cannot be undone.")
            }
        }
    }
    
    private func saveChanges() {
        tab.name = tabName.trimmingCharacters(in: .whitespacesAndNewlines)
        tab.color = getColorString(from: selectedColor)
        tab.modifiedDate = Date()
        if viewContext.inkSlateSave(module: "To-Do", retry: { saveChanges() }) {
            dismiss()
        } else if errorMessage.isEmpty {
            errorMessage = "Failed to save changes."
            showingError = true
        }
    }
    
    private func getColorString(from color: Color) -> String {
        if color == .blue { return "blue" }
        if color == .green { return "green" }
        if color == .orange { return "orange" }
        if color == .red { return "red" }
        if color == .purple { return "purple" }
        if color == .pink { return "pink" }
        if color == .cyan { return "cyan" }
        if color == .mint { return "mint" }
        if color == .indigo { return "indigo" }
        if color == .brown { return "brown" }
        return "blue"
    }
    
    private func deleteTab() {
        viewContext.delete(tab)
        if viewContext.inkSlateSave(module: "To-Do") {
            dismiss()
        } else if errorMessage.isEmpty {
            errorMessage = "Failed to delete list."
            showingError = true
        }
    }
}
