import Foundation

// MARK: - Gemini Service

class GeminiService: LLMService {
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models"

    private func getModelURL(model: String) -> String {
        "\(endpoint)/\(model):generateContent"
    }

    private func resolvedConfig(_ config: ModelConfig?) -> ModelConfig {
        if let config { return config }
        let saved = IntelligenceSettings.loadModelConfig()
        if saved.provider == .gemini { return saved }
        return ModelConfig(provider: .gemini, modelName: IntelligenceSettings.defaultModel(for: .gemini))
    }

    func generateResponse(
        prompt: String,
        context: String,
        config: ModelConfig? = nil
    ) async throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"],
              !apiKey.isEmpty else {
            throw LLMError.missingAPIKey
        }

        let resolved = resolvedConfig(config)
        let fullPrompt = buildPrompt(prompt: prompt, context: context)

        return try await callGemini(
            prompt: fullPrompt,
            apiKey: apiKey,
            model: resolved.modelName
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

    private func callGemini(prompt: String, apiKey: String, model: String) async throws -> String {
        guard let url = URL(string: "\(getModelURL(model: model))?key=\(apiKey)") else {
            throw LLMError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": 1024
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown error"
            throw LLMError.networkError(
                NSError(domain: "GeminiService", code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: errorBody])
            )
        }

        return try parseGeminiResponse(data)
    }

    private func parseGeminiResponse(_ data: Data) throws -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let candidates = json["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let text = parts.first?["text"] as? String {
            return text
        }
        throw LLMError.invalidResponse
    }
}
