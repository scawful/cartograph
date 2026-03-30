import SwiftUI

// MARK: - Provider Types

enum SourceProviderType: String, CaseIterable, Identifiable {
    case local = "Local Files"
    case bridge = "NERV Bridge"
    case github = "GitHub"
    case gitea = "Gitea"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .local: return "internaldrive"
        case .bridge: return "network"
        case .github: return "globe"
        case .gitea: return "server.rack"
        }
    }
}

// MARK: - Source Provider Manager

@MainActor
class SourceProviderManager: ObservableObject {
    @Published var activeType: SourceProviderType
    @Published var bridgeURL: String
    @Published var githubOwner: String
    @Published var githubRepo: String
    @Published var githubBranch: String
    @Published var githubToken: String
    @Published var giteaURL: String
    @Published var giteaOwner: String
    @Published var giteaRepo: String
    @Published var giteaBranch: String
    @Published var giteaToken: String

    init() {
        let defaults = UserDefaults.standard
        self.activeType = SourceProviderType(rawValue: defaults.string(forKey: "source.providerType") ?? "") ?? .local
        self.bridgeURL = defaults.string(forKey: "source.bridgeURL") ?? "http://localhost:11443"
        self.githubOwner = defaults.string(forKey: "source.github.owner") ?? ""
        self.githubRepo = defaults.string(forKey: "source.github.repo") ?? ""
        self.githubBranch = defaults.string(forKey: "source.github.branch") ?? "main"
        self.githubToken = defaults.string(forKey: "source.github.token") ?? ""
        self.giteaURL = defaults.string(forKey: "source.gitea.url") ?? "https://org.halext.org"
        self.giteaOwner = defaults.string(forKey: "source.gitea.owner") ?? ""
        self.giteaRepo = defaults.string(forKey: "source.gitea.repo") ?? ""
        self.giteaBranch = defaults.string(forKey: "source.gitea.branch") ?? "main"
        self.giteaToken = defaults.string(forKey: "source.gitea.token") ?? ""
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(activeType.rawValue, forKey: "source.providerType")
        defaults.set(bridgeURL, forKey: "source.bridgeURL")
        defaults.set(githubOwner, forKey: "source.github.owner")
        defaults.set(githubRepo, forKey: "source.github.repo")
        defaults.set(githubBranch, forKey: "source.github.branch")
        defaults.set(githubToken, forKey: "source.github.token")
        defaults.set(giteaURL, forKey: "source.gitea.url")
        defaults.set(giteaOwner, forKey: "source.gitea.owner")
        defaults.set(giteaRepo, forKey: "source.gitea.repo")
        defaults.set(giteaBranch, forKey: "source.gitea.branch")
        defaults.set(giteaToken, forKey: "source.gitea.token")
    }

    func activeProvider(projectRoot: String) -> SourceProvider {
        switch activeType {
        case .local:
            return LocalSourceProvider(projectRoot: projectRoot)
        case .bridge:
            return BridgeSourceProvider(baseURL: bridgeURL)
        case .github:
            return GitHubSourceProvider(
                owner: githubOwner,
                repo: githubRepo,
                branch: githubBranch,
                token: githubToken.isEmpty ? nil : githubToken
            )
        case .gitea:
            return GiteaSourceProvider(
                baseURL: giteaURL,
                owner: giteaOwner,
                repo: giteaRepo,
                branch: giteaBranch,
                token: giteaToken.isEmpty ? nil : giteaToken
            )
        }
    }
}
