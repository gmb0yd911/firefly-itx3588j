#!/usr/bin/env bash
# ==============================================================================
# build-uefi-image.sh
# Build a standard UEFI GPT Btrfs Base Image for Firefly ITX-3588J (EDK2 UEFI)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}"
CACHE_DIR="${WORK_DIR}/cache"
CONFIG_DIR="${WORK_DIR}/config"
BSP_DIR="${CACHE_DIR}/firefly-bsp"
IMG_FILE="${WORK_DIR}/archlinuxarm-firefly-itx3588j-uefi-btrfs.img"
IMG_SIZE_MIB="${IMG_SIZE_MIB:-12288}"
ESP_SIZE_MIB=512

TARGET_DIR="/mnt/firefly_uefi_target_$$"
LOOP_DEV=""

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (or with sudo)." >&2
  exit 1
fi

echo "===================================================================="
echo " Omarchy ARM - Firefly ITX-3588J EDK2 UEFI Image Builder"
echo " Image:    ${IMG_FILE}"
echo " Size:     ${IMG_SIZE_MIB} MiB"
echo " ESP Size: ${ESP_SIZE_MIB} MiB (FAT32 EFI System Partition)"
echo " Rootfs:   Btrfs subvolumes (@, @home, @snapshots, @var_log, @pkg)"
echo " Boot:     systemd-boot (BOOTAA64.EFI) + Device Tree Stub"
echo "===================================================================="

cleanup() {
  echo "Cleaning up mounts and loop devices..."
  sync
  set +e
  if mountpoint -q "${TARGET_DIR}/boot" 2>/dev/null; then umount -f "${TARGET_DIR}/boot"; fi
  if mountpoint -q "${TARGET_DIR}/home" 2>/dev/null; then umount -f "${TARGET_DIR}/home"; fi
  if mountpoint -q "${TARGET_DIR}/.snapshots" 2>/dev/null; then umount -f "${TARGET_DIR}/.snapshots"; fi
  if mountpoint -q "${TARGET_DIR}/var/log" 2>/dev/null; then umount -f "${TARGET_DIR}/var/log"; fi
  if mountpoint -q "${TARGET_DIR}/var/cache/pacman/pkg" 2>/dev/null; then umount -f "${TARGET_DIR}/var/cache/pacman/pkg"; fi
  if mountpoint -q "${TARGET_DIR}" 2>/dev/null; then umount -Rf "${TARGET_DIR}"; fi
  rm -rf "${TARGET_DIR}"
  if [[ -n "${LOOP_DEV}" && -b "${LOOP_DEV}" ]]; then
    losetup -d "${LOOP_DEV}" 2>/dev/null || true
  fi
  set -e
}
trap cleanup EXIT

# 1. Verify dependencies
for cmd in parted losetup mkfs.vfat mkfs.btrfs tar rsync; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: Required command '$cmd' is not installed." >&2
    exit 1
  fi
done

# 2. Check BSP assets and generic Arch Linux ARM rootfs
if [[ ! -d "${BSP_DIR}/boot" || ! -d "${BSP_DIR}/modules" ]]; then
  echo "Error: Firefly BSP directory ${BSP_DIR} is incomplete." >&2
  exit 1
fi

ROOTFS_TAR="${CACHE_DIR}/ArchLinuxARM-aarch64-latest.tar.gz"
if [[ ! -f "${ROOTFS_TAR}" ]]; then
  echo "Downloading generic Arch Linux ARM aarch64 rootfs..."
  curl -L -o "${ROOTFS_TAR}" "http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
fi

# 3. Create sparse disk image
echo "[1/6] Creating sparse disk image (${IMG_SIZE_MIB} MiB)..."
rm -f "${IMG_FILE}"
truncate -s "${IMG_SIZE_MIB}M" "${IMG_FILE}"

