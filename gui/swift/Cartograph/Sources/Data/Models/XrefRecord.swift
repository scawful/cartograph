import Foundation
import GRDB

struct XrefRecord: Codable, FetchableRecord, Identifiable {
    var id: Int
    var projectId: String
    var sourceId: String
    var targetId: String
    var sourceName: String
    var targetName: String
    var kind: String
    var line: Int?

    // Joined field
    var filePath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case sourceId = "source_id"
        case targetId = "target_id"
        case sourceName = "source_name"
        case targetName = "target_name"
        case kind
        case line
        case filePath = "relative_path"
    }
}
