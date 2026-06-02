import SwiftUI
import CoreData
import os

fileprivate let mindMapLog = Logger(subsystem: "com.lucas.InkSlateNew", category: "MindMaps")

// MARK: - Mind Map Views
struct MindMapListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \MindMap.modifiedDate, ascending: false)]
    ) private var mindMaps: FetchedResults<MindMap>
    @State private var showingAlert = false
    @State private var editingMindMap: MindMap?
    @State private var newMindMapName = ""
    @State private var searchText = ""
    
    var body: some View {
        List {
            if filteredMindMaps.isEmpty {
                mindMapsEmptyState
            } else {
                Section {
                    ForEach(filteredMindMaps) { mindMap in
                        NavigationLink(destination: MindMapDetailView(mindMap: mindMap)) {
                            MindMapRow(mindMap: mindMap)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete") {
                                viewContext.delete(mindMap)
                                viewContext.inkSlateSave(module: "Mind Maps")
                            }
                            .tint(.red)
                            
                            Button("Rename") {
                                editingMindMap = mindMap
                                newMindMapName = mindMap.title ?? "Untitled"
                                showingAlert = true
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                editingMindMap = mindMap
                                newMindMapName = mindMap.title ?? "Untitled"
                                showingAlert = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                viewContext.delete(mindMap)
                                viewContext.inkSlateSave(module: "Mind Maps")
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mind Maps")
                            .font(DesignSystem.Typography.title1)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .textCase(nil)
                        
                        Text("Tap to open. Long‑press nodes inside a map to view, edit, or delete.")
                            .font(DesignSystem.Typography.callout)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .textCase(nil)
                    }
                    .padding(.top, 6)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .navigationTitle("Mind Maps")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search mind maps")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: createNewMindMap) {
                    Image(systemName: "plus")
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                }
                .accessibilityLabel("New mind map")
            }
        }
        .alert("Rename Mind Map", isPresented: $showingAlert) {
            TextField("Name", text: $newMindMapName)
            Button("Cancel") { }
            Button("Save") {
                if let mindMap = editingMindMap {
                    mindMap.title = newMindMapName
                    mindMap.modifiedDate = Date()
                    viewContext.inkSlateSave(module: "Mind Maps")
                }
            }
        }
    }
    
    private var filteredMindMaps: [MindMap] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(mindMaps) }
        return mindMaps.filter { mindMap in
            (mindMap.title ?? "").localizedCaseInsensitiveContains(trimmed)
        }
    }
    
    @ViewBuilder
    private var mindMapsEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "mindmap")
                .font(.system(size: 42, weight: .light))
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .padding(.bottom, 2)
            
            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No mind maps yet" : "No results")
                .font(DesignSystem.Typography.title2)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.center)
            
            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? "Create your first mind map to start capturing ideas."
                 : "Try a different name.")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
            
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    createNewMindMap()
                } label: {
                    Text("Create mind map")
                }
                .minimalistButton(variant: .primary, size: .large)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
        .listRowBackground(Color.clear)
    }
    
    private func createNewMindMap() {
        let newMindMap = MindMap(context: viewContext)
        newMindMap.id = UUID()
        newMindMap.title = "Untitled Mind Map"
        newMindMap.createdDate = Date()
        newMindMap.modifiedDate = Date()
        viewContext.inkSlateSave(module: "Mind Maps")
    }
}

private struct MindMapRow: View {
    @ObservedObject var mindMap: MindMap

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
    
    private var topicCount: Int {
        mindMap.nodeCount
    }
    
