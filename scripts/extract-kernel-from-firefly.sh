#!/usr/bin/env bash
# ==============================================================================
# extract-kernel-from-firefly.sh
# Extracts Rockchip 6.1 BSP kernel, modules, DTBs, firmware, and U-Boot from
# the live Firefly ITX-3588J board (via SSH) into the local cache.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CACHE_DIR="${WORK_DIR}/cache"
BSP_DIR="${CACHE_DIR}/firefly-bsp"
SSH_HOST="${1:-firefly}"

echo "===================================================================="
echo " Extracting Firefly ITX-3588J BSP from ${SSH_HOST}"
echo " Destination: ${BSP_DIR}"
echo "===================================================================="

mkdir -p "${BSP_DIR}/boot" "${BSP_DIR}/modules" "${BSP_DIR}/u-boot" "${BSP_DIR}/firmware"

# 1. Fetch U-Boot binaries
echo "[1/4] Copying U-Boot binaries (idbloader.img, u-boot.itb)..."
rsync -avz --progress "${SSH_HOST}:/usr/lib/linux-u-boot-vendor-firefly-itx-3588j/" "${BSP_DIR}/u-boot/"

# 2. Fetch boot files (Kernel Image, initrd, DTBs, boot scripts)
echo "[2/4] Copying /boot files (kernel, DTB, boot scripts)..."
rsync -avz --progress \
  --exclude='lost+found' \
  --include='*6.1.115-vendor-rk35xx*' \
  --include='dtb***' \
  --include='boot.***' \
  --include='armbianEnv.txt' \
  --include='Image' \
  --include='uInitrd' \
  --exclude='*' \
  "${SSH_HOST}:/boot/" "${BSP_DIR}/boot/"

# 3. Fetch kernel modules
echo "[3/4] Copying kernel modules (6.1.115-vendor-rk35xx)..."
rsync -avz --progress "${SSH_HOST}:/lib/modules/6.1.115-vendor-rk35xx/" "${BSP_DIR}/modules/6.1.115-vendor-rk35xx/"

# 4. Fetch essential firmware (rockchip & mali CSF firmware)
echo "[4/4] Copying essential hardware firmware (Mali CSF, Rockchip NPU/ISP)..."
rsync -avz --progress "${SSH_HOST}:/lib/firmware/arm/" "${BSP_DIR}/firmware/arm/"
rsync -avz --progress "${SSH_HOST}:/lib/firmware/rockchip/" "${BSP_DIR}/firmware/rockchip/"

echo "===================================================================="
echo " BSP extraction complete! Stored in ${BSP_DIR}"
echo "===================================================================="
