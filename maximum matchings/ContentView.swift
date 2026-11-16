//
//  ContentView.swift
//  maximum matchings
//
//  Created by Allan Auezkhan on 16.11.2026.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - 1. Data Models & Algorithm State

struct Edge: Hashable, Identifiable {
    let u: Int // Left vertex (1-indexed)
    let v: Int // Right vertex (1-indexed)
    var id: String { "\(u)-\(v)" }
}

struct AlgorithmStep: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let matchedEdges: Set<Edge>
    let activePathEdges: Set<Edge>
    let highlightedLeftNode: Int?
}

final class BipartiteMatchingEngine: ObservableObject {
    @Published var numLeft: Int = 0
    @Published var numRight: Int = 0
    @Published var allEdges: [Edge] = []
    @Published var steps: [AlgorithmStep] = []
    @Published var currentStepIndex: Int = 0
    
    private var adj: [Int: [Int]] = [:]
    
    var currentStep: AlgorithmStep? {
        guard !steps.isEmpty, currentStepIndex >= 0, currentStepIndex < steps.count else { return nil }
        return steps[currentStepIndex]
    }
    
    // Robust parser with deduplication and bounds checking
    func loadGraph(from rawInput: String) {
        adj.removeAll()
        allEdges.removeAll()
        steps.removeAll()
        currentStepIndex = 0
        
        let lines = rawInput
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        
        guard let headerLine = lines.first else {
            loadEmptyGraph()
            return
        }
        
        let header = headerLine.split(separator: " ").compactMap { Int($0) }
        guard header.count >= 2 else {
            loadEmptyGraph()
            return
        }
        
        numLeft = header[0]
        numRight = header[1]
        
        for i in 1...max(1, numLeft) {
            adj[i] = []
        }
        
        var uniqueEdgesSet = Set<Edge>()
        var maxRightFound = numRight
        
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard !parts.isEmpty, let u = Int(parts[0].trimmingCharacters(in: .whitespaces)), u >= 1, u <= numLeft else { continue }
            
            var neighbors: [Int] = []
            if parts.count > 1 {
                neighbors = parts[1]
                    .split(separator: " ")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            }
            
            // Remove duplicate neighbors for the same left node
            let uniqueNeighbors = Array(Set(neighbors)).sorted()
            adj[u] = uniqueNeighbors
            
            for v in uniqueNeighbors {
                maxRightFound = max(maxRightFound, v)
                let edge = Edge(u: u, v: v)
                if uniqueEdgesSet.insert(edge).inserted {
                    allEdges.append(edge)
                }
            }
        }
        
        // Ensure numRight covers any referenced right nodes
        if maxRightFound > numRight {
            numRight = maxRightFound
        }
        
        runAugmentingPathAlgorithm()
    }
    
    private func loadEmptyGraph() {
        numLeft = 0
        numRight = 0
        allEdges = []
        steps = [AlgorithmStep(
            title: "Empty Graph",
            description: "Please provide a valid .g format input.",
            matchedEdges: [],
            activePathEdges: [],
            highlightedLeftNode: nil
        )]
    }
    
    // Augmenting Path Algorithm via DFS
    private func runAugmentingPathAlgorithm() {
        var matchRight: [Int: Int] = [:] // Right -> Left
        var matchLeft: [Int: Int] = [:]  // Left -> Right
        
        func currentMatchedSet() -> Set<Edge> {
            Set(matchLeft.map { Edge(u: $0.key, v: $0.value) })
        }
        
        steps.append(AlgorithmStep(
            title: "Initial Graph",
            description: "Loaded \(numLeft) left vertices, \(numRight) right vertices, and \(allEdges.count) edges.",
            matchedEdges: [],
            activePathEdges: [],
            highlightedLeftNode: nil
        ))
        
        func dfs(u: Int, visited: inout Set<Int>, path: inout [Edge]) -> Bool {
            for v in adj[u] ?? [] {
                if !visited.contains(v) {
                    visited.insert(v)
                    let forwardEdge = Edge(u: u, v: v)
                    
                    if let matchedU = matchRight[v] {
                        let backwardEdge = Edge(u: matchedU, v: v)
                        path.append(forwardEdge)
                        path.append(backwardEdge)
                        
                        if dfs(u: matchedU, visited: &visited, path: &path) {
                            matchRight[v] = u
                            matchLeft[u] = v
                            return true
                        }
                        path.removeLast(2)
                    } else {
                        path.append(forwardEdge)
                        matchRight[v] = u
                        matchLeft[u] = v
                        return true
                    }
                }
            }
            return false
        }
        
        for u in 1...numLeft {
            if matchLeft[u] == nil {
                var visited = Set<Int>()
                var augmentingPath: [Edge] = []
                
                steps.append(AlgorithmStep(
                    title: "Search from L\(u)",
                    description: "Node L\(u) is unmatched. Searching for an alternating path...",
                    matchedEdges: currentMatchedSet(),
                    activePathEdges: [],
                    highlightedLeftNode: u
                ))
                
                if dfs(u: u, visited: &visited, path: &augmentingPath) {
                    steps.append(AlgorithmStep(
                        title: "Augmenting Path Found!",
                        description: "Found augmenting path from L\(u). Flipping matched edges.",
                        matchedEdges: currentMatchedSet(),
                        activePathEdges: Set(augmentingPath),
                        highlightedLeftNode: u
                    ))
                } else {
                    steps.append(AlgorithmStep(
                        title: "No Path for L\(u)",
                        description: "Could not reach a free right vertex from L\(u).",
                        matchedEdges: currentMatchedSet(),
                        activePathEdges: [],
                        highlightedLeftNode: u
                    ))
                }
            }
        }
        
        let matchingSummary = matchLeft.keys.sorted().map { "L\($0)-R\(matchLeft[$0]!)" }.joined(separator: ", ")
        steps.append(AlgorithmStep(
            title: "Matching Complete",
            description: "Final matching size: \(matchLeft.count) edges" + (matchingSummary.isEmpty ? "." : " (\(matchingSummary))"),
            matchedEdges: currentMatchedSet(),
            activePathEdges: [],
            highlightedLeftNode: nil
        ))
    }
}

