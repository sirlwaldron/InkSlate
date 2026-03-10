//
//  ModernTaskTextField.swift
//  InkSlate
//
//  Created by UI Overhaul on 9/29/25.
//

import SwiftUI

// MARK: - Modern Task Text Field

struct ModernTaskTextField: View {
    @Binding var text: String
    let placeholder: String
    @Binding var isFocused: Bool
    let isMultiline: Bool
    
    var body: some View {
        Group {
            if isMultiline {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .padding(.vertical, DesignSystem.Spacing.lg)
                    }
                    
                    TextEditor(text: $text)
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.md)
                        .background(Color.clear)
                        .scrollContentBackground(.hidden)
                }
                .frame(minHeight: 80)
            } else {
                TextField(placeholder, text: $text)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.lg)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .fill(DesignSystem.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                        .stroke(
                            isFocused ? DesignSystem.Colors.accent : DesignSystem.Colors.border,
                            lineWidth: isFocused ? 1.5 : 0.5
                        )
                )
        )
        .onTapGesture {
            isFocused = true
        }
        .onChange(of: text) {
            if text.isEmpty {
                isFocused = false
            }
        }
    }
}
