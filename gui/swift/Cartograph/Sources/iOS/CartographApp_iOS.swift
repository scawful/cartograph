import SwiftUI
import UniformTypeIdentifiers

@main
struct CartographApp_iOS: App {
    @StateObject private var appState = AppState_iOS()
    @StateObject private var sourceManager = SourceProviderManager()

    var body: some Scene {
        WindowGroup {
            iOSContentView()
                .environmentObject(appState)
                .environmentObject(sourceManager)
        }
    }
}

@MainActor
class AppState_iOS: ObservableObject {
    @Published var database: CartographDatabase?
    @Published var projectStats: ProjectStats?
    @Published var errorMessage: String?
    @Published var showFileImporter = false

    init() {
        // Try to reopen last database on launch
        if let lastPath = UserDefaults.standard.string(forKey: "lastDatabaseLocalPath") {
            let url = URL(fileURLWithPath: lastPath)
            if FileManager.default.fileExists(atPath: url.path) {
                openLocalDatabase(at: url)
            }
        }
    }

    func openDatabase(at url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            // Copy to app's documents directory for persistent access
            let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let localURL = docDir.appendingPathComponent("cartograph.sqlite3")
            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
            try FileManager.default.copyItem(at: url, to: localURL)

            openLocalDatabase(at: localURL)

            // Remember for next launch
            UserDefaults.standard.set(localURL.path, forKey: "lastDatabaseLocalPath")
        } catch {
            self.errorMessage = "Failed to open database: \(error.localizedDescription)"
        }
    }

    private func openLocalDatabase(at url: URL) {
        do {
            let db = try CartographDatabase(path: url.path)
            self.database = db
            self.projectStats = try db.getProjectStats()
            self.errorMessage = nil
        } catch {
            self.errorMessage = "Failed to open database: \(error.localizedDescription)"
        }
    }
}
