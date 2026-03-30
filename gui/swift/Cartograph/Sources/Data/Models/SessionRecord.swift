import Foundation
import GRDB

struct SessionRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "sessions"

    var id: String
    var projectId: String
    var pathId: String?
    var currentStep: Int
    var startedAt: String?
    var lastActive: String?
    var status: String

    // Joined fields
    var pathName: String?
    var pathStrategy: String?
    var totalSteps: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case pathId = "path_id"
        case currentStep = "current_step"
        case startedAt = "started_at"
        case lastActive = "last_active"
        case status
        case pathName = "path_name"
        case pathStrategy = "path_strategy"
        case totalSteps = "total_steps"
    }

    var progressPercent: Double {
        guard let total = totalSteps, total > 0 else { return 0 }
        return Double(currentStep) / Double(total) * 100.0
    }

    var isActive: Bool { status == "active" }
}
