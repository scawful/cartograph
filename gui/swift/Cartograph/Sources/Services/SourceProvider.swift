import Foundation

// MARK: - Source Provider Protocol

protocol SourceProvider {
    func fetchSource(relativePath: String) async throws -> String
    var displayName: String { get }
}

// MARK: - Errors

enum SourceProviderError: LocalizedError {
    case fileNotFound(String)
    case networkError(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "File not found: \(path)"
        case .networkError(let msg): return "Network error: \(msg)"
        case .unauthorized: return "Authentication required"
        }
    }
}
