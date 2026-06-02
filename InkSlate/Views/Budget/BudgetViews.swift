import SwiftUI
import CoreData
import Foundation

// MARK: - Balance Status Enum

enum BalanceStatus {
    case underBudget
    case closeToLimit
    case overBudget
    
    var color: Color {
        switch self {
        case .underBudget:
            return DesignSystem.Colors.success
        case .closeToLimit:
            return .orange
        case .overBudget:
            return .red
        }
    }
    
    var icon: String {
        switch self {
        case .underBudget:
            return "checkmark.circle.fill"
        case .closeToLimit:
            return "exclamationmark.triangle.fill"
        case .overBudget:
            return "xmark.circle.fill"
        }
    }
}

// MARK: - Formatters

extension NumberFormatter {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter
    }()
}

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
    
    static let mediumDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}

// MARK: - Live budget while typing (avoids Core Data writes per keystroke)

private enum BudgetFieldParsing {
    static func displayAmount(text: String, committed: Double) -> Double {
        let filtered = text.filter { "0123456789.".contains($0) }
        if filtered.isEmpty { return 0 }
        if let v = Double(filtered), v.isFinite { return v }
        return committed
    }
}

private struct BudgetLiveBudgetPreferenceKey: PreferenceKey {
    static var defaultValue: [NSManagedObjectID: Double] { [:] }
    static func reduce(value: inout [NSManagedObjectID: Double], nextValue: () -> [NSManagedObjectID: Double]) {
        let next = nextValue()
        for (id, amount) in next {
            value[id] = amount
        }
    }
}

// MARK: - Budget Feature Views

struct BudgetMainView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BudgetCategory.sortOrder, ascending: true)]
    ) private var categories: FetchedResults<BudgetCategory>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BudgetItem.date, ascending: false)],
        predicate: NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "isIncome == YES"),
            NSPredicate(format: "name == %@ AND subcategory == nil", "Monthly Income")
        ])
    ) private var incomeItems: FetchedResults<BudgetItem>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BudgetSubcategory.sortOrder, ascending: true)]
    ) private var subcategories: FetchedResults<BudgetSubcategory>
    
    @StateObject private var budgetManager = BudgetManager.shared
    @State private var selectedItem: BudgetItem?
    @State private var showingCreateCategory = false
    @State private var showingCategoryManagement = false
    @State private var newItem: BudgetItem?
    @State private var showingIncomeInput = false
    @State private var showingResetAlert = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    @State private var collapsedCategoryObjectIDs: Set<NSManagedObjectID> = []
    @State private var sortedSubcategoriesByCategoryObjectID: [NSManagedObjectID: [BudgetSubcategory]] = [:]
    @State private var hasBuiltSubcategoryCache = false
    /// Orphan repair scans all subcategories/categories/items; run it at most once per session (not on every Budget appear) to avoid repeated fu...
    @State private var hasRepairedOrphans = false
    @State private var cloudKitRebuildTask: Task<Void, Never>?
    @AppStorage("budget.didEnsureDefaultSubcategories") private var didEnsureDefaultSubcategories = false
    @State private var subcategoryManagementCategory: BudgetCategory?
    @State private var addSubcategoryCategory: BudgetCategory?
    @State private var editCategorySheet: BudgetCategory?
    @State private var categoryToDelete: BudgetCategory?
    @State private var showingDeleteCategoryConfirmation = false
    @State private var liveBudgetBySubcategoryID: [NSManagedObjectID: Double] = [:]
    
    private var currentPeriod: Date {
        Date()
    }
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                budgetHeader
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.top, DesignSystem.Spacing.sm)
                    .padding(.bottom, DesignSystem.Spacing.md)
                
                if categories.isEmpty {
                    emptyStateView
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                } else {
                    budgetContent
                }
            }
        }
        .onAppear {
            if !hasRepairedOrphans {
                budgetManager.repairOrphanBudgetSubcategories(with: viewContext)
                hasRepairedOrphans = true
            }
            if categories.isEmpty {
                budgetManager.initializeDefaultCategories(with: viewContext)
            }
            budgetManager.cleanupExpiredItems(with: viewContext)
            if !didEnsureDefaultSubcategories {
                budgetManager.ensureAllDefaultSubcategoriesExist(categories: Array(categories), with: viewContext)
                didEnsureDefaultSubcategories = true
            }
            if !hasBuiltSubcategoryCache {
                rebuildSubcategoryCache()
                hasBuiltSubcategoryCache = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: viewContext)) { _ in
            rebuildSubcategoryCache()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudKitDataRefreshed)) { _ in
            scheduleCloudKitCacheRebuild()
        }
        .navigationBarHiddenIfPossible(true)
        .keyboardDismissToolbar()
        .sheet(item: $newItem) { item in
            BudgetItemDetailView(item: item, budgetManager: budgetManager, isNewItem: true)
        }
        .sheet(isPresented: $showingCreateCategory) {
            CreateCategoryView(budgetManager: budgetManager, viewContext: viewContext)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingCategoryManagement) {
            CategoryManagementView(budgetManager: budgetManager, viewContext: viewContext)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedItem) { item in
            BudgetItemDetailView(item: item, budgetManager: budgetManager)
        }
        .sheet(isPresented: $showingIncomeInput) {
            MonthlyIncomeInputView(
                income: .constant(monthlyIncome),
                onSave: { saveMonthlyIncome($0) }
            )
        }
        .sheet(item: $subcategoryManagementCategory) { category in
            SubcategoryManagementView(category: category)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $addSubcategoryCategory) { category in
            AddSubcategoryView(category: category)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editCategorySheet) { category in
            EditCategoryView(category: category, budgetManager: budgetManager)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Delete Category", isPresented: $showingDeleteCategoryConfirmation) {
            Button("Cancel", role: .cancel) {
                categoryToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let category = categoryToDelete {
                    viewContext.delete(category)
                    viewContext.saveQuietly(module: "Budget")
                    PersistenceController.shared.save()
                }
                categoryToDelete = nil
            }
        } message: {
            Text("This will delete the category and all of its subcategories and items. This action cannot be undone.")
        }
    }

    private var budgetHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Budget")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                Text(DateFormatter.monthYear.string(from: currentPeriod))
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()

            HStack(spacing: DesignSystem.Spacing.sm) {
                Button {
                    lightHaptic()
                    showingCreateCategory = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(DesignSystem.Colors.surface)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(DesignSystem.Colors.border.opacity(0.8), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Category")

                Button {
                    lightHaptic()
                    showingCategoryManagement = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(DesignSystem.Colors.surface)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(DesignSystem.Colors.border.opacity(0.8), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Manage Categories and Subcategories")

                Menu {
                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        Label("Reset Budget Data", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(DesignSystem.Colors.surface)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(DesignSystem.Colors.border.opacity(0.8), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More")
            }
        }
    }
    
    private var monthlyIncome: Double {
        incomeItems.first?.amount ?? 0.0
    }
    
    private func saveMonthlyIncome(_ amount: Double) {
        guard amount >= 0 else {
            showError("Income amount cannot be negative")
            return
        }
        
        let incomeSnapshot = Array(incomeItems)
        if incomeSnapshot.count > 1 {
            for item in incomeSnapshot.dropFirst() {
                viewContext.delete(item)
            }
        }
        
        if let existingItem = incomeSnapshot.first {
            existingItem.amount = amount
            existingItem.modifiedDate = Date()
            existingItem.isIncome = true
            existingItem.name = "Monthly Income"
        } else {
            let incomeItem = BudgetItem(context: viewContext)
            incomeItem.id = UUID()
            incomeItem.name = "Monthly Income"
            incomeItem.amount = amount
            incomeItem.date = Date()
            incomeItem.createdDate = Date()
            incomeItem.modifiedDate = Date()
            incomeItem.isIncome = true
            viewContext.insert(incomeItem)
        }
        
        viewContext.processPendingChanges()
        
        if !viewContext.inkSlateSave(module: "Budget") {
            showError("Failed to save monthly income")
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingErrorAlert = true
    }
    
    private var budgetContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.lg) {
                    BudgetHeroSummaryView(
                        monthlyIncome: monthlyIncome,
                        totalBudget: totalBudget,
                        remaining: monthlyIncome - totalBudget,
                        remainingColor: remainingColor,
                        remainingIcon: remainingIcon,
                        onTapIncome: { showingIncomeInput = true }
                    )
                    
                    HStack {
                        Text("Categories")
                            .font(DesignSystem.Typography.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        Spacer()
                        
                        Button {
                            showingCategoryManagement = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "slider.horizontal.3")
                                Text("Manage")
                            }
                            .font(DesignSystem.Typography.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(DesignSystem.Colors.accent)
                            .padding(.horizontal, DesignSystem.Spacing.md)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .background(DesignSystem.Colors.surface)
                            .cornerRadius(DesignSystem.CornerRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                    .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    ForEach(categories, id: \.objectID) { category in
                        BudgetCategoryAccordionCard(
                            category: category,
                            period: currentPeriod,
                            budgetManager: budgetManager,
                            isCollapsed: collapsedCategoryObjectIDs.contains(category.objectID),
                            subcategories: subcategoriesForCategory(category),
                            onToggleCollapsed: {
                                if collapsedCategoryObjectIDs.contains(category.objectID) {
                                    collapsedCategoryObjectIDs.remove(category.objectID)
                                } else {
                                    collapsedCategoryObjectIDs.insert(category.objectID)
                                }
                            },
                            onAddItem: { sub in
                                createNewItem(in: sub)
                            },
                            onAddSubcategory: {
                                addSubcategoryCategory = category
                            },
                            onManageSubcategories: {
                                subcategoryManagementCategory = category
                            },
                            onEditCategory: {
                                editCategorySheet = category
                            },
                            onDeleteCategory: {
                                categoryToDelete = category
                                showingDeleteCategoryConfirmation = true
                            }
                        )
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.xxl)
            }
            .onPreferenceChange(BudgetLiveBudgetPreferenceKey.self) { liveBudgetBySubcategoryID = $0 }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
        }
        .alert("Reset Budget Data", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                budgetManager.clearAllBudgetData(with: viewContext)
                budgetManager.initializeDefaultCategories(with: viewContext)
                didEnsureDefaultSubcategories = false
                budgetManager.ensureAllDefaultSubcategoriesExist(categories: Array(categories), with: viewContext)
                didEnsureDefaultSubcategories = true
                rebuildSubcategoryCache()
            }
        } message: {
            Text("This will permanently delete all budget categories, subcategories, and items. This action cannot be undone.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func createNewItem(in subcategory: BudgetSubcategory) {
        newItem = budgetManager.createBudgetItem(
            name: subcategory.name ?? "Item",
            amount: 0.0,
            subcategory: subcategory,
            with: viewContext
        )
        viewContext.saveQuietly(module: "Budget")
    }
    
    private func subcategoriesForCategory(_ category: BudgetCategory) -> [BudgetSubcategory] {
        sortedSubcategoriesByCategoryObjectID[category.objectID] ?? []
    }
    
    /// Debounces CloudKit import bursts so live edits aren't interrupted by repeated full cache rebuilds
    private func scheduleCloudKitCacheRebuild() {
        cloudKitRebuildTask?.cancel()
        cloudKitRebuildTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            rebuildSubcategoryCache()
        }
    }

    private func rebuildSubcategoryCache() {
        var next: [NSManagedObjectID: [BudgetSubcategory]] = [:]
        for category in categories {
            let subs = (category.subcategories as? Set<BudgetSubcategory>) ?? []
            next[category.objectID] = subs.sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return (lhs.name ?? "") < (rhs.name ?? "")
                }
                return lhs.sortOrder < rhs.sortOrder
            }
        }
        sortedSubcategoriesByCategoryObjectID = next
    }
    
    private var summaryCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.md) {
                Button {
                    showingIncomeInput = true
                } label: {
                    SummaryCardView(
                        title: "Total Income",
                        amount: monthlyIncome,
                        color: DesignSystem.Colors.success,
                        icon: "arrow.up.circle.fill"
                    )
                }
                .buttonStyle(.plain)
                
                SummaryCardView(
                    title: "Total Budget",
                    amount: totalBudget,
                    color: budgetColor,
                    icon: "target"
                )
                
                SummaryCardView(
                    title: "Total Remaining",
                    amount: monthlyIncome - totalBudget,
                    color: remainingColor,
                    icon: remainingIcon
                )
            }
            .padding(.horizontal, 2)
        }
    }
    
    private var remainingColor: Color {
        let remaining = monthlyIncome - totalBudget
        if remaining > 0 {
            return DesignSystem.Colors.success
        } else if remaining == 0 {
            return DesignSystem.Colors.accent
        } else {
            return .red
        }
    }
    
    private var remainingIcon: String {
        let remaining = monthlyIncome - totalBudget
        if remaining > 0 {
            return "checkmark.circle.fill"
        } else if remaining == 0 {
            return "equal.circle.fill"
        } else {
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var budgetColor: Color {
        if monthlyIncome == 0 {
            return DesignSystem.Colors.accent
        } else if totalBudget > monthlyIncome {
            return .red
        } else {
            return .green
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 60))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            
            Text("No Budget Categories")
                .font(DesignSystem.Typography.title2)
                .fontWeight(.medium)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Text("Tap the New Category button above to create your first budget category, or Manage to edit categories and subcategories.")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.xl)
        }
        .padding(DesignSystem.Spacing.xxl)
    }
    
    // MARK: - Computed Properties
    private var totalBudget: Double {
        subcategories.reduce(0.0) { total, subcategory in
            let amount = liveBudgetBySubcategoryID[subcategory.objectID] ?? subcategory.budgetAmount
            return total + (amount.isFinite ? amount : 0)
        }
    }
    
    private var totalSpent: Double {
        return categories.reduce(0.0) { total, category in
            guard let subcategories = category.subcategories else { return total }
            return total + subcategories.reduce(0.0) { subTotal, subcategory in
                if let sub = subcategory as? BudgetSubcategory {
                    return subTotal + budgetManager.calculateTotalSpent(for: sub, in: currentPeriod)
                } else {
                    return subTotal
                }
            }
        }
    }
    
}

