import Foundation
import GRDB

struct ProjectStats {
    let name: String
    let rootPath: String
    let fileCount: Int
    let symbolCount: Int
    let xrefCount: Int
    let indexedAt: String?
    let symbolsByKind: [String: Int]
}

final class CartographDatabase {
    let dbPool: DatabasePool
    let projectId: String?

    init(path: String) throws {
        var config = Configuration()
        config.busyMode = .timeout(5.0)
        dbPool = try DatabasePool(path: path, configuration: config)
        // Find the first project in the DB
        projectId = try dbPool.read { db in
            try String.fetchOne(db, sql: "SELECT id FROM projects LIMIT 1")
        }
    }

    func getProjectStats() throws -> ProjectStats? {
        guard let pid = projectId else { return nil }
        return try dbPool.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT name, root_path, file_count, symbol_count, indexed_at
                FROM projects WHERE id = ?
                """, arguments: [pid]) else { return nil }

            let kindRows = try Row.fetchAll(db, sql: """
                SELECT kind, COUNT(*) as cnt FROM symbols WHERE project_id = ? GROUP BY kind
                """, arguments: [pid])
            var kinds: [String: Int] = [:]
            for kr in kindRows {
                kinds[kr["kind"] as String] = kr["cnt"] as Int
            }

            let xrefCount: Int = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM xrefs WHERE project_id = ?
                """, arguments: [pid]) ?? 0

            return ProjectStats(
                name: row["name"],
                rootPath: row["root_path"],
                fileCount: row["file_count"],
                symbolCount: row["symbol_count"],
                xrefCount: xrefCount,
                indexedAt: row["indexed_at"],
                symbolsByKind: kinds
            )
        }
    }
}
