#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.derived-data}"
APP_NAME="snippingTool.app"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-Release}"
DESTINATION_PATH="${1:-/Applications/$APP_NAME}"
BUILD_APP_PATH="$DERIVED_DATA_PATH/Build/Products/$BUILD_CONFIGURATION/$APP_NAME"
EXECUTABLE_PATH="$DESTINATION_PATH/Contents/MacOS/snippingTool"
TEMP_INSTALL_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/snippingTool-install.XXXXXX")"
STAGED_APP_PATH="$TEMP_INSTALL_ROOT/$APP_NAME"
XCODEBUILD_ARGS=(
  -scheme snippingToolHost
  -configuration "$BUILD_CONFIGURATION"
  -destination 'platform=macOS'
  -derivedDataPath "$DERIVED_DATA_PATH"
)

cleanup() {
  rm -rf "$TEMP_INSTALL_ROOT"
}

trap cleanup EXIT

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  XCODEBUILD_ARGS+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
fi

if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  XCODEBUILD_ARGS+=("CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY")
fi

echo "Building $APP_NAME ($BUILD_CONFIGURATION)..."
xcodebuild build "${XCODEBUILD_ARGS[@]}"

if [[ ! -d "$BUILD_APP_PATH" ]]; then
  echo "Built app not found at $BUILD_APP_PATH" >&2
  exit 1
fi

SIGNATURE_DETAILS="$(
  /usr/bin/codesign -dvv "$BUILD_APP_PATH" 2>&1 || true
)"
TEAM_IDENTIFIER="$(printf '%s\n' "$SIGNATURE_DETAILS" | sed -n 's/^TeamIdentifier=//p' | head -n1)"

if [[ -z "$TEAM_IDENTIFIER" || "$TEAM_IDENTIFIER" == "not set" ]]; then
  cat >&2 <<EOF
Refusing to install an ad hoc signed release build.

macOS TCC permission retention requires a stable signing identity. The built app at:
  $BUILD_APP_PATH

does not have a TeamIdentifier, so updates will continue to lose Screen Recording and Accessibility permissions.

Fix this by building with a real signing team, for example:
  DEVELOPMENT_TEAM=YOURTEAMID ./scripts/install-release.sh

If you distribute outside Xcode, prefer a Developer ID Application certificate for release installs.
EOF
  exit 1
fi

echo "Verified signing team: $TEAM_IDENTIFIER"

SOURCE_SHA="$(shasum -a 256 "$BUILD_APP_PATH/Contents/MacOS/snippingTool" | awk '{print $1}')"

RUNNING_PIDS="$(
  ps -axo pid=,args= | awk -v executable="$EXECUTABLE_PATH" '$0 ~ executable { print $1 }'
)"

if [[ -n "$RUNNING_PIDS" ]]; then
  echo "Stopping running app..."
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill "$pid" 2>/dev/null || true
  done <<< "$RUNNING_PIDS"
fi

echo "Staging app bundle..."
/usr/bin/ditto "$BUILD_APP_PATH" "$STAGED_APP_PATH"

STAGED_SHA="$(shasum -a 256 "$STAGED_APP_PATH/Contents/MacOS/snippingTool" | awk '{print $1}')"

if [[ "$SOURCE_SHA" != "$STAGED_SHA" ]]; then
  echo "Staged app binary does not match the built app binary." >&2
  exit 1
fi

echo "Installing to $DESTINATION_PATH..."
rm -rf "$DESTINATION_PATH"
mv "$STAGED_APP_PATH" "$DESTINATION_PATH"

DESTINATION_SHA="$(shasum -a 256 "$DESTINATION_PATH/Contents/MacOS/snippingTool" | awk '{print $1}')"

if [[ "$SOURCE_SHA" != "$DESTINATION_SHA" ]]; then
  echo "Installed app binary does not match the built app binary." >&2
  exit 1
fi

echo "Installed $APP_NAME to $DESTINATION_PATH"
echo "For TCC permission retention, keep using the same destination path and signing identity for future updates."

echo "Launching updated app..."
open "$DESTINATION_PATH"