// MARK: - Summary Card View
struct SummaryCardView: View {
    let title: String
    let amount: Double
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
                
                Spacer()
            }
            
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Text(NumberFormatter.currency.string(from: NSNumber(value: amount)) ?? "$0.00")
                .font(DesignSystem.Typography.headline)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.Colors.textPrimary)
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .minimalistCard(.elevated)
    }
}

// MARK: - Hero Summary (New UI)
struct BudgetHeroSummaryView: View {
    let monthlyIncome: Double
    let totalBudget: Double
    let remaining: Double
    let remainingColor: Color
    let remainingIcon: String
    let onTapIncome: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This month")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    
                    Text(NumberFormatter.currency.string(from: NSNumber(value: remaining)) ?? "$0.00")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Image(systemName: remainingIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(remainingColor)
                        Text(remaining >= 0 ? "Remaining" : "Over budget")
                            .font(DesignSystem.Typography.callout)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
                
                Spacer()
                
                Button {
                    onTapIncome()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil")
                        Text("Income")
                    }
                    .font(DesignSystem.Typography.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                }
                .buttonStyle(.plain)
            }
            
            HStack(spacing: DesignSystem.Spacing.md) {
                BudgetHeroMetric(
                    title: "Income",
                    value: NumberFormatter.currency.string(from: NSNumber(value: monthlyIncome)) ?? "$0.00",
                    icon: "arrow.up.circle.fill",
                    tint: DesignSystem.Colors.success
                )
                
                BudgetHeroMetric(
                    title: "Budgeted",
                    value: NumberFormatter.currency.string(from: NSNumber(value: totalBudget)) ?? "$0.00",
                    icon: "target",
                    tint: DesignSystem.Colors.accent
                )
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
    }
}

struct BudgetHeroMetric: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Spacer()
            }
            
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            
            Text(value)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.backgroundSecondary.opacity(0.6))
        .cornerRadius(DesignSystem.CornerRadius.md)
    }
}

// MARK: - Category Accordion Card (New UI)
struct BudgetCategoryAccordionCard: View {
    let category: BudgetCategory
    let period: Date
    let budgetManager: BudgetManager
    let isCollapsed: Bool
    let subcategories: [BudgetSubcategory]
    
    @State private var liveBudgetBySubcategoryID: [NSManagedObjectID: Double] = [:]
    
    let onToggleCollapsed: () -> Void
    let onAddItem: (BudgetSubcategory) -> Void
    let onAddSubcategory: () -> Void
    let onManageSubcategories: () -> Void
    let onEditCategory: () -> Void
    let onDeleteCategory: () -> Void
    
