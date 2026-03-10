//
//  PantryItemRowView.swift
//  InkSlate
//
//  Modern minimalistic pantry item row
//

import SwiftUI
import CoreData

struct PantryItemRowView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var item: PantryItemEntity
    
    @State private var currentQuantity: Int = 1
    
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
        HStack(alignment: .center, spacing: 16) {
            // Left: Name and meta
            VStack(alignment: .leading, spacing: 4) {
                Text(item.wrappedName)
                    .font(.system(size: 16, weight: .medium, design: .default))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                if let expiration = expirationDisplay {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isExpiringSoon ? Color.orange : DesignSystem.Colors.textTertiary.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text(expiration)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(isExpiringSoon ? .orange : DesignSystem.Colors.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            // Right: Quantity stepper
            HStack(spacing: 0) {
                Button {
                    adjustQuantity(-1)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                
                Text(quantityDisplay)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .frame(minWidth: 48)
                
                Button {
                    adjustQuantity(1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(DesignSystem.Colors.textTertiary.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.vertical, 14)
        .onAppear {
            if let qty = Int(item.wrappedQuantity) {
                currentQuantity = max(1, qty)
            }
        }
    }
    
    private func adjustQuantity(_ delta: Int) {
        currentQuantity = max(1, currentQuantity + delta)
        item.quantity = String(currentQuantity)
        item.modifiedDate = Date()
        
        do {
            try viewContext.save()
            lightHaptic()
        } catch {
            print("Failed to update quantity: \(error.localizedDescription)")
        }
    }
}
