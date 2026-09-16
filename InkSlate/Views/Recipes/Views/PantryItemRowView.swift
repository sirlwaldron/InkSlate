import SwiftUI
import CoreData


struct PantryItemRowView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var item: PantryItemEntity
    var onEdit: (() -> Void)? = nil
    
    @State private var currentQuantity: Int = 1
    @State private var showingUsedUpPrompt = false
    
    private var quantityDisplay: String {
        let unit = item.wrappedUnit
        if unit.isEmpty {
            return "\(currentQuantity)"
        }
        return "\(currentQuantity) \(unit)"
    }
    
    private var isExpiringSoon: Bool {
        guard let date = item.expirationDate else { return false }
        return date < Date().addingTimeInterval(7 * 24 * 60 * 60)
    }
    
    private var expirationDisplay: String? {
        guard let date = item.expirationDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.wrappedName)
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(currentQuantity == 0 ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.textPrimary)
                
                if let expiration = expirationDisplay {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isExpiringSoon ? Color.orange : DesignSystem.Colors.textTertiary.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text(expiration)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(isExpiringSoon ? .orange : DesignSystem.Colors.textTertiary)
                    }
                }
                
                if currentQuantity == 0 {
                    Text("Out of stock")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.error)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onEdit?()
            }
            
            Spacer()
            
            HStack(spacing: 0) {
                Button {
                    adjustQuantity(-1)
                } label: {
                    Image(systemName: "minus")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.medium)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Text(quantityDisplay)
                    .font(DesignSystem.Typography.headline)
                    .monospacedDigit()
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .frame(minWidth: 48)
                
                Button {
                    adjustQuantity(1)
                } label: {
                    Image(systemName: "plus")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.medium)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(DesignSystem.Colors.textTertiary.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.vertical, DesignSystem.Spacing.md)
        .onAppear {
            currentQuantity = max(0, Int(item.wrappedQuantity) ?? 1)
        }
        .onChange(of: item.wrappedQuantity) { _, newValue in
            currentQuantity = max(0, Int(newValue) ?? currentQuantity)
        }
        .alert("\(item.wrappedName) used up?", isPresented: $showingUsedUpPrompt) {
            Button("Remove from Pantry", role: .destructive) {
                removeItem()
            }
            Button("Keep at 0", role: .cancel) { }
        } message: {
            Text("You're out of this item. Remove it from your pantry, or keep it at 0 as a reminder to restock.")
        }
    }
    
    private func adjustQuantity(_ delta: Int) {
        let newQuantity = max(0, currentQuantity + delta)
        guard newQuantity != currentQuantity else { return }
        currentQuantity = newQuantity
        item.quantity = String(newQuantity)
        item.modifiedDate = Date()

        if viewContext.inkSlateSave(module: "Pantry") {
            lightHaptic()
        }
        
        if newQuantity == 0 {
            showingUsedUpPrompt = true
        }
    }
    
    private func removeItem() {
        viewContext.delete(item)
        if viewContext.inkSlateSave(module: "Pantry") {
            lightHaptic()
        }
    }
}