    private var totalBudget: Double {
        subcategories.reduce(0.0) { sum, sub in
            let amount = liveBudgetBySubcategoryID[sub.objectID] ?? sub.budgetAmount
            return sum + (amount.isFinite ? amount : 0)
        }
    }
    
    private var totalSpent: Double {
        subcategories.reduce(0.0) { total, sub in
            total + budgetManager.calculateTotalSpent(for: sub, in: period)
        }
    }
    
    private var status: BalanceStatus {
        if totalBudget == 0 { return .underBudget }
        if totalSpent <= totalBudget { return .underBudget }
        if totalSpent <= totalBudget * 1.1 { return .closeToLimit }
        return .overBudget
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(DesignSystem.Spacing.lg)
            
            if !isCollapsed {
                Divider()
                    .background(DesignSystem.Colors.border.opacity(0.7))
                
                VStack(spacing: 0) {
                    ForEach(subcategories, id: \.objectID) { sub in
                        BudgetSubcategoryInlineCardRow(
                            subcategory: sub,
                            period: period,
                            budgetManager: budgetManager,
                            onAddItem: { onAddItem(sub) }
                        )
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.vertical, DesignSystem.Spacing.md)
                        
                        if sub.objectID != subcategories.last?.objectID {
                            Divider()
                                .padding(.leading, 62)
                                .background(DesignSystem.Colors.border.opacity(0.6))
                        }
                    }
                    
                    HStack(spacing: DesignSystem.Spacing.md) {
                        Button {
                            onAddSubcategory()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add subcategory")
                            }
                            .font(DesignSystem.Typography.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(DesignSystem.Colors.accent)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Button {
                            onManageSubcategories()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "slider.horizontal.3")
                                Text("Manage")
                            }
                            .font(DesignSystem.Typography.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(DesignSystem.Spacing.lg)
                }
            }
        }
        .onPreferenceChange(BudgetLiveBudgetPreferenceKey.self) { liveBudgetBySubcategoryID = $0 }
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
    }
    
    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Button {
                onToggleCollapsed()
                lightHaptic()
            } label: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(DesignSystem.Colors.backgroundSecondary)
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: category.icon ?? "tag")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.accent)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.displayName)
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .lineLimit(1)
                        
                        Text("\(NumberFormatter.currency.string(from: NSNumber(value: totalSpent)) ?? "$0.00") spent")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: status.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(status.color)
                    Text(NumberFormatter.currency.string(from: NSNumber(value: totalBudget)) ?? "$0.00")
                        .font(DesignSystem.Typography.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }
                
                HStack(spacing: 10) {
                    Menu {
                        Button {
                            onAddSubcategory()
                        } label: {
                            Label("Add Subcategory", systemImage: "plus")
                        }
                        
                        Button {
                            onManageSubcategories()
                        } label: {
                            Label("Manage Subcategories", systemImage: "list.bullet")
                        }
                        
                        Divider()
                        
                        Button {
                            onEditCategory()
                        } label: {
                            Label("Edit Category", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            onDeleteCategory()
                        } label: {
                            Label("Delete Category", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .frame(width: 28, height: 28)
                            .background(DesignSystem.Colors.backgroundSecondary.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
            }
        }
    }
}

// MARK: - Subcategory row (New UI)
struct BudgetSubcategoryInlineCardRow: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    let subcategory: BudgetSubcategory
    let period: Date
    let budgetManager: BudgetManager
    let onAddItem: () -> Void
    
    @State private var budgetText: String = ""
    @FocusState private var isFocused: Bool
    @State private var budgetDebounceTask: Task<Void, Never>?
    
    private var displayBudgetAmount: Double {
        BudgetFieldParsing.displayAmount(text: budgetText, committed: subcategory.budgetAmount)
    }
    
    private var spent: Double {
        budgetManager.calculateTotalSpent(for: subcategory, in: period)
    }
    
    private var status: BalanceStatus {
        let budget = displayBudgetAmount
        if budget <= 0 { return .underBudget }
        if spent <= budget { return .underBudget }
        if spent <= budget * 1.1 { return .closeToLimit }
        return .overBudget
    }
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ZStack {
                Circle()
                    .fill(status.color.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: status.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(status.color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(subcategory.displayName)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                
                Text("\(NumberFormatter.currency.string(from: NSNumber(value: spent)) ?? "$0.00") spent")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                Text("$")
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                
                TextField("0.00", text: $budgetText)
                    .font(DesignSystem.Typography.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 86)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .cornerRadius(10)
                    .onChange(of: budgetText) { _, newValue in
                        let filtered = newValue.filter { "0123456789.".contains($0) }
                        if filtered != newValue {
                            budgetText = filtered
                        }
                        scheduleDebouncedBudgetCommit()
                    }
                    .focused($isFocused)
                    .onSubmit {
                        budgetDebounceTask?.cancel()
                        commitBudget()
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            budgetDebounceTask?.cancel()
                            commitBudget()
                        }
                    }
            }
            
            Button {
                onAddItem()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.accent)
            }
            .buttonStyle(.plain)
        }
        .preference(key: BudgetLiveBudgetPreferenceKey.self, value: [subcategory.objectID: displayBudgetAmount])
        .onAppear {
            budgetText = subcategory.budgetAmount == 0 ? "" : String(format: "%.2f", subcategory.budgetAmount)
        }
        .onChange(of: subcategory.budgetAmount) { _, newAmount in
            guard !isFocused else { return }
            budgetText = newAmount == 0 ? "" : String(format: "%.2f", newAmount)
        }
    }

    private func scheduleDebouncedBudgetCommit() {
        budgetDebounceTask?.cancel()
        budgetDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            commitBudget()
        }
    }

    private func commitBudget() {
        let filtered = budgetText.filter { "0123456789.".contains($0) }
        if filtered != budgetText {
            budgetText = filtered
        }

        let newValue: Double
        if let value = Double(filtered) {
            newValue = value
        } else if filtered.isEmpty {
            newValue = 0.0
        } else {
            return
        }

        if abs(newValue - subcategory.budgetAmount) < 0.0001 { return }

        subcategory.budgetAmount = newValue
        subcategory.modifiedDate = Date()
        viewContext.saveQuietly(module: "Budget")
    }
}

// MARK: - Category Section Header (Simplified UI)
struct BudgetCategorySectionHeaderView: View {
    let category: BudgetCategory
    let period: Date
    let budgetManager: BudgetManager
    
    private var totalBudget: Double {
        let subs = (category.subcategories as? Set<BudgetSubcategory>) ?? []
        return subs.reduce(0.0) { $0 + $1.budgetAmount }
    }
    
    private var totalSpent: Double {
        let subs = (category.subcategories as? Set<BudgetSubcategory>) ?? []
        return subs.reduce(0.0) { total, sub in
            total + budgetManager.calculateTotalSpent(for: sub, in: period)
        }
    }
    
    private var status: BalanceStatus {
        if totalBudget == 0 { return .underBudget }
        if totalSpent <= totalBudget { return .underBudget }
        if totalSpent <= totalBudget * 1.1 { return .closeToLimit }
        return .overBudget
    }
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: category.icon ?? "tag")
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            
            Text(category.displayName)
                .font(DesignSystem.Typography.callout)
                .fontWeight(.semibold)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            
            Spacer()
            
            HStack(spacing: 6) {
                Image(systemName: status.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(status.color)
                
                Text(NumberFormatter.currency.string(from: NSNumber(value: totalBudget)) ?? "$0.00")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .textCase(nil)
        .padding(.top, 6)
    }
}

// MARK: - Category Section Header (Collapsible + Actions)
struct BudgetCategorySectionHeaderInteractiveView: View {
    let category: BudgetCategory
    let period: Date
    let budgetManager: BudgetManager
    let isCollapsed: Bool
    
    let onToggleCollapsed: () -> Void
    let onAddSubcategory: () -> Void
    let onManageSubcategories: () -> Void
    let onEditCategory: () -> Void
    let onDeleteCategory: () -> Void
    
    private var totalBudget: Double {
        let subs = (category.subcategories as? Set<BudgetSubcategory>) ?? []
        return subs.reduce(0.0) { $0 + $1.budgetAmount }
    }
    
    private var totalSpent: Double {
        let subs = (category.subcategories as? Set<BudgetSubcategory>) ?? []
        return subs.reduce(0.0) { total, sub in
            total + budgetManager.calculateTotalSpent(for: sub, in: period)
        }
    }
    