# 4. Partition disk image with standard GPT for UEFI
# Partition 1: 512 MiB FAT32 ESP (1MiB to 513MiB), boot & esp flags
# Partition 2: remainder Btrfs root
echo "[2/6] Partitioning disk image with standard UEFI GPT..."
parted -s "${IMG_FILE}" mklabel gpt
parted -s "${IMG_FILE}" mkpart primary fat32 1MiB "$((1 + ESP_SIZE_MIB))MiB"
parted -s "${IMG_FILE}" name 1 "BOOT"
parted -s "${IMG_FILE}" set 1 boot on
parted -s "${IMG_FILE}" set 1 esp on
parted -s "${IMG_FILE}" mkpart primary btrfs "$((1 + ESP_SIZE_MIB))MiB" 100%
parted -s "${IMG_FILE}" name 2 "ROOT"

# Setup loop device
echo "[3/6] Attaching loop device with partition scan..."
LOOP_DEV=$(losetup -Pf --show "${IMG_FILE}")
echo "Attached loop device: ${LOOP_DEV}"
sleep 1
if [[ ! -b "${LOOP_DEV}p1" || ! -b "${LOOP_DEV}p2" ]]; then
  partx -u "${LOOP_DEV}"
  sleep 1
fi

# 5. Format filesystems
echo "[4/6] Formatting filesystems (FAT32 for ESP, Btrfs for root)..."
mkfs.vfat -F 32 -n "BOOT" "${LOOP_DEV}p1"
mkfs.btrfs -f -L "ROOT" "${LOOP_DEV}p2"

# Retrieve UUIDs
BOOT_UUID=$(blkid -s UUID -o value "${LOOP_DEV}p1")
ROOT_UUID=$(blkid -s UUID -o value "${LOOP_DEV}p2")
echo "BOOT_UUID (ESP): ${BOOT_UUID}"
echo "ROOT_UUID:       ${ROOT_UUID}"

# Create Btrfs subvolumes
mkdir -p "${TARGET_DIR}"
mount -t btrfs "${LOOP_DEV}p2" "${TARGET_DIR}"
btrfs subvolume create "${TARGET_DIR}/@"
btrfs subvolume create "${TARGET_DIR}/@home"
btrfs subvolume create "${TARGET_DIR}/@snapshots"
btrfs subvolume create "${TARGET_DIR}/@var_log"
btrfs subvolume create "${TARGET_DIR}/@pkg"
sync
umount "${TARGET_DIR}"

# Mount target directory structure
mount -t btrfs -o subvol=@,compress=zstd:3,noatime,discard=async "${LOOP_DEV}p2" "${TARGET_DIR}"
mkdir -p "${TARGET_DIR}/home" "${TARGET_DIR}/.snapshots" "${TARGET_DIR}/var/log" "${TARGET_DIR}/var/cache/pacman/pkg" "${TARGET_DIR}/boot"
mount -t btrfs -o subvol=@home,compress=zstd:3,noatime,discard=async "${LOOP_DEV}p2" "${TARGET_DIR}/home"
mount -t btrfs -o subvol=@snapshots,compress=zstd:3,noatime,discard=async "${LOOP_DEV}p2" "${TARGET_DIR}/.snapshots"
mount -t btrfs -o subvol=@var_log,compress=zstd:3,noatime,discard=async "${LOOP_DEV}p2" "${TARGET_DIR}/var/log"
mount -t btrfs -o subvol=@pkg,noatime,nodatacow "${LOOP_DEV}p2" "${TARGET_DIR}/var/cache/pacman/pkg"
mount -t vfat "${LOOP_DEV}p1" "${TARGET_DIR}/boot"

# 6. Extract Arch Linux ARM rootfs
echo "[5/6] Extracting Arch Linux ARM root filesystem..."
tar -xpf "${ROOTFS_TAR}" -C "${TARGET_DIR}"

# 7. Install Firefly ITX-3588J BSP, Kernel, and standard UEFI bootloader
echo "[6/6] Installing Kernel, Device Tree, Modules, and systemd-boot..."
mkdir -p "${TARGET_DIR}/boot/EFI/BOOT" \
         "${TARGET_DIR}/boot/EFI/systemd" \
         "${TARGET_DIR}/boot/loader/entries" \
         "${TARGET_DIR}/boot/dtb/rockchip" \
         "${TARGET_DIR}/lib/modules" \
         "${TARGET_DIR}/lib/firmware"

