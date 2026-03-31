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

// MARK: - Project Library Entry

struct ProjectEntry: Codable, Identifiable, Hashable {
    let id: String          // UUID
    let name: String        // project name from DB
    let localFilename: String  // filename in Documents/CartographDBs/
    let addedAt: Date
    var symbolCount: Int
    var fileCount: Int
}

// MARK: - App State with Multi-Project Support

@MainActor
class AppState_iOS: ObservableObject {
    @Published var projects: [ProjectEntry] = []
    @Published var activeProject: ProjectEntry?
    @Published var database: CartographDatabase?
    @Published var projectStats: ProjectStats?
    @Published var errorMessage: String?
    @Published var showFileImporter = false

    private var dbsDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CartographDBs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var libraryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("cartograph_library.json")
    }

    init() {
        loadLibrary()
        // Reopen last active project
        if let lastId = UserDefaults.standard.string(forKey: "lastActiveProjectId"),
           let entry = projects.first(where: { $0.id == lastId }) {
            switchTo(entry)
        }
    }

    // MARK: - Import

    func importDatabase(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            // Read the DB to get the project name
            let tempDB = try CartographDatabase(path: url.path)
            let stats = try tempDB.getProjectStats()
            let projectName = stats?.name ?? url.deletingPathExtension().lastPathComponent

            // Use a unique filename based on project name
            let safeFilename = projectName
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: " ", with: "_")
            let localFilename = "\(safeFilename).sqlite3"
            let localURL = dbsDir.appendingPathComponent(localFilename)

            // Copy (overwrite if same project re-imported)
            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
            try FileManager.default.copyItem(at: url, to: localURL)

            // Create or update library entry
            let entry = ProjectEntry(
                id: projects.first(where: { $0.localFilename == localFilename })?.id ?? UUID().uuidString,
                name: projectName,
                localFilename: localFilename,
                addedAt: Date(),
                symbolCount: stats?.symbolCount ?? 0,
                fileCount: stats?.fileCount ?? 0
            )

            // Remove existing entry with same filename, add new one
            projects.removeAll { $0.localFilename == localFilename }
            projects.append(entry)
            saveLibrary()

            // Switch to it
            switchTo(entry)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to import: \(error.localizedDescription)"
        }
    }

    func importMultiple(from urls: [URL]) {
        for url in urls {
            importDatabase(from: url)
        }
    }

    // MARK: - Switch Project

    func switchTo(_ entry: ProjectEntry) {
        let localURL = dbsDir.appendingPathComponent(entry.localFilename)
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            errorMessage = "Database file missing: \(entry.localFilename)"
            return
        }

        do {
            let db = try CartographDatabase(path: localURL.path)
            self.database = db
            self.projectStats = try db.getProjectStats()
            self.activeProject = entry
            self.errorMessage = nil
            UserDefaults.standard.set(entry.id, forKey: "lastActiveProjectId")
        } catch {
            errorMessage = "Failed to open \(entry.name): \(error.localizedDescription)"
        }
    }

    // MARK: - Remove Project

    func removeProject(_ entry: ProjectEntry) {
        let localURL = dbsDir.appendingPathComponent(entry.localFilename)
        try? FileManager.default.removeItem(at: localURL)
        projects.removeAll { $0.id == entry.id }
        saveLibrary()

        if activeProject?.id == entry.id {
            activeProject = nil
            database = nil
            projectStats = nil
        }
    }

    // MARK: - Persistence

    private func loadLibrary() {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return }
        do {
            let data = try Data(contentsOf: libraryURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            projects = try decoder.decode([ProjectEntry].self, from: data)
        } catch {
            projects = []
        }
    }

    private func saveLibrary() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(projects)
            try data.write(to: libraryURL)
        } catch {
            // Silently fail — not critical
        }
    }
}
