# AlarmKit spike

A small app for learning how AlarmKit behaves on a real phone, kept because the answers shape the main app. **Its tests ring out loud.**

## Findings

iPhone 14 Pro, iOS 27.2.1, November 2026.

1. **Snooze works with the app closed.** iOS relaunches the app to run the snooze button's intent. Rings appeared within about two seconds of being due.
2. **Some rings are invisible.** AlarmKit reports the alarm as alerting, but no banner or Stop button appears:

| Ring | Shown |
|---|---|
| Fixed time, Stop only | Yes |
| Countdown, no ring before it, Stop only | Yes |
| Countdown after a snooze, Snooze and Stop | Yes |
| Countdown after a snooze, **Stop only** | **No** (2 of 2 runs) |
| Fixed time after a snooze, Stop only | Yes (1 run) |
| Countdown after a snooze, End and Stop | Yes (2 of 2 runs) |

All three conditions are needed: after a snooze, a countdown, and no second button. The cause inside iOS is unknown. The app uses the last row, which keeps the Live Activity countdown.

3. **Unproven:** whether an invisible ring makes a sound. The tests cannot hear.

## Run

With an unlocked phone and `Config/Local.xcconfig` set up as in the main README:

```sh
cd Spike
xcodegen generate
xcodebuild test -project AlarmingSpike.xcodeproj -scheme AlarmingSpike -destination 'id=<your phone>' -allowProvisioningUpdates
```

Run `testChainWithAppTerminated` once first, to grant alarm permission. The two tests of the invisible ring expect it to be missing, and fail if a later iOS fixes it. If a run is cut short, open the app and tap **Cancel all**.
