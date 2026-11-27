#!/bin/zsh
# Run: Scripts/screenshots.sh
# Regenerates the README logo and screenshots. Runs the UI tests on a fresh simulator with a clean status bar,
# then copies the screenshots they capture into docs/. Needs the project generated with `xcodegen generate`.
set -euo pipefail

root=${0:A:h:h}
device_type=com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro
runtime=com.apple.CoreSimulator.SimRuntime.iOS-27-2
# Screen width in points over corner radius in points, for iPhone 18 Pro.
screen_corner=0.137
# Width in pixels: twice the size the README shows them.
screen_width=560

# README name, then the name the UI test gives its screenshot.
shots=(
  list A-list
  editor 6-edit-options
  editor-dark C-dark-edit
  quick-add 4-quick
  one-time L-one-time
  day-groups I-day-groups
  sounds 8-tone-menu
)

work=$(mktemp -d)
udid=$(xcrun simctl create readme-screenshots $device_type $runtime)
trap 'xcrun simctl delete "$udid" 2>/dev/null; rm -rf "$work"' EXIT

xcrun simctl bootstatus "$udid" -b > /dev/null
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState discharging --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 --dataNetwork wifi

echo "Running the UI tests to capture screenshots..."
xcodebuild test -quiet -project "$root/Alarming.xcodeproj" -scheme Alarming -destination "id=$udid" \
  -resultBundlePath "$work/run.xcresult" > "$work/xcodebuild.log" 2>&1 || {
  tail -n 40 "$work/xcodebuild.log"
  exit 1
}
xcrun xcresulttool export attachments --path "$work/run.xcresult" --output-path "$work/shots" > /dev/null

mkdir -p "$root/docs/screenshots"
for name capture in $shots; do
  file=$(jq -r --arg capture "$capture" \
    '.[].attachments[] | select(.suggestedHumanReadableName | startswith($capture + "_")) | .exportedFileName' \
    "$work/shots/manifest.json" | head -n 1)
  if [[ -z $file ]]; then
    echo "No screenshot named $capture" >&2
    exit 1
  fi
  swift "$root/Scripts/readme_image.swift" "$work/shots/$file" "$root/docs/screenshots/$name.png" $screen_width $screen_corner
done

# The icon at 256 pixels with the corner of an iOS app icon.
swift "$root/Scripts/readme_image.swift" "$root/Resources/Assets.xcassets/AppIcon.appiconset/icon.png" \
  "$root/docs/logo.png" 256 0.2237
echo "Updated docs/logo.png and docs/screenshots/"
