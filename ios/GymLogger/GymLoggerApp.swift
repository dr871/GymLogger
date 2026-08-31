import SwiftUI

@main
struct GymLoggerApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await store.refreshNotificationStatus() }
            default:
                // Never rely on the debounce surviving a suspend.
                store.saveNow()
            }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "figure.strengthtraining.traditional") }
            HistoryView()
                .tabItem { Label("History", systemImage: "list.bullet") }
            ProgressTab()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
