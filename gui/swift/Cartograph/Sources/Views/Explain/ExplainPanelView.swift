import SwiftUI

// MARK: - Explain Panel View

struct ExplainPanelView: View {
    let symbol: SymbolRecord
    let projectRoot: String

    @State private var explanation: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var selectedLevel: String = "intermediate"

    private let explainService = ExplainService()

    var body: some View {
        VStack(alignment: .leading, spacing: CartographTheme.Spacing.md) {
            header
            LevelSelector(level: $selectedLevel)
            Divider()
            contentArea
        }
        .padding(CartographTheme.Spacing.lg)
        .frame(minWidth: 300, idealWidth: 400)
        .onChange(of: selectedLevel) { _, _ in
            Task { await generateExplanation() }
        }
        .task {
            await generateExplanation()
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: CartographTheme.Spacing.xs) {
                HStack(spacing: CartographTheme.Spacing.sm) {
                    if let kind = symbol.symbolKind {
                        Image(systemName: kind.icon)
                            .foregroundColor(kind.color)
                    }
                    Text(symbol.qualifiedName ?? symbol.name)
                        .font(.headline)
                }
                Text(symbol.locationString)
                    .font(CartographTheme.codeFontSmall)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: {
                Task { await generateExplanation() }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(isLoading)
            .help("Regenerate explanation")
        }
    }

    private var contentArea: some View {
        Group {
            if isLoading {
                VStack(spacing: CartographTheme.Spacing.md) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating explanation...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else if let error = errorMessage {
                VStack(spacing: CartographTheme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .font(.title2)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollView {
                    Text(explanation)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Actions

    private func generateExplanation() async {
        isLoading = true
        errorMessage = nil

        do {
            explanation = try await explainService.explain(
                symbol: symbol,
                projectRoot: projectRoot,
                level: selectedLevel
            )
        } catch {
            errorMessage = error.localizedDescription
            explanation = ""
        }

        isLoading = false
    }
}
