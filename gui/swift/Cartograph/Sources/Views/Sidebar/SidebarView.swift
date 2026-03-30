import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarTab?
    let database: CartographDatabase
    @State private var paths: [ReadingPathRecord] = []

    var body: some View {
        List(selection: $selection) {
            Section("Navigate") {
                Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent")
                    .tag(SidebarTab.dashboard)

                Label("Symbols", systemImage: "function")
                    .tag(SidebarTab.symbols)

                Label("Graph", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(SidebarTab.graph)

                Label("Focus", systemImage: "timer")
                    .tag(SidebarTab.focus)
            }

            if !paths.isEmpty {
                Section("Reading Paths") {
                    ForEach(paths) { path in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(path.name)
                                    .lineLimit(1)
                                Text("\(path.stepCount ?? 0) steps  ~\(String(format: "%.1f", path.hoursEstimate))h")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: pathIcon(for: path.strategy))
                        }
                        .tag(SidebarTab.path(id: path.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Cartograph")
        .task {
            loadPaths()
        }
    }

    private func loadPaths() {
        do {
            paths = try database.listPaths()
        } catch {
            paths = []
        }
    }

    private func pathIcon(for strategy: String) -> String {
        switch strategy {
        case "complexity-ascending": return "chart.bar.xaxis.ascending"
        case "topological": return "arrow.up.right.circle"
        case "entry-first": return "arrow.down.right.circle"
        default: return "list.number"
        }
    }
}