    private var status: BalanceStatus {
        if totalBudget == 0 { return .underBudget }
        if totalSpent <= totalBudget { return .underBudget }
        if totalSpent <= totalBudget * 1.1 { return .closeToLimit }
        return .overBudget
    }
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Button {
                onToggleCollapsed()
                lightHaptic()
            } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    
                    Image(systemName: category.icon ?? "tag")
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    
                    Text(category.displayName)
                        .font(DesignSystem.Typography.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            HStack(spacing: 6) {
                Image(systemName: status.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(status.color)
                
                Text(NumberFormatter.currency.string(from: NSNumber(value: totalBudget)) ?? "$0.00")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            
            Menu {
                Button {
                    onAddSubcategory()
                } label: {
                    Label("Add Subcategory", systemImage: "plus")
                }
                
                Button {
                    onManageSubcategories()
                } label: {
                    Label("Manage Subcategories", systemImage: "list.bullet")
                }
                
                Divider()
                
                Button {
                    onEditCategory()
                } label: {
                    Label("Edit Category", systemImage: "pencil")
                }
                
                Button(role: .destructive) {
                    onDeleteCategory()
                } label: {
                    Label("Delete Category", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .textCase(nil)
        .padding(.top, 6)
    }
}

// MARK: - Subcategory Row (Simplified UI)
struct BudgetSubcategoryBudgetRowView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    let subcategory: BudgetSubcategory
    let period: Date
    let budgetManager: BudgetManager
    let onAddItem: () -> Void
    
    @State private var budgetText: String = ""
    @FocusState private var isFocused: Bool
    @State private var budgetDebounceTask: Task<Void, Never>?
    
    private var spent: Double {
        budgetManager.calculateTotalSpent(for: subcategory, in: period)
    }
    
    private var status: BalanceStatus {
        let budget = subcategory.budgetAmount
        if budget <= 0 { return .underBudget }
        if spent <= budget { return .underBudget }
        if spent <= budget * 1.1 { return .closeToLimit }
        return .overBudget
    }
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subcategory.displayName)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                
                Text("\(NumberFormatter.currency.string(from: NSNumber(value: spent)) ?? "$0.00") spent")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                Image(systemName: status.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(status.color)
                
                Text("$")
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                
                TextField("0.00", text: $budgetText)
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .focused($isFocused)
                    .onChange(of: budgetText) { _, newValue in
                        let filtered = newValue.filter { "0123456789.".contains($0) }
                        if filtered != newValue {
                            budgetText = filtered
                        }
                        scheduleDebouncedBudgetCommit()
                    }
                    .onSubmit {
                        budgetDebounceTask?.cancel()
                        commitBudget()
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            budgetDebounceTask?.cancel()
                            commitBudget()
                        }
                    }
            }
            
            Button {
                onAddItem()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignSystem.Colors.accent)
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            budgetText = subcategory.budgetAmount == 0 ? "" : String(format: "%.2f", subcategory.budgetAmount)
        }
    }

    private func scheduleDebouncedBudgetCommit() {
        budgetDebounceTask?.cancel()
        budgetDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            commitBudget()
        }
    }

    private func commitBudget() {
        let filtered = budgetText.filter { "0123456789.".contains($0) }
        if filtered != budgetText {
            budgetText = filtered
        }

        let newValue: Double
        if let value = Double(filtered) {
            newValue = value
        } else if filtered.isEmpty {
            newValue = 0.0
        } else {
            return
        }

        if abs(newValue - subcategory.budgetAmount) < 0.0001 { return }

        subcategory.budgetAmount = newValue
        subcategory.modifiedDate = Date()
        viewContext.saveQuietly(module: "Budget")
    }
}

// MARK: - Budget Category Row (Home UI)
struct BudgetCategoryRowView: View {
    let category: BudgetCategory
    let budgetManager: BudgetManager
    let period: Date
    
    private var totalBudget: Double {
        guard let subs = category.subcategories as? Set<BudgetSubcategory> else { return 0.0 }
        return subs.reduce(0.0) { $0 + $1.budgetAmount }
    }
    
    private var totalSpent: Double {
        guard let subs = category.subcategories as? Set<BudgetSubcategory> else { return 0.0 }
        return subs.reduce(0.0) { total, sub in
            total + budgetManager.calculateTotalSpent(for: sub, in: period)
        }
    }
    
    private var progress: Double {
        guard totalBudget > 0 else { return 0.0 }
        return min(max(totalSpent / totalBudget, 0.0), 1.0)
    }
    
    private var statusColor: Color {
        if totalBudget == 0 { return DesignSystem.Colors.textTertiary }
        if totalSpent <= totalBudget { return DesignSystem.Colors.success }
        if totalSpent <= totalBudget * 1.1 { return DesignSystem.Colors.warning }
        return DesignSystem.Colors.error
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.backgroundSecondary)
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: category.icon ?? "tag")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.accent)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.displayName)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    
                    Text("\(NumberFormatter.currency.string(from: NSNumber(value: totalSpent)) ?? "$0.00") spent of \(NumberFormatter.currency.string(from: NSNumber(value: totalBudget)) ?? "$0.00")")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            
            ProgressView(value: progress)
                .tint(statusColor)
                .scaleEffect(x: 1, y: 1.35, anchor: .center)
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Budget Category Detail (New)
struct BudgetCategoryDetailView: View {
    let category: BudgetCategory
    let budgetManager: BudgetManager
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest private var subcategories: FetchedResults<BudgetSubcategory>
    
    @State private var showingSubcategoryManager = false
    @State private var showingAddSubcategory = false
    
    @State private var selectedItem: BudgetItem?
    @State private var newItem: BudgetItem?
    
    private var currentPeriod: Date { Date() }
    
    init(category: BudgetCategory, budgetManager: BudgetManager) {
        self.category = category
        self.budgetManager = budgetManager
        self._subcategories = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \BudgetSubcategory.sortOrder, ascending: true)],
            predicate: NSPredicate(format: "category == %@", category)
        )
    }
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()
            
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.md) {
                    headerCard
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        HStack {
                            Text("Subcategories")
                                .font(DesignSystem.Typography.callout)
                                .fontWeight(.semibold)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                            
                            Spacer()
                            
                            Button {
                                showingSubcategoryManager = true
                            } label: {
                                Text("Manage")
                                    .font(DesignSystem.Typography.callout)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(DesignSystem.Colors.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        VStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(subcategories, id: \.objectID) { sub in
                                BudgetSubcategoryCardView(
                                    subcategory: sub,
                                    period: currentPeriod,
                                    budgetManager: budgetManager,
                                    onAddItem: { createNewItem(in: sub) },
                                    onOpenItem: { item in selectedItem = item }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.xxl)
            }
        }
        .onAppear {
            BudgetManager.shared.repairOrphanBudgetSubcategories(with: viewContext)
            ensureDefaultSubcategoriesExist()
        }
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddSubcategory = true
                    } label: {
                        Label("New Subcategory", systemImage: "plus")
                    }
                    
                    Button {
                        showingSubcategoryManager = true
                    } label: {
                        Label("Manage Subcategories", systemImage: "list.bullet")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showingAddSubcategory) {
            AddSubcategoryView(category: category)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSubcategoryManager) {
            SubcategoryManagementView(category: category)
        }
        .sheet(item: $newItem) { item in
            BudgetItemDetailView(item: item, budgetManager: budgetManager, isNewItem: true)
        }
        .sheet(item: $selectedItem) { item in
            BudgetItemDetailView(item: item, budgetManager: budgetManager)
        }
    }
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.backgroundSecondary)
                        .frame(width: 46, height: 46)
                    
                    Image(systemName: category.icon ?? "tag")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.accent)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.displayName)
                        .font(DesignSystem.Typography.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    
                    Text("Manage subcategories and add items")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                
                Spacer()
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
    }
    
    private func createNewItem(in subcategory: BudgetSubcategory) {
        let name = subcategory.name ?? "Item"
        newItem = budgetManager.createBudgetItem(name: name, amount: 0.0, subcategory: subcategory, with: viewContext)
        viewContext.saveQuietly(module: "Budget")
    }

    private func ensureDefaultSubcategoriesExist() {
        let categoryName = category.name ?? ""
        let defaults = BudgetDefaultSubcategories.subcategories(for: categoryName)
        guard !defaults.isEmpty else { return }
        
        let existingNames = Set(subcategories.compactMap { $0.name })
        var didChange = false
        
        for name in defaults where !existingNames.contains(name) {
            _ = budgetManager.createSubcategory(name: name, category: category, budgetAmount: 0.0, with: viewContext)
            didChange = true
        }
        
        if didChange {
            viewContext.saveQuietly(module: "Budget")
            PersistenceController.shared.save()
        }
    }
}

