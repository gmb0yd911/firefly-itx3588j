#!/usr/bin/env bash
# ==============================================================================
# deploy-remote.sh
# Deploy Omarchy ARM directly to the live Firefly ITX-3588J hardware over SSH
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_TARGET="${1:-firefly}"
MODE="${2:-flash-image}" # Modes: 'flash-image', 'live-ssd'
TARGET_DRIVE="${3:-/dev/sda}" # Default target drive on the board: internal SSD

echo "===================================================================="
echo " Omarchy Remote Deployer: Firefly ITX-3588J"
echo " Host:         ${SSH_TARGET}"
echo " Mode:         ${MODE}"
echo " Target Disk:  ${TARGET_DRIVE}"
echo "===================================================================="

# Check connectivity
echo "Checking connection to ${SSH_TARGET}..."
ssh -o ConnectTimeout=5 "${SSH_TARGET}" "hostname && uname -a"

if [[ "${MODE}" == "flash-image" ]]; then
  IMG_FILE=$(ls -1 "${SCRIPT_DIR}"/output/*.img.zst "${SCRIPT_DIR}"/output/*.img "${SCRIPT_DIR}"/*.img 2>/dev/null | head -n1 || true)
  if [[ -z "${IMG_FILE}" || ! -f "${IMG_FILE}" ]]; then
    echo "Error: No built image found in output/ or workspace." >&2
    echo "Run ./build.sh or ./build-base-image.sh first." >&2
    exit 1
  fi

  echo "Found image: ${IMG_FILE}"
  echo "WARNING: Writing to ${TARGET_DRIVE} on ${SSH_TARGET} will DESTROY all data on that drive!"
  echo "Streaming image to remote drive..."

  if [[ "${IMG_FILE}" == *.zst ]]; then
    zstd -dc "${IMG_FILE}" | ssh "${SSH_TARGET}" "sudo dd of=${TARGET_DRIVE} bs=4M status=progress conv=fsync"
  else
    cat "${IMG_FILE}" | ssh "${SSH_TARGET}" "sudo dd of=${TARGET_DRIVE} bs=4M status=progress conv=fsync"
  fi

  echo "Flash completed successfully!"
  echo "Reboot the Firefly board to boot into the new Omarchy installation."

elif [[ "${MODE}" == "live-ssd" ]]; then
  echo "Live provisioning of ${TARGET_DRIVE} directly on ${SSH_TARGET}..."

  ssh -t "${SSH_TARGET}" << 'REMOTESH'
    set -euo pipefail
    TARGET_DEV="/dev/sda"
    MNT="/mnt/omarchy_install"

    echo "Unmounting any existing partitions on ${TARGET_DEV}..."
    sudo umount -Rf "${TARGET_DEV}"* 2>/dev/null || true

    echo "Partitioning ${TARGET_DEV} (GPT with Rockchip U-Boot space)..."
    sudo parted -s "${TARGET_DEV}" mklabel gpt
    sudo parted -s "${TARGET_DEV}" mkpart primary fat32 16MiB 528MiB
    sudo parted -s "${TARGET_DEV}" name 1 "BOOT"
    sudo parted -s "${TARGET_DEV}" set 1 boot on
    sudo parted -s "${TARGET_DEV}" set 1 esp on
    sudo parted -s "${TARGET_DEV}" mkpart primary btrfs 528MiB 100%
    sudo parted -s "${TARGET_DEV}" name 2 "ROOT"

    echo "Flashing U-Boot to ${TARGET_DEV}..."
    UBOOT_DIR="/usr/lib/linux-u-boot-vendor-firefly-itx-3588j"
    if [[ -d "${UBOOT_DIR}" ]]; then
      sudo dd if="${UBOOT_DIR}/idbloader.img" of="${TARGET_DEV}" seek=64 conv=notrunc status=none
      sudo dd if="${UBOOT_DIR}/u-boot.itb" of="${TARGET_DEV}" seek=16384 conv=notrunc status=none
    fi

    echo "Formatting filesystems..."
    sudo mkfs.vfat -F 32 -n "BOOT" "${TARGET_DEV}1"
    sudo mkfs.btrfs -f -L "ROOT" "${TARGET_DEV}2"

    BOOT_UUID=$(sudo blkid -s UUID -o value "${TARGET_DEV}1")
    ROOT_UUID=$(sudo blkid -s UUID -o value "${TARGET_DEV}2")

    echo "Creating Btrfs subvolumes..."
    sudo mkdir -p "${MNT}"
    sudo mount -t btrfs "${TARGET_DEV}2" "${MNT}"
    sudo btrfs subvolume create "${MNT}/@"
    sudo btrfs subvolume create "${MNT}/@home"
    sudo btrfs subvolume create "${MNT}/@snapshots"
    sudo btrfs subvolume create "${MNT}/@var_log"
    sudo btrfs subvolume create "${MNT}/@pkg"
    sudo sync
    sudo umount "${MNT}"

    echo "Mounting target structure..."
    sudo mount -t btrfs -o subvol=@,compress=zstd:3,noatime,discard=async "${TARGET_DEV}2" "${MNT}"
    sudo mkdir -p "${MNT}/home" "${MNT}/.snapshots" "${MNT}/var/log" "${MNT}/var/cache/pacman/pkg" "${MNT}/boot"
    sudo mount -t btrfs -o subvol=@home,compress=zstd:3,noatime,discard=async "${TARGET_DEV}2" "${MNT}/home"
    sudo mount -t btrfs -o subvol=@snapshots,compress=zstd:3,noatime,discard=async "${TARGET_DEV}2" "${MNT}/.snapshots"
    sudo mount -t btrfs -o subvol=@var_log,compress=zstd:3,noatime,discard=async "${TARGET_DEV}2" "${MNT}/var/log"
    sudo mount -t btrfs -o subvol=@pkg,noatime,nodatacow "${TARGET_DEV}2" "${MNT}/var/cache/pacman/pkg"
    sudo mount -t vfat "${TARGET_DEV}1" "${MNT}/boot"

    echo "Target structure ready at ${MNT}."
    echo "BOOT_UUID: ${BOOT_UUID}"
    echo "ROOT_UUID: ${ROOT_UUID}"
REMOTESH

  echo "Live disk layout prepared on remote hardware!"
fi
