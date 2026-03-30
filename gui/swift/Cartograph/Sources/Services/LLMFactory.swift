import Foundation

// MARK: - LLM Factory

enum LLMFactory {
    static func getService(for provider: ModelProvider) -> LLMService {
        switch provider {
        case .gemini:
            return GeminiService()
        case .ollama, .lmStudio:
            return LocalLLMService(provider: provider)
        }
    }

    /// Convenience: get service for the currently configured provider.
    static func getConfiguredService() -> LLMService {
        let config = IntelligenceSettings.loadModelConfig()
        return getService(for: config.provider)
    }
}
