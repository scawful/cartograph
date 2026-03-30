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
                    Label("Open Project Index", systemImage: "folder")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                VStack(spacing: CartographTheme.Spacing.sm) {
                    Text("Run `carto ingest <path>` on your Mac first,")
                    Text("then open the .sqlite3 file from")
                    Text("iCloud Drive or Files.")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(CartographTheme.Spacing.xl)
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $appState.showFileImporter,
                allowedContentTypes: [.database, .data, UTType(filenameExtension: "sqlite3") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        appState.openDatabase(at: url)
                    }
                case .failure(let error):
                    appState.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
