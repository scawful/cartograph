import SwiftUI

@main
struct CartographApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Project Index...") {
                    appState.showOpenPanel()
                }
                .keyboardShortcut("o")
            }
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var database: CartographDatabase?
    @Published var projectStats: ProjectStats?
    @Published var errorMessage: String?

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Select a cartograph.sqlite3 file"
        panel.allowedContentTypes = [.database]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            openDatabase(at: url.path)
        }
    }

    func openDatabase(at path: String) {
        do {
            let db = try CartographDatabase(path: path)
            self.database = db
            self.projectStats = try db.getProjectStats()
            self.errorMessage = nil
        } catch {
            self.errorMessage = "Failed to open database: \(error.localizedDescription)"
        }
    }

    func openProjectRoot(_ root: String) {
        let dbPath = "\(root)/.context/cartograph.sqlite3"
        openDatabase(at: dbPath)
    }
}
