#!/bin/bash
# App Store screenshots, taken from the debug build's screen fixtures
# (`-screen <state>`, see LocalTrivia/Design/ScreenStates.swift), on the two
# display sizes App Store Connect asks for: 6.9" iPhone and 13" iPad. The
# status bar reads 9:41 with full signal and battery, and the iPad runs apps
# full screen, with no window controls.
#
#   scripts/app-store-screenshots.sh [output folder]
#
# The output folder defaults to build/screenshots, one folder per device.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/screenshots}"
BUNDLE=com.stuffbysam.localtrivia
DERIVED=build/screenshots-derived
APP="$DERIVED/Build/Products/Debug-iphonesimulator/LocalTrivia.app"

# Simulator name | device type, created if it doesn't exist yet.
DEVICES=(
  "iPhone 18 Pro Max|com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max"
  "iPad Pro 13-inch (M5)|com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"
)

# File name | seconds to settle | launch arguments. In App Store order.
# A question's clock starts at 0:14 and turns red at 0:10, so questions are
# taken quickly; sheets need longer to slide up.
SHOTS=(
  "01-question|2|-screen question.chosen -chosen 1"
  "02-reveal|3|-screen result.correct"
  "03-host-lobby|3|-screen host.lobby"
  "04-standings|3|-screen standings"
  "05-drafts|4|-screen drafts"
  "06-podium|3|-screen final"
  "07-themes|4|-screen looks"
  "08-question-synthwave|2|-screen question.chosen -chosen 1 -theme synthwave -markers sky"
)

echo "Building the debug app…"
xcodebuild build -quiet -project LocalTrivia.xcodeproj -scheme LocalTrivia -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED"

udid_for() {
  local name="$1" type="$2" udid
  udid=$(xcrun simctl list devices available | grep -F "    $name (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)
  if [[ -z "$udid" ]]; then
    udid=$(xcrun simctl create "$name" "$type")
  fi
  echo "$udid"
}

for device in "${DEVICES[@]}"; do
  name="${device%%|*}"
  udid=$(udid_for "$name" "${device##*|}")
  folder="$OUT/$name"
  mkdir -p "$folder"
  echo "$name ($udid)"

  xcrun simctl bootstatus "$udid" -b > /dev/null
  if [[ "$name" == iPad* ]] && [[ "$(xcrun simctl spawn "$udid" defaults read com.apple.springboard SBMedusaMultitaskingEnabled 2>/dev/null)" != 0 ]]; then
    # Settings → Multitasking & Gestures → Full Screen Apps, which SpringBoard
    # reads when it starts.
    xcrun simctl spawn "$udid" defaults write com.apple.springboard SBMedusaMultitaskingEnabled -bool NO
    xcrun simctl spawn "$udid" defaults write com.apple.springboard SBChamoisWindowingEnabled -bool NO
    xcrun simctl shutdown "$udid"
    xcrun simctl bootstatus "$udid" -b > /dev/null
  fi
  xcrun simctl ui "$udid" appearance dark
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
  xcrun simctl install "$udid" "$APP"
  # A launch over another app shows a way back to it in the status bar; after
  # this one, every launch is over Trivia itself.
  xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" > /dev/null
  sleep 2

  for shot in "${SHOTS[@]}"; do
    IFS='|' read -r file settle arguments <<< "$shot"
    # shellcheck disable=SC2086 # the arguments are meant to split
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" $arguments > /dev/null
    sleep "$settle"
    xcrun simctl io "$udid" screenshot --type=png "$folder/$file.png" > /dev/null 2>&1
    echo "  $file"
  done

  xcrun simctl terminate "$udid" "$BUNDLE" || true
  xcrun simctl status_bar "$udid" clear
done

echo "Saved to $OUT"