    private var title: String {
        let raw = (mindMap.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "Untitled" : raw
    }
    
    private var subtitle: String {
        let topics = "\(topicCount) " + (topicCount == 1 ? "topic" : "topics")
        guard let date = mindMap.modifiedDate else { return topics }
        return "\(topics) • edited \(Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date()))"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DesignSystem.Colors.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(DesignSystem.Colors.borderLight, lineWidth: 0.75)
                    )
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.accent)
            }
            .frame(width: 44, height: 44)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(DesignSystem.Typography.callout)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 8)
            
            HStack(spacing: 8) {
                Text("\(topicCount)")
                    .font(DesignSystem.Typography.callout)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(DesignSystem.Colors.borderLight, lineWidth: 0.75)
        )
        .shadow(color: DesignSystem.Shadows.small, radius: 3, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct MindMapDetailView: View {
    @ObservedObject var mindMap: MindMap
    @Environment(\.managedObjectContext) private var viewContext
    @State private var currentNode: MindMapNode?
    @State private var navigationStack: [MindMapNode] = []
    @State private var selectedNodeForAction: MindMapNode?
    @State private var showingEditSheet = false
    @State private var focusTitleWhenEditSheetOpens = false
    @State private var showingViewSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var nodeToDelete: MindMapNode?
    @State private var showingBreadcrumbs = true
    @State private var showingSearch = false
    @State private var searchText = ""
    @State private var layoutStyle: MindMapLayoutStyle = .orbital
    @Environment(\.dismiss) private var dismiss
    
    init(mindMap: MindMap) {
        self._mindMap = ObservedObject(wrappedValue: mindMap)
        self._currentNode = State(initialValue: nil)
    }

    private enum MindMapLayoutStyle: String, CaseIterable {
        case orbital
        case tree

        var displayName: String {
            switch self {
            case .orbital: return "Orbital"
            case .tree: return "Tree"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            breadcrumbView
            mindMapContentView
        }
        .navigationTitle(mindMap.displayTitle)
        .inlineNavigationTitle()
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: navigationStack.isEmpty ? { dismiss() } : navigateBack) {
                    Text("Back")
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    if !navigationStack.isEmpty {
                        Button(action: { showingBreadcrumbs.toggle() }) {
                            Image(systemName: showingBreadcrumbs ? "list.bullet" : "list.bullet")
                                .foregroundColor(showingBreadcrumbs ? .blue : .gray)
                        }
                    }
                    
                    Button {
                        showingSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                    }

                    Menu {
                        Picker("View", selection: $layoutStyle) {
                            ForEach(MindMapLayoutStyle.allCases, id: \.rawValue) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                    } label: {
                        Image(systemName: "square.grid.3x3")
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .shadow(color: DesignSystem.Shadows.small, radius: 1, x: 0, y: 1)
                    }
                }
            }
        }
        .sheet(isPresented: $showingSearch) {
            MindMapSearchView(
                mindMap: mindMap,
                searchText: $searchText,
                onSelectNode: { node in
                    navigateToAnyNode(node)
                    showingSearch = false
                }
            )
        }
        .sheet(isPresented: $showingEditSheet) {
            if let selectedNode = selectedNodeForAction {
                EditNodeView(
                    node: selectedNode,
                    focusTitleOnAppear: focusTitleWhenEditSheetOpens,
                    onDismiss: {
                        focusTitleWhenEditSheetOpens = false
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
            if let firstRootNode = (mindMap.rootNodes?.allObjects as? [MindMapNode])?.first {
                currentNode = firstRootNode
            } else {
                let newRootNode = MindMapNode(context: viewContext)
                newRootNode.id = UUID()
                newRootNode.title = "Main Node"
                newRootNode.mindMap = mindMap
                newRootNode.createdDate = Date()
                newRootNode.modifiedDate = Date()
                mindMap.modifiedDate = Date()
                currentNode = newRootNode
                viewContext.inkSlateSave(module: "Mind Maps")
            }
        }
    }
    
    private func getNodePosition(for node: MindMapNode, in geometry: GeometryProxy) -> CGPoint {
        if let current = currentNode, node.id == current.id {
            return CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        
        let children = currentNode?.children?.allObjects as? [MindMapNode] ?? []
        
        let ring0Nodes = children.filter { $0.ring == 0 }
        let ring1Nodes = children.filter { $0.ring == 1 }
        
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
        let orbitalRings: [CGFloat] = [120, 210]
        
        let radius = orbitalRings[min(Int(node.ring), orbitalRings.count - 1)]
        
        let startAngle = -Double.pi / 2
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

    private func navigateToAnyNode(_ node: MindMapNode) {
        let path = pathFromRoot(to: node)
        navigationStack = Array(path.dropLast())
        currentNode = node
        selectedNodeForAction = nil
    }

    private func pathFromRoot(to node: MindMapNode) -> [MindMapNode] {
        var stack: [MindMapNode] = []
        var visited = Set<UUID>()
        var current: MindMapNode? = node

        while let c = current {
            if let id = c.id {
                if visited.contains(id) { break }
                visited.insert(id)
            }
            stack.append(c)
            current = c.parent
        }

        return stack.reversed()
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
        Group {
            if layoutStyle == .tree {
                treeMindMapContentView
            } else {
                GeometryReader { geometry in
                    ZStack {
                        backgroundView
                        
                        ZStack {
                            orbitalRingsView(geometry: geometry)
                            centerNodeView(geometry: geometry)
                            childNodesView(geometry: geometry)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentNode?.children?.count ?? 0)
                            actionBubblesView(geometry: geometry)
                        }
                        .scaleEffect(calculateZoomScale())
                        .animation(.easeInOut(duration: 0.3), value: currentNode?.children?.count ?? 0)
                        
                        addButtonView
                    }
                }
            }
        }
    }

    private var treeMindMapContentView: some View {
        ZStack {
            backgroundView
            if let root = (mindMap.rootNodes?.allObjects as? [MindMapNode])?.first {
                TreeMindMapView(
                    rootNode: root,
                    selectedNode: $selectedNodeForAction,
                    onTapNode: { node in
                        layoutStyle = .orbital
                        navigateToAnyNode(node)
                    }
                )
            } else {
                Text("No nodes yet")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func calculateZoomScale() -> CGFloat {
        let children = currentNode?.children?.allObjects as? [MindMapNode] ?? []
        let hasRing1Nodes = children.contains { $0.ring == 1 }
        
        if hasRing1Nodes {
            return 0.75
        } else {
            return 1.0
        }
    }
    
    private var backgroundView: some View {
        Color.adaptiveSystemBackground
            .ignoresSafeArea()
            .onTapGesture {
                selectedNodeForAction = nil
            }
    }
    
    private func orbitalRingsView(geometry: GeometryProxy) -> some View {
        let centerX = geometry.size.width / 2
        let centerY = geometry.size.height / 2
        let orbitalRings: [CGFloat] = [120, 210]
        
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
                        focusTitleWhenEditSheetOpens = false
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
        
        let children = current.children?.allObjects as? [MindMapNode] ?? []
        let ring0Count = children.filter { $0.ring == 0 }.count
        let assignedRing = ring0Count < 9 ? 0 : 1
        
        let newNode = MindMapNode(context: viewContext)
        newNode.id = UUID()
        newNode.title = "New Topic"
        newNode.parent = current
        newNode.mindMap = mindMap
        newNode.ring = Int16(assignedRing)
        newNode.createdDate = Date()
        newNode.modifiedDate = Date()
        
        current.modifiedDate = Date()
        mindMap.modifiedDate = Date()
        
        viewContext.inkSlateSave(module: "Mind Maps")
        
        focusTitleWhenEditSheetOpens = true
        selectedNodeForAction = newNode
        showingEditSheet = true
    }
    
    private func deleteNode(_ node: MindMapNode) {
        if let parent = node.parent {
            parent.modifiedDate = Date()
        }
        mindMap.modifiedDate = Date()
        
        viewContext.delete(node)
        viewContext.inkSlateSave(module: "Mind Maps")
    }
}

private struct MindMapSearchView: View {
    let mindMap: MindMap
    @Binding var searchText: String
    let onSelectNode: (MindMapNode) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchDebouncer = SearchDebouncer(delay: 0.2)
    
    @FetchRequest private var allNodes: FetchedResults<MindMapNode>
    
    init(mindMap: MindMap, searchText: Binding<String>, onSelectNode: @escaping (MindMapNode) -> Void) {
        self.mindMap = mindMap
        self._searchText = searchText
        self.onSelectNode = onSelectNode
        self._allNodes = FetchRequest<MindMapNode>(
            sortDescriptors: [NSSortDescriptor(keyPath: \MindMapNode.modifiedDate, ascending: false)],
            predicate: NSPredicate(format: "mindMap == %@", mindMap),
            animation: .default
        )
    }
    
    private var filtered: [MindMapNode] {
        let q = searchDebouncer.debouncedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(allNodes) }
        let lower = q.lowercased()
        return allNodes.filter { node in
            (node.title ?? "").lowercased().contains(lower) || (node.notes ?? "").lowercased().contains(lower)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered, id: \.objectID) { node in
                    Button {
                        onSelectNode(node)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(node.title ?? "Untitled")
                                .font(.headline)
                            if let notes = node.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Search Nodes")
            .searchable(text: $searchDebouncer.searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                searchDebouncer.searchText = searchText
            }
            .onChange(of: searchDebouncer.searchText) { _, newValue in
                searchText = newValue
            }
        }
    }
}

private struct TreeMindMapView: View {
    let rootNode: MindMapNode
    @Binding var selectedNode: MindMapNode?
    let onTapNode: (MindMapNode) -> Void
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                TreeNodeRow(node: rootNode, depth: 0, selectedNode: $selectedNode, onTapNode: onTapNode)
            }
            .padding(16)
        }
    }
}

private struct TreeNodeRow: View {
    @ObservedObject var node: MindMapNode
    let depth: Int
    @Binding var selectedNode: MindMapNode?
    let onTapNode: (MindMapNode) -> Void
    
    private var children: [MindMapNode] {
        (node.children?.allObjects as? [MindMapNode] ?? [])
            .sorted { ($0.title ?? "") < ($1.title ?? "") }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                selectedNode = node
                onTapNode(node)
            } label: {
                HStack(spacing: 10) {
                    Text(node.title ?? "Untitled")
                        .font(.system(size: depth == 0 ? 18 : 16, weight: depth == 0 ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    
                    Spacer(minLength: 8)
                    
                    Text("\(node.children?.count ?? 0)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.adaptiveSystemGray)
                        .clipShape(Capsule())
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            (selectedNode?.id == node.id) ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.06),
                            lineWidth: (selectedNode?.id == node.id) ? 2 : 1
                        )
                )
            }
            .buttonStyle(.plain)
            .padding(.leading, CGFloat(depth) * 18)
            
            if !children.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(children, id: \.objectID) { child in
                        TreeNodeRow(node: child, depth: depth + 1, selectedNode: $selectedNode, onTapNode: onTapNode)
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

struct NodeBubbleView: View {
    @ObservedObject var node: MindMapNode
    let isCenter: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var cachedFontSize: CGFloat?
    
    private var bubbleSize: CGFloat {
        return isCenter ? 80 : 60
    }
    
    private var fontSize: CGFloat {
        if let cachedFontSize { return cachedFontSize }
        let size = calculateOptimalFontSize()
        guard !size.isNaN && !size.isInfinite && size > 0 else {
            return isCenter ? 18 : 16
        }
        return size
    }
    
    private func calculateOptimalFontSize() -> CGFloat {
        let title = node.title ?? ""
        let maxFontSize: CGFloat = isCenter ? 18 : 16
        let minFontSize: CGFloat = 7
        
        guard !title.isEmpty else {
            return maxFontSize
        }
        
        let horizontalPadding: CGFloat = 8
        let verticalPadding: CGFloat = 6
        let availableWidth = bubbleSize - (horizontalPadding * 2) - 8
        let availableHeight = bubbleSize - (verticalPadding * 2) - 8
        
        guard availableWidth > 0 && availableHeight > 0 else {
            return minFontSize
        }
        
        let charCount = CGFloat(title.count)
        
        let avgCharWidthRatio: CGFloat = 0.55
        
        let estimatedWidthAtMaxSize = charCount * (maxFontSize * avgCharWidthRatio)
        let estimatedLines = max(1, ceil(estimatedWidthAtMaxSize / max(1, availableWidth)))
        
        var optimalSize: CGFloat = maxFontSize
        
        if charCount <= 8 {
            return maxFontSize
        }
        
        if estimatedLines <= 3 {
            let heightPerLine = availableHeight / max(1, estimatedLines)
            let fontSizeByHeight = heightPerLine * 0.8
            
            let avgCharsPerLine = charCount / max(1, estimatedLines)
            let fontSizeByWidth = (availableWidth / max(1, avgCharsPerLine)) / avgCharWidthRatio
            
            if fontSizeByHeight.isNaN || fontSizeByHeight.isInfinite {
                optimalSize = maxFontSize
            } else if fontSizeByWidth.isNaN || fontSizeByWidth.isInfinite {
                optimalSize = fontSizeByHeight
            } else {
                optimalSize = min(fontSizeByHeight, fontSizeByWidth, maxFontSize)
            }
        } else {
            let scaleFactor = 3.0 / max(1, estimatedLines)
            optimalSize = maxFontSize * scaleFactor
        }
        
        if optimalSize.isNaN || optimalSize.isInfinite || optimalSize <= 0 {
            optimalSize = maxFontSize
        }
        
        let words = title.components(separatedBy: " ")
        let maxWordLength = words.map { $0.count }.max() ?? 0
        if maxWordLength > 10 {
            let penalty = CGFloat(maxWordLength - 10) * 0.3
            optimalSize -= penalty
        }
        
        let finalSize = max(minFontSize, min(maxFontSize, optimalSize))
        
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
            .onAppear {
                if cachedFontSize == nil {
                    cachedFontSize = calculateOptimalFontSize()
                }
            }
            .onChange(of: node.title) { _, _ in
                cachedFontSize = calculateOptimalFontSize()
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
    var focusTitleOnAppear: Bool = false
    @State private var title: String
    @State private var notes: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    let onDismiss: () -> Void

    private enum FocusField: Hashable {
        case title
        case notes
    }

    @FocusState private var focusedField: FocusField?

    init(node: MindMapNode, focusTitleOnAppear: Bool = false, onDismiss: @escaping () -> Void) {
        self.node = node
        self.focusTitleOnAppear = focusTitleOnAppear
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

                    FocusableModernTaskTextField(
                        text: $title,
                        placeholder: "Enter node title",
                        isMultiline: false,
                        focusTag: .title,
                        focusedField: $focusedField
                    )
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Notes")
                        .font(DesignSystem.Typography.callout)
                        .fontWeight(.medium)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    FocusableModernTaskTextField(
                        text: $notes,
                        placeholder: "Add notes for this node...",
                        isMultiline: true,
                        focusTag: .notes,
                        focusedField: $focusedField
                    )
                    .frame(minHeight: 150)
                }

                Spacer()
            }
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.background)
            .navigationTitle("Edit Node")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        node.title = title.isEmpty ? "Untitled" : title
                        node.notes = notes
                        node.modifiedDate = Date()

                        if let mindMap = node.mindMap {
                            mindMap.modifiedDate = Date()
                        }

                        viewContext.inkSlateSave(module: "Mind Maps")
                        onDismiss()
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard focusTitleOnAppear else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    focusedField = .title
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
                        .background(Color.adaptiveSystemGray)
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
                            .background(Color.adaptiveSystemGray)
                            .cornerRadius(8)
                    }
                    .frame(minHeight: 150)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("View Node")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
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
        .background(Color.adaptiveSystemBackground)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.adaptiveSeparator),
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
                        .fill(isActive ? Color.adaptiveSystemGray : Color.clear)
                )
        }
        .disabled(isLast)
        .buttonStyle(PlainButtonStyle())
    }
}
