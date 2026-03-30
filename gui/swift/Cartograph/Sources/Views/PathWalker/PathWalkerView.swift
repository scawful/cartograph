import SwiftUI
import GRDB

struct PathWalkerView: View {
    let database: CartographDatabase
    let pathId: String
    @Binding var selectedSymbol: SymbolRecord?

    @State private var steps: [PathStepRecord] = []
    @State private var currentIndex: Int = 0
    @State private var loadError: String?

    // MARK: - Computed

    private var totalSteps: Int { steps.count }

    private var currentStep: PathStepRecord? {
        guard !steps.isEmpty, currentIndex >= 0, currentIndex < steps.count else { return nil }
        return steps[currentIndex]
    }

    private var canGoPrevious: Bool { currentIndex > 0 }
    private var canGoNext: Bool { currentIndex < totalSteps - 1 }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if let error = loadError {
                ContentUnavailableView(
                    "Could not load path",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if steps.isEmpty {
                ProgressView("Loading reading path...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                stepContent
            }
        }
        .task {
            await loadSteps()
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        VStack(spacing: CartographTheme.Spacing.lg) {
            // Header: step counter
            headerSection

            // Progress bar
            ProgressBarView(
                current: currentIndex + 1,
                total: totalSteps,
                label: "Reading Progress"
            )
            .padding(.horizontal, CartographTheme.Spacing.lg)

            Divider()

            // Symbol info
            if let step = currentStep {
                symbolInfoSection(step)
            }

            Spacer()

            Divider()

            // Navigation buttons
            navigationButtons
        }
        .padding(.vertical, CartographTheme.Spacing.lg)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Text("Step \(currentIndex + 1) of \(totalSteps)")
                .font(.title2.bold())

            Spacer()

            if let step = currentStep {
                Label("~\(step.estimatedMinutes) min", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, CartographTheme.Spacing.lg)
    }

    // MARK: - Symbol Info

    @ViewBuilder
    private func symbolInfoSection(_ step: PathStepRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CartographTheme.Spacing.md) {
                // Name + kind badge
                HStack(spacing: CartographTheme.Spacing.sm) {
                    if let kindStr = step.symbolKind, let kind = SymbolKind(rawValue: kindStr) {
                        Image(systemName: kind.icon)
                            .foregroundStyle(kind.color)
                            .font(.title3)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.symbolName ?? step.title)
                            .font(.headline)

                        if let qn = step.qualifiedName {
                            Text(qn)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Kind badge
                if let kindStr = step.symbolKind {
                    Text(kindStr)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: CartographTheme.Radius.sm))
                }

                // File path
                if let fp = step.filePath {
                    HStack(spacing: CartographTheme.Spacing.xs) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        Text(fp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let start = step.startLine, let end = step.endLine {
                            Text("L\(start)-\(end)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Signature
                if let sig = step.signature {
                    GroupBox("Signature") {
                        Text(sig)
                            .font(CartographTheme.codeFont)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Docstring
                if let doc = step.docstring, !doc.isEmpty {
                    GroupBox("Documentation") {
                        Text(doc)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Step description
                if let desc = step.description, !desc.isEmpty {
                    GroupBox("Notes") {
                        Text(desc)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, CartographTheme.Spacing.lg)
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: CartographTheme.Spacing.md) {
            Button {
                goToPrevious()
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(!canGoPrevious)
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button {
                skip()
            } label: {
                Label("Skip", systemImage: "forward")
            }
            .disabled(!canGoNext)

            Spacer()

            Button {
                goToNext()
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canGoNext)
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .padding(.horizontal, CartographTheme.Spacing.lg)
    }

    // MARK: - Actions

    private func goToPrevious() {
        guard canGoPrevious else { return }
        currentIndex -= 1
        selectCurrentSymbol()
    }

    private func goToNext() {
        guard canGoNext else { return }
        currentIndex += 1
        selectCurrentSymbol()
    }

    private func skip() {
        // Skip advances without updating the selected symbol in the detail pane
        guard canGoNext else { return }
        currentIndex += 1
    }

    private func selectCurrentSymbol() {
        guard let step = currentStep,
              let symbolId = step.symbolId,
              let fp = step.filePath,
              let startLine = step.startLine,
              let endLine = step.endLine else { return }

        selectedSymbol = SymbolRecord(
            id: symbolId,
            projectId: database.projectId ?? "",
            fileId: step.fileId ?? "",
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

    // MARK: - Loading

    private func loadSteps() async {
        do {
            steps = try database.getPathSteps(pathId: pathId)

            // Resume from active session if available
            if let session = try database.getActiveSession(),
               session.pathId == pathId {
                let resumeIndex = max(0, session.currentStep - 1)
                currentIndex = min(resumeIndex, steps.count - 1)
            }

            // Auto-select the current step's symbol
            if !steps.isEmpty {
                selectCurrentSymbol()
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}
