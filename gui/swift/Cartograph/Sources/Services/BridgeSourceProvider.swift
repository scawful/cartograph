import Foundation

/// Fetches source files from the Cartograph source server over HTTP (Tailscale / NERV Bridge).
struct BridgeSourceProvider: SourceProvider {
    let baseURL: String  // e.g. "http://100.x.y.z:11443"
    var displayName: String { "NERV Bridge" }

    func fetchSource(relativePath: String) async throws -> String {
        guard let encoded = relativePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/api/v1/source?path=\(encoded)") else {
            throw SourceProviderError.networkError("Invalid URL")
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceProviderError.networkError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200:
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? String else {
                throw SourceProviderError.networkError("Invalid response format")
            }
            return content
        case 403:
            throw SourceProviderError.networkError("Access denied (path traversal blocked)")
        case 404:
            throw SourceProviderError.fileNotFound(relativePath)
        default:
            throw SourceProviderError.networkError("HTTP \(httpResponse.statusCode)")
        }
    }
}
