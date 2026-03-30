import SwiftUI

struct iOSPathView: View {
    let database: CartographDatabase

    @State private var paths: [ReadingPathRecord] = []
    @State private var activeSession: SessionRecord?

    var body: some View {
        pathContent
            .navigationTitle("Reading Paths")
            .navigationDestination(for: String.self) { pathId in
                iOSPathWalkerView(database: database, pathId: pathId)
            }
            .task {
                loadData()
            }
    }

    @ViewBuilder
    private var pathContent: some View {
        if paths.isEmpty {
            ContentUnavailableView("No reading paths",
                systemImage: "book.closed",
                description: Text("Run `carto path` to generate reading paths for your project"))
        } else {
            List {
                // Active session card
                if let session = activeSession, let pathId = session.pathId {
                    Section {
                        NavigationLink(value: pathId) {
                            VStack(alignment: .leading, spacing: CartographTheme.Spacing.sm) {
                                Label("Continue Reading", systemImage: "bookmark.fill")
                                    .font(.headline)
                                    .foregroundStyle(Color.accentColor)

                                Text(session.pathName ?? "Reading Path")
                                    .font(.body)

                                ProgressView(value: session.progressPercent / 100.0)
                                    .tint(session.progressPercent >= 75 ? .green : session.progressPercent >= 40 ? .orange : .accentColor)

                                Text("Step \(session.currentStep) of \(session.totalSteps ?? 0) - \(String(format: "%.0f", session.progressPercent))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, CartographTheme.Spacing.xs)
                        }
                    }
                }

                // All paths
                Section("Reading Paths") {
                    ForEach(paths) { path in
                        NavigationLink(value: path.id) {
                            VStack(alignment: .leading, spacing: CartographTheme.Spacing.xs) {
                                Text(path.name)
                                    .font(.body)
                                HStack(spacing: CartographTheme.Spacing.sm) {
                                    Label("\(path.stepCount ?? 0) steps", systemImage: "list.number")
                                    Label("~\(String(format: "%.1f", path.hoursEstimate))h", systemImage: "clock")
                                    Text(path.strategy)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary)
                                        .clipShape(Capsule())
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, CartographTheme.Spacing.xs)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func loadData() {
        paths = (try? database.listPaths()) ?? []
        activeSession = try? database.getActiveSession()
    }
}

// MARK: - Path Walker for iOS

struct iOSPathWalkerView: View {
    let database: CartographDatabase
    let pathId: String

    @State private var steps: [PathStepRecord] = []
    @State private var currentIndex: Int = 0
    @State private var loadError: String?

    private var totalSteps: Int { steps.count }

    private var currentStep: PathStepRecord? {
        guard !steps.isEmpty, currentIndex >= 0, currentIndex < steps.count else { return nil }
        return steps[currentIndex]
    }

    private var canGoPrevious: Bool { currentIndex > 0 }
    private var canGoNext: Bool { currentIndex < totalSteps - 1 }

    var body: some View {
        walkerContent
            .navigationTitle("Reading Path")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SymbolRecord.self) { symbol in
                iOSCodeViewerView(symbol: symbol, database: database)
            }
            .task {
                await loadSteps()
            }
    }

    @ViewBuilder
    private var walkerContent: some View {
        if let error = loadError {
            ContentUnavailableView("Could not load path",
                systemImage: "exclamationmark.triangle",
                description: Text(error))
        } else if steps.isEmpty {
            ProgressView("Loading reading path...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                // Progress bar
                ProgressView(value: Double(currentIndex + 1), total: Double(totalSteps))
                    .padding(.horizontal)
                    .padding(.top, CartographTheme.Spacing.sm)

                Text("Step \(currentIndex + 1) of \(totalSteps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, CartographTheme.Spacing.xs)

                Divider()
                    .padding(.top, CartographTheme.Spacing.sm)

                // Step content
                if let step = currentStep {
                    stepContentView(step)
                }

                Divider()

                // Navigation
                HStack(spacing: CartographTheme.Spacing.lg) {
                    Button {
                        if canGoPrevious { currentIndex -= 1 }
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .disabled(!canGoPrevious)

                    Spacer()

                    if let step = currentStep {
                        NavigationLink(value: symbolFromStep(step)) {
                            Label("View Code", systemImage: "doc.text")
                        }
                    }

                    Spacer()

                    Button {
                        if canGoNext { currentIndex += 1 }
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canGoNext)
                }
                .padding(CartographTheme.Spacing.lg)
            }
        }
    }

    @ViewBuilder
    private func stepContentView(_ step: PathStepRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CartographTheme.Spacing.md) {
                // Symbol name
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

                // Time estimate
                Label("~\(step.estimatedMinutes) min", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Signature
                if let sig = step.signature {
                    GroupBox("Signature") {
                        Text(sig)
                            .font(CartographTheme.codeFontSmall)
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

                // Step notes
                if let desc = step.description, !desc.isEmpty {
                    GroupBox("Notes") {
                        Text(desc)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(CartographTheme.Spacing.lg)
        }
    }

    private func symbolFromStep(_ step: PathStepRecord) -> SymbolRecord {
        SymbolRecord(
            id: step.symbolId ?? String(step.id),
            projectId: database.projectId ?? "",
            fileId: step.fileId ?? "",
            name: step.symbolName ?? step.title,
            qualifiedName: step.qualifiedName,
            kind: step.symbolKind ?? "function",
            startLine: step.startLine ?? 1,
            endLine: step.endLine ?? 1,
            signature: step.signature,
            docstring: step.docstring,
            filePath: step.filePath
        )
    }

    private func loadSteps() async {
        do {
            steps = try database.getPathSteps(pathId: pathId)
            if let session = try database.getActiveSession(),
               session.pathId == pathId {
                let resumeIndex = max(0, session.currentStep - 1)
                currentIndex = min(resumeIndex, steps.count - 1)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}
