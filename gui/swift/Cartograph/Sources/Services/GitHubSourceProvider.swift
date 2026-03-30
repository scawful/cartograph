import Foundation

/// Fetches source files from GitHub (raw content for public repos, API for private repos).
struct GitHubSourceProvider: SourceProvider {
    let owner: String
    let repo: String
    let branch: String
    let token: String?  // optional, for private repos
    var displayName: String { "GitHub (\(owner)/\(repo))" }

    func fetchSource(relativePath: String) async throws -> String {
        let url: URL
        if let token = token {
            // API endpoint for private repos
            guard let u = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contents/\(relativePath)?ref=\(branch)") else {
                throw SourceProviderError.networkError("Invalid URL")
            }
            url = u
        } else {
            // Raw content for public repos
            guard let u = URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(relativePath)") else {
                throw SourceProviderError.networkError("Invalid URL")
            }
            url = u
        }

        var request = URLRequest(url: url)
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceProviderError.networkError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200:
            // With raw+json accept header or raw.githubusercontent.com, content is plain text
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
