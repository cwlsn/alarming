import SwiftUI
import WidgetKit

/// Opens the app from Control Center or the Lock Screen.
struct OpenAlarmingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "OpenAlarming") {
            ControlWidgetButton(action: OpenAlarmingIntent()) {
                Label("Alarming", image: "CatClock")
            }
        }
        .displayName("Open Alarming")
        .description("Opens your alarms.")
    }
}
