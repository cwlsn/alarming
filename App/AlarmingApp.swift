import AlarmKit
import SwiftUI

@main
struct AlarmingApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if Services.isUITesting { UIView.setAnimationsEnabled(false) }
    }

    var body: some Scene {
        WindowGroup {
            AlarmListView(model: Services.model)
                .tint(Color.accentText)
                .preferredColorScheme(Services.forcesDark ? .dark : nil)
                .withoutAnimationsWhenUITesting()
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

extension View {
    /// UI tests wait for animations to settle after every step, so they run without them.
    /// A sheet does not inherit this, so each presented screen applies it again.
    func withoutAnimationsWhenUITesting() -> some View {
        transaction {
            guard Services.isUITesting else { return }
            $0.animation = nil
            $0.disablesAnimations = true
        }
    }
}
