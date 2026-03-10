//
//  MindMapViews.swift
//  InkSlate
//
//  Created by Lucas Waldron on 9/29/25.
//

import SwiftUI
import CoreData

// MARK: - Mind Map Views
struct MindMapListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \MindMap.modifiedDate, ascending: false)]
    ) private var mindMaps: FetchedResults<MindMap>
    @State private var showingAlert = false
    @State private var editingMindMap: MindMap?
    @State private var newMindMapName = ""
    
    var body: some View {
        List {
            ForEach(mindMaps) { mindMap in
                NavigationLink(destination: MindMapDetailView(mindMap: mindMap)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mindMap.title ?? "Untitled")
                            .font(.headline)
                        Text("\(mindMap.rootNodes?.count ?? 0) topics")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete") {
                        viewContext.delete(mindMap)
                        do {
                            try viewContext.save()
                        } catch {
                            print("Failed to delete mind map: \(error)")
                        }
                    }
                    .tint(.red)
                    
                    Button("Rename") {
                        editingMindMap = mindMap
                        newMindMapName = mindMap.title ?? "Untitled"
                        showingAlert = true
                    }
                    .tint(.blue)
                }
            }
        }
        .navigationTitle("Mind Maps")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: createNewMindMap) {
                    Image(systemName: "plus")
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                }
            }
        }
        .alert("Rename Mind Map", isPresented: $showingAlert) {
            TextField("Name", text: $newMindMapName)
            Button("Cancel") { }
            Button("Save") {
                if let mindMap = editingMindMap {
                    mindMap.title = newMindMapName
                    mindMap.modifiedDate = Date()
                    do {
                        try viewContext.save()
                    } catch {
                        print("Failed to rename mind map: \(error)")
                    }
                }
            }
        }
    }
    
    private func createNewMindMap() {
        let newMindMap = MindMap(context: viewContext)
        newMindMap.id = UUID()  // Required for CloudKit sync
        newMindMap.title = "Untitled Mind Map"
        newMindMap.createdDate = Date()
        newMindMap.modifiedDate = Date()
        do {
            try viewContext.save()
        } catch {
            print("Failed to create mind map: \(error)")
        }
    }
}

struct MindMapDetailView: View {
    let mindMap: MindMap
    @Environment(\.managedObjectContext) private var viewContext
    @State private var currentNode: MindMapNode?
    @State private var navigationStack: [MindMapNode] = []
    @State private var selectedNodeForAction: MindMapNode?
    @State private var showingEditSheet = false
    @State private var showingViewSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var nodeToDelete: MindMapNode?
    @State private var showingBreadcrumbs = true
    @Environment(\.dismiss) private var dismiss
    
