"""SymbolGraph: extends AFS KnowledgeGraph ABC for code-level symbol graphs.

Falls back to a standalone implementation if AFS is not installed.
"""

from __future__ import annotations

import logging
from collections import defaultdict
from typing import Any

from .storage import CartographDB, SymbolRow

log = logging.getLogger(__name__)


# Try to import AFS KnowledgeGraph; fall back to standalone if unavailable
try:
    from afs.knowledge.graph_core import GraphEdge, GraphNode, KnowledgeGraph

    _HAS_AFS = True
except ImportError:
    _HAS_AFS = False

    # Minimal standalone base matching AFS's interface
    class GraphNode:  # type: ignore[no-redef]
        def __init__(self, id: str, name: str, node_type: str, properties: dict | None = None):
            self.id = id
            self.name = name
            self.node_type = node_type
            self.properties = properties or {}

        def to_dict(self) -> dict:
            return {
                "id": self.id,
                "name": self.name,
                "node_type": self.node_type,
                "properties": self.properties,
            }

    class GraphEdge:  # type: ignore[no-redef]
        def __init__(
            self,
            source_id: str,
            target_id: str,
            edge_type: str,
            weight: float = 1.0,
            properties: dict | None = None,
        ):
            self.source_id = source_id
            self.target_id = target_id
            self.edge_type = edge_type
            self.weight = weight
            self.properties = properties or {}

        def to_dict(self) -> dict:
            return {
                "source_id": self.source_id,
                "target_id": self.target_id,
                "edge_type": self.edge_type,
                "weight": self.weight,
                "properties": self.properties,
            }

    class KnowledgeGraph:  # type: ignore[no-redef]
        def __init__(self):
            self._nodes: dict[str, GraphNode] = {}
            self._edges: list[GraphEdge] = []
            self._adjacency: dict[str, list[str]] = {}
            self._reverse_adjacency: dict[str, list[str]] = {}

        def add_node(self, node: GraphNode) -> None:
            self._nodes[node.id] = node
            self._adjacency.setdefault(node.id, [])
            self._reverse_adjacency.setdefault(node.id, [])

        def get_node(self, node_id: str) -> GraphNode | None:
            return self._nodes.get(node_id)

        def add_edge(self, edge: GraphEdge) -> None:
            self._edges.append(edge)
            self._adjacency.setdefault(edge.source_id, []).append(edge.target_id)
            self._reverse_adjacency.setdefault(edge.target_id, []).append(edge.source_id)

        def get_neighbors(self, node_id: str) -> list[GraphNode]:
            return [
                self._nodes[nid]
                for nid in self._adjacency.get(node_id, [])
                if nid in self._nodes
            ]

        def get_predecessors(self, node_id: str) -> list[GraphNode]:
            return [
                self._nodes[pid]
                for pid in self._reverse_adjacency.get(node_id, [])
                if pid in self._nodes
            ]

        @property
        def node_count(self) -> int:
            return len(self._nodes)

        @property
        def edge_count(self) -> int:
            return len(self._edges)

        def to_dict(self) -> dict:
            return {
                "nodes": [n.to_dict() for n in self._nodes.values()],
                "edges": [e.to_dict() for e in self._edges],
            }


