import Testing
@testable import AlarmingCore

@Test func whiteTextIsReadableAtEveryMinute() {
    for minute in 0..<1440 {
        let sky = SkyPalette(minuteOfDay: minute)
        // Include the blends between stops, which is what actually appears on screen.
        for step in 0...10 {
            let t = Double(step) / 10
            #expect(sky.top.mixed(with: sky.middle, by: t).contrastWithWhite >= 4.5, "\(minute)")
            #expect(sky.middle.mixed(with: sky.horizon, by: t).contrastWithWhite >= 4.5, "\(minute)")
        }
    }
}

@Test func skyIsContinuousThroughMidnight() {
    #expect(SkyPalette(minuteOfDay: 1440) == SkyPalette(minuteOfDay: 0))
    #expect(abs(SkyPalette(minuteOfDay: 1439).top.blue - SkyPalette(minuteOfDay: 0).top.blue) < 0.01)
}
