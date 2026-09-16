import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Side Drawer Menu View
struct SideDrawerMenuView: View {
    @Binding var isDrawerOpen: Bool
    @Binding var selectedView: MenuViewType
    var onSelectMenu: (MenuViewType) -> Void
    var onUpgradePro: ((MenuViewType) -> Void)? = nil

    @EnvironmentObject private var subscription: SubscriptionService
    @EnvironmentObject private var themeService: ThemeService
    @EnvironmentObject private var profileService: ProfileService

    @State private var menuItems: [MenuViewType] = []
    @State private var hiddenItems: Set<MenuViewType> = []

    private let userDefaults = UserDefaults.standard
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let menuOrderKey = "MenuOrder"
    private let hiddenMenuItemsKey = "HiddenMenuItems"

    private var mainDrawerItems: [MenuViewType] {
        MenuViewType.sidebarItems(
            from: menuItems,
            hidden: hiddenItems,
            pinHomeToTop: true,
            pinBottomItems: [.profile, .settings],
            includePinnedBottom: false
        )
    }

    private var footerDrawerItems: [MenuViewType] {
        [.profile, .settings].filter { !hiddenItems.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            drawerHeader
                .padding(.top, safeAreaTop + 14)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            Divider()
                .opacity(0.6)

            // Scrollable Navigation Items
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(mainDrawerItems, id: \.self) { item in
                        drawerRow(for: item)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 16)
            }

            Divider()
                .opacity(0.6)

            // Footer
            VStack(spacing: 6) {
                ForEach(footerDrawerItems, id: \.self) { item in
                    drawerRow(for: item)
                }

                if !subscription.isPro {
                    proUpsellBanner
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, safeAreaBottom + 16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                DesignSystem.Colors.surface
                themeService.accentColor.opacity(0.03)
            }
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 24,
                topTrailingRadius: 24,
                style: .continuous
            )
        )
        .shadow(color: Color.black.opacity(0.18), radius: 24, x: 8, y: 0)
        .onAppear {
            loadMenuConfiguration()
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
                .filter { ($0.object as? NSUbiquitousKeyValueStore) === cloudStore }
                .receive(on: DispatchQueue.main)
        ) { _ in
            loadMenuConfiguration()
        }
    }

    // MARK: - Header
    private var drawerHeader: some View {
        HStack(spacing: 14) {
            // Profile Avatar / Icon
            ZStack {
                if let image = profileService.userImage {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(themeService.accentColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: profileService.userIcon)
                        .font(.system(size: 24))
                        .foregroundStyle(themeService.accentColor)
                }
            }
            .overlay(
                Circle()
                    .stroke(themeService.accentColor.opacity(0.35), lineWidth: 1.5)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(profileService.userName.isEmpty ? "InkSlate" : profileService.userName)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if subscription.isPro {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(themeService.accentColor)
                        Text("Pro Member")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(themeService.accentColor)
                    } else {
                        Text("Mindful Workspace")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
            }

            Spacer()

            // Close button
            Button {
                triggerHaptic()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    isDrawerOpen = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close menu")
        }
    }

    // MARK: - Row
    private func drawerRow(for menu: MenuViewType) -> some View {
        let isSelected = selectedView == menu
        let isLocked = menu.requiresPro && !subscription.isPro

        return Button {
            triggerHaptic()
            if isLocked {
                onUpgradePro?(menu)
            } else {
                onSelectMenu(menu)
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                isDrawerOpen = false
            }
        } label: {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? themeService.accentColor : themeService.accentColor.opacity(0.12))
                        .frame(width: 36, height: 36)

                    Image(systemName: menu.icon)
                        .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.white : themeService.accentColor)
                }

                // Title
                Text(menu.menuTitle)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? themeService.accentColor : DesignSystem.Colors.textPrimary)

                Spacer()

                // Badges
                if isLocked {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                        Text("PRO")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(themeService.accentColor.opacity(0.14))
                    .foregroundStyle(themeService.accentColor)
                    .clipShape(Capsule())
                } else if isSelected {
                    Circle()
                        .fill(themeService.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? themeService.accentColor.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pro Upsell
    private var proUpsellBanner: some View {
        Button {
            triggerHaptic()
            onUpgradePro?(.notes)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                isDrawerOpen = false
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(themeService.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock InkSlate Pro")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("Mind Maps, Journal, Recipes & more")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(themeService.accentColor.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(themeService.accentColor.opacity(0.22), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers
    private var safeAreaTop: CGFloat {
        #if canImport(UIKit)
        return (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first?.safeAreaInsets.top) ?? 44
        #else
        return 20
        #endif
    }

    private var safeAreaBottom: CGFloat {
        #if canImport(UIKit)
        return (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first?.safeAreaInsets.bottom) ?? 20
        #else
        return 20
        #endif
    }

    private func triggerHaptic() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    private func loadMenuConfiguration() {
        let menuOrder: [String]?
        if let cloudOrder = cloudStore.array(forKey: menuOrderKey) as? [String], !cloudOrder.isEmpty {
            menuOrder = cloudOrder
        } else if let localOrder = userDefaults.array(forKey: menuOrderKey) as? [String], !localOrder.isEmpty {
            menuOrder = localOrder
            cloudStore.set(localOrder, forKey: menuOrderKey)
            cloudStore.synchronize()
        } else {
            menuOrder = nil
        }

        if let savedOrder = menuOrder {
            let orderedItems = savedOrder.compactMap { MenuViewType(rawValue: $0) }
            menuItems = orderedItems.isEmpty ? MenuViewType.allCases : orderedItems
        } else {
            menuItems = MenuViewType.allCases
        }

        let hiddenItemsData: [String]?
        if let cloudHidden = cloudStore.array(forKey: hiddenMenuItemsKey) as? [String], !cloudHidden.isEmpty {
            hiddenItemsData = cloudHidden
        } else if let localHidden = userDefaults.array(forKey: hiddenMenuItemsKey) as? [String], !localHidden.isEmpty {
            hiddenItemsData = localHidden
            cloudStore.set(localHidden, forKey: hiddenMenuItemsKey)
            cloudStore.synchronize()
        } else {
            hiddenItemsData = nil
        }

        if let hiddenData = hiddenItemsData {
            hiddenItems = Set(hiddenData.compactMap { MenuViewType(rawValue: $0) })
        } else {
            hiddenItems = []
        }
    }
}
