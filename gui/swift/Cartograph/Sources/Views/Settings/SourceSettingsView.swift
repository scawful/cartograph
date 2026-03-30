import SwiftUI

struct SourceSettingsView: View {
    @ObservedObject var manager: SourceProviderManager
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            // Provider picker
            Section("Source Provider") {
                Picker("Type", selection: $manager.activeType) {
                    ForEach(SourceProviderType.allCases) { type in
                        Label(type.rawValue, systemImage: type.icon)
                            .tag(type)
                    }
                }
            }

            // Conditional configuration
            switch manager.activeType {
            case .local:
                Section("Local Files") {
                    Text("Source files are read directly from disk.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("This works on macOS where the project root is accessible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .bridge:
                Section("NERV Bridge") {
                    TextField("Server URL", text: $manager.bridgeURL)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                    Text("URL of the Cartograph source server (carto serve)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .github:
                Section("GitHub") {
                    TextField("Owner", text: $manager.githubOwner)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    TextField("Repository", text: $manager.githubRepo)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    TextField("Branch", text: $manager.githubBranch)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    SecureField("Token (optional, for private repos)", text: $manager.githubToken)
                }

            case .gitea:
                Section("Gitea") {
                    TextField("Server URL", text: $manager.giteaURL)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                    TextField("Owner", text: $manager.giteaOwner)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    TextField("Repository", text: $manager.giteaRepo)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    TextField("Branch", text: $manager.giteaBranch)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    SecureField("Token (optional)", text: $manager.giteaToken)
                }
            }

            // Test and Save
            Section {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView()
                                #if os(iOS)
                                .controlSize(.small)
                                #endif
                            Text("Testing...")
                        } else {
                            Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                }
                .disabled(isTesting)

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("OK") ? .green : .red)
                }

                Button {
                    manager.save()
                } label: {
                    Label("Save Settings", systemImage: "checkmark.circle")
                }
            }
        }
        .navigationTitle("Source Provider")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let provider = manager.activeProvider(projectRoot: "")

        Task {
            do {
                // Try to fetch a nonexistent file to verify connectivity
                // A 404 still means the server responded (connection works)
                _ = try await provider.fetchSource(relativePath: "__test_connectivity__")
                testResult = "OK: Connected to \(provider.displayName)"
            } catch let error as SourceProviderError {
                switch error {
                case .fileNotFound:
                    // Server responded with 404 -- connection works
                    testResult = "OK: Connected to \(provider.displayName)"
                case .networkError(let msg):
                    testResult = "Error: \(msg)"
                case .unauthorized:
                    testResult = "Error: Unauthorized -- check your token"
                }
            } catch {
                testResult = "Error: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
