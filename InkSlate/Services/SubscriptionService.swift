import Foundation
import StoreKit
import os

// MARK: - StoreKit 2 subscription state (auto-refreshes from Apple entitlements)

@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    @Published private(set) var isPro = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var activeProductID: String?
    @Published var purchaseErrorMessage: String?
    @Published var isPurchasing = false

    private let log = Logger(subsystem: "com.lucas.InkSlateNew", category: "Subscription")
    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactionUpdates()
        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    var monthlyProduct: Product? { product(for: InkSlateProducts.monthly) }
    var yearlyProduct: Product? { product(for: InkSlateProducts.yearly) }
    var lifetimeProduct: Product? { product(for: InkSlateProducts.lifetime) }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: InkSlateProducts.loadOrder)
            products = InkSlateProducts.loadOrder.compactMap { id in
                loaded.first { $0.id == id }
            }
            log.info("Loaded \(self.products.count) IAP products")
        } catch {
            log.error("Product load failed: \(error.localizedDescription, privacy: .public)")
            purchaseErrorMessage = "Couldn’t load subscription options. Check your connection and try again."
        }
    }

    func refreshEntitlements() async {
        var pro = false
        var activeID: String?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard InkSlateProducts.allProductIDs.contains(transaction.productID) else { continue }
            if transaction.revocationDate == nil {
                pro = true
                activeID = transaction.productID
            }
        }

        isPro = pro
        activeProductID = activeID
        log.info("Entitlements refreshed — isPro=\(pro, privacy: .public)")
    }

    func purchase(_ product: Product) async {
        purchaseErrorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .userCancelled:
                break
            case .pending:
                purchaseErrorMessage = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            log.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            purchaseErrorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
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
            log.error("Restore failed: \(error.localizedDescription, privacy: .public)")
            purchaseErrorMessage = error.localizedDescription
        }
    }

    func canAccess(_ menu: MenuViewType) -> Bool {
        !menu.requiresPro || isPro
    }

    // MARK: - Private

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handleTransactionUpdate(update)
            }
        }
    }

    private func handleTransactionUpdate(_ update: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(update) else { return }
        await transaction.finish()
        await refreshEntitlements()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
