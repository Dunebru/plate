#!/usr/bin/env bash
# Builds Plate and installs it on a connected iPhone.
#   usage: scripts/install-device.sh <TEAM_ID> [device name or UDID]
# Needs Xcode with your Apple ID signed in, or set the App Store Connect key variables
# ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID to let xcodebuild manage provisioning itself.
set -euo pipefail
cd "$(dirname "$0")/.."
TEAM="${1:?team id}"
DEVICE="${2:-}"
command -v xcodegen >/dev/null && xcodegen generate >/dev/null
if [ -z "$DEVICE" ]; then
  DEVICE="$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone.*connected/ {print $1; exit}')"
  [ -n "$DEVICE" ] || { echo "No connected iPhone found. Plug it in, unlock it, and trust this Mac."; exit 1; }
fi
AUTH=()
if [ -n "${ASC_KEY_PATH:-}" ]; then
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi
xcodebuild -project Plate.xcodeproj -scheme Plate -configuration Release \
  -destination "generic/platform=iOS" -derivedDataPath build \
  DEVELOPMENT_TEAM="$TEAM" -allowProvisioningUpdates "${AUTH[@]}" build | grep -E "error:|BUILD"
xcrun devicectl device install app --device "$DEVICE" build/Build/Products/Release-iphoneos/Plate.app
echo "Installed. On the phone: Settings > General > VPN & Device Management, trust the developer app if asked."
