import SwiftUI
import StoreKit

// MARK: - Full-screen upgrade (shown when tapping a Pro module)

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var subscription: SubscriptionService
    @EnvironmentObject private var themeService: ThemeService

    var highlightFeature: MenuViewType?

    @State private var selectedPlan: PaywallPlan = .yearly

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    header
                    featureGrid
                    planPicker
                    purchaseSection
                    legalFooter
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not Now") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .interactiveDismissDisabled(subscription.isPurchasing)
        .task {
            if subscription.products.isEmpty {
                await subscription.loadProducts()
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                themeService.accentColor.opacity(0.35),
                                themeService.accentColor.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(themeService.accentColor)
            }
            .padding(.top, DesignSystem.Spacing.sm)

            Text("InkSlate Pro")
                .font(DesignSystem.Typography.largeTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            if let highlightFeature, highlightFeature.requiresPro {
                Text("Unlock \(highlightFeature.proFeatureTitle) and every Pro module.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Notes, Budget, and Calendar stay free. Pro unlocks everything else.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Text(selectedPlanTrialHeader)
                .font(DesignSystem.Typography.callout)
                .foregroundStyle(themeService.accentColor)
                .multilineTextAlignment(.center)
        }
    }

    private var featureGrid: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Included with Pro")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignSystem.Spacing.sm) {
                ForEach(MenuViewType.proModules, id: \.self) { module in
                    HStack(spacing: 8) {
                        Image(systemName: module.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(themeService.accentColor)
                            .frame(width: 22)
                        Text(module.proFeatureTitle)
                            .font(DesignSystem.Typography.callout)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(DesignSystem.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var planPicker: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            PaywallPlanCard(
                plan: .yearly,
                product: subscription.yearlyProduct,
                isSelected: selectedPlan == .yearly,
                badge: "Best value"
            ) { selectedPlan = .yearly }

            PaywallPlanCard(
                plan: .monthly,
                product: subscription.monthlyProduct,
                isSelected: selectedPlan == .monthly,
                badge: nil
            ) { selectedPlan = .monthly }

            PaywallPlanCard(
                plan: .lifetime,
                product: subscription.lifetimeProduct,
                isSelected: selectedPlan == .lifetime,
                badge: "Pay once"
            ) { selectedPlan = .lifetime }
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            if selectedPlan.hasFreeTrial {
                billingDisclosure
            }

            Button {
                Task { await purchaseSelectedPlan() }
            } label: {
                Group {
                    if subscription.isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(primaryButtonTitle)
                            .font(DesignSystem.Typography.button)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .background(themeService.accentColor)
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md, style: .continuous))
            .disabled(subscription.isPurchasing || productForSelectedPlan == nil)

            if selectedPlan.hasFreeTrial {
                Text("Cancel anytime in Settings › Apple ID › Subscriptions.")
                    .font(DesignSystem.Typography.footnote)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let message = subscription.purchaseErrorMessage {
                Text(message)
                    .font(DesignSystem.Typography.footnote)
                    .foregroundStyle(DesignSystem.Colors.error)
                    .multilineTextAlignment(.center)
            }

            Button("Restore Purchases") {
                Task { await subscription.restorePurchases() }
            }
            .font(DesignSystem.Typography.callout)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .disabled(subscription.isPurchasing)

            if subscription.isPro {
                Label("You have InkSlate Pro", systemImage: "checkmark.seal.fill")
                    .font(DesignSystem.Typography.callout)
                    .foregroundStyle(DesignSystem.Colors.success)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            dismiss()
                        }
                    }
            }
        }
    }

    private var legalFooter: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Text(subscriptionLegalBlurb)
                .font(DesignSystem.Typography.footnote)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: DesignSystem.Spacing.lg) {
                Button("Terms") { openURL(InkSlateLegal.termsOfUse) }
                Button("Privacy") { openURL(InkSlateLegal.privacyPolicy) }
                if subscription.isPro {
                    Button("Manage") { openURL(InkSlateLegal.manageSubscriptions) }
                }
            }
            .font(DesignSystem.Typography.footnote)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding(.bottom, DesignSystem.Spacing.lg)
    }

    // MARK: - Helpers

    private var productForSelectedPlan: Product? {
        switch selectedPlan {
        case .monthly: return subscription.monthlyProduct
        case .yearly: return subscription.yearlyProduct
        case .lifetime: return subscription.lifetimeProduct
        }
    }

    private var selectedPlanTrialHeader: String {
        switch selectedPlan {
        case .monthly:
            let price = subscription.monthlyProduct?.displayPrice ?? "$1.99"
            return "7 days free, then \(price)/month"
        case .yearly:
            let price = subscription.yearlyProduct?.displayPrice ?? "$14.99"
            return "7 days free, then \(price)/year"
        case .lifetime:
            return "One-time purchase — no subscription"
        }
    }

    private var billingDisclosure: some View {
        Text(billingDisclosureText)
            .font(DesignSystem.Typography.callout)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .multilineTextAlignment(.center)
            .padding(DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 1)
            )
    }

    private var billingDisclosureText: String {
        switch selectedPlan {
        case .monthly:
            let price = subscription.monthlyProduct?.displayPrice ?? "$1.99"
            return """
            Your 7-day free trial starts today. When the trial ends, your Apple ID will be automatically charged \(price) for the first month. After that, \(price)/month renews automatically unless you cancel at least 24 hours before each renewal date.
            """
        case .yearly:
            let price = subscription.yearlyProduct?.displayPrice ?? "$14.99"
            return """
            Your 7-day free trial starts today. When the trial ends, your Apple ID will be automatically charged \(price) for the first year. After that, \(price)/year renews automatically unless you cancel at least 24 hours before each renewal date.
            """
        case .lifetime:
            return ""
        }
    }

    private var primaryButtonTitle: String {
        switch selectedPlan {
        case .monthly, .yearly:
            return "Start 7-Day Free Trial"
        case .lifetime:
            return "Unlock Lifetime Pro"
        }
    }

    private var subscriptionLegalBlurb: String {
        switch selectedPlan {
        case .monthly:
            let price = subscription.monthlyProduct?.displayPrice ?? "$1.99"
            return """
            InkSlate Pro Monthly includes a 7-day free trial. After the trial, \(price)/month is automatically charged to your Apple ID and the subscription renews each month unless canceled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions.
            """
        case .yearly:
            let price = subscription.yearlyProduct?.displayPrice ?? "$14.99"
            return """
            InkSlate Pro Yearly includes a 7-day free trial. After the trial, \(price)/year is automatically charged to your Apple ID and the subscription renews each year unless canceled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions.
            """
        case .lifetime:
            let price = subscription.lifetimeProduct?.displayPrice ?? "$49.99"
            return """
            InkSlate Pro Lifetime: one-time \(price) purchase. Permanent Pro access on devices using the same Apple ID. No subscription. Restore anytime via Restore Purchases.
            """
        }
    }

    private func purchaseSelectedPlan() async {
        guard let product = productForSelectedPlan else {
            subscription.purchaseErrorMessage = "Plans aren’t available yet. Try again in a moment."
            await subscription.loadProducts()
            return
        }
        await subscription.purchase(product)
        if subscription.isPro {
            dismiss()
        }
    }
}

