import Foundation
import GRDB

struct GraphNodeData: Identifiable {
    let id: String
    let name: String
    let qualifiedName: String
    let kind: String
    let filePath: String
    let startLine: Int
    let lineCount: Int
}

struct GraphEdgeData {
    let sourceId: String
    let targetId: String
    let kind: String  // calls, imports, inherits
}

extension CartographDatabase {

    /// Load the full project graph (limited to `limit` nodes that have at least one edge).
    func loadGraphData(limit: Int = 500) throws -> (nodes: [GraphNodeData], edges: [GraphEdgeData]) {
        guard let pid = projectId else { return ([], []) }
        return try dbPool.read { db in
            // Fetch internal edges (skip external: targets)
            let edgeRows = try Row.fetchAll(db, sql: """
                SELECT source_id, target_id, kind
                FROM xrefs
                WHERE project_id = ? AND target_id NOT LIKE 'external:%'
                """, arguments: [pid])

            var edges: [GraphEdgeData] = []
            var connectedIds: Set<String> = []
            for row in edgeRows {
                let sourceId: String = row["source_id"]
                let targetId: String = row["target_id"]
                let kind: String = row["kind"]
                edges.append(GraphEdgeData(sourceId: sourceId, targetId: targetId, kind: kind))
                connectedIds.insert(sourceId)
                connectedIds.insert(targetId)
            }

            // Fetch only symbols that participate in at least one edge
            let idList = Array(connectedIds.prefix(limit))
            guard !idList.isEmpty else { return ([], []) }

            let placeholders = idList.map { _ in "?" }.joined(separator: ",")
            let nodeRows = try Row.fetchAll(db, sql: """
                SELECT s.id, s.name, s.qualified_name, s.kind, s.start_line, s.end_line,
                       sf.relative_path
                FROM symbols s
                JOIN source_files sf ON s.file_id = sf.id
                WHERE s.id IN (\(placeholders))
                """, arguments: StatementArguments(idList))

            let nodeIdSet = Set(idList)
            var nodes: [GraphNodeData] = []
            for row in nodeRows {
                let startLine: Int = row["start_line"]
                let endLine: Int = row["end_line"]
                nodes.append(GraphNodeData(
                    id: row["id"],
                    name: row["name"],
                    qualifiedName: row["qualified_name"] ?? row["name"],
                    kind: row["kind"],
                    filePath: row["relative_path"] ?? "",
                    startLine: startLine,
                    lineCount: endLine - startLine + 1
                ))
            }

            // Filter edges to only include those between loaded nodes
            let filteredEdges = edges.filter { nodeIdSet.contains($0.sourceId) && nodeIdSet.contains($0.targetId) }

            return (nodes, filteredEdges)
        }
    }

    /// BFS from a symbol out to `depth` hops, collecting all encountered nodes and edges.
    func loadNeighborhood(symbolId: String, depth: Int = 2) throws -> (nodes: [GraphNodeData], edges: [GraphEdgeData]) {
        guard let pid = projectId else { return ([], []) }
        return try dbPool.read { db in
            var visited: Set<String> = [symbolId]
            var frontier: Set<String> = [symbolId]
            var allEdges: [GraphEdgeData] = []

            for _ in 0..<depth {
                guard !frontier.isEmpty else { break }
                let placeholders = frontier.map { _ in "?" }.joined(separator: ",")
                let args = Array(frontier)

                // Outgoing edges
                let outRows = try Row.fetchAll(db, sql: """
                    SELECT source_id, target_id, kind
                    FROM xrefs
                    WHERE project_id = ? AND target_id NOT LIKE 'external:%'
                      AND source_id IN (\(placeholders))
                    """, arguments: StatementArguments([pid] + args))

                // Incoming edges
                let inRows = try Row.fetchAll(db, sql: """
                    SELECT source_id, target_id, kind
                    FROM xrefs
                    WHERE project_id = ? AND target_id NOT LIKE 'external:%'
                      AND target_id IN (\(placeholders))
                    """, arguments: StatementArguments([pid] + args))

                var nextFrontier: Set<String> = []
                for row in outRows + inRows {
                    let sourceId: String = row["source_id"]
                    let targetId: String = row["target_id"]
                    let kind: String = row["kind"]
                    allEdges.append(GraphEdgeData(sourceId: sourceId, targetId: targetId, kind: kind))
                    if !visited.contains(targetId) {
                        visited.insert(targetId)
                        nextFrontier.insert(targetId)
                    }
                    if !visited.contains(sourceId) {
                        visited.insert(sourceId)
                        nextFrontier.insert(sourceId)
                    }
                }
                frontier = nextFrontier
            }

            // Deduplicate edges
            var edgeSet: Set<String> = []
            var uniqueEdges: [GraphEdgeData] = []
            for edge in allEdges {
                let key = "\(edge.sourceId)->\(edge.targetId):\(edge.kind)"
                if edgeSet.insert(key).inserted {
                    uniqueEdges.append(edge)
                }
            }

            // Fetch node data for all visited symbols
            let idList = Array(visited)
            guard !idList.isEmpty else { return ([], []) }
            let placeholders = idList.map { _ in "?" }.joined(separator: ",")
            let nodeRows = try Row.fetchAll(db, sql: """
                SELECT s.id, s.name, s.qualified_name, s.kind, s.start_line, s.end_line,
                       sf.relative_path
                FROM symbols s
                JOIN source_files sf ON s.file_id = sf.id
                WHERE s.id IN (\(placeholders))
                """, arguments: StatementArguments(idList))

            var nodes: [GraphNodeData] = []
            for row in nodeRows {
                let startLine: Int = row["start_line"]
                let endLine: Int = row["end_line"]
                nodes.append(GraphNodeData(
                    id: row["id"],
                    name: row["name"],
                    qualifiedName: row["qualified_name"] ?? row["name"],
                    kind: row["kind"],
                    filePath: row["relative_path"] ?? "",
                    startLine: startLine,
                    lineCount: endLine - startLine + 1
                ))
            }

            return (nodes, uniqueEdges)
        }
    }
}
