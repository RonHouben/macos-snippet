#!/bin/zsh
set -e

SCHEME="snippingToolHost"
APP_NAME="snippingTool"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"

echo "Building $SCHEME..."
xcodebuild build -scheme "$SCHEME" -destination 'platform=macOS' -configuration Debug -quiet

APP_PATH=$(find "$DERIVED_DATA" -path "*/$SCHEME-*/Build/Products/Debug/$APP_NAME.app" -maxdepth 5 2>/dev/null | head -1)

if [[ -z "$APP_PATH" ]]; then
  echo "Error: Could not find $APP_NAME.app in DerivedData"
  exit 1
fi

# Quit existing instance if running
pkill -x "$APP_NAME" 2>/dev/null && sleep 0.5 || true

echo "Launching $APP_PATH"
open "$APP_PATH"

cleanup() {
  echo "\nStopping $APP_NAME..."
  pkill -x "$APP_NAME" 2>/dev/null || true
  exit 0
}
trap cleanup INT TERM

echo "Press Ctrl+C to quit"
while kill -0 $(pgrep -x "$APP_NAME") 2>/dev/null; do
  sleep 1
done