    init(mindMap: MindMap) {
        self.mindMap = mindMap
        // We'll initialize currentNode in onAppear since we need viewContext
        self._currentNode = State(initialValue: nil)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            breadcrumbView
            mindMapContentView
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(navigationStack.isEmpty ? false : true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !navigationStack.isEmpty {
                    Button(action: navigateBack) {
                        HStack {
                            Image(systemName: "chevron.left")
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                            Text("Back")
                        }
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if !navigationStack.isEmpty {
                        Button(action: { showingBreadcrumbs.toggle() }) {
                            Image(systemName: showingBreadcrumbs ? "list.bullet" : "list.bullet")
                                .foregroundColor(showingBreadcrumbs ? .blue : .gray)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let selectedNode = selectedNodeForAction {
                EditNodeView(
                    node: selectedNode,
                    onDismiss: {
                        selectedNodeForAction = nil
                    }
                )
            } else {
                Text("No node selected")
                    .padding()
            }
        }
        .sheet(isPresented: $showingViewSheet) {
            if let selectedNode = selectedNodeForAction {
                ViewNodeView(node: selectedNode)
            } else {
                Text("No node selected")
                    .padding()
            }
        }
        .alert("Delete Node", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                selectedNodeForAction = nil
            }
            Button("Delete", role: .destructive) {
                if let node = nodeToDelete {
                    deleteNode(node)
                }
                selectedNodeForAction = nil
            }
        } message: {
            if let node = nodeToDelete {
                Text("This node has \(node.children?.count ?? 0) child node(s). Are you sure you want to delete it and all its children?")
            }
        }
        .onAppear {
            // Initialize currentNode with the first root node or create a new one
            if let firstRootNode = (mindMap.rootNodes?.allObjects as? [MindMapNode])?.first {
                currentNode = firstRootNode
            } else {
                // Create a new root node if none exists
                let newRootNode = MindMapNode(context: viewContext)
                newRootNode.id = UUID()  // Required for CloudKit sync
                newRootNode.title = "Main Node"
                newRootNode.mindMap = mindMap
                newRootNode.createdDate = Date()
                newRootNode.modifiedDate = Date()
                mindMap.modifiedDate = Date()
                currentNode = newRootNode
                do {
                    try viewContext.save()
                } catch {
                    print("Failed to create root node: \(error)")
                }
            }
        }
    }
    
    private func getNodePosition(for node: MindMapNode, in geometry: GeometryProxy) -> CGPoint {
        if let current = currentNode, node.id == current.id {
            return CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        
        let children = currentNode?.children?.allObjects as? [MindMapNode] ?? []
        
        // Group nodes by ring
        let ring0Nodes = children.filter { $0.ring == 0 }
        let ring1Nodes = children.filter { $0.ring == 1 }
        
        // Determine which ring group this node belongs to
        let nodesInRing: Int
        let indexInRing: Int
        
        if node.ring == 0 {
            nodesInRing = ring0Nodes.count
            indexInRing = ring0Nodes.firstIndex(where: { $0.id == node.id }) ?? 0
        } else {
            nodesInRing = ring1Nodes.count
            indexInRing = ring1Nodes.firstIndex(where: { $0.id == node.id }) ?? 0
        }
        
        return calculateOrbitalPosition(
            node: node,
            nodesInRing: nodesInRing,
            indexInRing: indexInRing,
            centerX: geometry.size.width / 2,
            centerY: geometry.size.height / 2
        )
    }
    
    private func calculateOrbitalPosition(node: MindMapNode, nodesInRing: Int, indexInRing: Int, centerX: CGFloat, centerY: CGFloat) -> CGPoint {
        // Define orbital rings with different radii
        let orbitalRings: [CGFloat] = [120, 210]
        
        // Use the stored ring value
        let radius = orbitalRings[min(Int(node.ring), orbitalRings.count - 1)]
        
        // Calculate angle for this node based on its position in its ring
        let startAngle = -Double.pi / 2  // Start at top
        let angleStep = 2 * Double.pi / Double(max(nodesInRing, 1))
        let angle = startAngle + Double(indexInRing) * angleStep
        
        let x = centerX + cos(angle) * radius
        let y = centerY + sin(angle) * radius
        
        return CGPoint(x: x, y: y)
    }
    
    private func getNodeDepth(_ node: MindMapNode) -> Int {
        var depth = 0
        var current = node.parent
        while current != nil {
            depth += 1
            current = current?.parent
        }
        return depth
    }
    
    private func navigateToNode(_ node: MindMapNode) {
        guard getNodeDepth(node) < 10 else { return }
        if let current = currentNode {
            navigationStack.append(current)
        }
        currentNode = node
        selectedNodeForAction = nil
    }
    
    private func navigateBack() {
        guard let previousNode = navigationStack.popLast() else { return }
        currentNode = previousNode
        selectedNodeForAction = nil
    }
    
    private func navigateToNodeAtIndex(_ index: Int) {
        if index == -1 {
            navigationStack.removeAll()
            currentNode = (mindMap.rootNodes?.allObjects as? [MindMapNode])?.first
            selectedNodeForAction = nil
        } else if index < navigationStack.count {
            let targetNode = navigationStack[index]
            navigationStack = Array(navigationStack.prefix(index))
            currentNode = targetNode
            selectedNodeForAction = nil
        }
    }
    
    private var breadcrumbView: some View {
        Group {
            if showingBreadcrumbs && (!navigationStack.isEmpty || currentNode?.id != (mindMap.rootNodes?.allObjects as? [MindMapNode])?.first?.id) {
                if let current = currentNode {
                    BreadcrumbNavigationView(
                        mindMap: mindMap,
                        navigationStack: navigationStack,
                        currentNode: current,
                        onNavigateToNode: navigateToNodeAtIndex
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
    
    private var mindMapContentView: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundView
                
                // Scaled content (rings, nodes, action bubbles)
                ZStack {
                    orbitalRingsView(geometry: geometry)
                    centerNodeView(geometry: geometry)
                    childNodesView(geometry: geometry)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentNode?.children?.count ?? 0)
                    actionBubblesView(geometry: geometry)
                }
                .scaleEffect(calculateZoomScale())
                .animation(.easeInOut(duration: 0.3), value: currentNode?.children?.count ?? 0)
                
                // Add button stays fixed (not affected by zoom)
                addButtonView
            }
        }
    }
    
    private func calculateZoomScale() -> CGFloat {
        let children = currentNode?.children?.allObjects as? [MindMapNode] ?? []
        let hasRing1Nodes = children.contains { $0.ring == 1 }
        
        if hasRing1Nodes {
            // Both rings visible
            return 0.75
        } else {
            // Only ring 0 visible
            return 1.0
        }
    }
    
    private var backgroundView: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
            .onTapGesture {
                selectedNodeForAction = nil
            }
    }
    
    private func orbitalRingsView(geometry: GeometryProxy) -> some View {
        let centerX = geometry.size.width / 2
        let centerY = geometry.size.height / 2
        let orbitalRings: [CGFloat] = [120, 210]
        
        // Only show rings that have nodes
        let children = currentNode?.children?.allObjects as? [MindMapNode] ?? []
        var visibleRings: [Int] = []
        
        if children.contains(where: { $0.ring == 0 }) {
            visibleRings.append(0)
        }
        if children.contains(where: { $0.ring == 1 }) {
            visibleRings.append(1)
        }
        
        return ZStack {
            ForEach(visibleRings, id: \.self) { index in
                Circle()
                    .stroke(
                        Color.blue.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
                    .frame(width: orbitalRings[index] * 2, height: orbitalRings[index] * 2)
                    .position(x: centerX, y: centerY)
            }
        }
    }
    
    @ViewBuilder
    private func centerNodeView(geometry: GeometryProxy) -> some View {
        if let current = currentNode {
            NodeBubbleView(
                node: current,
                isCenter: true,
                onTap: {},
                onLongPress: {
                    selectedNodeForAction = current
                }
            )
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
    
    @ViewBuilder
    private func childNodesView(geometry: GeometryProxy) -> some View {
        let children = currentNode?.children?.allObjects as? [MindMapNode] ?? []
        let ring0Nodes = children.filter { $0.ring == 0 }
        let ring1Nodes = children.filter { $0.ring == 1 }
        
        ForEach(children, id: \.id) { child in
            let nodesInRing = child.ring == 0 ? ring0Nodes.count : ring1Nodes.count
            let indexInRing: Int = {
                if child.ring == 0 {
                    return ring0Nodes.firstIndex(where: { $0.id == child.id }) ?? 0
                } else {
                    return ring1Nodes.firstIndex(where: { $0.id == child.id }) ?? 0
                }
            }()
            
            let position = calculateOrbitalPosition(
                node: child,
                nodesInRing: nodesInRing,
                indexInRing: indexInRing,
                centerX: geometry.size.width / 2,
                centerY: geometry.size.height / 2
            )
            
            NodeBubbleView(
                node: child,
                isCenter: false,
                onTap: {
                    navigateToNode(child)
                },
                onLongPress: {
                    selectedNodeForAction = child
                }
            )
            .position(x: position.x, y: position.y)
        }
    }
    
    private func actionBubblesView(geometry: GeometryProxy) -> some View {
        Group {
            if let selectedNode = selectedNodeForAction {
                let nodePosition = getNodePosition(for: selectedNode, in: geometry)
                
                HStack(spacing: 15) {
                    ActionBubbleView(title: "View", color: .green) {
                        showingViewSheet = true
                    }
                    
                    ActionBubbleView(title: "Edit", color: .blue) {
                        DispatchQueue.main.async {
                            showingEditSheet = true
                        }
                    }
                    
                    if selectedNode.id != currentNode?.id {
                        ActionBubbleView(title: "Delete", color: .red) {
                            if (selectedNode.children?.count ?? 0) == 0 {
                                deleteNode(selectedNode)
                                selectedNodeForAction = nil
                            } else {
                                nodeToDelete = selectedNode
                                showingDeleteConfirmation = true
                            }
                        }
                    }
                }
                .position(x: nodePosition.x, y: nodePosition.y - 80)
            }
        }
    }
    
    private var addButtonView: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: addNewNode) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.black)
                        .clipShape(Circle())
                        .shadow(color: DesignSystem.Shadows.medium, radius: 4, x: 0, y: 2)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
    }
    
    private func addNewNode() {
        guard let current = currentNode, (current.children?.count ?? 0) < 20 else { return }
        
        // Determine which ring to place the new node on
        let children = current.children?.allObjects as? [MindMapNode] ?? []
        let ring0Count = children.filter { $0.ring == 0 }.count
        let assignedRing = ring0Count < 9 ? 0 : 1
        
        let newNode = MindMapNode(context: viewContext)
        newNode.id = UUID()  // Required for CloudKit sync
        newNode.title = "New Topic"
        newNode.parent = current
        newNode.ring = Int16(assignedRing)
        newNode.createdDate = Date()
        newNode.modifiedDate = Date()
        
        // Update parent's modification date
        current.modifiedDate = Date()
        mindMap.modifiedDate = Date()
        
        do {
            try viewContext.save()
        } catch {
            print("Failed to add new node: \(error)")
        }
        
        // Immediately open edit sheet for the new node
        selectedNodeForAction = newNode
        showingEditSheet = true
    }
    
    private func deleteNode(_ node: MindMapNode) {
        // Update parent's modification date before deleting
        if let parent = node.parent {
            parent.modifiedDate = Date()
        }
        mindMap.modifiedDate = Date()
        
        viewContext.delete(node)
        do {
            try viewContext.save()
        } catch {
            print("Failed to delete node: \(error)")
        }
    }
}

struct NodeBubbleView: View {
    var node: MindMapNode
    let isCenter: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    // Dynamic bubble sizes based on position
    private var bubbleSize: CGFloat {
        return isCenter ? 80 : 60
    }
    
    private var fontSize: CGFloat {
        let size = calculateOptimalFontSize()
        // Extra safety: ensure the returned size is always valid
        guard !size.isNaN && !size.isInfinite && size > 0 else {
            return isCenter ? 18 : 16
        }
        return size
    }
    
    // Smart algorithm to calculate optimal font size based on text and bubble constraints
    private func calculateOptimalFontSize() -> CGFloat {
        let title = node.title ?? ""
        let maxFontSize: CGFloat = isCenter ? 18 : 16
        let minFontSize: CGFloat = 7
        
        // Handle empty text
        guard !title.isEmpty else {
            return maxFontSize
        }
        
        // Available space inside the bubble (accounting for padding and circular shape)
        let horizontalPadding: CGFloat = 8
        let verticalPadding: CGFloat = 6
        let availableWidth = bubbleSize - (horizontalPadding * 2) - 8 // Extra margin for circular shape
        let availableHeight = bubbleSize - (verticalPadding * 2) - 8
        
        // Ensure we have positive available space
        guard availableWidth > 0 && availableHeight > 0 else {
            return minFontSize
        }
        
        // Character metrics
        let charCount = CGFloat(title.count)
        
        // Estimate average character width at max font size (rough approximation)
        let avgCharWidthRatio: CGFloat = 0.55 // Average char width is ~55% of font size
        
        // Calculate how many lines we'd need at max font size
        let estimatedWidthAtMaxSize = charCount * (maxFontSize * avgCharWidthRatio)
        let estimatedLines = max(1, ceil(estimatedWidthAtMaxSize / max(1, availableWidth)))
        
        // Calculate optimal size based on constraints
        var optimalSize: CGFloat = maxFontSize
        
        // If text is short, use max size
        if charCount <= 8 {
            return maxFontSize
        }
        
        // For longer text, calculate based on area constraint
        if estimatedLines <= 3 {
            // Try to fit in available lines
            let heightPerLine = availableHeight / max(1, estimatedLines)
            let fontSizeByHeight = heightPerLine * 0.8 // 80% of line height for text
            
            // Also check width constraint
            let avgCharsPerLine = charCount / max(1, estimatedLines)
            let fontSizeByWidth = (availableWidth / max(1, avgCharsPerLine)) / avgCharWidthRatio
            
            // Use the smaller of the two constraints, ensuring valid values
            if fontSizeByHeight.isNaN || fontSizeByHeight.isInfinite {
                optimalSize = maxFontSize
            } else if fontSizeByWidth.isNaN || fontSizeByWidth.isInfinite {
                optimalSize = fontSizeByHeight
            } else {
                optimalSize = min(fontSizeByHeight, fontSizeByWidth, maxFontSize)
            }
        } else {
            // Too much text, use more aggressive scaling
            let scaleFactor = 3.0 / max(1, estimatedLines)
            optimalSize = maxFontSize * scaleFactor
        }
        
        // Ensure optimalSize is valid after calculation
        if optimalSize.isNaN || optimalSize.isInfinite || optimalSize <= 0 {
            optimalSize = maxFontSize
        }
        
        // Additional penalties for very long words (they're harder to wrap)
        let words = title.components(separatedBy: " ")
        let maxWordLength = words.map { $0.count }.max() ?? 0
        if maxWordLength > 10 {
            let penalty = CGFloat(maxWordLength - 10) * 0.3
            optimalSize -= penalty
        }
        
        // Clamp to min/max bounds and ensure no NaN or invalid values
        let finalSize = max(minFontSize, min(maxFontSize, optimalSize))
        
        // Final safety check - if we somehow got NaN or invalid, return default
        if finalSize.isNaN || finalSize.isInfinite || finalSize <= 0 {
            return minFontSize
        }
        
        return finalSize
    }
    
    var body: some View {
        let textContent = Text(node.title ?? "Untitled")
            .font(.system(size: fontSize, weight: isCenter ? .semibold : .medium))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.5)
        
        let backgroundContent = ZStack {
            Circle()
                .fill(Color.black)
            
            if isCenter {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.2), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: bubbleSize / 2
                        )
                    )
            }
        }
        
        let strokeColor = isCenter ? Color.blue.opacity(0.6) : Color.gray.opacity(0.5)
        let strokeWidth: CGFloat = isCenter ? 2 : 1
        
        let shadowColor = isCenter ? Color.blue.opacity(0.3) : Color.black.opacity(0.2)
        let shadowRadius: CGFloat = isCenter ? 8 : 4
        
        return textContent
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: bubbleSize, height: bubbleSize)
            .background(backgroundContent)
            .overlay(Circle().stroke(strokeColor, lineWidth: strokeWidth))
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: 2)
            .onTapGesture {
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                onLongPress()
            }
    }
}

