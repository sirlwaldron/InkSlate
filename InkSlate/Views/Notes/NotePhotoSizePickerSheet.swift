import SwiftUI

struct NotePhotoSizePickerSheet: View {
    let maxLayoutWidth: CGFloat
    let currentWidth: CGFloat
    let onPick: (CGFloat) -> Void
    let onDone: () -> Void

    private var presets: [(title: String, width: CGFloat)] {
        let m = max(120, maxLayoutWidth)
        return [
            ("Extra Small", min(100, m * 0.30)),
            ("Small", min(160, m * 0.46)),
            ("Medium", min(240, m * 0.66)),
            ("Large", m)
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        Text("Choose how wide the image appears in the note.")
                            .font(DesignSystem.Typography.callout)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(Array(presets.enumerated()), id: \.offset) { _, item in
                                let selected = abs(item.width - currentWidth) < 14
                                Button {
                                    lightHaptic()
                                    onPick(item.width)
                                    onDone()
                                } label: {
                                    HStack(spacing: DesignSystem.Spacing.md) {
                                        Text(item.title)
                                            .font(DesignSystem.Typography.button)
                                            .foregroundColor(selected ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textPrimary)
                                        Spacer(minLength: 0)
                                        if selected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(DesignSystem.Colors.textInverse)
                                        }
                                    }
                                    .padding(.horizontal, DesignSystem.Spacing.lg)
                                    .padding(.vertical, DesignSystem.Spacing.md)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                                            .fill(selected ? DesignSystem.Colors.accent : DesignSystem.Colors.surface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous)
                                            .stroke(DesignSystem.Colors.border, lineWidth: selected ? 0 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.top, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.xxl)
                }
            }
            .navigationTitle("Image size")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignSystem.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        lightHaptic()
                        onDone()
                    }
                    .font(DesignSystem.Typography.button)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                }
            }
        }
    }
}
