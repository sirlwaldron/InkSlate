//
//  BudgetViews.swift
//  InkSlate
//
//  Created by Lucas Waldron on 1/2/25.
//

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

// MARK: - Budget Feature Views

struct BudgetMainView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BudgetCategory.sortOrder, ascending: true)]
    ) private var categories: FetchedResults<BudgetCategory>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BudgetItem.date, ascending: false)],
        predicate: NSPredicate(format: "name == %@", "Monthly Income")
    ) private var incomeItems: FetchedResults<BudgetItem>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BudgetSubcategory.sortOrder, ascending: true)]
    ) private var subcategories: FetchedResults<BudgetSubcategory>
    
    @StateObject private var budgetManager = BudgetManager.shared
    @State private var selectedItem: BudgetItem?
    @State private var showingCreateItem = false
    @State private var showingCreateCategory = false
    @State private var showingCategoryManagement = false
    @State private var newItem: BudgetItem?
    @State private var showingIncomeInput = false
    @State private var showingResetAlert = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    // Current period for budget calculations (can be extended for monthly views later)
    private var currentPeriod: Date {
        Date()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom header right below navigation bar
            HStack {
                Text("Budget")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Spacer()
                
                HStack(spacing: DesignSystem.Spacing.md) {
                    Button(action: {
                        showingCreateCategory = true
                    }) {
                        Image(systemName: "folder.badge.plus")
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                    }
                    
                    Button(action: {
                        showingCategoryManagement = true
                    }) {
                        Image(systemName: "folder")
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                    }
                    
                    // Reset budget data button
                    Button(action: {
                        showingResetAlert = true
                    }) {
                        Image(systemName: "trash.circle")
                            .foregroundColor(.red)
                            .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.bottom, DesignSystem.Spacing.md)
            
            // Main content
            if categories.isEmpty {
                emptyStateView
            } else {
                budgetContent
            }
        }
        .onAppear {
            if categories.isEmpty {
                budgetManager.initializeDefaultCategories(with: viewContext)
            }
            budgetManager.cleanupExpiredItems(with: viewContext)
        }
        .sheet(isPresented: $showingCreateItem) {
            if let item = newItem {
                BudgetItemDetailView(item: item, budgetManager: budgetManager)
            }
        }
        .sheet(isPresented: $showingCreateCategory) {
            CreateCategoryView(budgetManager: budgetManager, viewContext: viewContext)
        }
        .sheet(isPresented: $showingCategoryManagement) {
            CategoryManagementView(budgetManager: budgetManager, viewContext: viewContext)
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
    }
    
    private var monthlyIncome: Double {
        incomeItems.first?.amount ?? 0.0
    }
    
    private func saveMonthlyIncome(_ amount: Double) {
        guard amount >= 0 else {
            showError("Income amount cannot be negative")
            return
        }
        
        // Ensure only one income item exists
        if incomeItems.count > 1 {
            // Remove duplicates, keep the first one
            for item in incomeItems.dropFirst() {
                viewContext.delete(item)
            }
        }
        
        if let existingItem = incomeItems.first {
            existingItem.amount = amount
            existingItem.modifiedDate = Date()
        } else {
            let incomeItem = BudgetItem(context: viewContext)
            incomeItem.id = UUID()  // Required for CloudKit sync
            incomeItem.name = "Monthly Income"
            incomeItem.amount = amount
            incomeItem.date = Date()
            incomeItem.createdDate = Date()
            incomeItem.modifiedDate = Date()
            viewContext.insert(incomeItem)
        }
        
        viewContext.processPendingChanges()
        
        do {
            try viewContext.save()
            PersistenceController.shared.save()
        } catch {
            showError("Failed to save monthly income: \(error.localizedDescription)")
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingErrorAlert = true
    }
    
    private var budgetContent: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.md) {
                // Summary cards
                summaryCards
                
                // Category list - @FetchRequest already sorted
                ForEach(categories, id: \.objectID) { category in
                    CategoryCardView(
                        category: category,
                        budgetManager: budgetManager,
                        onItemTap: { item in
                            selectedItem = item
                        },
                        onCreateItem: { subcategory in
                            // Create a subcategory first, then create the budget item
                            let subcategoryEntity = budgetManager.createSubcategory(
                                name: subcategory,
                                category: category,
                                with: viewContext
                            )
                            newItem = budgetManager.createBudgetItem(
                                name: subcategory,
                                amount: 0.0,
                                subcategory: subcategoryEntity,
                                with: viewContext
                            )
                            
                            // Save context immediately after creating the item
                            do {
                                try viewContext.save()
                            } catch {
                                showError("Failed to save new item: \(error.localizedDescription)")
                            }
                            
                            showingCreateItem = true
                        }
                    )
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.xxl)
        }
        .alert("Reset Budget Data", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                budgetManager.clearAllBudgetData(with: viewContext)
                budgetManager.initializeDefaultCategories(with: viewContext)
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
    
    private var summaryCards: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Button(action: {
                showingIncomeInput = true
            }) {
                SummaryCardView(
                    title: "Total Income",
                    amount: monthlyIncome,
                    color: DesignSystem.Colors.success,
                    icon: "arrow.up.circle.fill"
                )
            }
            .buttonStyle(PlainButtonStyle())
                
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
            
            Text("Tap the folder icon with plus in the top right to create your first budget category")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.xl)
        }
        .padding(DesignSystem.Spacing.xxl)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: DesignSystem.Spacing.md) {
                Button(action: {
                    showingCreateCategory = true
                }) {
                    Image(systemName: "folder.badge.plus")
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                }
                
                Button(action: {
                    showingCategoryManagement = true
                }) {
                    Image(systemName: "folder")
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                }
                
            }
        }
    }
    
    // MARK: - Computed Properties
    private var totalBudget: Double {
        subcategories.reduce(0.0) { total, subcategory in
            total + subcategory.budgetAmount
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
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.leading)
                            .textFieldStyle(.plain)
                            .focused($isFieldFocused)
                            .onChange(of: incomeText) { _, newValue in
                                // Format as user types
                                if !newValue.isEmpty && newValue != "0" {
                                    // Allow only valid decimal input
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
            .navigationBarTitleDisplayMode(.inline)
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
            // Invalid input - show error
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
            // Category header
            categoryHeader
            
            // Subcategories section
            subcategoriesSection
            
            // Balance summary
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
                    .presentationDetents([.fraction(0.4)])
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
            // Icon container
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
            
            // Subcategory count badge
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
            // Section header with toggle
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
                    
                    // Add subcategory section
                    if showingAddSubcategoryField {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            TextField("New subcategory name", text: $newSubcategoryName)
                                .textInputAutocapitalization(.words)
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
        
        do {
            try viewContext.save()
            PersistenceController.shared.save()
        } catch {
            print("Failed to delete subcategory: \(error.localizedDescription)")
        }
        
        subcategoryToDelete = nil
    }
    
    private func loadSubcategoryBudgets() {
        subcategoryBudgets.removeAll()
        for name in subcategoryNames {
            guard let subcategory = findOrCreateSubcategory(named: name) else { continue }
            subcategoryBudgets[name] = subcategory.budgetAmount
        }
        
        if viewContext.hasChanges {
            do {
                try viewContext.save()
            } catch {
                // Error will be handled by parent view if needed
            }
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
        
        do {
            try viewContext.save()
            PersistenceController.shared.save()
        } catch {
            print("Failed to save subcategory budget: \(error.localizedDescription)")
        }
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
        
        do {
            try viewContext.save()
            lightHaptic()
        } catch {
            print("Failed to add subcategory: \(error.localizedDescription)")
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
            // Budget vs Spent row
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
            
            // Status indicator
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
            // Subcategory name
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
            
            // Budget input
            HStack(spacing: 2) {
                Text("$")
                    .font(DesignSystem.Typography.callout)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                TextField("0.00", text: $textInput)
                    .font(DesignSystem.Typography.callout)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .keyboardType(.decimalPad)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
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
        
        // Check for duplicate names within the same category
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
        
        do {
            try viewContext.save()
            PersistenceController.shared.save()
            dismiss()
        } catch {
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
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
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var name: String = ""
    @State private var amount: Double = 0.0
    @State private var date: Date = Date()
    @State private var notes: String = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    // Details Section
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
                            }
                            
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                                Text("Amount")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                
                                TextField("$0.00", value: $amount, format: .currency(code: "USD"))
                                    .font(DesignSystem.Typography.body)
                                    .keyboardType(.decimalPad)
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
                    
                    // Notes Section
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
                    
                    // Save Button
                    Button {
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
            .navigationTitle("Budget Item")
            .navigationBarTitleDisplayMode(.inline)
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
    }
    
    private func loadItem() {
        name = item.name ?? ""
        amount = item.amount
        date = item.date ?? Date()
        notes = item.notes ?? ""
    }
    
    private func saveItem() {
        item.name = name.isEmpty ? "Untitled Item" : name
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
                    // Category Details Section
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
                                    .keyboardType(.decimalPad)
                                    .padding(DesignSystem.Spacing.md)
                                    .background(DesignSystem.Colors.backgroundSecondary)
                                    .cornerRadius(DesignSystem.CornerRadius.sm)
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                    
                    // Icon Section
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
                    
                    // Color Section
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
                    
                    // Create Button
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
            .navigationBarTitleDisplayMode(.inline)
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
    @State private var editingCategory: BudgetCategory?
    @State private var showingEditCategory = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.md) {
                    ForEach(categories, id: \.objectID) { category in
                        CategoryManagementRow(
                            category: category,
                            onEdit: {
                                editingCategory = category
                                showingEditCategory = true
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(DesignSystem.Colors.accent)
                }
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
            .sheet(isPresented: $showingEditCategory) {
                if let category = editingCategory {
                    EditCategoryView(category: category, budgetManager: budgetManager)
                        .presentationDetents([.fraction(0.7)])
                        .presentationDragIndicator(.visible)
                }
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
        do {
            try viewContext.save()
            PersistenceController.shared.save()
        } catch {
            print("Failed to delete category: \(error.localizedDescription)")
        }
        
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
            // Icon
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.backgroundSecondary)
                    .frame(width: 40, height: 40)
                
                Image(systemName: category.icon ?? "tag")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.accent)
            }
            
            // Info
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
            
            // Action buttons
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
                    // Name section
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
                    
                    // Icon section
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
                    
                    // Color section
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
                    
                    // Save button
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
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
        
        do {
            try viewContext.save()
            PersistenceController.shared.save()
            dismiss()
        } catch {
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
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
    ) private var deletedItems: FetchedResults<BudgetItem>
    
    var body: some View {
        NavigationView {
            Group {
                if deletedItems.isEmpty {
                    VStack(spacing: DesignSystem.Spacing.xl) {
                        Image(systemName: "trash")
                            .font(.system(size: 48))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        
                        Text("Trash is Empty")
                            .font(DesignSystem.Typography.title3)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        Text("Deleted items will appear here")
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(DesignSystem.Colors.accent)
                }
                if !deletedItems.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Empty Trash") {
                            emptyTrash()
                        }
                        .foregroundColor(DesignSystem.Colors.error)
                    }
                }
            }
        }
    }
    
    private func emptyTrash() {
        for item in deletedItems {
            budgetManager.deleteBudgetItem(item, with: viewContext)
        }
    }
}
