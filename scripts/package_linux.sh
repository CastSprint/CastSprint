#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist/linux"
PKG_NAME="CastSprint-v0.2.0-Linux-x86_64"
PKG_DIR="${DIST_DIR}/${PKG_NAME}"
TAR_PATH="${DIST_DIR}/${PKG_NAME}.tar.gz"

echo "=========================================================="
echo " CastSprint for Linux — Automated Packaging & Release     "
echo " Version: 0.2.0                                           "
echo "=========================================================="

echo "==> 1. Configuring CMake (Release)..."
cmake -S "${ROOT_DIR}" -B "${ROOT_DIR}/build" -DCMAKE_BUILD_TYPE=Release

echo "==> 2. Building CastSprint Linux Receiver..."
cmake --build "${ROOT_DIR}/build" --target castsprint_receiver_linux --parallel

echo "==> 3. Running Smoke Test..."
"${ROOT_DIR}/build/apps/linux/castsprint_receiver_linux" --smoke-test

echo "==> 4. Assembling Linux Package Directory..."
rm -rf "${PKG_DIR}" "${TAR_PATH}"
mkdir -p "${PKG_DIR}/bin"
mkdir -p "${PKG_DIR}/share/applications"
mkdir -p "${PKG_DIR}/share/icons/hicolor/256x256/apps"
mkdir -p "${PKG_DIR}/docs"

cp "${ROOT_DIR}/build/apps/linux/castsprint_receiver_linux" "${PKG_DIR}/bin/"
chmod +x "${PKG_DIR}/bin/castsprint_receiver_linux"
cp "${ROOT_DIR}/apps/linux/castsprint.desktop" "${PKG_DIR}/share/applications/"
cp "${ROOT_DIR}/assest/logo.png" "${PKG_DIR}/share/icons/hicolor/256x256/apps/castsprint.png"
cp "${ROOT_DIR}/README.md" "${ROOT_DIR}/LICENSE" "${PKG_DIR}/"
cp "${ROOT_DIR}/docs/OBS_GUIDE.md" "${ROOT_DIR}/docs/USB_CONNECTION.md" "${ROOT_DIR}/docs/WIFI_CONNECTION.md" "${ROOT_DIR}/docs/TROUBLESHOOTING.md" "${PKG_DIR}/docs/"

echo "==> 5. Creating Tarball..."
tar -czvf "${TAR_PATH}" -C "${DIST_DIR}" "${PKG_NAME}"

echo "==> 6. Generating SHA-256..."
sha256sum "${TAR_PATH}" > "${TAR_PATH}.sha256"
cat "${TAR_PATH}.sha256"

echo "=========================================================="
echo " CastSprint Linux distribution package ready!             "
echo " Archive: ${TAR_PATH}                                     "
echo "=========================================================="