// MARK: - Plan model

private enum PaywallPlan: String, CaseIterable {
    case monthly
    case yearly
    case lifetime

    var hasFreeTrial: Bool {
        switch self {
        case .monthly, .yearly: return true
        case .lifetime: return false
        }
    }

    var title: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .lifetime: return "Lifetime"
        }
    }

    func subtitle(displayPrice: String?) -> String {
        switch self {
        case .monthly:
            let price = displayPrice ?? "$1.99"
            return "7 days free, then \(price)/month"
        case .yearly:
            let price = displayPrice ?? "$14.99"
            return "7 days free, then \(price)/year"
        case .lifetime:
            return "One-time · Keep forever"
        }
    }

    func priceLabel(displayPrice: String?) -> String {
        switch self {
        case .monthly:
            return "\(displayPrice ?? "$1.99")/mo"
        case .yearly:
            return "\(displayPrice ?? "$14.99")/yr"
        case .lifetime:
            return displayPrice ?? "$49.99"
        }
    }

    var fallbackPrice: String {
        switch self {
        case .monthly: return "$1.99/mo"
        case .yearly: return "$14.99/yr"
        case .lifetime: return "$49.99"
        }
    }
}

// MARK: - Plan card

private struct PaywallPlanCard: View {
    let plan: PaywallPlan
    let product: Product?
    let isSelected: Bool
    let badge: String?
    let onSelect: () -> Void

    @EnvironmentObject private var themeService: ThemeService

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(themeService.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    Text(plan.subtitle(displayPrice: product?.displayPrice))
                        .font(DesignSystem.Typography.footnote)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if plan.hasFreeTrial {
                        Text("Free for 7 days")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(themeService.accentColor)
                    }
                    Text(plan.priceLabel(displayPrice: product?.displayPrice))
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? themeService.accentColor : DesignSystem.Colors.textTertiary)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md, style: .continuous)
                    .strokeBorder(
                        isSelected ? themeService.accentColor : DesignSystem.Colors.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inline lock placeholder

// MARK: - Pro badge (menu reorder, radial launcher)

struct ProFeatureBadge: View {
    var compact: Bool = false

    var body: some View {
        Text("PRO")
            .font(.system(size: compact ? 9 : 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 5 : 6)
            .padding(.vertical, compact ? 2 : 3)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.accent,
                                DesignSystem.Colors.accent.opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .accessibilityLabel("Pro feature")
    }
}

struct ProLockedFeatureView: View {
    let feature: MenuViewType
    var title: String?
    var message: String?
    var onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text(title ?? "\(feature.proFeatureTitle) is Pro")
                .font(DesignSystem.Typography.title2)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text(message ?? "Notes, Budget, and Calendar are free. Upgrade to open this module.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("View InkSlate Pro", action: onUpgrade)
                .font(DesignSystem.Typography.button)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(DesignSystem.Colors.accent)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background.ignoresSafeArea())
    }
}
