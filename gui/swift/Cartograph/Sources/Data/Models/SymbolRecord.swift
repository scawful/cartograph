import Foundation
import GRDB

struct SymbolRecord: Codable, FetchableRecord, Identifiable, Hashable {
    var id: String
    var projectId: String
    var fileId: String
    var name: String
    var qualifiedName: String?
    var kind: String
    var startLine: Int
    var endLine: Int
    var signature: String?
    var docstring: String?
    var parentId: String?
    var parentName: String?

    // Joined field from source_files
    var filePath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case fileId = "file_id"
        case name
        case qualifiedName = "qualified_name"
        case kind
        case startLine = "start_line"
        case endLine = "end_line"
        case signature
        case docstring
        case parentId = "parent_id"
        case parentName = "parent_name"
        case filePath = "relative_path"
    }

    var lineCount: Int { endLine - startLine + 1 }

    var symbolKind: SymbolKind? {
        SymbolKind(rawValue: kind)
    }

    var displaySignature: String {
        signature ?? name
    }

    var locationString: String {
        if let fp = filePath {
            return "\(fp):\(startLine)"
        }
        return ":\(startLine)"
    }
}
