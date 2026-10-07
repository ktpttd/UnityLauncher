#!/bin/sh
# Installs or updates Unity Launcher from the latest GitHub release:
#   curl -fsSL https://raw.githubusercontent.com/ktpttd/UnityLauncher/main/scripts/install.sh | bash
# The app is ad-hoc signed, not notarized.
set -eu
URL="${UNITY_LAUNCHER_ZIP:-https://github.com/ktpttd/UnityLauncher/releases/latest/download/UnityLauncher.zip}"
DEST="${UNITY_LAUNCHER_DEST:-/Applications}"
[ -w "$DEST" ] || DEST="$HOME/Applications"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "Downloading $URL"
curl -fsSL "$URL" -o "$TMP/UnityLauncher.zip"
ditto -x -k "$TMP/UnityLauncher.zip" "$TMP"
[ -d "$TMP/UnityLauncher.app" ] || { echo "The download has no UnityLauncher.app."; exit 1; }

pkill -x UnityLauncher 2>/dev/null || true
mkdir -p "$DEST"
rm -rf "$DEST/UnityLauncher.app"
ditto "$TMP/UnityLauncher.app" "$DEST/UnityLauncher.app"
echo "Installed $DEST/UnityLauncher.app"

[ -x "$HOME/.unity/bin/unity" ] || command -v unity >/dev/null 2>&1 || echo "It needs the Unity CLI:
  curl -fsSL https://public-cdn.cloud.unity3d.com/hub/prod/cli/install.sh | UNITY_CLI_CHANNEL=beta bash"
[ "${UNITY_LAUNCHER_NO_OPEN:-0}" = 1 ] || open "$DEST/UnityLauncher.app"
