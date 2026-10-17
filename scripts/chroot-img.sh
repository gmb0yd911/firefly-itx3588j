#!/usr/bin/env bash
# ==============================================================================
# chroot-img.sh - Drop into interactive QEMU aarch64 chroot
# ==============================================================================
set -euo pipefail

MNT_DIR="${1:-/mnt/firefly_build}"

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (or with sudo)." >&2
  exit 1
fi

if ! mountpoint -q "${MNT_DIR}" 2>/dev/null; then
  echo "Error: ${MNT_DIR} is not mounted. Run ./scripts/mount-img.sh first." >&2
  exit 1
fi

echo "Entering QEMU aarch64 chroot at ${MNT_DIR}..."
arch-chroot "${MNT_DIR}" /bin/bash
