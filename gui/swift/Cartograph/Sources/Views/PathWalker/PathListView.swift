import SwiftUI

struct PathListView: View {
    let database: CartographDatabase
    let pathId: String
    @Binding var selectedSymbol: SymbolRecord?

    @State private var steps: [PathStepRecord] = []

    var body: some View {
        List(steps) { step in
            Button {
                selectStep(step)
            } label: {
                HStack(spacing: CartographTheme.Spacing.sm) {
                    Text("\(step.stepOrder)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.symbolName ?? step.title)
                            .font(.body)
                            .lineLimit(1)

                        HStack(spacing: CartographTheme.Spacing.xs) {
                            if let kind = step.symbolKind {
                                Text(kind)
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.quaternary)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            if let fp = step.filePath {
                                Text(fp)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer()

                    Text("~\(step.estimatedMinutes)m")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .navigationTitle("Reading Path")
        .task {
            do {
                steps = try database.getPathSteps(pathId: pathId)
            } catch {
                steps = []
            }
        }
    }

    private func selectStep(_ step: PathStepRecord) {
        guard let symbolId = step.symbolId,
              let fp = step.filePath,
              let startLine = step.startLine,
              let endLine = step.endLine else { return }

        selectedSymbol = SymbolRecord(
            id: symbolId,
            projectId: database.projectId ?? "",
            fileId: "",
            name: step.symbolName ?? step.title,
            qualifiedName: step.qualifiedName,
            kind: step.symbolKind ?? "function",
            startLine: startLine,
            endLine: endLine,
            signature: step.signature,
            docstring: step.docstring,
            filePath: fp
        )
    }
}
