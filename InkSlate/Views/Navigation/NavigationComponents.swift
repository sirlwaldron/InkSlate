import SwiftUI
import Foundation

// MARK: - Navigation Types
enum MenuViewType: String, CaseIterable {
    case wantToWatch = "Want to Watch"
    case notes = "Notes"
    case mindMaps = "Mind Maps"
    case journal = "Journal"
    case todo = "To-Do"
    case budget = "Budget"
    case recipes = "Recipes"
    case places = "Places"
    case settings = "Settings"
    case calendar = "Calendar"
    case items = "Home"
    case quotes = "Quotes"
    case profile = "Profile"
    
    var icon: String {
        switch self {
        case .items: return "house.fill"
        case .notes: return "note.text"
        case .mindMaps: return "brain.head.profile"
        case .journal: return "book.closed"
            case .todo: return "checklist"
            case .budget: return "chart.pie.fill"
            case .recipes: return "fork.knife"
            case .places: return "mappin.and.ellipse"
            case .quotes: return "quote.bubble"
            case .calendar: return "calendar"
        case .wantToWatch: return "tv"
        case .settings: return "gear"
        case .profile: return "person.fill"
        }
    }
    
    var menuTitle: String {
        switch self {
        case .wantToWatch: return "Watchlist"
        default: return rawValue
        }
    }
}


// MARK: - Radial Launcher Components
struct RadialLauncherButton: View {
    @Binding var isMenuOpen: Bool
    @Binding var isHovering: Bool
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                isMenuOpen.toggle()
            }
        }) {
            ModernMenuLogo(isMenuOpen: isMenuOpen)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .scaleEffect(isHovering ? 1.1 : 1.0)
        .opacity(isHovering ? 0.7 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0.15) {
            withAnimation(.easeInOut(duration: 0.25)) {
                isMenuOpen = true
            }
        }
    }
}

private struct ModernMenuLogo: View {
    let isMenuOpen: Bool
    @EnvironmentObject private var themeService: ThemeService
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let rotation = Angle.degrees(time.truncatingRemainder(dividingBy: 10.0) / 10.0 * 360.0)
            let outerBreath = (sin(time * 1.15) + 1.0) / 2.0
            let innerBreath = (sin((time * 1.15) + Double.pi) + 1.0) / 2.0
            let accent = themeService.accentColor
            
            ZStack {
                Circle()
                    .fill(accent.opacity(isMenuOpen ? 0.22 : 0.18 + (outerBreath * 0.16)))
                    .frame(width: 34, height: 34)
                    .scaleEffect(isMenuOpen ? 0.92 : 0.88 + (outerBreath * 0.24))
                    .overlay(
                        Circle()
                            .stroke(
                                accent.opacity(isMenuOpen ? 0.38 : 0.30 + (outerBreath * 0.20)),
                                lineWidth: 1
                            )
                    )
                
                Circle()
                    .fill(
                        Color.primary.opacity(0.06 + (innerBreath * 0.05))
                    )
                    .frame(width: 25, height: 25)
                    .scaleEffect(isMenuOpen ? 0.98 : 1.02 - (innerBreath * 0.16))
                    .overlay(
                        Circle()
                            .stroke(accent.opacity(0.28 + (innerBreath * 0.12)), lineWidth: 0.8)
                    )
                
                RoundedRectangle(cornerRadius: isMenuOpen ? 4 : 5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.94),
                                Color.black.opacity(0.78)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: isMenuOpen ? 15 : 13, height: isMenuOpen ? 15 : 13)
                    .rotationEffect(rotation)
                    .overlay(
                        RoundedRectangle(cornerRadius: isMenuOpen ? 4 : 5, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: 4, x: 0, y: 2)
                
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(DesignSystem.Colors.surface.opacity(0.72))
                    .frame(width: 6, height: 6)
                    .rotationEffect(-rotation)
            }
            .padding(5)
            .scaleEffect(isMenuOpen ? 0.96 : 1.0 + (outerBreath * 0.02))
            .animation(.easeInOut(duration: 0.24), value: isMenuOpen)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Backwards-compatible alias
struct MenuLauncherButton: View {
    @Binding var isMenuOpen: Bool
    @Binding var isHovering: Bool