// MARK: - Subcategory card (Detail UI)
struct BudgetSubcategoryCardView: View {
    let subcategory: BudgetSubcategory
    let period: Date
    let budgetManager: BudgetManager
    let onAddItem: () -> Void
    let onOpenItem: (BudgetItem) -> Void
    
    @State private var showingItems = false
    
    private var spent: Double {
        budgetManager.calculateTotalSpent(for: subcategory, in: period)
    }
    
    private var progress: Double {
        guard subcategory.budgetAmount > 0 else { return 0.0 }
        return min(max(spent / subcategory.budgetAmount, 0.0), 1.0)
    }
    
    private var statusColor: Color {
        if subcategory.budgetAmount == 0 { return DesignSystem.Colors.textTertiary }
        if spent <= subcategory.budgetAmount { return DesignSystem.Colors.success }
        if spent <= subcategory.budgetAmount * 1.1 { return DesignSystem.Colors.warning }
        return DesignSystem.Colors.error
    }
    
    private var itemsSorted: [BudgetItem] {
        let items = (subcategory.items as? Set<BudgetItem>) ?? []
        return items.sorted(by: { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subcategory.displayName)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    
                    Text("\(NumberFormatter.currency.string(from: NSNumber(value: spent)) ?? "$0.00") spent")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    Text(subcategory.formattedBudgetAmount)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    
                    Button {
                        onAddItem()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(DesignSystem.Colors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            ProgressView(value: progress)
                .tint(statusColor)
                .scaleEffect(x: 1, y: 1.2, anchor: .center)
            
            if !itemsSorted.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingItems.toggle()
                    }
                } label: {
                    HStack {
                        Text("\(itemsSorted.count) item\(itemsSorted.count == 1 ? "" : "s")")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Spacer()
                        Image(systemName: showingItems ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                
                if showingItems {
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach(itemsSorted.prefix(5), id: \.objectID) { item in
                            BudgetItemRowView(item: item, onTap: onOpenItem)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Monthly Income Input View
struct MonthlyIncomeInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var income: Double
    let onSave: (Double) -> Void
    
    @State private var incomeText: String = ""
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @FocusState private var isFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: DesignSystem.Spacing.xl) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Monthly Income")
                        .font(DesignSystem.Typography.title1)
                        .fontWeight(.bold)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Text("Enter your total monthly income")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    HStack(spacing: 4) {
                        Text("$")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        TextField("0.00", text: $incomeText)
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.leading)
                            .textFieldStyle(.plain)
                            .focused($isFieldFocused)
                            .onChange(of: incomeText) { _, newValue in
                                if !newValue.isEmpty && newValue != "0" {
                                    let filtered = newValue.filter { "0123456789.".contains($0) }
                                    if filtered != newValue {
                                        incomeText = filtered
                                    }
                                }
                            }
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .fill(DesignSystem.Colors.backgroundSecondary)
                    )
                }
                
                Spacer()
            }
            .padding(DesignSystem.Spacing.xl)
            .background(DesignSystem.Colors.background)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveIncome()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.accent)
                }
            }
            .onAppear {
                incomeText = income > 0 ? String(format: "%.2f", income) : ""
                isFieldFocused = true
            }
            .alert("Invalid Input", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .keyboardDismissToolbar()
        }
    }
    
    private func saveIncome() {
        let cleanedText = incomeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(cleanedText), value >= 0 {
            onSave(value)
            dismiss()
        } else if cleanedText.isEmpty {
            onSave(0.0)
            dismiss()
        } else {
            errorMessage = "Please enter a valid amount (numbers and decimal point only)"
            showingErrorAlert = true
        }
    }
}

// MARK: - Category Card View
struct CategoryCardView: View {
    let category: BudgetCategory
    let budgetManager: BudgetManager
    let onItemTap: (BudgetItem) -> Void
    let onCreateItem: (String) -> Void
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingSubcategories = false
    @State private var subcategoryBudgets: [String: Double] = [:]
    @State private var subcategoryTextInputs: [String: String] = [:]
    @State private var showingAddSubcategoryField = false
    @State private var newSubcategoryName: String = ""
    @State private var editingSubcategory: BudgetSubcategory?
    @State private var showingEditSubcategory = false
    @State private var showingDeleteConfirmation = false
    @State private var subcategoryToDelete: BudgetSubcategory?
    @FocusState private var focusedSubcategory: String?
    @FocusState private var isAddingSubcategoryFocused: Bool
    
    private var totalBudget: Double {
        guard let subcategories = category.subcategories as? Set<BudgetSubcategory> else { return 0.0 }
        return subcategories.reduce(0.0) { result, subcategory in
            result + subcategory.budgetAmount
        }
    }
    
    private var totalSpent: Double {
        guard let subcategories = category.subcategories else { return 0.0 }
        let currentPeriod = Date()
        
        return subcategories.reduce(0.0) { total, subcategory in
            if let sub = subcategory as? BudgetSubcategory {
                return total + budgetManager.calculateTotalSpent(for: sub, in: currentPeriod)
            }
            return total
        }
    }
    
    
    private var balanceStatus: BalanceStatus {
        if totalSpent <= totalBudget {
            return .underBudget
        } else if totalSpent <= totalBudget * 1.1 {
            return .closeToLimit
        } else {
            return .overBudget
        }
    }
    
    private var defaultSubcategories: [String] {
        BudgetDefaultSubcategories.subcategories(for: category.name ?? "")
    }
    
    private var subcategoryEntities: [BudgetSubcategory] {
        guard let existing = category.subcategories as? Set<BudgetSubcategory> else { return [] }
        return existing.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return (lhs.name ?? "") < (rhs.name ?? "")
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }
    
