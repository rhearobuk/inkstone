import AuthorData
import SwiftUI

struct MurderBoardDiagramGroup: Identifiable {
    let category: StoryBibleCategory
    let heading: CGPoint
    var id: StoryBibleCategory { category }
}

struct MurderBoardDiagramLink: Identifiable {
    let edge: MurderBoardGraphEdge
    let start: CGPoint
    let end: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let label: CGPoint

    var id: UUID { edge.id }

    var path: Path {
        Path {
            $0.move(to: start)
            $0.addCurve(to: end, control1: control1, control2: control2)
        }
    }

    var arrowhead: Path {
        let angle = atan2(end.y - control2.y, end.x - control2.x)
        return Path {
            $0.move(to: end)
            $0.addLine(to: CGPoint(x: end.x - 12 * cos(angle - 0.45), y: end.y - 12 * sin(angle - 0.45)))
            $0.addLine(to: CGPoint(x: end.x - 12 * cos(angle + 0.45), y: end.y - 12 * sin(angle + 0.45)))
            $0.closeSubpath()
        }
    }
}

struct MurderBoardDiagramLayout {
    static let nodeSize = CGSize(width: 180, height: 72)
    let positions: [UUID: CGPoint]
    let groups: [MurderBoardDiagramGroup]
    let links: [MurderBoardDiagramLink]
    let bounds: CGRect

    init(graph: MurderBoardGraph, focusID: UUID, categories: [StoryBibleCategory]) {
        var positions: [UUID: CGPoint] = [focusID: .zero]
        var groups: [MurderBoardDiagramGroup] = []
        let populated = categories.compactMap { category -> (StoryBibleCategory, [MurderBoardGraphNode])? in
            let nodes = graph.nodes.filter { $0.id != focusID && category.contains(kind: $0.entity.kind) }
                .sorted { ($0.entity.canonicalName, $0.id.uuidString) < ($1.entity.canonicalName, $1.id.uuidString) }
            return nodes.isEmpty ? nil : (category, nodes)
        }
        func rowHeight(_ node: MurderBoardGraphNode) -> CGFloat {
            let count = graph.edges.filter { $0.sourceID == node.id || $0.targetID == node.id }.count
            return max(116, CGFloat(count) * 52 + 48)
        }
        for side in 0...1 {
            let sideGroups = populated.enumerated().filter { $0.offset % 2 == side }.map(\.element)
            let totalHeight = sideGroups.reduce(CGFloat(0)) { total, group in
                total + group.1.reduce(CGFloat(0)) { $0 + rowHeight($1) } + 64
            }
            var y = -totalHeight / 2
            let x: CGFloat = side == 0 ? 440 : -440
            for (category, nodes) in sideGroups {
                groups.append(.init(category: category, heading: CGPoint(x: x, y: y + 16)))
                y += 48
                for node in nodes {
                    let height = rowHeight(node)
                    positions[node.id] = CGPoint(x: x, y: y + height / 2)
                    y += height
                }
                y += 16
            }
        }

        let links = graph.edges.compactMap { edge -> MurderBoardDiagramLink? in
            guard let source = positions[edge.sourceID], let target = positions[edge.targetID] else { return nil }
            let otherID = edge.sourceID == focusID ? edge.targetID : edge.sourceID
            let siblings = graph.edges.filter { $0.sourceID == otherID || $0.targetID == otherID }
            let index = siblings.firstIndex { $0.id == edge.id } ?? 0
            let lane = (CGFloat(index) - CGFloat(siblings.count - 1) / 2) * 60
            let direction: CGFloat = target.x > source.x ? 1 : -1
            let start = CGPoint(x: source.x + direction * Self.nodeSize.width / 2, y: source.y)
            let end = CGPoint(x: target.x - direction * Self.nodeSize.width / 2, y: target.y)
            let span = abs(end.x - start.x) * 0.45
            let control1 = CGPoint(x: start.x + direction * span, y: start.y + lane)
            let control2 = CGPoint(x: end.x - direction * span, y: end.y + lane)
            let label = CGPoint(
                x: (start.x + 3 * control1.x + 3 * control2.x + end.x) / 8,
                y: (start.y + 3 * control1.y + 3 * control2.y + end.y) / 8
            )
            return .init(edge: edge, start: start, end: end, control1: control1, control2: control2, label: label)
        }
        var bounds = CGRect(x: -120, y: -80, width: 240, height: 160)
        for point in Array(positions.values) + groups.map(\.heading) + links.map(\.label) {
            bounds = bounds.union(CGRect(x: point.x - 110, y: point.y - 50, width: 220, height: 100))
        }
        self.positions = positions
        self.groups = groups
        self.links = links
        self.bounds = bounds.insetBy(dx: -36, dy: -36)
    }
}

