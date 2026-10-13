#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MAC_DIR="${ROOT_DIR}/apps/macos/CastSprintMac"
BUILD_DIR="${MAC_DIR}/.build/release"
APP_DIR="${MAC_DIR}/CastSprint.app"

echo "==> Building CastSprint for macOS (Release)..."
cd "${MAC_DIR}"
swift build -c release

echo "==> Packaging CastSprint.app bundle..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/CastSprintMac" "${APP_DIR}/Contents/MacOS/CastSprintMac"
cp "${MAC_DIR}/Info.plist" "${APP_DIR}/Contents/Info.plist"

# Copy metal shaders / resources if present
if [ -d "${BUILD_DIR}/CastSprintMac_CastSprintMac.bundle" ]; then
    cp -R "${BUILD_DIR}/CastSprintMac_CastSprintMac.bundle" "${APP_DIR}/Contents/Resources/"
fi

# Copy CastSprint logo
if [ -f "${ROOT_DIR}/assest/logo.png" ]; then
    cp "${ROOT_DIR}/assest/logo.png" "${APP_DIR}/Contents/Resources/AppIcon.png"
fi

echo "==> Successfully packaged ${APP_DIR}!"
