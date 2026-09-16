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
            // Compact Header
            drawerHeader
                .padding(.top, safeAreaTop + 4)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            Divider()
                .opacity(0.4)

            // Navigation Items (compact, fits without scrolling)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(mainDrawerItems, id: \.self) { item in
                        drawerRow(for: item)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider()
                .opacity(0.4)

            // Footer (Profile, Settings, Pro)
            VStack(spacing: 2) {
                ForEach(footerDrawerItems, id: \.self) { item in
                    drawerRow(for: item)
                }

                if !subscription.isPro {
                    proUpsellBanner
                        .padding(.top, 3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, safeAreaBottom + 8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                DesignSystem.Colors.surface
                themeService.accentColor.opacity(0.025)
            }
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 20,
                topTrailingRadius: 20,
                style: .continuous
            )
        )
        .shadow(color: Color.black.opacity(0.16), radius: 20, x: 6, y: 0)
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

    // MARK: - Compact Header
    private var drawerHeader: some View {
        HStack(spacing: 10) {
            // Profile Avatar / Icon (30x30)
            ZStack {
                if let image = profileService.userImage {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(themeService.accentColor.opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: profileService.userIcon)
                        .font(.system(size: 15))
                        .foregroundStyle(themeService.accentColor)
                }
            }
            .overlay(
                Circle()
                    .stroke(themeService.accentColor.opacity(0.3), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(profileService.userName.isEmpty ? "InkSlate" : profileService.userName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 3) {
                    if subscription.isPro {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(themeService.accentColor)
                        Text("Pro Member")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(themeService.accentColor)
                    } else {
                        Text("Mindful Workspace")
                            .font(.system(size: 10.5))
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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close menu")
        }
    }

    // MARK: - Compact Row
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
            HStack(spacing: 11) {
                // Compact Icon (26x26)
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? themeService.accentColor : themeService.accentColor.opacity(0.12))
                        .frame(width: 26, height: 26)

                    Image(systemName: menu.icon)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.white : themeService.accentColor)
                }

                // Compact Title
                Text(menu.menuTitle)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? themeService.accentColor : DesignSystem.Colors.textPrimary)

                Spacer()

                // Badges
                if isLocked {
                    HStack(spacing: 2.5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 7.5))
                        Text("PRO")
                            .font(.system(size: 8.5, weight: .bold))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(themeService.accentColor.opacity(0.14))
                    .foregroundStyle(themeService.accentColor)
                    .clipShape(Capsule())
                } else if isSelected {
                    Circle()
                        .fill(themeService.accentColor)
                        .frame(width: 4.5, height: 4.5)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? themeService.accentColor.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Slim Pro Upsell
    private var proUpsellBanner: some View {
        Button {
            triggerHaptic()
            onUpgradePro?(.notes)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                isDrawerOpen = false
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(themeService.accentColor)

                Text("Unlock InkSlate Pro")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(themeService.accentColor.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(themeService.accentColor.opacity(0.20), lineWidth: 1)
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
