//
//  NavigationComponents.swift
//  InkSlate
//
//  Created by Lucas Waldron on 9/29/25.
//

import SwiftUI
import Foundation

// MARK: - Navigation Types
enum MenuViewType: String, CaseIterable {
    case items = "Home"
    case notes = "Notes"
    case mindMaps = "Mind Maps"
    case journal = "Journal"
    case todo = "To-Do"
    case budget = "Budget"
    case recipes = "Recipes"
    case places = "Places"
    case quotes = "Quotes"
    case calendar = "Calendar"
    case wantToWatch = "Want to Watch"
    case settings = "Settings"
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
    
    /// Label text for the floating radial menu (can differ from `rawValue` for storage compatibility).
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
            Image(systemName: isMenuOpen ? "xmark" : "circle.grid.2x2.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary)
            .frame(width: 44, height: 44)  // Minimum tap target size
            .contentShape(Rectangle())  // Make entire frame tappable
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

// MARK: - Backwards-compatible alias
// Some screens still reference `HamburgerMenuButton`; keep it as a wrapper so
// navigation stays consistent while we migrate call sites.
struct HamburgerMenuButton: View {
    @Binding var isMenuOpen: Bool
    @Binding var isHovering: Bool
    
    var body: some View {
        RadialLauncherButton(isMenuOpen: $isMenuOpen, isHovering: $isHovering)
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
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Circle()
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(
                        Circle().strokeBorder(
                            Color.primary.opacity(isSelected ? 0.18 : 0.10),
                            lineWidth: 1
                        )
                    )
                    .shadow(color: DesignSystem.Shadows.small, radius: 10, x: 0, y: 6)
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: viewType.icon)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.white : DesignSystem.Colors.textPrimary)
                    }
                
                Text(viewType.menuTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.98))
                    // Soft outline + very light drop shadow (no background box).
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
    @State private var visibleMenuItems: [MenuViewType] = []
    @State private var hiddenItems: Set<MenuViewType> = []
    @State private var isHovering = false
    @State private var bloom: Bool = false
    @State private var presented: Bool = false
    
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let safeBottom = proxy.safeAreaInsets.bottom
            let items = radialItems()
            let buttonSize: CGFloat = 56
            let margin: CGFloat = 16
            
            // Fixed anchor for all screens (clean + consistent).
            // Slightly above the bottom "clock" area, centered horizontally.
            let unclamped = CGPoint(
                x: size.width / 2,
                y: size.height - safeBottom - 64
            )
            let buttonCenter = CGPoint(
                x: min(max(unclamped.x, margin + buttonSize / 2), size.width - margin - buttonSize / 2),
                y: min(max(unclamped.y, margin + buttonSize / 2), size.height - margin - buttonSize / 2)
            )
            
            // Two-ring blossom: outer (far) + inner (near). We bias slightly more items
            // to the outer ring to reduce crowding on each arc.
            // Spread the outer ring a bit more horizontally, keep elegant bounds.
            let outerRadius = min(max(size.width, size.height) * 0.21, 198)
            // Inner ring: keep it clearly separated from the outer ring (bigger gap than before).
            let innerRadius = max(outerRadius * 0.58, 100)
            
            // A little breathing room on the 0°/180° ends of the arc.
            let anglePadDeg: CGFloat = 9
            
            ZStack {
                // Tap outside to close (subtle, not a full-screen modal feel).
                if presented {
                    Color.black.opacity(0.10)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeWithSuckBack()
                        }
                        .transition(.opacity)
                }
                
                // Semi-circle items: 0° → 180° (right to left), blossom like a flower.
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
                            isSelected: selectedView == entry.viewType
                        ) {
                            selectedView = entry.viewType
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
                
                // Floating launcher button (always visible).
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
            .onChange(of: isMenuOpen) { _, open in
                if open {
                    openWithBloom()
                } else {
                    // If something external closes it, still animate suck-back.
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
        // Keep source of truth in sync.
        if !isMenuOpen {
            isMenuOpen = true
        }
    }
    
    private func closeWithSuckBack(external: Bool = false) {
        // Collapse the petals into the button first...
        withAnimation(.spring(response: 0.22, dampingFraction: 0.92)) {
            bloom = false
        }
        // ...then remove the overlay after the collapse finishes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            presented = false
            if !external {
                isMenuOpen = false
            }
        }
        if external {
            // Ensure we don't get stuck presented=true when bound value flips.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                if !isMenuOpen {
                    presented = false
                }
            }
        }
    }
    
    private func loadMenuConfiguration() {
        // Load saved menu order
        if let savedOrder = UserDefaults.standard.array(forKey: "MenuOrder") as? [String] {
            let orderedItems = savedOrder.compactMap { MenuViewType(rawValue: $0) }
            if !orderedItems.isEmpty {
                visibleMenuItems = orderedItems.filter { !hiddenItems.contains($0) }
            } else {
                visibleMenuItems = MenuViewType.allCases.filter { !hiddenItems.contains($0) }
            }
        } else {
            visibleMenuItems = MenuViewType.allCases.filter { !hiddenItems.contains($0) }
        }
        
        // Load hidden items
        if let hiddenItemsData = UserDefaults.standard.array(forKey: "HiddenMenuItems") as? [String] {
            hiddenItems = Set(hiddenItemsData.compactMap { MenuViewType(rawValue: $0) })
            visibleMenuItems = visibleMenuItems.filter { !hiddenItems.contains($0) }
        }
        
    }
    
    private func radialItems() -> [MenuViewType] {
        // Prefer the saved/visible order, but fall back to all cases.
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
            // Single item: place straight up (90°).
            return CGPoint(x: center.x, y: center.y - radius)
        }
        
        let start = startDegrees * CGFloat.pi / 180
        let end = endDegrees * CGFloat.pi / 180
        let step = (end - start) / CGFloat(count - 1)
        let angle = start + (CGFloat(index) * step)
        
        // Upper semi-circle in screen coords (y goes down), so negate sin(angle).
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
        // Text labels need tangential space, so for larger counts we use two rings.
        if items.isEmpty { return [] }
        if items.count <= 6 {
            return items.enumerated().map { idx, vt in
                FlowerEntry(viewType: vt, ring: .outer, index: idx, count: items.count)
            }
        }
        
        // Two rings. Bias a bit more items to the larger-radius ring to reduce per-arc crowding.
        // Example: 14 -> 8 outer / 6 inner (instead of 7/7).
        var outerCount = Int(ceil(Double(items.count) * 0.55))
        outerCount = min(max(outerCount, 1), items.count - 1) // must be split
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