class SymbolGraph(KnowledgeGraph):
    """Code-level symbol graph backed by a CartographDB.

    Nodes are symbols (functions, classes, methods, etc.).
    Edges are cross-references (calls, imports, inherits).
    """

    def __init__(self, db: CartographDB, project_id: str):
        super().__init__()
        self.db = db
        self.project_id = project_id
        self._loaded = False

    def load_from_db(self) -> None:
        """Load the full symbol graph from SQLite into memory."""
        if self._loaded:
            return

        # Load all symbols as nodes
        rows = self.db.conn.execute(
            """
            SELECT s.id, s.name, s.qualified_name, s.kind,
                   sf.relative_path, s.start_line, s.end_line,
                   s.signature, s.docstring, s.parent_name
            FROM symbols s
            JOIN source_files sf ON s.file_id = sf.id
            WHERE s.project_id = ?
            """,
            (self.project_id,),
        ).fetchall()

        for r in rows:
            node = GraphNode(
                id=r[0],
                name=r[1],
                node_type=r[3],  # kind
                properties={
                    "qualified_name": r[2],
                    "file_path": r[4],
                    "start_line": r[5],
                    "end_line": r[6],
                    "signature": r[7] or "",
                    "docstring": r[8] or "",
                    "parent_name": r[9] or "",
                    "line_count": r[6] - r[5] + 1,
                },
            )
            self.add_node(node)

        # Load all xrefs as edges (only internal ones)
        xrefs = self.db.conn.execute(
            """
            SELECT source_id, target_id, kind
            FROM xrefs
            WHERE project_id = ? AND target_id NOT LIKE 'external:%'
            """,
            (self.project_id,),
        ).fetchall()

        for source_id, target_id, kind in xrefs:
            if source_id in self._nodes and target_id in self._nodes:
                edge = GraphEdge(
                    source_id=source_id,
                    target_id=target_id,
                    edge_type=kind,
                )
                self.add_edge(edge)

        self._loaded = True
        log.info(
            "Loaded symbol graph: %d nodes, %d edges",
            self.node_count,
            self.edge_count,
        )

    def get_entry_points(self) -> list[GraphNode]:
        """Find entry point symbols: __main__, main(), CLI entry points, __init__.py exports."""
        self.load_from_db()
        entries = []
        for node in self._nodes.values():
            name = node.name
            props = node.properties
            file_path = props.get("file_path", "")

            if name in ("main", "__main__", "cli", "app"):
                entries.append(node)
            elif name == "__init__" and node.node_type == "module":
                entries.append(node)
            elif file_path.endswith("__main__.py"):
                entries.append(node)
            elif file_path.endswith("__init__.py") and node.node_type in ("function", "class"):
                entries.append(node)
            elif "cli" in file_path.lower() and node.node_type == "function":
                entries.append(node)

        return entries

    def get_leaf_nodes(self) -> list[GraphNode]:
        """Find leaf symbols: nodes with no outgoing call edges."""
        self.load_from_db()
        leaves = []
        for node_id, neighbors in self._adjacency.items():
            if not neighbors and node_id in self._nodes:
                leaves.append(self._nodes[node_id])
        return leaves

    def topological_sort(self) -> list[str]:
        """Topological sort of the call graph. Returns node IDs in dependency order."""
        self.load_from_db()

        in_degree: dict[str, int] = defaultdict(int)
        for node_id in self._nodes:
            in_degree[node_id] = 0
        for edge in self._edges:
            if edge.edge_type == "calls" and edge.target_id in self._nodes:
                in_degree[edge.target_id] += 1

        # Start with nodes that have no incoming call edges (leaves)
        queue = [nid for nid, deg in in_degree.items() if deg == 0]
        queue.sort(key=lambda nid: self._nodes[nid].name)  # stable ordering

        result = []
        visited = set()

        while queue:
            nid = queue.pop(0)
            if nid in visited:
                continue
            visited.add(nid)
            result.append(nid)

            for neighbor_id in self._adjacency.get(nid, []):
                if neighbor_id in in_degree:
                    in_degree[neighbor_id] -= 1
                    if in_degree[neighbor_id] <= 0 and neighbor_id not in visited:
                        queue.append(neighbor_id)

        # Add any remaining nodes (cycles)
        for nid in self._nodes:
            if nid not in visited:
                result.append(nid)

        return result

    def complexity_order(self) -> list[str]:
        """Order nodes by line count ascending (simplest first)."""
        self.load_from_db()
        nodes = list(self._nodes.values())
        nodes.sort(key=lambda n: (n.properties.get("line_count", 0), n.name))
        return [n.id for n in nodes]

    def bfs_from_entries(self) -> list[str]:
        """BFS from entry points outward through call edges."""
        self.load_from_db()
        entries = self.get_entry_points()
        if not entries:
            # Fall back to topological
            return self.topological_sort()

        visited = set()
        queue = [e.id for e in entries]
        result = []

        while queue:
            nid = queue.pop(0)
            if nid in visited:
                continue
            visited.add(nid)
            result.append(nid)

            for neighbor_id in self._adjacency.get(nid, []):
                if neighbor_id not in visited and neighbor_id in self._nodes:
                    queue.append(neighbor_id)

        # Add unreachable nodes at the end
        for nid in self._nodes:
            if nid not in visited:
                result.append(nid)

        return result

    # Required by AFS KnowledgeGraph ABC
    def get_context_for_prompt(self, query: str, max_entities: int = 10) -> str:
        """Get relevant symbol context for an LLM prompt."""
        self.load_from_db()

        # Search by name
        matching = []
        query_lower = query.lower()
        for node in self._nodes.values():
            if query_lower in node.name.lower() or query_lower in node.properties.get(
                "qualified_name", ""
            ).lower():
                matching.append(node)

        matching = matching[:max_entities]
        if not matching:
            return f"No symbols found matching '{query}'."

        lines = []
        for node in matching:
            p = node.properties
            lines.append(
                f"- {p.get('qualified_name', node.name)} ({node.node_type}) "
                f"in {p.get('file_path', '?')}:{p.get('start_line', '?')}"
            )
            if p.get("signature"):
                lines.append(f"  Signature: {p['signature']}")
            if p.get("docstring"):
                doc = p["docstring"][:200]
                lines.append(f"  Doc: {doc}")

            # Add caller/callee context
            callers = self.get_predecessors(node.id)[:3]
            if callers:
                caller_names = [c.properties.get("qualified_name", c.name) for c in callers]
                lines.append(f"  Called by: {', '.join(caller_names)}")

            callees = self.get_neighbors(node.id)[:3]
            if callees:
                callee_names = [c.properties.get("qualified_name", c.name) for c in callees]
                lines.append(f"  Calls: {', '.join(callee_names)}")

        return "\n".join(lines)

    def validate_output(self, output: str) -> list[tuple[bool, str]]:
        """Validate generated output references real symbols."""
        results = []
        # Check if any symbol names in output exist in graph
        for node in self._nodes.values():
            if node.name in output:
                results.append((True, f"References known symbol: {node.name}"))
                break
        return results

    def get_statistics(self) -> dict[str, Any]:
        """Extended statistics including code-specific metrics."""
        self.load_from_db()
        base = {
            "total_nodes": self.node_count,
            "total_edges": self.edge_count,
        }

        # Count by kind
        kinds: dict[str, int] = {}
        for node in self._nodes.values():
            kinds[node.node_type] = kinds.get(node.node_type, 0) + 1
        base["nodes_by_kind"] = kinds

        # Count by edge type
        edge_types: dict[str, int] = {}
        for edge in self._edges:
            edge_types[edge.edge_type] = edge_types.get(edge.edge_type, 0) + 1
        base["edges_by_type"] = edge_types

        # Entry points and leaves
        base["entry_points"] = len(self.get_entry_points())
        base["leaf_nodes"] = len(self.get_leaf_nodes())

        return base