// MARK: - 2. SwiftUI Graphic Visualizer

struct BipartiteGraphCanvas: View {
    let numLeft: Int
    let numRight: Int
    let allEdges: [Edge]
    let step: AlgorithmStep
    
    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 280)
            let height = max(geo.size.height, 280)
            let leftX: CGFloat = 50
            let rightX: CGFloat = max(width - 50, 100)
            
            let leftPositions = calculatePositions(count: numLeft, x: leftX, height: height)
            let rightPositions = calculatePositions(count: numRight, x: rightX, height: height)
            
            ZStack {
                // Draw Edges
                ForEach(allEdges) { edge in
                    if let start = leftPositions[edge.u], let end = rightPositions[edge.v] {
                        let isMatched = step.matchedEdges.contains(edge)
                        let isAugmenting = step.activePathEdges.contains(edge)
                        
                        Path { path in
                            path.move(to: start)
                            path.addLine(to: end)
                        }
                        .stroke(
                            edgeColor(isMatched: isMatched, isAugmenting: isAugmenting),
                            style: StrokeStyle(
                                lineWidth: (isMatched || isAugmenting) ? 4 : 2,
                                lineCap: .round,
                                dash: isAugmenting && !isMatched ? [5, 3] : []
                            )
                        )
                    }
                }
                
                // Draw Left Vertices
                ForEach(1...max(1, numLeft), id: \.self) { u in
                    if u <= numLeft, let pos = leftPositions[u] {
                        NodeView(number: u, prefix: "L", isHighlighted: step.highlightedLeftNode == u, color: Color(red: 0.12, green: 0.35, blue: 0.48))
                            .position(pos)
                    }
                }
                
                // Draw Right Vertices
                ForEach(1...max(1, numRight), id: \.self) { v in
                    if v <= numRight, let pos = rightPositions[v] {
                        NodeView(number: v, prefix: "R", isHighlighted: false, color: Color(red: 0.25, green: 0.48, blue: 0.32))
                            .position(pos)
                    }
                }
            }
        }
    }
    
    private func calculatePositions(count: Int, x: CGFloat, height: CGFloat) -> [Int: CGPoint] {
        var dict: [Int: CGPoint] = [:]
        guard count > 0 else { return dict }
        let spacing = height / CGFloat(count + 1)
        for i in 1...count {
            dict[i] = CGPoint(x: x, y: spacing * CGFloat(i))
        }
        return dict
    }
    
    private func edgeColor(isMatched: Bool, isAugmenting: Bool) -> Color {
        if isAugmenting { return .blue }
        if isMatched { return .red }
        return .primary.opacity(0.25)
    }
}

