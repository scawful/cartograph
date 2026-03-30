import SwiftUI

struct iOSCodeViewerView: View {
    let symbol: SymbolRecord
    let database: CartographDatabase

    @State private var codeLines: [CodeLine] = []
    @State private var loadError: String?
    @State private var showExplainSheet = false
    @State private var language: String = "python"

    private var projectRoot: String {
        (try? database.getProjectStats())?.rootPath ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Symbol header
            HStack(spacing: CartographTheme.Spacing.sm) {
                if let kind = symbol.symbolKind {
                    Image(systemName: kind.icon)
                        .foregroundStyle(kind.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(symbol.qualifiedName ?? symbol.name)
                        .font(.subheadline.bold())
                        .lineLimit(2)
                    Text(symbol.locationString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
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
                        .padding(CartographTheme.Spacing.xs)
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
        .navigationTitle(symbol.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showExplainSheet = true
                } label: {
                    Label("Explain", systemImage: "lightbulb")
                }
            }
        }
        .sheet(isPresented: $showExplainSheet) {
            NavigationStack {
                ExplainPanelView(symbol: symbol, projectRoot: projectRoot)
                    .navigationTitle("Explain")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showExplainSheet = false }
                        }
                    }
            }
        }
        .task(id: symbol.id) {
            loadSource()
        }
    }

    private func loadSource() {
        guard let filePath = symbol.filePath else {
            loadError = "No file path for this symbol"
            return
        }

        let root = projectRoot
        let fullPath = "\(root)/\(filePath)"
        do {
            let content = try String(contentsOfFile: fullPath, encoding: .utf8)
            let rawLines = content.components(separatedBy: "\n")
            codeLines = rawLines.enumerated().map { CodeLine(num: $0.offset + 1, text: $0.element) }
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
