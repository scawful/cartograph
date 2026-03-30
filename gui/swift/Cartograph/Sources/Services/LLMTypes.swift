import Foundation

// MARK: - Model Provider

enum ModelProvider: String, Codable, CaseIterable, Identifiable {
    case gemini = "Gemini (Cloud)"
    case ollama = "Ollama (Local)"
    case lmStudio = "LM Studio (Local)"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        }
    }
}

// MARK: - Model Configuration

struct ModelConfig: Codable, Hashable {
    var provider: ModelProvider
    var modelName: String

    static let defaultCloud = ModelConfig(provider: .gemini, modelName: "gemini-2.0-flash")
    static let defaultLocal = ModelConfig(provider: .ollama, modelName: "llama3.2")
}

// MARK: - Generation Context

struct GenerationContext: Codable {
    let timezone: String
    let currentDate: String
    let projectName: String?

    static func current(projectName: String? = nil) -> GenerationContext {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return GenerationContext(
            timezone: TimeZone.current.identifier,
            currentDate: formatter.string(from: Date()),
            projectName: projectName
        )
    }
}

// MARK: - LLM Service Protocol

protocol LLMService {
    func generateResponse(
        prompt: String,
        context: String,
        config: ModelConfig?
    ) async throws -> String
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case networkError(Error)
    case unsupportedProvider

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key not configured. Set GEMINI_API_KEY in environment."
        case .invalidResponse:
            return "Received an invalid response from the LLM."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unsupportedProvider:
            return "This operation is not supported by the selected provider."
        }
    }
}
