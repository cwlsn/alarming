import AlarmKit
import SwiftUI

@main
struct AlarmingApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AlarmListView(model: Services.model)
                .tint(Color.accentText)
                .preferredColorScheme(Services.forcesDark ? .dark : nil)
                .task {
                    #if DEBUG
                    if Services.isSeeded { await Services.seed() }
                    #endif
                    guard !Services.isUITesting else { return }
                    for await _ in AlarmManager.shared.alarmUpdates { try? await Services.model.reconcile() }
                }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { Task { try? await Services.model.reconcile() } }
        }
    }
}
