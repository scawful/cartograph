import Foundation
import GRDB

struct ReadingPathRecord: Codable, FetchableRecord, Identifiable {
    var id: String
    var projectId: String
    var name: String
    var strategy: String
    var createdAt: String?

    // Aggregated
    var stepCount: Int?
    var totalMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case name
        case strategy
        case createdAt = "created_at"
        case stepCount = "step_count"
        case totalMinutes = "total_minutes"
    }

    var hoursEstimate: Double {
        Double(totalMinutes ?? 0) / 60.0
    }
}