    private var subcategoryNames: [String] {
        var names = defaultSubcategories
        for subcategory in subcategoryEntities {
            guard let name = subcategory.name, !name.isEmpty else { continue }
            if !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            categoryHeader
            
            subcategoriesSection
            
            balanceSummary
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
        .onAppear {
            loadSubcategoryBudgets()
        }
        .onChange(of: category.subcategories?.count ?? 0) { _, _ in
            loadSubcategoryBudgets()
        }
        .sheet(isPresented: $showingEditSubcategory) {
            if let subcategory = editingSubcategory {
                EditSubcategoryView(subcategory: subcategory)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .alert("Delete Subcategory", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                subcategoryToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let subcategory = subcategoryToDelete {
                    deleteSubcategory(subcategory)
                }
            }
        } message: {
            if let subcategory = subcategoryToDelete {
                let itemCount = subcategory.items?.count ?? 0
                if itemCount > 0 {
                    Text("This will delete '\(subcategory.name ?? "Untitled")' and its \(itemCount) item\(itemCount == 1 ? "" : "s"). This action cannot be undone.")
                } else {
                    Text("Are you sure you want to delete '\(subcategory.name ?? "Untitled")'?")
                }
            }
        }
    }
    
    private var categoryHeader: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.backgroundSecondary)
                    .frame(width: 36, height: 36)
                
                Image(systemName: category.icon ?? "tag")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.accent)
            }
            
            Text(category.name ?? "Untitled")
                .font(DesignSystem.Typography.headline)
                .fontWeight(.semibold)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Spacer()
            
            Text("\(subcategoryEntities.count)")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(DesignSystem.Colors.backgroundSecondary)
                .cornerRadius(DesignSystem.CornerRadius.xs)
        }
    }
    
    private var subcategoriesSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingSubcategories.toggle()
                    lightHaptic()
                }
            }) {
                HStack {
                    Text("Subcategories")
                        .font(DesignSystem.Typography.callout)
                        .fontWeight(.medium)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    Spacer()
                    
                    Image(systemName: showingSubcategories ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .padding(.vertical, DesignSystem.Spacing.xs)
            }
            .buttonStyle(.plain)
            
            if showingSubcategories {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    if subcategoryNames.isEmpty {
                        HStack {
                            Image(systemName: "tray")
                                .font(.system(size: 14))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                            Text("No subcategories yet")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, DesignSystem.Spacing.md)
                    }
                    
                    ForEach(subcategoryNames, id: \.self) { subcategoryName in
                        SubcategoryRowView(
                            name: subcategoryName,
                            budgetAmount: Binding(
                                get: { subcategoryBudgets[subcategoryName] ?? 0.0 },
                                set: { newValue in
                                    subcategoryBudgets[subcategoryName] = newValue
                                    saveSubcategoryBudget(subcategoryName, amount: newValue)
                                }
                            ),
                            textInput: Binding(
                                get: { subcategoryTextInputs[subcategoryName] ?? formatAmount(subcategoryBudgets[subcategoryName] ?? 0.0) },
                                set: { subcategoryTextInputs[subcategoryName] = $0 }
                            ),
                            isFocused: focusedSubcategory == subcategoryName,
                            onTap: { onCreateItem(subcategoryName) },
                            onFocus: {
                                subcategoryTextInputs[subcategoryName] = ""
                                focusedSubcategory = subcategoryName
                            },
                            onEdit: {
                                if let entity = findSubcategoryEntity(named: subcategoryName) {
                                    editingSubcategory = entity
                                    showingEditSubcategory = true
                                }
                            },
                            onDelete: {
                                if let entity = findSubcategoryEntity(named: subcategoryName) {
                                    subcategoryToDelete = entity
                                    showingDeleteConfirmation = true
                                }
                            }
                        )
                    }
                    
                    if showingAddSubcategoryField {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            TextField("New subcategory name", text: $newSubcategoryName)
                                #if os(iOS)
                                .textInputAutocapitalization(.words)
                                #endif
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .padding(DesignSystem.Spacing.md)
                                .background(DesignSystem.Colors.backgroundSecondary)
                                .cornerRadius(DesignSystem.CornerRadius.sm)
                                .focused($isAddingSubcategoryFocused)
                                .onAppear {
                                    isAddingSubcategoryFocused = true
                                }
                                .onSubmit {
                                    addNewSubcategory()
                                }
                            
                            Button {
                                addNewSubcategory()
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(newSubcategoryName.isEmpty ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.success)
                            }
                            .disabled(newSubcategoryName.isEmpty)
                            
                            Button {
                                newSubcategoryName = ""
                                showingAddSubcategoryField = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                            }
                        }
                        .padding(.top, DesignSystem.Spacing.sm)
                    } else {
                        Button {
                            showingAddSubcategoryField = true
                            lightHaptic()
                        } label: {
                            HStack(spacing: DesignSystem.Spacing.sm) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16))
                                Text("Add Subcategory")
                                    .font(DesignSystem.Typography.callout)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(DesignSystem.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignSystem.Spacing.md)
                            .background(DesignSystem.Colors.backgroundSecondary)
                            .cornerRadius(DesignSystem.CornerRadius.sm)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private func findSubcategoryEntity(named name: String) -> BudgetSubcategory? {
        return subcategoryEntities.first { $0.name == name }
    }
    
    private func deleteSubcategory(_ subcategory: BudgetSubcategory) {
        let name = subcategory.name ?? ""
        subcategoryBudgets.removeValue(forKey: name)
        subcategoryTextInputs.removeValue(forKey: name)
        
        viewContext.delete(subcategory)

        _ = viewContext.inkSlateSave(module: "Budget")
        
        subcategoryToDelete = nil
    }
    
    private func loadSubcategoryBudgets() {
        subcategoryBudgets.removeAll()
        for name in subcategoryNames {
            guard let subcategory = findOrCreateSubcategory(named: name) else { continue }
            subcategoryBudgets[name] = subcategory.budgetAmount
        }
        
        if viewContext.hasChanges {
            _ = viewContext.inkSlateSave(module: "Budget")
        }
    }
    
    private func formatAmount(_ amount: Double) -> String {
        if amount == 0.0 {
            return ""
        }
        return String(format: "%.2f", amount)
    }
    
    private func saveSubcategoryBudget(_ subcategory: String, amount: Double) {
        guard let subcategoryEntity = findOrCreateSubcategory(named: subcategory) else { return }
        subcategoryEntity.budgetAmount = amount
        subcategoryEntity.modifiedDate = Date()
        
        viewContext.processPendingChanges()

        _ = viewContext.inkSlateSave(module: "Budget")
    }
    
    private func addNewSubcategory() {
        let trimmedName = newSubcategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard !subcategoryNames.contains(trimmedName) else {
            newSubcategoryName = ""
            showingAddSubcategoryField = false
            return
        }
        
        if let subcategory = findOrCreateSubcategory(named: trimmedName) {
            subcategoryBudgets[trimmedName] = subcategory.budgetAmount
            subcategoryTextInputs[trimmedName] = ""
            subcategory.sortOrder = Int16(subcategoryNames.count)
        }

        if viewContext.inkSlateSave(module: "Budget") {
            lightHaptic()
        }
        
        newSubcategoryName = ""
        showingAddSubcategoryField = false
    }
    
    private func findOrCreateSubcategory(named name: String) -> BudgetSubcategory? {
        if let existing = category.subcategories?.first(where: {
            guard let sub = $0 as? BudgetSubcategory else { return false }
            return sub.name == name
        }) as? BudgetSubcategory {
            return existing
        }
        
        let subcategory = BudgetSubcategory(context: viewContext)
        subcategory.id = UUID()
        subcategory.name = name
        subcategory.category = category
        subcategory.budgetAmount = 0.0
        subcategory.createdDate = Date()
        subcategory.modifiedDate = Date()
        subcategory.sortOrder = Int16(subcategoryNames.count)
        return subcategory
    }
    
    private var balanceSummary: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Budget")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text(NumberFormatter.currency.string(from: NSNumber(value: totalBudget)) ?? "$0.00")
                        .font(DesignSystem.Typography.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: DesignSystem.Spacing.xs) {
                    Text("Spent")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text(NumberFormatter.currency.string(from: NSNumber(value: totalSpent)) ?? "$0.00")
                        .font(DesignSystem.Typography.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
            }
            
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: balanceStatus.icon)
                    .font(.system(size: 12))
                    .foregroundColor(balanceStatus.color)
                
                Text(balanceStatusText)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.medium)
                    .foregroundColor(balanceStatus.color)
                
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(balanceStatus.color.opacity(0.1))
            .cornerRadius(DesignSystem.CornerRadius.sm)
        }
    }
    
    private var balanceStatusText: String {
        switch balanceStatus {
        case .underBudget:
            return "Under budget"
        case .closeToLimit:
            return "Approaching limit"
        case .overBudget:
            return "Over budget"
        }
    }
}

// MARK: - Subcategory Row View
struct SubcategoryRowView: View {
    let name: String
    @Binding var budgetAmount: Double
    @Binding var textInput: String
    let isFocused: Bool
    let onTap: () -> Void
    let onFocus: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Button(action: onTap) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Circle()
                        .fill(DesignSystem.Colors.accent.opacity(0.3))
                        .frame(width: 8, height: 8)
                    
                    Text(name)
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            HStack(spacing: 2) {
                Text("$")
                    .font(DesignSystem.Typography.callout)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                TextField("0.00", text: $textInput)
                    .font(DesignSystem.Typography.callout)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                    .onTapGesture {
                        onFocus()
                    }
                    .onChange(of: textInput) { _, newValue in
                        if let value = Double(newValue) {
                            budgetAmount = value
                        } else if newValue.isEmpty {
                            budgetAmount = 0.0
                        }
                    }
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(DesignSystem.Colors.backgroundSecondary)
            .cornerRadius(DesignSystem.CornerRadius.xs)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.backgroundSecondary.opacity(0.5))
        .cornerRadius(DesignSystem.CornerRadius.sm)
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit Name", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Edit Subcategory View
struct EditSubcategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let subcategory: BudgetSubcategory
    @State private var name: String
    @State private var showingError = false
    @State private var errorMessage = ""
    
    init(subcategory: BudgetSubcategory) {
        self.subcategory = subcategory
        self._name = State(initialValue: subcategory.name ?? "")
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: DesignSystem.Spacing.xl) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Subcategory Name")
                        .font(DesignSystem.Typography.callout)
                        .fontWeight(.medium)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    TextField("Enter name", text: $name)
                        .font(DesignSystem.Typography.body)
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.backgroundSecondary)
                        .cornerRadius(DesignSystem.CornerRadius.sm)
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
                        .background(name.isEmpty ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.accent)
                        .cornerRadius(DesignSystem.CornerRadius.md)
                }
                .disabled(name.isEmpty)
            }
            .padding(DesignSystem.Spacing.lg)
            .navigationTitle("Edit Subcategory")
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
    
    private func saveChanges() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        if let category = subcategory.category,
           let siblings = category.subcategories as? Set<BudgetSubcategory> {
            let duplicateExists = siblings.contains { sibling in
                sibling.objectID != subcategory.objectID && sibling.name == trimmedName
            }
            if duplicateExists {
                errorMessage = "A subcategory with this name already exists."
                showingError = true
                return
            }
        }
        
        subcategory.name = trimmedName
        subcategory.modifiedDate = Date()
        
        if viewContext.inkSlateSave(module: "Budget") {
            dismiss()
        } else {
            errorMessage = "Failed to save changes."
            showingError = true
        }
    }
}

