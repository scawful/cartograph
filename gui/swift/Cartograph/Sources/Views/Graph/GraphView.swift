import SwiftUI

// MARK: - View Model

@MainActor
class GraphViewModel: ObservableObject {
    struct NodePosition {
        var x: Double
        var y: Double
        var vx: Double = 0
        var vy: Double = 0
    }

    @Published var positions: [String: NodePosition] = [:]
    @Published var nodes: [GraphNodeData] = []
    @Published var edges: [GraphEdgeData] = []
    @Published var selectedNodeId: String?
    @Published var isSimulating = false
    @Published var focusQuery: String = ""

    private let database: CartographDatabase

    init(database: CartographDatabase) {
        self.database = database
    }

    func load(focusedSymbolId: String? = nil) {
        do {
            let data: (nodes: [GraphNodeData], edges: [GraphEdgeData])
            if let sid = focusedSymbolId {
                data = try database.loadNeighborhood(symbolId: sid, depth: 2)
            } else {
                data = try database.loadGraphData(limit: 500)
            }
            nodes = data.nodes
            edges = data.edges
            initializePositions()
        } catch {
            nodes = []
            edges = []
        }
    }

    private func initializePositions() {
        positions.removeAll()
        let count = nodes.count
        guard count > 0 else { return }
        let radius = Double(count) * 3.0 + 100.0
        for (i, node) in nodes.enumerated() {
            let angle = 2.0 * .pi * Double(i) / Double(count)
            positions[node.id] = NodePosition(
                x: cos(angle) * radius,
                y: sin(angle) * radius
            )
        }
    }

