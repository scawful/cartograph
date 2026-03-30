import Foundation
import GRDB

struct PathStepRecord: Codable, FetchableRecord, Identifiable {
    var id: Int
    var pathId: String
    var stepOrder: Int
    var symbolId: String?
    var fileId: String?
    var title: String
    var description: String?
    var estimatedMinutes: Int

    // Joined fields from symbols
    var symbolName: String?
    var qualifiedName: String?
    var symbolKind: String?
    var startLine: Int?
    var endLine: Int?
    var signature: String?
    var docstring: String?

    // Joined from source_files
    var filePath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case pathId = "path_id"
        case stepOrder = "step_order"
        case symbolId = "symbol_id"
        case fileId = "file_id"
        case title
        case description
        case estimatedMinutes = "estimated_minutes"
        case symbolName = "symbol_name"
        case qualifiedName = "qualified_name"
        case symbolKind = "symbol_kind"
        case startLine = "start_line"
        case endLine = "end_line"
        case signature
        case docstring
        case filePath = "relative_path"
    }
}
