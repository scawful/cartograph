import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var sidebarSelection: SidebarTab? = .dashboard
    @State private var selectedSymbol: SymbolRecord?

    var body: some View {
        if let db = appState.database {
            NavigationSplitView {
                SidebarView(selection: $sidebarSelection, database: db)
            } content: {
                switch sidebarSelection {
                case .dashboard:
                    DashboardView(database: db)
                case .symbols:
                    SymbolBrowserView(database: db, selectedSymbol: $selectedSymbol)
                case .path(let pathId):
                    PathWalkerView(database: db, pathId: pathId, selectedSymbol: $selectedSymbol)
                case .graph:
                    GraphView(database: db, selectedSymbol: $selectedSymbol)
                case .focus:
                    FocusTimerView()
                case nil:
                    Text("Select an item from the sidebar")
                        .foregroundStyle(.secondary)
                }
            } detail: {
                if let symbol = selectedSymbol, let stats = appState.projectStats {
                    CodeViewerView(
                        symbol: symbol,
                        projectRoot: stats.rootPath,
                        database: db
                    )
                } else {
                    VStack(spacing: CartographTheme.Spacing.lg) {
                        Image(systemName: "map")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("Select a symbol to view its source code")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(appState.projectStats?.name ?? "Cartograph")
        } else {
            WelcomeView()
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: CartographTheme.Spacing.xl) {
            Image(systemName: "map")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Cartograph")
                .font(.largeTitle.bold())

            Text("Map your codebase for learning")
                .font(.title3)
                .foregroundStyle(.secondary)

            if let error = appState.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button("Open Project Index...") {
                appState.showOpenPanel()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Run `carto ingest <path>` first to create an index")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            if let provider = providers.first {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        Task { @MainActor in
                            appState.openDatabase(at: url.path)
                        }
                    }
                }
            }
            return true
        }
    }
}
