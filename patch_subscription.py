import re

with open("InkSlate/Services/SubscriptionService.swift", "r") as f:
    content = f.read()

old_block = """    func restorePurchases() async {
        purchaseErrorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPro {
                purchaseErrorMessage = "No active InkSlate Pro subscription was found for this Apple ID."
            }
        } catch {
            log.error("Restore failed: \\(error.localizedDescription, privacy: .public)")
            purchaseErrorMessage = error.localizedDescription
        }
    }"""

new_block = """    func restorePurchases() async {
        purchaseErrorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlementsWithRetry()
            if !isPro {
                purchaseErrorMessage = "No active InkSlate Pro subscription was found for this Apple ID."
            }
        } catch {
            log.error("Restore failed: \\(error.localizedDescription, privacy: .public)")
            purchaseErrorMessage = error.localizedDescription
        }
    }"""

if old_block in content:
    content = content.replace(old_block, new_block)
    with open("InkSlate/Services/SubscriptionService.swift", "w") as f:
        f.write(content)
    print("Patched SubscriptionService successfully.")
else:
    print("Block not found!")
