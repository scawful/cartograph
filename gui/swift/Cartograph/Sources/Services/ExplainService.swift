import Foundation

// MARK: - Explain Service

class ExplainService {

    // MARK: - Prompt Template

    private static let promptTemplate = """
        Explain the following {kind} from a codebase. Be concise (2-4 paragraphs).

        Level: {level}
        - beginner: Explain what this does in plain language, no jargon.
        - intermediate: Explain purpose, design decisions, and how it fits the system.
        - expert: Focus on edge cases, performance, tradeoffs, and alternatives.

        Symbol: {qualified_name}
        File: {file_path}:{start_line}-{end_line}
        {signature_line}
        {docstring_line}

        Source code:
        ```{language}
        {source_code}
        ```

        Explain this {kind}:
        """

    // MARK: - Public API

    /// Generate an LLM explanation for a symbol.
    ///
    /// - Parameters:
    ///   - symbol: The symbol record to explain.
    ///   - projectRoot: Absolute path to the project root directory.
    ///   - level: Explanation level — "beginner", "intermediate", or "expert".
    /// - Returns: The explanation text from the LLM.
    func explain(
        symbol: SymbolRecord,
        projectRoot: String,
        level: String = "intermediate"
    ) async throws -> String {
        let sourceCode = readSourceCode(
            projectRoot: projectRoot,
            relativePath: symbol.filePath ?? "",
            startLine: symbol.startLine,
            endLine: symbol.endLine
        )

        let prompt = buildPrompt(symbol: symbol, sourceCode: sourceCode, level: level)

        let config = IntelligenceSettings.loadModelConfig()
        let service = LLMFactory.getService(for: config.provider)

        return try await service.generateResponse(
            prompt: prompt,
            context: "",
            config: config
        )
    }

    // MARK: - Private

    private func buildPrompt(symbol: SymbolRecord, sourceCode: String, level: String) -> String {
        let kind = symbol.kind
        let qualifiedName = symbol.qualifiedName ?? symbol.name
        let filePath = symbol.filePath ?? "unknown"
        let signatureLine = symbol.signature.map { "Signature: \($0)" } ?? ""
        let docstringLine = symbol.docstring.map { "Docstring: \($0)" } ?? ""

        // Infer language from file extension
        let language = inferLanguage(from: filePath)

        return Self.promptTemplate
            .replacingOccurrences(of: "{kind}", with: kind)
            .replacingOccurrences(of: "{level}", with: level)
            .replacingOccurrences(of: "{qualified_name}", with: qualifiedName)
            .replacingOccurrences(of: "{file_path}", with: filePath)
            .replacingOccurrences(of: "{start_line}", with: String(symbol.startLine))
            .replacingOccurrences(of: "{end_line}", with: String(symbol.endLine))
            .replacingOccurrences(of: "{signature_line}", with: signatureLine)
            .replacingOccurrences(of: "{docstring_line}", with: docstringLine)
            .replacingOccurrences(of: "{language}", with: language)
            .replacingOccurrences(of: "{source_code}", with: sourceCode)
    }

    private func readSourceCode(
        projectRoot: String,
        relativePath: String,
        startLine: Int,
        endLine: Int
    ) -> String {
        let fullPath = (projectRoot as NSString).appendingPathComponent(relativePath)

        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            return "(source code unavailable)"
        }

        let allLines = content.components(separatedBy: .newlines)
        // Include a couple lines of context before, clamp to bounds
        let start = max(0, startLine - 2)
        let end = min(allLines.count, endLine + 1)

        guard start < end else {
            return "(source code unavailable)"
        }

        return allLines[start..<end].joined(separator: "\n")
    }

    private func inferLanguage(from filePath: String) -> String {
        let ext = (filePath as NSString).pathExtension.lowercased()
        switch ext {
        case "py": return "python"
        case "swift": return "swift"
        case "js": return "javascript"
        case "ts": return "typescript"
        case "rs": return "rust"
        case "go": return "go"
        case "java": return "java"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "rb": return "ruby"
        case "lua": return "lua"
        case "asm", "s": return "asm"
        default: return ext.isEmpty ? "text" : ext
        }
    }
}
