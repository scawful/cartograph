import SwiftUI
import UniformTypeIdentifiers

struct ProjectLibraryView: View {
    @EnvironmentObject var appState: AppState_iOS
    @Environment(\.dismiss) private var dismiss
    @State private var showFileImporter = false

    var body: some View {
        NavigationStack {
            List {
                if appState.projects.isEmpty {
                    ContentUnavailableView(
                        "No Projects",
                        systemImage: "map",
                        description: Text("Import a cartograph.sqlite3 file to get started")
                    )
                } else {
                    ForEach(appState.projects) { project in
                        Button {
                            appState.switchTo(project)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(project.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        if project.id == appState.activeProject?.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                                .font(.caption)
                                        }
                                    }
                                    HStack(spacing: CartographTheme.Spacing.md) {
                                        Label("\(project.symbolCount)", systemImage: "function")
                                        Label("\(project.fileCount)", systemImage: "doc")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            appState.removeProject(appState.projects[idx])
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Import", systemImage: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
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