    var body: some View {
        RadialLauncherButton(isMenuOpen: $isMenuOpen, isHovering: $isHovering)
    }
}

@available(*, deprecated, renamed: "MenuLauncherButton")
struct HamburgerMenuButton: View {
    @Binding var isMenuOpen: Bool
    @Binding var isHovering: Bool

    var body: some View {
        MenuLauncherButton(isMenuOpen: $isMenuOpen, isHovering: $isHovering)
    }
}

// MARK: - Menu Item Component
struct MenuItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 20)
                .foregroundColor(isSelected ? .white : DesignSystem.Colors.textPrimary)
                .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isSelected ? .white : DesignSystem.Colors.textPrimary)
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : (isHovering ? Color.accentColor.opacity(0.1) : Color.clear))
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            action()
        }
    }
}

private struct RadialLauncherItemButton: View {
    let viewType: MenuViewType
    let isSelected: Bool
    let isLocked: Bool
    let action: () -> Void
    @State private var isHovering = false
    @EnvironmentObject private var themeService: ThemeService
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Circle()
                    .fill(isSelected ? AnyShapeStyle(themeService.accentColor) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(
                        Circle().strokeBorder(
                            isSelected
                                ? Color.white.opacity(0.38)
                                : themeService.accentColor.opacity(isLocked ? 0.28 : 0.48),
                            lineWidth: isSelected ? 1.1 : 1.35
                        )
                    )
                    .shadow(color: DesignSystem.Shadows.small, radius: 10, x: 0, y: 6)
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: viewType.icon)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.white : DesignSystem.Colors.textPrimary.opacity(isLocked ? 0.72 : 1))
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Circle().fill(themeService.accentColor))
                                .offset(x: 4, y: 4)
                        }
                    }
                
                HStack(spacing: 3) {
                    Text(viewType.menuTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.98))
                    if isLocked {
                        ProFeatureBadge(compact: true)
                    }
                }
                    .shadow(color: Color.black.opacity(0.20), radius: 0, x: 0.6, y: 0.0)
                    .shadow(color: Color.black.opacity(0.20), radius: 0, x: -0.6, y: 0.0)
                    .shadow(color: Color.black.opacity(0.20), radius: 0, x: 0.0, y: 0.6)
                    .shadow(color: Color.black.opacity(0.20), radius: 0, x: 0.0, y: -0.6)
                    .shadow(color: Color.black.opacity(0.10), radius: 1.0, x: 0, y: 0.5)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 56)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.06 : 1.0)
        .opacity(isHovering ? 0.9 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(Text(viewType.menuTitle))
    }
}

struct FloatingRadialLauncher: View {
    @Binding var isMenuOpen: Bool
    @Binding var selectedView: MenuViewType
    var onSelectMenu: (MenuViewType) -> Void
    @EnvironmentObject private var subscription: SubscriptionService
    @State private var visibleMenuItems: [MenuViewType] = []
    @State private var hiddenItems: Set<MenuViewType> = []
    @State private var isHovering = false
    @State private var bloom: Bool = false
    @State private var presented: Bool = false
    
    private let userDefaults = UserDefaults.standard
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let menuOrderKey = "MenuOrder"
    private let hiddenMenuItemsKey = "HiddenMenuItems"
    
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let safeBottom = proxy.safeAreaInsets.bottom
            let items = radialItems()
            let buttonSize: CGFloat = 56
            let margin: CGFloat = 16
            
            let unclamped = CGPoint(
                x: size.width / 2,
                y: size.height - safeBottom - 64
            )
            let buttonCenter = CGPoint(
                x: min(max(unclamped.x, margin + buttonSize / 2), size.width - margin - buttonSize / 2),
                y: min(max(unclamped.y, margin + buttonSize / 2), size.height - margin - buttonSize / 2)
            )
            
            let outerRadius = min(max(size.width, size.height) * 0.21, 198)
            let innerRadius = max(outerRadius * 0.58, 100)
            
            let anglePadDeg: CGFloat = 9
            
            ZStack {
                if presented {
                    Color.black.opacity(0.10)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeWithSuckBack()
                        }
                        .transition(.opacity)
                }
                
