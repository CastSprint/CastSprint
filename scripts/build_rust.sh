#!/usr/bin/env bash
# build_rust.sh — Unified Build & Verification Pipeline for CastSprint Rust Core & Native Desktop
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=========================================================="
echo " CastSprint Rust Core & Native Desktop Build Pipeline     "
echo " Target Architecture: Core in Rust, Native UI on OS       "
echo "=========================================================="

cd "${ROOT_DIR}"

echo "==> 1. Running Unit & Golden Vector Tests..."
cargo test --offline

echo "==> 2. Running Subsystems Smoke Test..."
cargo run --bin castsprint-desktop -- --smoke-test

echo "==> 3. Building Production Release..."
cargo build --release --offline

echo "==> 4. Artifact Summary:"
DESKTOP_BIN="${ROOT_DIR}/target/release/castsprint-desktop"
FFI_LIB="${ROOT_DIR}/target/release/libcastsprint_ffi.a"

if [ -f "${DESKTOP_BIN}" ]; then
    SIZE=$(ls -lh "${DESKTOP_BIN}" | awk '{print $5}')
    echo "  [OK] Native Desktop Receiver (Win/Linux/Mac): ${DESKTOP_BIN} (${SIZE})"
fi

if [ -f "${FFI_LIB}" ]; then
    SIZE=$(ls -lh "${FFI_LIB}" | awk '{print $5}')
    echo "  [OK] C-ABI Static Library (for Swift Mac/iOS):  ${FFI_LIB} (${SIZE})"
fi

echo "=========================================================="
echo " Build successful! All core logic compiled & verified.    "
echo "=========================================================="
