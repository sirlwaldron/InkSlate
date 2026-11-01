import Foundation
import StoreKit
import os

// MARK: - StoreKit 2 subscription state (auto-refreshes from Apple entitlements)

@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    @Published private(set) var isPro: Bool = UserDefaults.standard.bool(forKey: "isPro") {
        didSet { UserDefaults.standard.set(isPro, forKey: "isPro") }
    }
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var activeProductID: String? = UserDefaults.standard.string(forKey: "activeProductID") {
        didSet {
            if let activeProductID {
                UserDefaults.standard.set(activeProductID, forKey: "activeProductID")
            } else {
                UserDefaults.standard.removeObject(forKey: "activeProductID")
            }
        }
    }
    @Published private(set) var isEligibleForIntroOffer = false
    @Published var purchaseErrorMessage: String?
    @Published var isPurchasing = false

    private let log = Logger(subsystem: "com.lucas.InkSlateNew", category: "Subscription")
    /// When Pro was last confirmed by StoreKit. Lets a cached Pro state survive a transient
    /// empty/failed entitlement check (offline, StoreKit hiccup) for a limited time.
    private static let proVerifiedAtKey = "proLastVerifiedAt"
    private static let proGraceInterval: TimeInterval = 7 * 24 * 60 * 60
    private var transactionListener: Task<Void, Never>?

    private init() {
        Task { @MainActor in
            self.transactionListener = self.listenForTransactionUpdates()
            await self.refreshEntitlements()
            await self.loadProducts()
            // Subscription status can only be checked once products are loaded, so re-check now.
            await self.refreshEntitlements()
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
            await updateIntroOfferEligibility()
            log.info("Loaded \(self.products.count) IAP products")
        } catch {
            log.error("Product load failed: \(error.localizedDescription, privacy: .public)")
            purchaseErrorMessage = "Couldn’t load subscription options. Check your connection and try again."
        }
    }

    /// Re-reads entitlements from StoreKit. Returns `true` only when StoreKit confirmed Pro just now
    /// (not when Pro is merely being kept from the cache during the grace period).
    ///
    /// An empty result is treated as transient unless StoreKit explicitly reported a revoked or
    /// expired entitlement (or `allowGrace` is false): the cached Pro state is kept for up to
    /// `proGraceInterval` after the last confirmation instead of locking the user out at once.
    @discardableResult
    func refreshEntitlements(allowGrace: Bool = true) async -> Bool {
        var pro = false
        var activeID: String?
        var sawEndedEntitlement = false

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard InkSlateProducts.allProductIDs.contains(transaction.productID) else { continue }
            if transaction.revocationDate == nil {
                pro = true
                activeID = transaction.productID
            } else {
                sawEndedEntitlement = true
            }
        }

        if !pro {
            for productID in InkSlateProducts.subscriptionIDs {
                guard let product = product(for: productID),
                      let subscription = product.subscription else { continue }
                do {
                    let statuses = try await subscription.status
                    for status in statuses {
                        guard case .verified(let renewalInfo) = status.renewalInfo else { continue }
                        switch status.state {
                        case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                            pro = true
                            activeID = renewalInfo.currentProductID
                        case .expired, .revoked:
                            sawEndedEntitlement = true
                        default:
                            break
                        }
                    }
                } catch {
                    log.error("Subscription status check failed: \(error.localizedDescription, privacy: .public)")
                }
                if pro { break }
            }
        }

        if pro {
            isPro = true
            activeProductID = activeID
            UserDefaults.standard.set(Date(), forKey: Self.proVerifiedAtKey)
            log.info("Entitlements refreshed — isPro=true")
            return true
        }

        if allowGrace, !sawEndedEntitlement, isPro,
           let verifiedAt = UserDefaults.standard.object(forKey: Self.proVerifiedAtKey) as? Date,
           Date().timeIntervalSince(verifiedAt) < Self.proGraceInterval {
            log.info("Entitlements empty — keeping cached Pro during grace period")
            return false
        }

        isPro = false
        activeProductID = nil
        UserDefaults.standard.removeObject(forKey: Self.proVerifiedAtKey)
        log.info("Entitlements refreshed — isPro=false")
        return false
    }

    func hasFreeTrial(for product: Product?) -> Bool {
        guard let product,
              isEligibleForIntroOffer,
              let offer = product.subscription?.introductoryOffer else { return false }
        return offer.paymentMode == .freeTrial
    }

    func freeTrialPeriodDescription(for product: Product?) -> String? {
        guard let product,
              let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return Self.describe(period: offer.period)
    }

    func subscriptionTrialSubtitle(for product: Product, fallbackPrice: String) -> String {
        if hasFreeTrial(for: product),
           let trial = freeTrialPeriodDescription(for: product) {
            return "\(trial) free, then \(fallbackPrice)"
        }
        return fallbackPrice
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
                await refreshEntitlements()
                await transaction.finish()
                await refreshEntitlementsWithRetry()
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
            // An explicit restore asks Apple directly, so its answer is definitive (no grace period).
            let confirmed = await refreshEntitlementsWithRetry(allowGrace: false)
            if !confirmed {
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
        // A revocation (refund) is an explicit signal: don't apply the grace period to it.
        await refreshEntitlements(allowGrace: transaction.revocationDate == nil)
        await transaction.finish()
        await refreshEntitlementsWithRetry(allowGrace: transaction.revocationDate == nil)
    }

    private func updateIntroOfferEligibility() async {
        guard let groupID = yearlyProduct?.subscription?.subscriptionGroupID
            ?? monthlyProduct?.subscription?.subscriptionGroupID else {
            isEligibleForIntroOffer = false
            return
        }
        isEligibleForIntroOffer = await Product.SubscriptionInfo.isEligibleForIntroOffer(for: groupID)
        log.info("Intro offer eligible=\(self.isEligibleForIntroOffer, privacy: .public)")
    }

    /// Retries because a fresh purchase/restore can take a moment to show up in StoreKit.
    /// Returns whether StoreKit confirmed Pro.
    @discardableResult
    private func refreshEntitlementsWithRetry(maxAttempts: Int = 5, allowGrace: Bool = true) async -> Bool {
        for attempt in 0..<maxAttempts {
            if await refreshEntitlements(allowGrace: allowGrace) { return true }
            guard attempt < maxAttempts - 1 else { break }
            let delayMs = 250 * (attempt + 1)
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
        }
        return false
    }

    private static func describe(period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day:
            return period.value == 1 ? "1 day" : "\(period.value) days"
        case .week:
            return period.value == 1 ? "1 week" : "\(period.value) weeks"
        case .month:
            return period.value == 1 ? "1 month" : "\(period.value) months"
        case .year:
            return period.value == 1 ? "1 year" : "\(period.value) years"
        @unknown default:
            return "\(period.value) days"
        }
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
