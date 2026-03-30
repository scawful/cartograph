import SwiftUI

struct SymbolBrowserView: View {
    let database: CartographDatabase
    @Binding var selectedSymbol: SymbolRecord?

    @State private var searchText = ""
    @State private var selectedKind: String?
    @State private var symbols: [SymbolRecord] = []
    @State private var isSearching = false

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: CartographTheme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search symbols...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit { performSearch() }

                Picker("Kind", selection: Binding(
                    get: { selectedKind ?? "all" },
                    set: { selectedKind = $0 == "all" ? nil : $0 }
                )) {
                    Text("All").tag("all")
                    Divider()
                    ForEach(SymbolKind.allCases) { kind in
                        Label(kind.rawValue, systemImage: kind.icon)
                            .tag(kind.rawValue)
                    }
                }
                .frame(width: 130)
            }
            .padding(CartographTheme.Spacing.md)

            Divider()

            // Results
            if symbols.isEmpty && !searchText.isEmpty {
                ContentUnavailableView("No symbols found",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search term"))
            } else if symbols.isEmpty {
                ContentUnavailableView("Search symbols",
                    systemImage: "function",
                    description: Text("Type a name to search the codebase index"))
            } else {
                List(symbols, selection: $selectedSymbol) { symbol in
                    SymbolRow(symbol: symbol)
                        .tag(symbol)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Symbols")
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

struct SymbolRow: View {
    let symbol: SymbolRecord

    var body: some View {
        HStack(spacing: CartographTheme.Spacing.sm) {
            if let kind = symbol.symbolKind {
                Image(systemName: kind.icon)
                    .foregroundStyle(kind.color)
                    .frame(width: 20)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(symbol.qualifiedName ?? symbol.name)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: CartographTheme.Spacing.xs) {
                    Text(symbol.locationString)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let sig = symbol.signature, !sig.isEmpty {
                        Text(sig)
                            .font(CartographTheme.codeFontSmall)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text("[\(symbol.kind)]")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
