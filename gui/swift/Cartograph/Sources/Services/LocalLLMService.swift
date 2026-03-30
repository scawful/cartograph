import Foundation

// MARK: - Local LLM Service (Ollama / LM Studio)

class LocalLLMService: LLMService {
    let provider: ModelProvider
    let baseURL: String

    init(provider: ModelProvider) {
        self.provider = provider
        switch provider {
        case .ollama:
            self.baseURL = IntelligenceSettings.ollamaHost
        case .lmStudio:
            self.baseURL = IntelligenceSettings.lmStudioHost
        default:
            self.baseURL = ""
        }
    }

    private func resolvedConfig(_ config: ModelConfig?) -> ModelConfig {
        if let config { return config }
        let saved = IntelligenceSettings.loadModelConfig()
        if saved.provider == provider { return saved }
        return ModelConfig(provider: provider, modelName: IntelligenceSettings.defaultModel(for: provider))
    }

    func generateResponse(
        prompt: String,
        context: String,
        config: ModelConfig? = nil
    ) async throws -> String {
        let resolved = resolvedConfig(config)
        let fullPrompt = buildPrompt(prompt: prompt, context: context)

        return try await requestCompletion(
            model: resolved.modelName,
            prompt: fullPrompt
        )
    }

    // MARK: - Private

    private func buildPrompt(prompt: String, context: String) -> String {
        var sections: [String] = []
        if !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("[Context]\n\(context)")
        }
        sections.append(prompt)
        return sections.joined(separator: "\n\n")
    }

    private func requestCompletion(model: String, prompt: String) async throws -> String {
        let urlString: String
        let body: [String: Any]

        if provider == .ollama {
            urlString = "\(baseURL)/api/generate"
            body = [
                "model": model,
                "system": "You are a helpful code explanation assistant. Be concise and accurate.",
                "prompt": prompt,
                "stream": false,
                "options": [
                    "temperature": 0.3,
                    "num_predict": 1024
                ]
            ]
        } else {
            // LM Studio uses OpenAI-compatible API
            urlString = "\(baseURL)/v1/chat/completions"
            body = [
                "model": model,
                "messages": [
                    ["role": "system", "content": "You are a helpful code explanation assistant. Be concise and accurate."],
                    ["role": "user", "content": prompt]
                ],
                "temperature": 0.3,
                "max_tokens": 1024
            ]
        }

        guard let url = URL(string: urlString) else {
            throw LLMError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse
        }

        // Parse Ollama response format
        if provider == .ollama, let response = json["response"] as? String {
            return response
        }

        // Parse LM Studio (OpenAI-compatible) response format
        if provider == .lmStudio,
           let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }

        throw LLMError.invalidResponse
    }
}
