#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/liquid_productivity_design_system/captures"}"
APP_NAME="Nexus"
WORKSPACE="$ROOT_DIR/Nexus.xcworkspace"
SCHEME="NexusMac"
CONFIGURATION="Debug"
WINDOW_LEFT=80
WINDOW_TOP=80
WINDOW_WIDTH=1448
WINDOW_HEIGHT=1086

mkdir -p "$OUT_DIR"

echo "Building $SCHEME ($CONFIGURATION)..."
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  build >/dev/null

TARGET_BUILD_DIR="$(
  xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null |
    awk -F'= ' '/ TARGET_BUILD_DIR = / { value=$2 } END { print value }'
)"
APP_PATH="$TARGET_BUILD_DIR/$APP_NAME.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/$APP_NAME"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle not found: $APP_PATH" >&2
  exit 1
fi
if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Expected executable not found: $APP_EXECUTABLE" >&2
  exit 1
fi

echo "Launching $APP_EXECUTABLE with reference fixtures"
pkill -x "$APP_NAME" 2>/dev/null || true
NEXUS_LIQUID_REFERENCE_DATA=1 "$APP_EXECUTABLE" --liquid-reference-data &
APP_PID=$!
trap 'kill "$APP_PID" 2>/dev/null || true' EXIT

sleep 2

set_window_bounds() {
  osascript <<APPLESCRIPT >/dev/null
tell application "System Events"
  tell process "$APP_NAME"
    set frontmost to true
    set position of window 1 to {$WINDOW_LEFT, $WINDOW_TOP}
    set size of window 1 to {$WINDOW_WIDTH, $WINDOW_HEIGHT}
  end tell
end tell
APPLESCRIPT
}

front_window_id() {
  osascript <<APPLESCRIPT
tell application "System Events"
  tell process "$APP_NAME"
    return id of window 1
  end tell
end tell
APPLESCRIPT
}

capture_step() {
  local slug="$1"
  local label="$2"
  local output="$OUT_DIR/$slug.png"

  echo
  echo "Navigate to: $label"
  read -r -p "Press Enter when the $label screen is ready..."
  set_window_bounds
  sleep 0.4

  local window_id
  window_id="$(front_window_id | tr -d '\r')"
  if [[ -n "$window_id" ]] && screencapture -x -o -l "$window_id" "$output"; then
    echo "Captured $output"
  else
    echo "Window capture failed; falling back to full-screen capture."
    screencapture -x "$output"
    echo "Captured $output"
  fi
}

set_window_bounds
capture_step "01_today_dashboard" "Today"
capture_step "02_calendar_week" "Calendar Week"
capture_step "03_projects_execution" "Projects Execution"
capture_step "04_meetings_notes" "Meetings Notes"

echo
echo "Reference captures written to $OUT_DIR"
