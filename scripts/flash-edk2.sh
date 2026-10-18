#!/usr/bin/env bash
# ==============================================================================
# flash-edk2.sh
# Flash official EDK2 UEFI firmware to the Firefly ITX-3588J (eMMC /dev/mmcblk0)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(dirname "${SCRIPT_DIR}")"
CACHE_DIR="${WORK_DIR}/cache/edk2"
FIRMWARE_IMG="${CACHE_DIR}/itx-3588j_UEFI_Release_v1.1.img"
FIRMWARE_URL="https://github.com/edk2-porting/edk2-rk3588/releases/download/v1.1/itx-3588j_UEFI_Release_v1.1.img"

SSH_TARGET="${1:-firefly}"
TARGET_DEV="${2:-/dev/mmcblk0}"

echo "===================================================================="
echo " Firefly ITX-3588J EDK2 UEFI Firmware Flasher"
echo " Host:           ${SSH_TARGET}"
echo " Firmware Image: ${FIRMWARE_IMG}"
echo " Target Device:  ${TARGET_DEV}"
echo "===================================================================="

# 1. Download firmware if missing
if [[ ! -f "${FIRMWARE_IMG}" ]]; then
  echo "Downloading official EDK2 UEFI firmware (v1.1)..."
  mkdir -p "${CACHE_DIR}"
  curl -L -o "${FIRMWARE_IMG}" "${FIRMWARE_URL}"
fi

# 2. Check SSH connection
echo "Checking connection to ${SSH_TARGET}..."
ssh -o ConnectTimeout=5 "${SSH_TARGET}" "hostname && uname -a"

echo ""
echo "WARNING: Writing EDK2 UEFI to ${TARGET_DEV} on ${SSH_TARGET} will replace"
echo "the existing bootloader / OS on that device with EDK2 UEFI BIOS."
echo "Press Ctrl+C within 5 seconds to cancel, or wait to continue..."
sleep 5

echo "Streaming EDK2 UEFI image to ${TARGET_DEV}..."
cat "${FIRMWARE_IMG}" | ssh "${SSH_TARGET}" "sudo dd of=${TARGET_DEV} bs=4M status=progress conv=fsync"

echo ""
echo "===================================================================="
echo " EDK2 UEFI Flashing Complete!"
echo "===================================================================="
echo "Next Steps:"
echo "1. Connect keyboard and HDMI display to HDMI Output 1 (top port)."
echo "2. Reboot the board."
echo "3. Press ESC or F2 immediately during power-on to enter UEFI Setup."
echo "4. In UEFI Setup, navigate to:"
echo "     Device Manager -> Rockchip Platform Configuration"
echo "   Ensure 'Config Table Mode' is set to 'Device Tree' (FDT)."
echo "5. Save and exit (F10)."
echo "===================================================================="