// MARK: - Budget Item Row View
struct BudgetItemRowView: View {
    let item: BudgetItem
    let onTap: (BudgetItem) -> Void
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name ?? "Untitled")
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                
                                    if let notes = item.notes, !notes.isEmpty {
                        Text(notes)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .lineLimit(1)
                    }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(NumberFormatter.currency.string(from: NSNumber(value: item.amount)) ?? "$0.00")
                        .font(DesignSystem.Typography.body)
                        .fontWeight(.medium)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                
                if let date = item.date {
                    Text(DateFormatter.shortDate.string(from: date))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.backgroundSecondary)
        .cornerRadius(DesignSystem.CornerRadius.sm)
        .onTapGesture {
            onTap(item)
        }
    }
}

// MARK: - Budget Item Detail View
struct BudgetItemDetailView: View {
    let item: BudgetItem
    let budgetManager: BudgetManager
    /// True when the sheet is presenting a freshly-inserted item ("+")
    var isNewItem: Bool = false
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var name: String = ""
    @State private var amount: Double = 0.0
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var didCommit = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Details")
                            .font(DesignSystem.Typography.headline)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        VStack(spacing: DesignSystem.Spacing.md) {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                                Text("Item Name")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                
                                TextField("Enter item name", text: $name)
                                    .font(DesignSystem.Typography.body)
                                    .padding(DesignSystem.Spacing.md)
                                    .background(DesignSystem.Colors.backgroundSecondary)
                                    .cornerRadius(DesignSystem.CornerRadius.sm)
                                    .disabled(item.isIncome)
                            }
                            
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                                Text("Amount")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                
                                TextField("$0.00", value: $amount, format: .currency(code: "USD"))
                                    .font(DesignSystem.Typography.body)
                                    #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                                    .padding(DesignSystem.Spacing.md)
                                    .background(DesignSystem.Colors.backgroundSecondary)
                                    .cornerRadius(DesignSystem.CornerRadius.sm)
                            }
                            
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                                Text("Date")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                
                                DatePicker("", selection: $date, displayedComponents: .date)
                                    .labelsHidden()
                                    .padding(DesignSystem.Spacing.sm)
                                    .background(DesignSystem.Colors.backgroundSecondary)
                                    .cornerRadius(DesignSystem.CornerRadius.sm)
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Notes")
                            .font(DesignSystem.Typography.headline)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        TextField("Add notes (optional)", text: $notes, axis: .vertical)
                            .font(DesignSystem.Typography.body)
                            .lineLimit(3...6)
                            .padding(DesignSystem.Spacing.md)
                            .background(DesignSystem.Colors.backgroundSecondary)
                            .cornerRadius(DesignSystem.CornerRadius.sm)
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                    
                    Button {
                        didCommit = true
                        saveItem()
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.textInverse)
                            .frame(maxWidth: .infinity)
                            .padding(DesignSystem.Spacing.lg)
                            .background(DesignSystem.Colors.accent)
                            .cornerRadius(DesignSystem.CornerRadius.md)
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle(item.isIncome ? "Monthly Income" : "Budget Item")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .onAppear {
            loadItem()
        }
        .onDisappear {
            guard isNewItem, !didCommit else { return }
            guard !item.isDeleted, item.managedObjectContext != nil else { return }
            budgetManager.deleteBudgetItem(item, with: viewContext)
        }
    }
    
    private func loadItem() {
        name = item.name ?? ""
        amount = item.amount
        date = item.date ?? Date()
        notes = item.notes ?? ""
    }
    
    private func saveItem() {
        if item.isIncome {
            item.name = "Monthly Income"
        } else {
            item.name = name.isEmpty ? "Untitled Item" : name
        }
        item.amount = amount
        item.date = date
        item.notes = notes
        item.modifiedDate = Date()
        
        budgetManager.saveBudgetItem(item, with: viewContext)
    }
}

// MARK: - Create Category View
struct CreateCategoryView: View {
    let budgetManager: BudgetManager
    let viewContext: NSManagedObjectContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var budget: Double = 0.0
    @State private var selectedIcon = "dollarsign.circle"
    @State private var selectedColor = "#8B4513"
    @State private var showingDuplicateAlert = false
    
    let icons = ["dollarsign.circle", "house.fill", "car.fill", "cart.fill", "fork.knife", "banknote.fill", "graduationcap.fill", "cross.fill", "gift.fill", "ellipsis.circle.fill"]
    let colors = ["#8B4513", "#2196F3", "#FF9800", "#4CAF50", "#E91E63", "#9C27B0", "#3F51B5", "#F44336", "#FF5722", "#607D8B"]
    
    private var isDuplicateName: Bool {
        let request: NSFetchRequest<BudgetCategory> = BudgetCategory.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@", name)
        let existingCategories = (try? viewContext.fetch(request)) ?? []
        return !existingCategories.isEmpty
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Category Details")
                            .font(DesignSystem.Typography.headline)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        VStack(spacing: DesignSystem.Spacing.md) {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                                Text("Name")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                
                                TextField("Category name", text: $name)
                                    .font(DesignSystem.Typography.body)
                                    .padding(DesignSystem.Spacing.md)
                                    .background(DesignSystem.Colors.backgroundSecondary)
                                    .cornerRadius(DesignSystem.CornerRadius.sm)
                            }
                            
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                                Text("Monthly Budget (Optional)")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                
                                TextField("$0.00", value: $budget, format: .currency(code: "USD"))
                                    .font(DesignSystem.Typography.body)
                                    #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                                    .padding(DesignSystem.Spacing.md)
                                    .background(DesignSystem.Colors.backgroundSecondary)
                                    .cornerRadius(DesignSystem.CornerRadius.sm)
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Icon")
                            .font(DesignSystem.Typography.headline)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: DesignSystem.Spacing.md) {
                            ForEach(icons, id: \.self) { icon in
                                Button {
                                    selectedIcon = icon
                                    lightHaptic()
                                } label: {
                                    Image(systemName: icon)
                                        .font(.system(size: 22))
                                        .foregroundColor(selectedIcon == icon ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textPrimary)
                                        .frame(width: 48, height: 48)
                                        .background(selectedIcon == icon ? DesignSystem.Colors.accent : DesignSystem.Colors.backgroundSecondary)
                                        .cornerRadius(DesignSystem.CornerRadius.sm)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Color")
                            .font(DesignSystem.Typography.headline)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: DesignSystem.Spacing.md) {
                            ForEach(colors, id: \.self) { color in
                                Button {
                                    selectedColor = color
                                    lightHaptic()
                                } label: {
                                    Circle()
                                        .fill(Color(hex: color) ?? .gray)
                                        .frame(width: 48, height: 48)
                                        .overlay(
                                            Circle()
                                                .stroke(selectedColor == color ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.border, lineWidth: selectedColor == color ? 3 : 1)
                                        )
                                        .scaleEffect(selectedColor == color ? 1.1 : 1.0)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                    
                    Button {
                        if isDuplicateName {
                            showingDuplicateAlert = true
                        } else {
                            let _ = budgetManager.createCategory(
                                name: name,
                                icon: selectedIcon,
                                color: selectedColor,
                                initialBudget: budget,
                                with: viewContext
                            )
                            lightHaptic()
                            dismiss()
                        }
                    } label: {
                        Text("Create Category")
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.textInverse)
                            .frame(maxWidth: .infinity)
                            .padding(DesignSystem.Spacing.lg)
                            .background(name.isEmpty ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.accent)
                            .cornerRadius(DesignSystem.CornerRadius.md)
                    }
                    .disabled(name.isEmpty)
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("New Category")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .alert("Duplicate Category", isPresented: $showingDuplicateAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("A category with this name already exists. Please choose a different name.")
            }
        }
    }
}

// MARK: - Category Management View
struct CategoryManagementView: View {
    let budgetManager: BudgetManager
    let viewContext: NSManagedObjectContext
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BudgetCategory.sortOrder, ascending: true)]
    ) private var categories: FetchedResults<BudgetCategory>
    
    @State private var categoryToDelete: BudgetCategory?
    @State private var showingDeleteConfirmation = false
    @State private var editCategorySheet: BudgetCategory?
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.md) {
                    ForEach(categories, id: \.objectID) { category in
                        CategoryManagementRow(
                            category: category,
                            onEdit: {
                                editCategorySheet = category
                            },
                            onDelete: {
                                deleteCategory(category)
                            }
                        )
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Manage Categories")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(DesignSystem.Colors.accent)
                }
            }
            .onAppear {
                budgetManager.repairOrphanBudgetSubcategories(with: viewContext)
            }
            .alert("Delete Category", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    categoryToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    confirmDeleteCategory()
                }
            } message: {
                if let category = categoryToDelete {
                    let subcategoryCount = category.subcategories?.count ?? 0
                    let itemCount = (category.subcategories as? Set<BudgetSubcategory>)?.reduce(0) { total, sub in
                        total + (sub.items?.count ?? 0)
                    } ?? 0
                    
                    if subcategoryCount > 0 || itemCount > 0 {
                        Text("This will delete '\(category.name ?? "Untitled")' and all \(subcategoryCount) subcategories with \(itemCount) items. This action cannot be undone.")
                    } else {
                        Text("Are you sure you want to delete '\(category.name ?? "Untitled")'?")
                    }
                }
            }
            .sheet(item: $editCategorySheet) { category in
                EditCategoryView(category: category, budgetManager: budgetManager)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
    
    private func deleteCategory(_ category: BudgetCategory) {
        categoryToDelete = category
        showingDeleteConfirmation = true
    }
    
    private func confirmDeleteCategory() {
        guard let category = categoryToDelete else { return }
        
        viewContext.delete(category)
        _ = viewContext.inkSlateSave(module: "Budget")
        
        categoryToDelete = nil
    }
}

