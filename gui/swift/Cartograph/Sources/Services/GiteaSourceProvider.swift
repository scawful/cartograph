import Foundation

/// Fetches source files from a Gitea server (e.g. org.halext.org).
struct GiteaSourceProvider: SourceProvider {
    let baseURL: String  // e.g. "https://org.halext.org"
    let owner: String
    let repo: String
    let branch: String
    let token: String?  // optional
    var displayName: String { "Gitea (\(repo))" }

    func fetchSource(relativePath: String) async throws -> String {
        // Gitea raw content endpoint: /{owner}/{repo}/raw/branch/{branch}/{path}
        guard let encoded = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/\(owner)/\(repo)/raw/branch/\(branch)/\(encoded)") else {
            throw SourceProviderError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        if let token = token {
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceProviderError.networkError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200:
            guard let content = String(data: data, encoding: .utf8) else {
                throw SourceProviderError.networkError("Could not decode response")
            }
            return content
        case 401, 403:
            throw SourceProviderError.unauthorized
        case 404:
            throw SourceProviderError.fileNotFound(relativePath)
        default:
            throw SourceProviderError.networkError("HTTP \(httpResponse.statusCode)")
        }
    }
}
