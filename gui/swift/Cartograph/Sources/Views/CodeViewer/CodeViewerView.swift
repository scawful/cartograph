import SwiftUI

struct CodeLine: Identifiable {
    let num: Int
    let text: String
    var id: Int { num }
}

struct CodeViewerView: View {
    let symbol: SymbolRecord
    let projectRoot: String
    let database: CartographDatabase
    var sourceProvider: SourceProvider?

    @State private var codeLines: [CodeLine] = []
    @State private var fileSymbols: [SymbolRecord] = []
    @State private var loadError: String?
    @State private var showExplainPanel = false
    @State private var language: String = "python"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                if let kind = symbol.symbolKind {
                    Image(systemName: kind.icon)
                        .foregroundStyle(kind.color)
                }
                Text(symbol.qualifiedName ?? symbol.name)
                    .font(.headline)
                Spacer()
                Text(symbol.locationString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(CartographTheme.Spacing.md)

            Divider()

            if let error = loadError {
                ContentUnavailableView("Could not load source",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error))
            } else if codeLines.isEmpty {
                ProgressView("Loading source...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(codeLines) { entry in
                                CodeLineRow(
                                    lineNum: entry.num,
                                    text: entry.text,
                                    isHighlighted: entry.num >= symbol.startLine && entry.num <= symbol.endLine,
                                    language: language
                                )
                                .id(entry.num)
                            }
                        }
                        .padding(CartographTheme.Spacing.sm)
                    }
                    .background(CartographTheme.CodeColors.background)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(max(1, symbol.startLine - 3), anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showExplainPanel.toggle()
                } label: {
                    Label("Explain", systemImage: "lightbulb")
                }
            }
        }
        #if os(macOS)
        .inspector(isPresented: $showExplainPanel) {
            ExplainPanelView(symbol: symbol, projectRoot: projectRoot)
                .inspectorColumnWidth(min: 280, ideal: 340, max: 500)
        }
        #else
        .sheet(isPresented: $showExplainPanel) {
            NavigationStack {
                ExplainPanelView(symbol: symbol, projectRoot: projectRoot)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showExplainPanel = false }
                        }
                    }
            }
        }
        #endif
        .task(id: symbol.id) {
            loadSource()
        }
    }

    private func loadSource() {
        guard let filePath = symbol.filePath else {
            loadError = "No file path for this symbol"
            return
        }

        let provider = sourceProvider ?? LocalSourceProvider(projectRoot: projectRoot)

        Task {
            do {
                let content = try await provider.fetchSource(relativePath: filePath)
                let rawLines = content.components(separatedBy: "\n")
                codeLines = rawLines.enumerated().map { CodeLine(num: $0.offset + 1, text: $0.element) }
                fileSymbols = (try? database.getFileSymbols(filePath: filePath)) ?? []
                // Infer language from extension
                let ext = (filePath as NSString).pathExtension.lowercased()
                switch ext {
                case "ts", "tsx": language = "typescript"
                case "js", "jsx": language = "javascript"
                default: language = "python"
                }
                loadError = nil
            } catch {
                loadError = "Could not read \(filePath): \(error.localizedDescription)"
                codeLines = []
            }
        }
    }
}

struct CodeLineRow: View {
    let lineNum: Int
    let text: String
    let isHighlighted: Bool
    var language: String = "python"

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(lineNum)")
                .font(CartographTheme.codeFontSmall)
                .foregroundStyle(CartographTheme.CodeColors.lineNumber)
                .frame(width: 50, alignment: .trailing)
                .padding(.trailing, CartographTheme.Spacing.sm)

            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 1)
                .padding(.trailing, CartographTheme.Spacing.sm)

            Text(text.isEmpty ? AttributedString(" ") : SyntaxTokenizer.highlight(text, language: language))
                .font(CartographTheme.codeFont)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
        .background(isHighlighted ? CartographTheme.CodeColors.highlight : Color.clear)
    }
}