struct NodeView: View {
    let number: Int
    let prefix: String
    let isHighlighted: Bool
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 38, height: 38)
                .overlay(Circle().stroke(isHighlighted ? Color.blue : Color.black, lineWidth: isHighlighted ? 3 : 2))
                .shadow(radius: 1)
            
            Text("\(prefix)\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - 3. Main App View

struct ContentView: View {
    @StateObject private var engine = BipartiteMatchingEngine()
    
    static let example1 = """
    3 3
    1: 1 2 3
    2: 1
    3: 2
    """
    
    static let example2 = """
    5 4
    1: 1 3
    2: 2 3
    3: 2
    4:
    5: 3 4
    """
    
    @State private var inputText: String = example1
    @State private var showingFileImporter = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Top Actions
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            Button("Import .g File") { showingFileImporter = true }
                                .buttonStyle(.borderedProminent)
                            Button("Example 1") {
                                inputText = Self.example1
                                engine.loadGraph(from: inputText)
                            }
                            .buttonStyle(.bordered)
                            Button("Example 2") {
                                inputText = Self.example2
                                engine.loadGraph(from: inputText)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    // Graph Canvas
                    if let step = engine.currentStep {
                        VStack(spacing: 8) {
                            BipartiteGraphCanvas(
                                numLeft: engine.numLeft,
                                numRight: engine.numRight,
                                allEdges: engine.allEdges,
                                step: step
                            )
                            .frame(height: 320)
                            .background(Color.gray.opacity(0.06))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.25)))
                            
                            // Legend
                            HStack(spacing: 16) {
                                Label("Unmatched", systemImage: "minus")
                                    .foregroundColor(.secondary)
                                Label("Matched", systemImage: "minus")
                                    .foregroundColor(.red)
                                Label("Path", systemImage: "minus")
                                    .foregroundColor(.blue)
                            }
                            .font(.caption)
                        }
                        
                        // Step Info
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Step \(engine.currentStepIndex + 1) of \(engine.steps.count): \(step.title)")
                                .font(.headline)
                            Text(step.description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(10)
                        
                        // Controls
                        HStack {
                            Button(action: { if engine.currentStepIndex > 0 { engine.currentStepIndex -= 1 } }) {
                                Label("Prev", systemImage: "chevron.left")
                            }
                            .disabled(engine.currentStepIndex == 0)
                            
                            Spacer()
                            
                            Button("Jump to Final") {
                                engine.currentStepIndex = max(0, engine.steps.count - 1)
                            }
                            .disabled(engine.currentStepIndex == engine.steps.count - 1)
                            
                            Spacer()
                            
                            Button(action: { if engine.currentStepIndex < engine.steps.count - 1 { engine.currentStepIndex += 1 } }) {
                                Label("Next", systemImage: "chevron.right")
                            }
                            .disabled(engine.currentStepIndex >= engine.steps.count - 1)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Divider().padding(.vertical, 4)
                    
                    // Input & Output Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Graph Input (.g format)")
                            .font(.headline)
                        
                        TextEditor(text: $inputText)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 120)
                            .padding(4)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4)))
                        
                        Button(action: {
                            engine.loadGraph(from: inputText)
                        }) {
                            Label("Run Algorithm", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Text("Current Matching Output:")
                            .font(.headline)
                            .padding(.top, 6)
                        
                        if let step = engine.currentStep {
                            let sortedEdges = step.matchedEdges.sorted { $0.u < $1.u }
                            if sortedEdges.isEmpty {
                                Text("No edges matched yet.")
                                    .foregroundColor(.secondary)
                            } else {
                                FlowLayout(spacing: 8) {
                                    ForEach(sortedEdges) { edge in
                                        Text("L\(edge.u) — R\(edge.v)")
                                            .font(.system(.body, design: .monospaced).bold())
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.red.opacity(0.1))
                                            .foregroundColor(.red)
                                            .cornerRadius(6)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Max Matching")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .onAppear {
            engine.loadGraph(from: inputText)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [UTType.plainText, UTType(filenameExtension: "g") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            do {
                let selectedFile = try result.get()
                guard let url = selectedFile.first else { return }
                
                // Secure access for sandbox files
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                let fileContent = try String(contentsOf: url, encoding: .utf8)
                DispatchQueue.main.async {
                    inputText = fileContent
                    engine.loadGraph(from: inputText)
                }
            } catch {
                print("Error reading imported file: \(error.localizedDescription)")
            }
        }
    }
}

// FlowLayout helper for result chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? 300
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var positions: [CGPoint] = []
        var maxX: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }
        
        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}