struct ActionBubbleView: View {
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(color)
                .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct EditNodeView: View {
    var node: MindMapNode
    @State private var title: String
    @State private var notes: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    let onDismiss: () -> Void
    
    init(node: MindMapNode, onDismiss: @escaping () -> Void) {
        self.node = node
        self.onDismiss = onDismiss
        self._title = State(initialValue: node.title ?? "")
        self._notes = State(initialValue: node.notes ?? "")
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: DesignSystem.Spacing.xl) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Node Title")
                        .font(DesignSystem.Typography.callout)
                        .fontWeight(.medium)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    ModernTaskTextField(
                        text: $title,
                        placeholder: "Enter node title",
                        isFocused: .constant(false),
                        isMultiline: false
                    )
                }
                
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Notes")
                        .font(DesignSystem.Typography.callout)
                        .fontWeight(.medium)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    ModernTaskTextField(
                        text: $notes,
                        placeholder: "Add notes for this node...",
                        isFocused: .constant(false),
                        isMultiline: true
                    )
                    .frame(minHeight: 150)
                }
                
                Spacer()
            }
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.background)
            .navigationTitle("Edit Node")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        node.title = title.isEmpty ? "Untitled" : title
                        node.notes = notes
                        node.modifiedDate = Date()
                        
                        // Update parent mindMap's modification date
                        if let mindMap = node.mindMap {
                            mindMap.modifiedDate = Date()
                        }
                        
                        do {
                            try viewContext.save()
                        } catch {
                            print("Failed to save node: \(error)")
                        }
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ViewNodeView: View {
    var node: MindMapNode
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text((node.title?.isEmpty ?? true) ? "Untitled" : (node.title ?? "Untitled"))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        Text((node.notes?.isEmpty ?? true) ? "No notes added yet" : (node.notes ?? ""))
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    .frame(minHeight: 150)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("View Node")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct BreadcrumbNavigationView: View {
    let mindMap: MindMap
    let navigationStack: [MindMapNode]
    let currentNode: MindMapNode
    let onNavigateToNode: (Int) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                BreadcrumbItemView(
                    title: mindMap.title ?? "Untitled",
                    isActive: currentNode.id == (mindMap.rootNodes?.allObjects.first as? MindMapNode)?.id,
                    isLast: false
                ) {
                    onNavigateToNode(-1)
                }
                
                ForEach(Array(navigationStack.enumerated()), id: \.offset) { index, node in
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                        
                        BreadcrumbItemView(
                            title: node.title ?? "Untitled",
                            isActive: false,
                            isLast: false
                        ) {
                            onNavigateToNode(index)
                        }
                    }
                }
                
                if let firstRootNode = (mindMap.rootNodes?.allObjects.first as? MindMapNode), currentNode.id != firstRootNode.id {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                        
                        BreadcrumbItemView(
                            title: currentNode.title ?? "Untitled",
                            isActive: true,
                            isLast: true
                        ) {
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }
}

struct BreadcrumbItemView: View {
    let title: String
    let isActive: Bool
    let isLast: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.system(size: 14, weight: isActive ? .semibold : .medium))
                .foregroundColor(isActive ? .primary : .secondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color(.systemGray5) : Color.clear)
                )
        }
        .disabled(isLast)
        .buttonStyle(PlainButtonStyle())
    }
}
