# AlarmKit on a real phone

What a small test app showed about AlarmKit, kept because the answers shape this app. The test app itself was removed once it had answered them.

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

## Check again after an iOS update

If a later iOS shows the invisible ring, the second button on the last ring can go (`needsEndButton` in `Core`).

The test app and its tests are in git history, in the `Spike` folder. They need an unlocked phone and **ring out loud**:

```sh
git checkout 3b057e7 -- Spike
```

Its README explains how to run it. Remove it again with `git rm -rf Spike`.
