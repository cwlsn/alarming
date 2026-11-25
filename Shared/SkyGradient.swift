import AlarmingCore
import SwiftUI

extension Color {
    init(_ rgb: SkyPalette.RGB) { self.init(red: rgb.red, green: rgb.green, blue: rgb.blue) }

    /// Accent behind white text and for controls. 4.5:1 against white.
    static let accentFill = Color(red: 0.15, green: 0.39, blue: 0.92)
    /// Accent on the black and glass surfaces iOS draws alarms on.
    static let accentBright = Color(red: 0.36, green: 0.62, blue: 1)
}

/// Still sky, for list rows and the widget.
struct SkyGradient: View {
    let minute: Int

    var body: some View {
        let sky = SkyPalette(minuteOfDay: minute)
        LinearGradient(colors: [Color(sky.top), Color(sky.middle), Color(sky.horizon)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
