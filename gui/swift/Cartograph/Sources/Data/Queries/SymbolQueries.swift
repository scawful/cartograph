import Foundation
import GRDB

extension CartographDatabase {

    func searchSymbols(query: String?, kind: String? = nil, limit: Int = 50) throws -> [SymbolRecord] {
        guard let pid = projectId else { return [] }
        return try dbPool.read { db in
            if let query = query, !query.isEmpty {
                guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else {
                    return []
                }
                var sql = """
                    SELECT s.*, sf.relative_path
                    FROM symbols_fts fts
                    JOIN symbols s ON s.rowid = fts.rowid
                    JOIN source_files sf ON s.file_id = sf.id
                    WHERE symbols_fts MATCH ? AND s.project_id = ?
                """
                var args: [any DatabaseValueConvertible] = [pattern, pid]
                if let kind = kind {
                    sql += " AND s.kind = ?"
                    args.append(kind)
                }
                sql += " LIMIT ?"
                args.append(limit)
                return try SymbolRecord.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            } else {
                var sql = """
                    SELECT s.*, sf.relative_path
                    FROM symbols s
                    JOIN source_files sf ON s.file_id = sf.id
                    WHERE s.project_id = ?
                """
                var args: [any DatabaseValueConvertible] = [pid]
                if let kind = kind {
                    sql += " AND s.kind = ?"
                    args.append(kind)
                }
                sql += " ORDER BY sf.relative_path, s.start_line LIMIT ?"
                args.append(limit)
                return try SymbolRecord.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            }
        }
    }

    func getFileSymbols(filePath: String) throws -> [SymbolRecord] {
        guard let pid = projectId else { return [] }
        return try dbPool.read { db in
            try SymbolRecord.fetchAll(db, sql: """
                SELECT s.*, sf.relative_path
                FROM symbols s
                JOIN source_files sf ON s.file_id = sf.id
                WHERE s.project_id = ? AND sf.relative_path = ?
                ORDER BY s.start_line
                """, arguments: [pid, filePath])
        }
    }

    func findCallers(symbolName: String) throws -> [XrefRecord] {
        guard let pid = projectId else { return [] }
        return try dbPool.read { db in
            try XrefRecord.fetchAll(db, sql: """
                SELECT x.*, sf.relative_path
                FROM xrefs x
                JOIN symbols s ON x.source_id = s.id
                JOIN source_files sf ON s.file_id = sf.id
                WHERE x.project_id = ?
                  AND (x.target_name = ? OR x.target_name LIKE ?)
                  AND x.kind = 'calls'
                ORDER BY sf.relative_path, x.line
                """, arguments: [pid, symbolName, "%.\(symbolName)"])
        }
    }

    func findCallees(symbolName: String) throws -> [XrefRecord] {
        guard let pid = projectId else { return [] }
        return try dbPool.read { db in
            try XrefRecord.fetchAll(db, sql: """
                SELECT x.*, sf.relative_path
                FROM xrefs x
                JOIN symbols s ON x.source_id = s.id
                JOIN source_files sf ON s.file_id = sf.id
                WHERE x.project_id = ?
                  AND (x.source_name = ? OR x.source_name LIKE ?)
                  AND x.kind = 'calls'
                ORDER BY x.line
                """, arguments: [pid, symbolName, "%.\(symbolName)"])
        }
    }

    func listPaths() throws -> [ReadingPathRecord] {
        guard let pid = projectId else { return [] }
        return try dbPool.read { db in
            try ReadingPathRecord.fetchAll(db, sql: """
                SELECT rp.*,
                       COUNT(ps.id) as step_count,
                       SUM(ps.estimated_minutes) as total_minutes
                FROM reading_paths rp
                LEFT JOIN path_steps ps ON rp.id = ps.path_id
                WHERE rp.project_id = ?
                GROUP BY rp.id
                ORDER BY rp.created_at DESC
                """, arguments: [pid])
        }
    }

    func getPathSteps(pathId: String) throws -> [PathStepRecord] {
        return try dbPool.read { db in
            try PathStepRecord.fetchAll(db, sql: """
                SELECT ps.*,
                       s.name as symbol_name, s.qualified_name, s.kind as symbol_kind,
                       s.start_line, s.end_line, s.signature, s.docstring,
                       sf.relative_path
                FROM path_steps ps
                LEFT JOIN symbols s ON ps.symbol_id = s.id
                LEFT JOIN source_files sf ON s.file_id = sf.id
                WHERE ps.path_id = ?
                ORDER BY ps.step_order
                """, arguments: [pathId])
        }
    }

    func getActiveSession() throws -> SessionRecord? {
        guard let pid = projectId else { return nil }
        return try dbPool.read { db in
            try SessionRecord.fetchOne(db, sql: """
                SELECT s.*,
                       rp.name as path_name, rp.strategy as path_strategy,
                       (SELECT COUNT(*) FROM path_steps WHERE path_id = s.path_id) as total_steps
                FROM sessions s
                JOIN reading_paths rp ON s.path_id = rp.id
                WHERE s.project_id = ? AND s.status = 'active'
                ORDER BY s.last_active DESC
                LIMIT 1
                """, arguments: [pid])
        }
    }
}
