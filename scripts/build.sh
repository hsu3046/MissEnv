#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"
APP_PATH="$TASK_ROOT/build/MissEnv.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH/MissEnv" "$APP_PATH/Contents/MacOS/MissEnv"
cp resources/Info.plist "$APP_PATH/Contents/Info.plist"
cp LICENSE "$APP_PATH/Contents/Resources/LICENSE"
if [ ! -f resources/MissEnv.icns ]; then
    swift scripts/make-icon.swift
    iconutil -c icns work/MissEnv.iconset -o resources/MissEnv.icns
fi
cp resources/MissEnv.icns "$APP_PATH/Contents/Resources/MissEnv.icns"
# Local builds are ad-hoc signed. Sandbox entitlements are reserved for a provisioned distribution build.
codesign --force --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
printf 'Built %s\n' "$APP_PATH"
