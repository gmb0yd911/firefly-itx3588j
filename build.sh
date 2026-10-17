#!/usr/bin/env bash
# ==============================================================================
# build.sh - End-to-end master build script for Omarchy on Firefly ITX-3588J
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
IMG_BASE="archlinuxarm-firefly-itx3588j-btrfs.img"
IMG_PATH="${SCRIPT_DIR}/${IMG_BASE}"
WITH_AUR="${1:-false}"

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (or with sudo)." >&2
  exit 1
fi

echo "===================================================================="
echo " Omarchy Master Build Pipeline: Firefly ITX-3588J"
echo " Target Image: ${IMG_PATH}"
echo " Output Dir:   ${OUTPUT_DIR}"
echo " With AUR:     ${WITH_AUR}"
echo "===================================================================="

mkdir -p "${OUTPUT_DIR}"

# Step 1: Build base Arch Linux ARM image with Btrfs & Rockchip BSP
echo ">>> [Step 1/4] Building Base Arch Linux ARM Btrfs Image..."
"${SCRIPT_DIR}/build-base-image.sh"

# Step 2: Apply Omarchy Desktop environment and configurations
echo ">>> [Step 2/4] Provisioning Omarchy Desktop Suite..."
"${SCRIPT_DIR}/apply-omarchy.sh" "${IMG_PATH}" "/mnt/firefly_build" "${WITH_AUR}"

# Step 3: Move image to output directory and compute checksum
echo ">>> [Step 3/4] Generating SHA256 Checksum..."
mv "${IMG_PATH}" "${OUTPUT_DIR}/${IMG_BASE}"
cd "${OUTPUT_DIR}"
sha256sum "${IMG_BASE}" > "${IMG_BASE}.sha256"

# Step 4: Compress with zstd
echo ">>> [Step 4/4] Compressing image with zstd (3 threads)..."
zstd -3 -T3 --rm -f "${IMG_BASE}" -o "${IMG_BASE}.zst"
sha256sum "${IMG_BASE}.zst" > "${IMG_BASE}.zst.sha256"

echo "===================================================================="
echo " Master Build Complete!"
echo " Artifacts in: ${OUTPUT_DIR}/"
ls -lh "${OUTPUT_DIR}/"
echo "===================================================================="
