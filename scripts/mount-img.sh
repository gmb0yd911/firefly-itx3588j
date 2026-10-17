#!/usr/bin/env bash
# ==============================================================================
# mount-img.sh - Mount Firefly ITX-3588J Btrfs image to /mnt/firefly_build
# ==============================================================================
set -euo pipefail

IMG_FILE="${1:-}"
MNT_DIR="${2:-/mnt/firefly_build}"

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (or with sudo)." >&2
  exit 1
fi

if [[ -z "${IMG_FILE}" || ! -f "${IMG_FILE}" ]]; then
  echo "Usage: sudo $0 <path-to-image.img> [mount-point]" >&2
  exit 1
fi

echo "Attaching image: ${IMG_FILE}"
LOOP_DEV=$(losetup -Pf --show "${IMG_FILE}")
echo "Attached loop: ${LOOP_DEV}"
sleep 1
if [[ ! -b "${LOOP_DEV}p1" || ! -b "${LOOP_DEV}p2" ]]; then
  partx -u "${LOOP_DEV}"
  sleep 1
fi

mkdir -p "${MNT_DIR}"
echo "Mounting Btrfs subvolumes to ${MNT_DIR}..."
mount -t btrfs -o subvol=@,compress=zstd:3,noatime,discard=async "${LOOP_DEV}p2" "${MNT_DIR}"
mkdir -p "${MNT_DIR}/home" "${MNT_DIR}/.snapshots" "${MNT_DIR}/var/log" "${MNT_DIR}/var/cache/pacman/pkg" "${MNT_DIR}/boot"
mount -t btrfs -o subvol=@home,compress=zstd:3,noatime,discard=async "${LOOP_DEV}p2" "${MNT_DIR}/home"
mount -t btrfs -o subvol=@snapshots,compress=zstd:3,noatime,discard=async "${LOOP_DEV}p2" "${MNT_DIR}/.snapshots"
mount -t btrfs -o subvol=@var_log,compress=zstd:3,noatime,discard=async "${LOOP_DEV}p2" "${MNT_DIR}/var/log"
mount -t btrfs -o subvol=@pkg,noatime,nodatacow "${LOOP_DEV}p2" "${MNT_DIR}/var/cache/pacman/pkg"
mount -t vfat "${LOOP_DEV}p1" "${MNT_DIR}/boot"

echo "Mounted successfully at ${MNT_DIR}."
echo "To enter chroot: sudo ./scripts/chroot-img.sh"
echo "To unmount: sudo ./scripts/umount-img.sh"
