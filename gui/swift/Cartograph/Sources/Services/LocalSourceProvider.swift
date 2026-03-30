import Foundation

struct LocalSourceProvider: SourceProvider {
    let projectRoot: String
    var displayName: String { "Local Files" }

    func fetchSource(relativePath: String) async throws -> String {
        let path = "\(projectRoot)/\(relativePath)"
        guard FileManager.default.fileExists(atPath: path) else {
            throw SourceProviderError.fileNotFound(relativePath)
        }
        return try String(contentsOfFile: path, encoding: .utf8)
    }
}
