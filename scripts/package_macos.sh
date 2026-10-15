#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MAC_DIR="${ROOT_DIR}/apps/macos/CastSprintMac"
BUILD_DIR="${MAC_DIR}/.build/release"
APP_DIR="${MAC_DIR}/CastSprint.app"
DIST_DIR="${ROOT_DIR}/dist/macos"
VERSION="$(plutil -extract CFBundleShortVersionString raw "${MAC_DIR}/Info.plist")"
BUILD_NUMBER="$(plutil -extract CFBundleVersion raw "${MAC_DIR}/Info.plist")"
DMG_PATH="${DIST_DIR}/CastSprint-v${VERSION}-macOS.dmg"

echo "=========================================================="
echo " CastSprint for macOS — Professional Packaging & Release  "
echo " Version: ${VERSION}                                      "
echo "=========================================================="

echo "==> 1. Building CastSprintMac (Release)..."
cd "${MAC_DIR}"
swift build -c release

echo "==> 2. Assembling CastSprint.app bundle..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/CastSprintMac" "${APP_DIR}/Contents/MacOS/CastSprintMac"
chmod +x "${APP_DIR}/Contents/MacOS/CastSprintMac"
cp "${MAC_DIR}/Info.plist" "${APP_DIR}/Contents/Info.plist"

# Embed an exact, machine-readable build identity. A dirty suffix is deliberate:
# it prevents a locally repaired binary from being mistaken for the HEAD commit.
GIT_COMMIT="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
GIT_DIRTY=""
if [ -n "$(git -C "${ROOT_DIR}" status --porcelain --untracked-files=normal)" ]; then
    GIT_DIRTY="-dirty"
fi
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SWIFT_VERSION="$(swift --version | head -n 1)"
UNSIGNED_EXECUTABLE_SHA256="$(shasum -a 256 "${APP_DIR}/Contents/MacOS/CastSprintMac" | awk '{print $1}')"
BUILD_MANIFEST="${APP_DIR}/Contents/Resources/BuildManifest.plist"
plutil -create xml1 "${BUILD_MANIFEST}"
plutil -insert appVersion -string "${VERSION}" "${BUILD_MANIFEST}"
plutil -insert buildNumber -string "${BUILD_NUMBER}" "${BUILD_MANIFEST}"
plutil -insert configuration -string "release" "${BUILD_MANIFEST}"
plutil -insert gitRevision -string "${GIT_COMMIT}${GIT_DIRTY}" "${BUILD_MANIFEST}"
plutil -insert buildDateUTC -string "${BUILD_DATE}" "${BUILD_MANIFEST}"
plutil -insert unsignedExecutableSHA256 -string "${UNSIGNED_EXECUTABLE_SHA256}" "${BUILD_MANIFEST}"
plutil -insert swiftVersion -string "${SWIFT_VERSION}" "${BUILD_MANIFEST}"

# Copy Metal shaders bundle
if [ -d "${BUILD_DIR}/CastSprintMac_CastSprintMac.bundle" ]; then
    cp -R "${BUILD_DIR}/CastSprintMac_CastSprintMac.bundle" "${APP_DIR}/Contents/Resources/"
fi

# Copy AppIcon.icns
if [ -f "${MAC_DIR}/Resources/AppIcon.icns" ]; then
    cp "${MAC_DIR}/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
elif [ -f "${ROOT_DIR}/assest/logo.png" ]; then
    cp "${ROOT_DIR}/assest/logo.png" "${APP_DIR}/Contents/Resources/AppIcon.png"
fi

echo "==> CastSprint.app bundle successfully created at ${APP_DIR}!"

# Optional Developer ID Code Signing & Hardened Runtime
if [ -n "${CODESIGN_IDENTITY}" ]; then
    echo "==> 3. Signing CastSprint.app with Developer ID (${CODESIGN_IDENTITY}) & Hardened Runtime..."
    codesign --deep --force --options runtime \
        --entitlements "${MAC_DIR}/CastSprintMac.entitlements" \
        --sign "${CODESIGN_IDENTITY}" "${APP_DIR}"
    echo "==> Verifying signature..."
    codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
else
    echo "==> 3. Ad-hoc signing CastSprint.app (CODESIGN_IDENTITY not set)..."
    codesign --force --deep \
        --entitlements "${MAC_DIR}/CastSprintMac.entitlements" \
        --sign - "${APP_DIR}"
fi

# Signing changes Mach-O bytes. Record the exact signed install payload in a
# sidecar manifest so installation can compare byte-for-byte without creating
# a circular dependency between a signed resource and the code signature.
SIGNED_EXECUTABLE_SHA256="$(shasum -a 256 "${APP_DIR}/Contents/MacOS/CastSprintMac" | awk '{print $1}')"
INSTALL_MANIFEST="${DIST_DIR}/CastSprint-v${VERSION}-macOS-build.plist"
mkdir -p "${DIST_DIR}"
plutil -create xml1 "${INSTALL_MANIFEST}"
plutil -insert appVersion -string "${VERSION}" "${INSTALL_MANIFEST}"
plutil -insert buildNumber -string "${BUILD_NUMBER}" "${INSTALL_MANIFEST}"
plutil -insert configuration -string "release" "${INSTALL_MANIFEST}"
plutil -insert gitRevision -string "${GIT_COMMIT}${GIT_DIRTY}" "${INSTALL_MANIFEST}"
plutil -insert buildDateUTC -string "${BUILD_DATE}" "${INSTALL_MANIFEST}"
plutil -insert signedExecutableSHA256 -string "${SIGNED_EXECUTABLE_SHA256}" "${INSTALL_MANIFEST}"
plutil -insert swiftVersion -string "${SWIFT_VERSION}" "${INSTALL_MANIFEST}"

echo "==> 4. Generating professional DMG disk image..."
mkdir -p "${DIST_DIR}"
DMG_TEMP="${DIST_DIR}/dmg_temp"
rm -rf "${DMG_TEMP}" "${DMG_PATH}"
mkdir -p "${DMG_TEMP}"

cp -R "${APP_DIR}" "${DMG_TEMP}/"
ln -s /Applications "${DMG_TEMP}/Applications"

hdiutil create -volname "CastSprint" \
    -srcfolder "${DMG_TEMP}" \
    -ov -format UDZO \
    "${DMG_PATH}"

rm -rf "${DMG_TEMP}"

echo "==> 5. Computing SHA-256 Checksums..."
shasum -a 256 "${DMG_PATH}" > "${DMG_PATH}.sha256"
cat "${DMG_PATH}.sha256"

echo "=========================================================="
echo " CastSprint macOS distribution package ready!             "
echo " DMG: ${DMG_PATH}                                         "
echo " Checksum: ${DMG_PATH}.sha256                             "
echo "=========================================================="
