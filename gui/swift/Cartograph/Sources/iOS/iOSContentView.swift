import SwiftUI

struct iOSContentView: View {
    @EnvironmentObject var appState: AppState_iOS
    @EnvironmentObject var sourceManager: SourceProviderManager
    @State private var selectedTab = 0

    var body: some View {
        if let db = appState.database {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    DashboardView(database: db)
                        .navigationTitle(appState.projectStats?.name ?? "Dashboard")
                }
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent") }
                .tag(0)

                NavigationStack {
                    iOSSymbolBrowserView(
                        database: db,
                        sourceProvider: sourceManager.activeProvider(
                            projectRoot: appState.projectStats?.rootPath ?? ""
                        )
                    )
                }
                .tabItem { Label("Symbols", systemImage: "function") }
                .tag(1)

                NavigationStack {
                    iOSPathView(database: db)
                }
                .tabItem { Label("Read", systemImage: "book") }
                .tag(2)

                NavigationStack {
                    QuizView(reviewStore: ReviewStore())
                        .navigationTitle("Quiz")
                }
                .tabItem { Label("Quiz", systemImage: "brain.head.profile") }
                .tag(3)

                NavigationStack {
                    SourceSettingsView(manager: sourceManager)
                }
                .tabItem { Label("Source", systemImage: "network") }
                .tag(4)

                NavigationStack {
                    FocusTimerView()
                }
                .tabItem { Label("Focus", systemImage: "timer") }
                .tag(5)
            }
        } else {
            iOSWelcomeView()
        }
    }
}
