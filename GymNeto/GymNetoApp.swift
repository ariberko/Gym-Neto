import SwiftUI
import GymNetoKit

@main
struct GymNetoApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if DemoData.isEnabled {
                    DemoRootView()
                } else {
                    HomeView()
                }
            }
            .environmentObject(model)
            .preferredColorScheme(.dark)
            .tint(Theme.work)
            .task {
                if DemoData.isEnabled {
                    model.loadDemo()
                } else {
                    await model.requestAuthorization()
                }
            }
        }
    }
}

/// Opens one screen with demo data (used for screenshots).
struct DemoRootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        switch DemoData.screen {
        case "live":
            NavigationStack {
                if let live = model.watchLive {
                    LiveWorkoutView(snapshot: live, source: .watch)
                        .navigationTitle("Live on Watch")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        case "summary":
            NavigationStack {
                if let record = model.history.first {
                    SummaryView(record: record)
                }
            }
        case "settings":
            SettingsView()
        default:
            HomeView()
        }
    }
}
