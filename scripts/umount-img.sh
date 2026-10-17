#!/usr/bin/env bash
# ==============================================================================
# umount-img.sh - Safely unmount Firefly Btrfs image and detach loop device
# ==============================================================================
set -euo pipefail

MNT_DIR="${1:-/mnt/firefly_build}"

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (or with sudo)." >&2
  exit 1
fi

echo "Flushing disk buffers..."
sync

echo "Unmounting subvolumes from ${MNT_DIR}..."
set +e
if mountpoint -q "${MNT_DIR}/boot" 2>/dev/null; then umount -f "${MNT_DIR}/boot"; fi
if mountpoint -q "${MNT_DIR}/home" 2>/dev/null; then umount -f "${MNT_DIR}/home"; fi
if mountpoint -q "${MNT_DIR}/.snapshots" 2>/dev/null; then umount -f "${MNT_DIR}/.snapshots"; fi
if mountpoint -q "${MNT_DIR}/var/log" 2>/dev/null; then umount -f "${MNT_DIR}/var/log"; fi
if mountpoint -q "${MNT_DIR}/var/cache/pacman/pkg" 2>/dev/null; then umount -f "${MNT_DIR}/var/cache/pacman/pkg"; fi
if mountpoint -q "${MNT_DIR}" 2>/dev/null; then umount -Rf "${MNT_DIR}"; fi

# Detach any loop devices associated with MNT_DIR
for dev in $(losetup -j "${MNT_DIR}" 2>/dev/null | cut -d: -f1); do
  echo "Detaching loop device: ${dev}"
  losetup -d "${dev}" || true
done

# Also detach any loops whose backing file matches firefly images if still attached
for dev in $(losetup -a | grep -i 'firefly' | cut -d: -f1); do
  echo "Detaching firefly loop device: ${dev}"
  losetup -d "${dev}" || true
done
set -e

echo "Unmounted cleanly."