                if presented {
                    let layout = flowerLayout(items)
                        
                    ForEach(Array(layout.enumerated()), id: \.element.viewType) { idx, entry in
                        let pOpen = arcPosition(
                            index: entry.index,
                            count: entry.count,
                            center: buttonCenter,
                            radius: entry.ring == .outer ? outerRadius : innerRadius,
                            startDegrees: 0 + anglePadDeg,
                            endDegrees: 180 - anglePadDeg
                        )
                        let p = bloom ? pOpen : buttonCenter
                        
                        RadialLauncherItemButton(
                            viewType: entry.viewType,
                            isSelected: selectedView == entry.viewType,
                            isLocked: entry.viewType.requiresPro && !subscription.isPro
                        ) {
                            onSelectMenu(entry.viewType)
                            closeWithSuckBack()
                        }
                        .position(p)
                        .animation(
                            .spring(response: 0.26, dampingFraction: 0.86)
                                .delay(Double(idx) * 0.010),
                            value: bloom
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    }
                }
                
                RadialLauncherButton(isMenuOpen: $isMenuOpen, isHovering: $isHovering)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(
                        Circle()
                            .fill(DesignSystem.Colors.surface)
                            .shadow(color: DesignSystem.Shadows.small, radius: 12, x: 0, y: 8)
                    )
                    .clipShape(Circle())
                    .position(buttonCenter)
                    .onLongPressGesture(minimumDuration: 0.15) {
                        openWithBloom()
                    }
            }
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
            .onChange(of: isMenuOpen) { _, open in
                if open {
                    openWithBloom()
                } else {
                    closeWithSuckBack(external: true)
                }
            }
        }
    }
    
    private func openWithBloom() {
        if !presented {
            presented = true
        }
        bloom = false
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            bloom = true
        }
        if !isMenuOpen {
            isMenuOpen = true
        }
    }
    
    private func closeWithSuckBack(external: Bool = false) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.92)) {
            bloom = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            presented = false
            if !external {
                isMenuOpen = false
            }
        }
        if external {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                if !isMenuOpen {
                    presented = false
                }
            }
        }
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
            if !orderedItems.isEmpty {
                visibleMenuItems = orderedItems
            } else {
                visibleMenuItems = MenuViewType.allCases
            }
        } else {
            visibleMenuItems = MenuViewType.allCases
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
        
        visibleMenuItems = visibleMenuItems.filter { !hiddenItems.contains($0) }
    }
    
    private func radialItems() -> [MenuViewType] {
        let base = visibleMenuItems.isEmpty ? MenuViewType.allCases : visibleMenuItems
        return base.filter { !hiddenItems.contains($0) }
    }
    
    private func arcPosition(
        index: Int,
        count: Int,
        center: CGPoint,
        radius: CGFloat,
        startDegrees: CGFloat,
        endDegrees: CGFloat
    ) -> CGPoint {
        guard count > 0 else { return center }
        if count == 1 {
            return CGPoint(x: center.x, y: center.y - radius)
        }
        
        let start = startDegrees * CGFloat.pi / 180
        let end = endDegrees * CGFloat.pi / 180
        let step = (end - start) / CGFloat(count - 1)
        let angle = start + (CGFloat(index) * step)
        
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y - sin(angle) * radius
        )
    }
    
    private enum Ring {
        case outer
        case inner
    }
    
    private struct FlowerEntry {
        let viewType: MenuViewType
        let ring: Ring
        let index: Int
        let count: Int
    }
    
    private func flowerLayout(_ items: [MenuViewType]) -> [FlowerEntry] {
        if items.isEmpty { return [] }
        if items.count <= 6 {
            return items.enumerated().map { idx, vt in
                FlowerEntry(viewType: vt, ring: .outer, index: idx, count: items.count)
            }
        }
        
        var outerCount = Int(ceil(Double(items.count) * 0.55))
        outerCount = min(max(outerCount, 1), items.count - 1)
        let innerCount = items.count - outerCount
        
        let outer = items.prefix(outerCount).enumerated().map { idx, vt in
            FlowerEntry(viewType: vt, ring: .outer, index: idx, count: outerCount)
        }
        
        let inner = items.suffix(innerCount).enumerated().map { idx, vt in
            FlowerEntry(viewType: vt, ring: .inner, index: idx, count: max(innerCount, 1))
        }
        
        return Array(outer) + Array(inner)
    }
}