# Copy kernel and initramfs files directly to ESP
KERNEL_FILE=$(ls -1 "${BSP_DIR}/boot"/vmlinuz-* 2>/dev/null | head -n1)
KERNEL_NAME=$(basename "${KERNEL_FILE}")
cp "${KERNEL_FILE}" "${TARGET_DIR}/boot/${KERNEL_NAME}"

INITRD_FILE=$(ls -1 "${BSP_DIR}/boot"/initrd.img-* 2>/dev/null | head -n1)
INITRD_NAME=$(basename "${INITRD_FILE}")
cp "${INITRD_FILE}" "${TARGET_DIR}/boot/${INITRD_NAME}"

# Copy device tree directly to ESP
DTB_FILE=$(find "${BSP_DIR}/boot" -name "rk3588-firefly-itx-3588j.dtb" | head -n1)
cp "${DTB_FILE}" "${TARGET_DIR}/boot/dtb/rockchip/rk3588-firefly-itx-3588j.dtb"

# Copy kernel modules and firmware to rootfs
rsync -a "${BSP_DIR}/modules/" "${TARGET_DIR}/lib/modules/"
rsync -a "${BSP_DIR}/firmware/" "${TARGET_DIR}/lib/firmware/"

# Setup ARM64 systemd-boot binary
BOOT_EFI_SRC="${TARGET_DIR}/usr/lib/systemd/boot/efi/systemd-bootaa64.efi"
if [[ -f "${BOOT_EFI_SRC}" ]]; then
  cp "${BOOT_EFI_SRC}" "${TARGET_DIR}/boot/EFI/systemd/systemd-bootaa64.efi"
  cp "${BOOT_EFI_SRC}" "${TARGET_DIR}/boot/EFI/BOOT/BOOTAA64.EFI"
else
  echo "Warning: ${BOOT_EFI_SRC} not found in rootfs. UEFI fallback will need to be installed during pacman provisioning."
fi

# Write systemd-boot configuration
cat <<EOF > "${TARGET_DIR}/boot/loader/loader.conf"
default omarchy.conf
timeout 3
console-mode max
editor no
EOF

cat <<EOF > "${TARGET_DIR}/boot/loader/entries/omarchy.conf"
title      Omarchy Linux ARM (Firefly ITX-3588J UEFI)
linux      /${KERNEL_NAME}
initrd     /${INITRD_NAME}
devicetree /dtb/rockchip/rk3588-firefly-itx-3588j.dtb
options    root=UUID=${ROOT_UUID} rootflags=subvol=@,compress=zstd:3 rw quiet loglevel=3 cma=256M splash drm.edid_firmware=HDMI-A-1:edid/dell_p2720dc.bin video=HDMI-A-1:2560x1440@60
EOF

# Configure /etc/fstab
cat <<EOF > "${TARGET_DIR}/etc/fstab"
# <file system> <mount point> <type> <options> <dump> <pass>
UUID=${BOOT_UUID}  /boot                   vfat   defaults,noatime,umask=0077                         0 2
UUID=${ROOT_UUID}  /                       btrfs  subvol=@,compress=zstd:3,noatime,discard=async       0 0
UUID=${ROOT_UUID}  /home                   btrfs  subvol=@home,compress=zstd:3,noatime,discard=async   0 0
UUID=${ROOT_UUID}  /.snapshots             btrfs  subvol=@snapshots,compress=zstd:3,noatime,discard=async 0 0
UUID=${ROOT_UUID}  /var/log                btrfs  subvol=@var_log,compress=zstd:3,noatime,discard=async 0 0
UUID=${ROOT_UUID}  /var/cache/pacman/pkg   btrfs  subvol=@pkg,noatime,nodatacow                       0 0
EOF

# Setup hostname and pacman config
echo "omarchy-firefly" > "${TARGET_DIR}/etc/hostname"
if [[ -f "${CONFIG_DIR}/pacman-chroot.conf" ]]; then
  cp "${CONFIG_DIR}/pacman-chroot.conf" "${TARGET_DIR}/etc/pacman.conf"
fi

sync
echo "===================================================================="
echo " UEFI Base Image built successfully!"
echo " Image: ${IMG_FILE}"
echo " To provision full Omarchy desktop onto this image:"
echo "   sudo ./apply-omarchy.sh ${IMG_FILE}"
echo "===================================================================="