    func runSimulation(iterations: Int = 100) {
        guard !nodes.isEmpty else { return }
        isSimulating = true

        // Build adjacency for quick lookup
        var adjacency: [String: Set<String>] = [:]
        for edge in edges {
            adjacency[edge.sourceId, default: []].insert(edge.targetId)
            adjacency[edge.targetId, default: []].insert(edge.sourceId)
        }

        Task {
            for iter in 0..<iterations {
                let temperature = 1.0 - Double(iter) / Double(iterations)
                let damping = 0.85 * temperature + 0.1

                // Repulsion between all node pairs
                let nodeIds = nodes.map(\.id)
                var forces: [String: (dx: Double, dy: Double)] = [:]
                for id in nodeIds { forces[id] = (0, 0) }

                for i in 0..<nodeIds.count {
                    for j in (i + 1)..<nodeIds.count {
                        let a = nodeIds[i], b = nodeIds[j]
                        guard let pa = positions[a], let pb = positions[b] else { continue }
                        let dx = pa.x - pb.x
                        let dy = pa.y - pb.y
                        let dist = max(sqrt(dx * dx + dy * dy), 1.0)
                        let repulsion = 5000.0 / (dist * dist)
                        let fx = (dx / dist) * repulsion
                        let fy = (dy / dist) * repulsion
                        forces[a]!.dx += fx
                        forces[a]!.dy += fy
                        forces[b]!.dx -= fx
                        forces[b]!.dy -= fy
                    }
                }

                // Attraction along edges
                for edge in edges {
                    guard let pa = positions[edge.sourceId], let pb = positions[edge.targetId] else { continue }
                    let dx = pb.x - pa.x
                    let dy = pb.y - pa.y
                    let dist = max(sqrt(dx * dx + dy * dy), 1.0)
                    let attraction = dist * 0.01
                    let fx = (dx / dist) * attraction
                    let fy = (dy / dist) * attraction
                    forces[edge.sourceId]!.dx += fx
                    forces[edge.sourceId]!.dy += fy
                    forces[edge.targetId]!.dx -= fx
                    forces[edge.targetId]!.dy -= fy
                }

                // Centering force
                for id in nodeIds {
                    guard let p = positions[id] else { continue }
                    forces[id]!.dx -= p.x * 0.001
                    forces[id]!.dy -= p.y * 0.001
                }

                // Apply forces
                for id in nodeIds {
                    guard var p = positions[id], let f = forces[id] else { continue }
                    p.vx = (p.vx + f.dx) * damping
                    p.vy = (p.vy + f.dy) * damping
                    // Clamp velocity
                    let maxV = 50.0 * temperature + 5.0
                    let speed = sqrt(p.vx * p.vx + p.vy * p.vy)
                    if speed > maxV {
                        p.vx = p.vx / speed * maxV
                        p.vy = p.vy / speed * maxV
                    }
                    p.x += p.vx
                    p.y += p.vy
                    positions[id] = p
                }

                // Yield to UI every 5 iterations
                if iter % 5 == 0 {
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
            isSimulating = false
        }
    }

    func nodeAt(point: CGPoint, offset: CGSize, scale: CGFloat, in size: CGSize) -> GraphNodeData? {
        let cx = size.width / 2 + offset.width
        let cy = size.height / 2 + offset.height
        let threshold: CGFloat = 12.0 / scale
        var closest: GraphNodeData?
        var closestDist = Double.infinity
        for node in nodes {
            guard let pos = positions[node.id] else { continue }
            let screenX = cx + CGFloat(pos.x) * scale
            let screenY = cy + CGFloat(pos.y) * scale
            let dx = point.x - screenX
            let dy = point.y - screenY
            let dist = sqrt(dx * dx + dy * dy)
            if dist < threshold * scale && dist < closestDist {
                closestDist = dist
                closest = node
            }
        }
        return closest
    }
}

// MARK: - View

struct GraphView: View {
    let database: CartographDatabase
    @Binding var selectedSymbol: SymbolRecord?

    @StateObject private var viewModel: GraphViewModel
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0

    init(database: CartographDatabase, selectedSymbol: Binding<SymbolRecord?>) {
        self.database = database
        self._selectedSymbol = selectedSymbol
        self._viewModel = StateObject(wrappedValue: GraphViewModel(database: database))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            canvas
                .gesture(dragGesture)
                .gesture(magnifyGesture)
                .onTapGesture { location in
                    handleTap(at: location)
                }

            overlay
        }
        .toolbar {
            toolbarContent
        }
        .navigationTitle("Graph (\(viewModel.nodes.count) nodes)")
        .task {
            viewModel.load()
            viewModel.runSimulation()
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        Canvas { context, size in
            let cx = size.width / 2 + offset.width + dragOffset.width
            let cy = size.height / 2 + offset.height + dragOffset.height

            // Edges
            for edge in viewModel.edges {
                guard let sp = viewModel.positions[edge.sourceId],
                      let tp = viewModel.positions[edge.targetId] else { continue }
                var path = Path()
                path.move(to: CGPoint(x: cx + sp.x * Double(scale), y: cy + sp.y * Double(scale)))
                path.addLine(to: CGPoint(x: cx + tp.x * Double(scale), y: cy + tp.y * Double(scale)))
                let edgeColor: Color = edge.kind == "inherits" ? .purple.opacity(0.4) :
                                       edge.kind == "imports" ? .green.opacity(0.3) : .gray.opacity(0.25)
                context.stroke(path, with: .color(edgeColor), lineWidth: 0.5)
            }

            // Nodes
            for node in viewModel.nodes {
                guard let pos = viewModel.positions[node.id] else { continue }
                let screenX = cx + pos.x * Double(scale)
                let screenY = cy + pos.y * Double(scale)
                let nodeRadius: CGFloat = 6
                let color = SymbolKind(rawValue: node.kind)?.color ?? .gray

                // Selection ring
                if node.id == viewModel.selectedNodeId {
                    let ring = Path(ellipseIn: CGRect(
                        x: screenX - nodeRadius - 3,
                        y: screenY - nodeRadius - 3,
                        width: (nodeRadius + 3) * 2,
                        height: (nodeRadius + 3) * 2
                    ))
                    context.stroke(ring, with: .color(.accentColor), lineWidth: 2)
                }

                let circle = Path(ellipseIn: CGRect(
                    x: screenX - nodeRadius,
                    y: screenY - nodeRadius,
                    width: nodeRadius * 2,
                    height: nodeRadius * 2
                ))
                context.fill(circle, with: .color(color))

                // Label (only when zoomed in enough)
                if scale > 0.6 {
                    let text = Text(node.name).font(.system(size: 9)).foregroundColor(.primary)
                    context.draw(text, at: CGPoint(x: screenX, y: screenY + nodeRadius + 8))
                }
            }
        }
        #if os(macOS)
        .background(Color(nsColor: .controlBackgroundColor))
        #else
        .background(Color(.systemBackground))
        #endif
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
                dragOffset = .zero
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = max(0.1, min(5.0, value.magnification))
            }
    }

    // MARK: - Tap

    private func handleTap(at location: CGPoint) {
        // Adjust for drag offset in the tap coordinate space
        let adjustedOffset = CGSize(
            width: offset.width + dragOffset.width,
            height: offset.height + dragOffset.height
        )
        // We need the canvas size; use a reasonable approach
        if let node = viewModel.nodeAt(point: location, offset: adjustedOffset, scale: scale, in: .zero) {
            viewModel.selectedNodeId = node.id
            // Convert GraphNodeData to a SymbolRecord for the detail pane
            selectedSymbol = SymbolRecord(
                id: node.id,
                projectId: database.projectId ?? "",
                fileId: "",
                name: node.name,
                qualifiedName: node.qualifiedName,
                kind: node.kind,
                startLine: node.startLine,
                endLine: node.startLine + node.lineCount - 1,
                filePath: node.filePath
            )
        }
    }

    // MARK: - Overlay

    private var overlay: some View {
        VStack(alignment: .trailing, spacing: CartographTheme.Spacing.sm) {
            if viewModel.isSimulating {
                Label("Simulating...", systemImage: "gearshape.2")
                    .font(.caption)
                    .padding(CartographTheme.Spacing.sm)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CartographTheme.Radius.sm))
            }
            if let sel = viewModel.selectedNodeId,
               let node = viewModel.nodes.first(where: { $0.id == sel }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name).font(.caption.bold())
                    Text(node.filePath).font(.caption2).foregroundStyle(.secondary)
                    Text("\(node.kind) - \(node.lineCount) lines").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(CartographTheme.Spacing.sm)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CartographTheme.Radius.sm))
            }
        }
        .padding(CartographTheme.Spacing.md)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            TextField("Focus symbol...", text: $viewModel.focusQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .onSubmit {
                    applyFocus()
                }

            Button {
                viewModel.load()
                viewModel.runSimulation()
                offset = .zero
                scale = 1.0
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            Button { scale = min(5.0, scale * 1.3) } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            Button { scale = max(0.1, scale / 1.3) } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
        }
    }

    private func applyFocus() {
        let query = viewModel.focusQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            viewModel.load()
            viewModel.runSimulation()
            return
        }
        // Find a matching symbol by name
        if let match = viewModel.nodes.first(where: { $0.name.localizedCaseInsensitiveContains(query) }) {
            viewModel.load(focusedSymbolId: match.id)
        } else {
            // Try loading from DB via search, then focus
            if let results = try? database.searchSymbols(query: query, limit: 1),
               let first = results.first {
                viewModel.load(focusedSymbolId: first.id)
            }
        }
        viewModel.runSimulation()
        offset = .zero
        scale = 1.0
    }
}
