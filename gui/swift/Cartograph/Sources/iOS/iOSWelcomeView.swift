import SwiftUI
import UniformTypeIdentifiers

struct iOSWelcomeView: View {
    @EnvironmentObject var appState: AppState_iOS

    var body: some View {
        NavigationStack {
            VStack(spacing: CartographTheme.Spacing.xl) {
                Spacer()

                Image(systemName: "map")
                    .font(.system(size: 72))
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
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    appState.showFileImporter = true
                } label: {
                    Label("Import Projects", systemImage: "folder.badge.plus")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                // Show previously imported projects
                if !appState.projects.isEmpty {
                    VStack(alignment: .leading, spacing: CartographTheme.Spacing.sm) {
                        Text("Recent Projects")
                            .font(.headline)
                            .padding(.top)

                        ForEach(appState.projects) { project in
                            Button {
                                appState.switchTo(project)
                            } label: {
                                HStack {
                                    Image(systemName: "map")
                                        .foregroundStyle(.tint)
                                    VStack(alignment: .leading) {
                                        Text(project.name)
                                            .font(.body)
                                        Text("\(project.symbolCount) symbols")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(CartographTheme.Spacing.sm)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: CartographTheme.Radius.md))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    VStack(spacing: CartographTheme.Spacing.sm) {
                        Text("Run `carto ingest <path>` on your Mac,")
                        Text("then select one or more .sqlite3 files")
                        Text("from iCloud Drive or Files.")
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(CartographTheme.Spacing.xl)
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $appState.showFileImporter,
                allowedContentTypes: [.database, .data, UTType(filenameExtension: "sqlite3") ?? .data],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    appState.importMultiple(from: urls)
                case .failure(let error):
                    appState.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
