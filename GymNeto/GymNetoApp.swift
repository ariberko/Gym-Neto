import SwiftUI
import GymNetoKit

@main
struct GymNetoApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Theme.work)
                .task { await model.requestAuthorization() }
        }
    }
}