struct MurderBoardDiagram: View {
    let graph: MurderBoardGraph
    let focusID: UUID
    let categories: [StoryBibleCategory]
    let selectRelationship: (MurderBoardGraphEdge) -> Void
    let openEntity: (SemanticEntity) -> Void
    let focusEntity: (SemanticEntity) -> Void
    @State private var zoom = 1.0
    @State private var pan = CGSize.zero
    @GestureState private var drag = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            let layout = MurderBoardDiagramLayout(graph: graph, focusID: focusID, categories: categories)
            let fit = min(1, min(proxy.size.width / layout.bounds.width, proxy.size.height / layout.bounds.height))
            let scale = max(0.1, fit * zoom)
            let transform = CGAffineTransform(
                a: scale, b: 0, c: 0, d: scale,
                tx: proxy.size.width / 2 - layout.bounds.midX * scale + pan.width + drag.width,
                ty: proxy.size.height / 2 - layout.bounds.midY * scale + pan.height + drag.height
            )
            ZStack {
                Color.secondary.opacity(0.035)
                Canvas { context, _ in
                    for link in layout.links {
                        context.stroke(link.path.applying(transform), with: .color(.accentColor.opacity(0.7)), lineWidth: 2)
                        context.fill(link.arrowhead.applying(transform), with: .color(.accentColor))
                    }
                }
                .accessibilityHidden(true)
                ForEach(layout.groups) { group in
                    Label(group.category.murderBoardTitle, systemImage: group.category.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .scaleEffect(scale)
                        .position(group.heading.applying(transform))
                }
                ForEach(layout.links) { link in
                    Button {
                        selectRelationship(link.edge)
                    } label: {
                        Text(link.edge.relationship.kind)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.regularMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.accentColor.opacity(0.3)))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 190)
                    .scaleEffect(scale)
                    .position(link.label.applying(transform))
                    .accessibilityLabel(link.edge.relationship.sentence)
                    .help(link.edge.relationship.sentence + " — click to edit")
                }
                ForEach(graph.nodes) { node in
                    if let position = layout.positions[node.id] {
                        nodeView(node)
                            .scaleEffect(scale)
                            .position(position.applying(transform))
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 5)
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded {
                        pan.width += $0.translation.width
                        pan.height += $0.translation.height
                    }
            )
            .clipped()
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 12) {
                    Button { zoom = max(0.4, zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                        .accessibilityLabel("Zoom out")
                    Button("Fit") { zoom = 1; pan = .zero }
                    Button { zoom = min(8, zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                        .accessibilityLabel("Zoom in")
                }
                .buttonStyle(.borderless)
                .padding(10)
                .background(.regularMaterial, in: Capsule())
                .padding(12)
            }
            .overlay(alignment: .bottomLeading) {
                Text(graph.edges.isEmpty ? "No connections in the selected categories." : "Click a relationship to edit. Drag to pan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: focusID) { _, _ in resetViewport() }
        .onChange(of: graph.nodes.map(\.id)) { _, _ in resetViewport() }
    }

    private func nodeView(_ node: MurderBoardGraphNode) -> some View {
        let isFocus = node.id == focusID
        let category = StoryBibleCategory.murderBoardCategories.first { $0.contains(kind: node.entity.kind) }
        return Button {
            if isFocus { openEntity(node.entity) } else { focusEntity(node.entity) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: category?.systemImage ?? "circle")
                    .foregroundStyle(isFocus ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(node.entity.canonicalName)
                        .font(.headline)
                        .lineLimit(2)
                    if isFocus {
                        Text("Focus").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: MurderBoardDiagramLayout.nodeSize.width, height: MurderBoardDiagramLayout.nodeSize.height)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                isFocus ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: isFocus ? 2 : 1
            ))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(node.entity.canonicalName)
        .help(isFocus ? "Open Story Bible Entry" : "Focus on \(node.entity.canonicalName)")
        .contextMenu {
            Button("Open Story Bible Entry") { openEntity(node.entity) }
            if !isFocus {
                Button("Focus on \(node.entity.canonicalName)") { focusEntity(node.entity) }
            }
        }
    }

    private func resetViewport() {
        zoom = 1
        pan = .zero
    }
}
