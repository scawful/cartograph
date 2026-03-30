import Foundation

// MARK: - Intelligence Settings

struct IntelligenceSettings {
    private static let defaults = UserDefaults.standard

    // MARK: - Default Hosts

    static let ollamaHost = "http://localhost:11434"
    static let lmStudioHost = "http://localhost:1234"

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let provider = "cartograph.intelligence.provider"
        static let modelName = "cartograph.intelligence.modelName"
    }

    // MARK: - Default Models

    static func defaultModel(for provider: ModelProvider) -> String {
        switch provider {
        case .gemini: return "gemini-2.0-flash"
        case .ollama: return "llama3.2"
        case .lmStudio: return "default"
        }
    }

    // MARK: - Load / Save

    static func loadModelConfig() -> ModelConfig {
        let provider = defaults.string(forKey: Keys.provider)
            .flatMap(ModelProvider.init(rawValue:))
            ?? .gemini

        let storedModel = defaults.string(forKey: Keys.modelName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = (storedModel?.isEmpty == false)
            ? storedModel!
            : defaultModel(for: provider)

        return ModelConfig(provider: provider, modelName: modelName)
    }

    static func saveModelConfig(_ config: ModelConfig) {
        defaults.set(config.provider.rawValue, forKey: Keys.provider)
        defaults.set(config.modelName, forKey: Keys.modelName)
    }
}
