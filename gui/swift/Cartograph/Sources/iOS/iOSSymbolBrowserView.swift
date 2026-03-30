import SwiftUI

struct iOSSymbolBrowserView: View {
    let database: CartographDatabase
    var sourceProvider: SourceProvider?

    @State private var searchText = ""
    @State private var selectedKind: String?
    @State private var symbols: [SymbolRecord] = []

    var body: some View {
        Group {
            if symbols.isEmpty && !searchText.isEmpty {
                ContentUnavailableView("No symbols found",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search term"))
            } else if symbols.isEmpty {
                ContentUnavailableView("Search symbols",
                    systemImage: "function",
                    description: Text("Type a name to search the codebase index"))
            } else {
                List(symbols) { symbol in
                    NavigationLink(value: symbol) {
                        SymbolRow(symbol: symbol)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Symbols")
        .searchable(text: $searchText, prompt: "Search symbols...")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("All") { selectedKind = nil }
                    Divider()
                    ForEach(SymbolKind.allCases) { kind in
                        Button {
                            selectedKind = kind.rawValue
                        } label: {
                            Label(kind.rawValue, systemImage: kind.icon)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: selectedKind != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .navigationDestination(for: SymbolRecord.self) { symbol in
            iOSCodeViewerView(symbol: symbol, database: database, sourceProvider: sourceProvider)
        }
        .onChange(of: searchText) { _, _ in performSearch() }
        .onChange(of: selectedKind) { _, _ in performSearch() }
        .task { performSearch() }
    }

    private func performSearch() {
        do {
            symbols = try database.searchSymbols(
                query: searchText.isEmpty ? nil : searchText,
                kind: selectedKind,
                limit: 100
            )
        } catch {
            symbols = []
        }
    }
}
