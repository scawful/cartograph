import Foundation
import GRDB

extension CartographDatabase {

    func advanceSession(sessionId: String, toStep: Int) throws {
        try dbPool.write { db in
            let now = ISO8601DateFormatter().string(from: Date())
            try db.execute(
                sql: "UPDATE sessions SET current_step = ?, last_active = ? WHERE id = ?",
                arguments: [toStep, now, sessionId]
            )
        }
    }

    func createSession(pathId: String) throws -> String {
        guard let pid = projectId else {
            throw DatabaseError(message: "No project loaded")
        }
        let sessionId = UUID().uuidString.lowercased()
        let now = ISO8601DateFormatter().string(from: Date())
        try dbPool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO sessions (id, project_id, path_id, current_step, started_at, last_active, status)
                    VALUES (?, ?, ?, 0, ?, ?, 'active')
                    """,
                arguments: [sessionId, pid, pathId, now, now]
            )
        }
        return sessionId
    }

    func completeSession(sessionId: String) throws {
        try dbPool.write { db in
            let now = ISO8601DateFormatter().string(from: Date())
            try db.execute(
                sql: "UPDATE sessions SET status = 'completed', last_active = ? WHERE id = ?",
                arguments: [now, sessionId]
            )
        }
    }
}
