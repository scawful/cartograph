import SwiftUI

struct DashboardView: View {
    let database: CartographDatabase

    @State private var stats: ProjectStats?
    @State private var activeSession: SessionRecord?
    @State private var paths: [ReadingPathRecord] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CartographTheme.Spacing.xl) {

                // Active session card
                if let session = activeSession {
                    GroupBox {
                        VStack(alignment: .leading, spacing: CartographTheme.Spacing.sm) {
                            Label("Continue Reading", systemImage: "bookmark.fill")
                                .font(.headline)

                            Text(session.pathName ?? "Reading Path")
                                .font(.title3)

                            ProgressView(value: session.progressPercent / 100.0) {
                                Text("Step \(session.currentStep) of \(session.totalSteps ?? 0)")
                                    .font(.caption)
                            }

                            Text("\(String(format: "%.0f", session.progressPercent))% complete")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(CartographTheme.Spacing.sm)
                    }
                }

                // Stats
                if let stats = stats {
                    Text("Project Index")
                        .font(.headline)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: CartographTheme.Spacing.md) {
                        StatsCard(title: "Files", value: "\(stats.fileCount)", icon: "doc")
                        StatsCard(title: "Symbols", value: "\(stats.symbolCount)", icon: "function")
                        StatsCard(title: "Cross-refs", value: "\(stats.xrefCount)", icon: "arrow.triangle.branch")
                    }

                    if !stats.symbolsByKind.isEmpty {
                        Text("Symbols by Kind")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                        ], spacing: CartographTheme.Spacing.sm) {
                            ForEach(stats.symbolsByKind.sorted(by: { $0.value > $1.value }), id: \.key) { kind, count in
                                HStack {
                                    if let sk = SymbolKind(rawValue: kind) {
                                        Image(systemName: sk.icon)
                                            .foregroundStyle(sk.color)
                                    }
                                    Text(kind)
                                        .font(.caption)
                                    Spacer()
                                    Text("\(count)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // Reading paths
                if !paths.isEmpty {
                    Text("Reading Paths")
                        .font(.headline)

                    ForEach(paths) { path in
                        GroupBox {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(path.name)
                                        .font(.body)
                                    Text("\(path.stepCount ?? 0) steps  ~\(String(format: "%.1f", path.hoursEstimate))h  [\(path.strategy)]")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(CartographTheme.Spacing.xl)
        }
        .navigationTitle("Dashboard")
        .task {
            loadData()
        }
    }

    private func loadData() {
        stats = try? database.getProjectStats()
        activeSession = try? database.getActiveSession()
        paths = (try? database.listPaths()) ?? []
    }
}

struct StatsCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        GroupBox {
            VStack(spacing: CartographTheme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(value)
                    .font(.title2.monospacedDigit().bold())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(CartographTheme.Spacing.sm)
        }
    }
}
