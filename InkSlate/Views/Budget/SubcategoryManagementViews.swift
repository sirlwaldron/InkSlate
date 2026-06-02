import SwiftUI
import CoreData

struct AddSubcategoryView: View {
    let category: BudgetCategory

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var name: String = ""
    @State private var selectedIcon: String = "tag"
    @State private var showingError = false
    @State private var errorMessage = ""
    @FocusState private var isNameFocused: Bool

    private let availableIcons: [String] = [
        "tag",
        "cart.fill",
        "fork.knife",
        "house.fill",
        "car.fill",
        "bus.fill",
        "fuelpump.fill",
        "creditcard.fill",
        "banknote.fill",
        "doc.plaintext.fill",
        "bag.fill",
        "gift.fill",
        "gamecontroller.fill",
        "tv.fill",
        "music.note",
        "heart.fill",
        "cross.case.fill",
        "graduationcap.fill",
        "airplane",
        "figure.walk",
        "pawprint.fill",
        "wrench.and.screwdriver.fill",
        "sparkles"
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Subcategory Name")
                            .font(DesignSystem.Typography.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)

                        TextField("Enter name", text: $name)
                            #if os(iOS)
                            .textInputAutocapitalization(.words)
                            #endif
                            .font(DesignSystem.Typography.body)
                            .padding(DesignSystem.Spacing.md)
                            .background(DesignSystem.Colors.backgroundSecondary)
                            .cornerRadius(DesignSystem.CornerRadius.sm)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                            .onSubmit { createSubcategory() }
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        HStack {
                            Text("Icon")
                                .font(DesignSystem.Typography.callout)
                                .fontWeight(.medium)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            Spacer()
                            Image(systemName: selectedIcon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.accent)
                                .frame(width: 34, height: 34)
                                .background(DesignSystem.Colors.backgroundSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                                        .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                                )
                        }

                        let columns = Array(repeating: GridItem(.flexible(), spacing: DesignSystem.Spacing.sm), count: 6)
                        LazyVGrid(columns: columns, spacing: DesignSystem.Spacing.sm) {
                            ForEach(availableIcons, id: \.self) { icon in
                                Button {
                                    selectedIcon = icon
                                    lightHaptic()
                                } label: {
                                    Image(systemName: icon)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(selectedIcon == icon ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textPrimary)
                                        .frame(width: 40, height: 40)
                                        .background(selectedIcon == icon ? DesignSystem.Colors.accent : DesignSystem.Colors.backgroundSecondary)
                                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                                                .stroke(DesignSystem.Colors.border.opacity(selectedIcon == icon ? 0.0 : 1.0), lineWidth: 0.5)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(icon))
                            }
                        }
                    }

                    Button {
                        createSubcategory()
                    } label: {
                        Text("Create Subcategory")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textInverse)
                            .frame(maxWidth: .infinity)
                            .padding(DesignSystem.Spacing.lg)
                            .background(canSave ? DesignSystem.Colors.accent : DesignSystem.Colors.textTertiary)
                            .cornerRadius(DesignSystem.CornerRadius.md)
                    }
                    .disabled(!canSave)
                    .padding(.top, DesignSystem.Spacing.sm)
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("New Subcategory")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            .onAppear {
                if let icon = category.icon, !icon.isEmpty {
                    selectedIcon = icon
                } else {
                    selectedIcon = "tag"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isNameFocused = true
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func createSubcategory() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let siblings = category.subcategories as? Set<BudgetSubcategory> {
            if siblings.contains(where: { $0.name == trimmedName }) {
                errorMessage = "A subcategory with this name already exists."
                showingError = true
                return
            }
        }

        let subcategory = BudgetSubcategory(context: viewContext)
        subcategory.id = UUID()
        subcategory.name = trimmedName
        subcategory.category = category
        subcategory.budgetAmount = 0.0
        subcategory.icon = selectedIcon
        subcategory.createdDate = Date()
        subcategory.modifiedDate = Date()

        let nextSortOrder: Int16 = {
            guard let siblings = category.subcategories as? Set<BudgetSubcategory> else { return 0 }
            return (siblings.map(\.sortOrder).max() ?? -1) + 1
        }()
        subcategory.sortOrder = nextSortOrder

        if viewContext.inkSlateSave(module: "Budget") {
            dismiss()
        } else {
            errorMessage = "Failed to create subcategory."
            showingError = true
        }
    }
}

struct SubcategoryManagementView: View {
    let category: BudgetCategory

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest private var subcategories: FetchedResults<BudgetSubcategory>

    @State private var subcategoryToDelete: BudgetSubcategory?
    @State private var showingDeleteConfirmation = false

    @State private var editSubcategorySheet: BudgetSubcategory?

    init(category: BudgetCategory) {
        self.category = category
        self._subcategories = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \BudgetSubcategory.sortOrder, ascending: true)],
            predicate: NSPredicate(format: "category == %@", category)
        )
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(subcategories, id: \.objectID) { subcategory in
                    SubcategoryManagementRow(
                        subcategory: subcategory,
                        onEdit: {
                            editSubcategorySheet = subcategory
                        },
                        onDelete: {
                            subcategoryToDelete = subcategory
                            showingDeleteConfirmation = true
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(DesignSystem.Colors.background)
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            editSubcategorySheet = subcategory
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(DesignSystem.Colors.accent)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            subcategoryToDelete = subcategory
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DesignSystem.Colors.background)
            .navigationTitle("Manage Subcategories")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.accent)
                }
            }
            .alert("Delete Subcategory", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    subcategoryToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    confirmDelete()
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
            .sheet(item: $editSubcategorySheet) { subcategory in
                EditSubcategoryView(subcategory: subcategory)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func confirmDelete() {
        guard let subcategory = subcategoryToDelete else { return }

        viewContext.delete(subcategory)
        _ = viewContext.inkSlateSave(module: "Budget")

        subcategoryToDelete = nil
    }
}

private struct SubcategoryManagementRow: View {
    let subcategory: BudgetSubcategory
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(subcategory.name ?? "Untitled")
                    .font(DesignSystem.Typography.headline)
                    .fontWeight(.medium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                HStack(spacing: DesignSystem.Spacing.md) {
                    Label("\(subcategory.items?.count ?? 0)", systemImage: "tray.full")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text(subcategory.formattedBudgetAmount)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }

            Spacer()

            HStack(spacing: DesignSystem.Spacing.sm) {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(DesignSystem.Colors.accent)
                }
                .buttonStyle(.plain)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(DesignSystem.Colors.error)
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