// MARK: - Category Management Row
struct CategoryManagementRow: View {
    let category: BudgetCategory
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    private var subcategoryCount: Int {
        category.subcategories?.count ?? 0
    }
    
    private var totalBudget: Double {
        guard let subcategories = category.subcategories as? Set<BudgetSubcategory> else { return 0.0 }
        return subcategories.reduce(0.0) { $0 + $1.budgetAmount }
    }
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.backgroundSecondary)
                    .frame(width: 40, height: 40)
                
                Image(systemName: category.icon ?? "tag")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.accent)
            }
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(category.name ?? "Untitled")
                    .font(DesignSystem.Typography.headline)
                    .fontWeight(.medium)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                HStack(spacing: DesignSystem.Spacing.md) {
                    Label("\(subcategoryCount)", systemImage: "folder")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    Text(NumberFormatter.currency.string(from: NSNumber(value: totalBudget)) ?? "$0.00")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: DesignSystem.Spacing.sm) {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(DesignSystem.Colors.accent)
                }
                .buttonStyle(.plain)
                
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(DesignSystem.Colors.error)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Edit Category View
struct EditCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let category: BudgetCategory
    let budgetManager: BudgetManager
    
    @State private var name: String
    @State private var selectedIcon: String
    @State private var selectedColor: String
    @State private var showingError = false
    @State private var errorMessage = ""
    
    let icons = ["dollarsign.circle", "house.fill", "car.fill", "cart.fill", "fork.knife", "banknote.fill", "graduationcap.fill", "cross.fill", "gift.fill", "ellipsis.circle.fill"]
    let colors = ["#8B4513", "#2196F3", "#FF9800", "#4CAF50", "#E91E63", "#9C27B0", "#3F51B5", "#F44336", "#FF5722", "#607D8B"]
    
    init(category: BudgetCategory, budgetManager: BudgetManager) {
        self.category = category
        self.budgetManager = budgetManager
        self._name = State(initialValue: category.name ?? "")
        self._selectedIcon = State(initialValue: category.icon ?? "dollarsign.circle")
        self._selectedColor = State(initialValue: category.color ?? "#8B4513")
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Category Name")
                            .font(DesignSystem.Typography.callout)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        TextField("Enter name", text: $name)
                            .font(DesignSystem.Typography.body)
                            .padding(DesignSystem.Spacing.md)
                            .background(DesignSystem.Colors.backgroundSecondary)
                            .cornerRadius(DesignSystem.CornerRadius.sm)
                    }
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Icon")
                            .font(DesignSystem.Typography.callout)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: DesignSystem.Spacing.md) {
                            ForEach(icons, id: \.self) { icon in
                                Button {
                                    selectedIcon = icon
                                    lightHaptic()
                                } label: {
                                    Image(systemName: icon)
                                        .font(.system(size: 22))
                                        .foregroundColor(selectedIcon == icon ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textPrimary)
                                        .frame(width: 44, height: 44)
                                        .background(selectedIcon == icon ? DesignSystem.Colors.accent : DesignSystem.Colors.backgroundSecondary)
                                        .cornerRadius(DesignSystem.CornerRadius.sm)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Color")
                            .font(DesignSystem.Typography.callout)
                            .fontWeight(.medium)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: DesignSystem.Spacing.md) {
                            ForEach(colors, id: \.self) { color in
                                Button {
                                    selectedColor = color
                                    lightHaptic()
                                } label: {
                                    Circle()
                                        .fill(Color(hex: color) ?? .gray)
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Circle()
                                                .stroke(selectedColor == color ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.border, lineWidth: selectedColor == color ? 3 : 1)
                                        )
                                        .scaleEffect(selectedColor == color ? 1.1 : 1.0)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    Spacer(minLength: DesignSystem.Spacing.xl)
                    
                    Button {
                        saveChanges()
                    } label: {
                        Text("Save Changes")
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.textInverse)
                            .frame(maxWidth: .infinity)
                            .padding(DesignSystem.Spacing.lg)
                            .background(name.isEmpty ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.accent)
                            .cornerRadius(DesignSystem.CornerRadius.md)
                    }
                    .disabled(name.isEmpty)
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Edit Category")
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
    
    private func saveChanges() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        category.name = trimmedName
        category.icon = selectedIcon
        category.color = selectedColor
        category.modifiedDate = Date()
        
        if viewContext.inkSlateSave(module: "Budget") {
            dismiss()
        } else {
            errorMessage = "Failed to save changes."
            showingError = true
        }
    }
}

// MARK: - Budget Trash View
struct BudgetTrashView: View {
    let budgetManager: BudgetManager
    let viewContext: NSManagedObjectContext
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BudgetItem.date, ascending: false)]
        , predicate: NSPredicate(value: false)
    ) private var deletedItems: FetchedResults<BudgetItem>
    
    var body: some View {
        NavigationView {
            Group {
                if deletedItems.isEmpty {
                    VStack(spacing: DesignSystem.Spacing.xl) {
                        Image(systemName: "trash")
                            .font(.system(size: 48))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        
                        Text("Trash is unavailable")
                            .font(DesignSystem.Typography.title3)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        Text("Budget items are currently deleted permanently. A safe trash feature will be added after soft-delete support is implemented.")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .padding(DesignSystem.Spacing.xxl)
                } else {
                    ScrollView {
                        LazyVStack(spacing: DesignSystem.Spacing.md) {
                            ForEach(deletedItems, id: \.objectID) { item in
                                HStack(spacing: DesignSystem.Spacing.md) {
                                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                                        Text(item.name ?? "Untitled")
                                            .font(DesignSystem.Typography.headline)
                                            .fontWeight(.medium)
                                            .foregroundColor(DesignSystem.Colors.textPrimary)
                                        
                                        Text("Deleted \(DateFormatter.mediumDateTime.string(from: item.modifiedDate ?? Date()))")
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundColor(DesignSystem.Colors.textSecondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button {
                                        budgetManager.deleteBudgetItem(item, with: viewContext)
                                    } label: {
                                        Image(systemName: "trash.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(DesignSystem.Colors.error)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(DesignSystem.Spacing.lg)
                                .background(DesignSystem.Colors.surface)
                                .cornerRadius(DesignSystem.CornerRadius.md)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                        .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                                )
                            }
                        }
                        .padding(DesignSystem.Spacing.lg)
                    }
                }
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Recently Deleted")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(DesignSystem.Colors.accent)
                }
            }
        }
    }
}
