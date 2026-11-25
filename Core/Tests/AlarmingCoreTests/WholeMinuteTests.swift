import Foundation
import Testing
@testable import AlarmingCore

/// https://github.com/cwlsn/alarming/issues/1
@Suite struct WholeMinuteTests {
    private static let styles: [SnoozePolicy.Style] =
        [.constant] + (1...15).map { .subtract(minutes: $0) } + SnoozePolicy.Fraction.allCases.map { .multiply($0) }

    @Test(arguments: styles)
    func everySnoozeAndRingIsAWholeMinute(style: SnoozePolicy.Style) throws {
        let start = Date(timeIntervalSince1970: 1_795_600_800)
        for first in 1...30 {
            for limit in [nil, 1, 2, 3, 5, 10] as [Int?] {
                let policy = SnoozePolicy(firstMinutes: first, style: style, limit: limit)
                for seconds in policy.intervals ?? [] { #expect(seconds % 60 == 0 && seconds >= 60) }
                for ring in policy.ringTimes(from: start) ?? [] { #expect(Int(ring.timeIntervalSince1970) % 60 == 0) }
                #expect(policy.summary.firstMatch(of: /\d+s\b/) == nil)
            }
        }
    }

    @Test func unevenDivisionTakesTheNextMinute() {
        func minutes(_ first: Int, _ fraction: SnoozePolicy.Fraction) -> [Int]? {
            SnoozePolicy(firstMinutes: first, style: .multiply(fraction)).intervals?.map { $0 / 60 }
        }
        #expect(minutes(15, .half) == [15, 8, 4, 2])
        #expect(minutes(10, .half) == [10, 5, 3, 2])
        #expect(minutes(10, .third) == [10, 4, 2])
    }

    @Test(arguments: ["en_US", "en_GB", "de_DE", "fr_CA", "ja_JP"])
    func timesAreShownWithoutSeconds(locale: String) throws {
        let zone = TimeZone(identifier: "America/New_York")!
        for offset in [0, 1, 30, 59, 45_296] {
            let text = ClockText.string(Date(timeIntervalSince1970: 1_795_600_800 + Double(offset)), locale: Locale(identifier: locale), timeZone: zone)
            #expect(text.matches(of: /\d+/).count == 2, "\(text)")
        }
    }
}
