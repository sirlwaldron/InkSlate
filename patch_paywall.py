import re

with open("InkSlate/Views/Settings/PaywallView.swift", "r") as f:
    content = f.read()

old_block = """            if subscription.isPro {
                Label("You have InkSlate Pro", systemImage: "checkmark.seal.fill")
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(DesignSystem.Colors.success)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            dismiss()
                        }
                    }
            }"""

new_block = """            if subscription.isPro {
                Label("You have InkSlate Pro", systemImage: "checkmark.seal.fill")
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(DesignSystem.Colors.success)
            }"""

content = content.replace(old_block, new_block)

with open("InkSlate/Views/Settings/PaywallView.swift", "w") as f:
    f.write(content)

print("Patched PaywallView successfully.")
