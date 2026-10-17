#!/usr/bin/env bash
# ==============================================================================
# build-base-image.sh
# Build Arch Linux ARM Base Image for Firefly ITX-3588J with Btrfs Filesystem
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}"
CACHE_DIR="${WORK_DIR}/cache"
CONFIG_DIR="${WORK_DIR}/config"
BSP_DIR="${CACHE_DIR}/firefly-bsp"
IMG_FILE="${WORK_DIR}/archlinuxarm-firefly-itx3588j-btrfs.img"
IMG_SIZE_MIB="${IMG_SIZE_MIB:-12288}"
BOOT_SIZE_MIB=512

TARGET_DIR="/mnt/firefly_target_$$"
MNT_TMP="/mnt/firefly_tmp_$$"
LOOP_DEV=""

echo "===================================================================="
echo " Arch Linux ARM Image Builder for Firefly ITX-3588J (Btrfs)"
echo " Output Image: ${IMG_FILE}"
echo " Image Size:   ${IMG_SIZE_MIB} MiB"
echo "===================================================================="

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (or with sudo)." >&2
  exit 1
fi

unmount_all() {
  echo "=== Unmounting filesystems and cleaning mounts ==="
  sync
  set +e
  if mountpoint -q "${TARGET_DIR}/boot" 2>/dev/null; then umount -f "${TARGET_DIR}/boot"; fi
  if mountpoint -q "${TARGET_DIR}/home" 2>/dev/null; then umount -f "${TARGET_DIR}/home"; fi
  if mountpoint -q "${TARGET_DIR}/.snapshots" 2>/dev/null; then umount -f "${TARGET_DIR}/.snapshots"; fi
  if mountpoint -q "${TARGET_DIR}/var/log" 2>/dev/null; then umount -f "${TARGET_DIR}/var/log"; fi
  if mountpoint -q "${TARGET_DIR}/var/cache/pacman/pkg" 2>/dev/null; then umount -f "${TARGET_DIR}/var/cache/pacman/pkg"; fi
  if mountpoint -q "${TARGET_DIR}" 2>/dev/null; then umount -Rf "${TARGET_DIR}"; fi
  if mountpoint -q "${MNT_TMP}" 2>/dev/null; then umount -Rf "${MNT_TMP}"; fi
  rm -rf "${TARGET_DIR}" "${MNT_TMP}"

  if [[ -n "${LOOP_DEV:-}" && -b "${LOOP_DEV}" ]]; then
    losetup -d "${LOOP_DEV}" || true
    LOOP_DEV=""
  fi
  set -e
}

cleanup() {
  if [[ -d "${TARGET_DIR}" || -d "${MNT_TMP}" || -n "${LOOP_DEV:-}" ]]; then
    unmount_all
  fi
}
trap cleanup EXIT

# 1. Verify dependencies
for cmd in parted losetup mkfs.ext4 mkfs.btrfs tar rsync; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: Required command '$cmd' is not installed." >&2
    exit 1
  fi
done

# 2. Check BSP assets
if [[ ! -f "${BSP_DIR}/u-boot/idbloader.img" || ! -f "${BSP_DIR}/u-boot/u-boot.itb" ]]; then
  echo "BSP U-Boot binaries missing in ${BSP_DIR}/u-boot."
  echo "Attempting to extract from Firefly board..."
  "${WORK_DIR}/scripts/extract-kernel-from-firefly.sh" firefly
fi

# 3. Check / download Arch Linux ARM generic rootfs
ROOTFS_TAR="${CACHE_DIR}/ArchLinuxARM-aarch64-latest.tar.gz"
if [[ ! -f "${ROOTFS_TAR}" ]]; then
  echo "Downloading Arch Linux ARM aarch64 generic rootfs..."
  curl -L -C - -o "${ROOTFS_TAR}" "http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
fi

# 4. Create sparse disk image
echo "[1/7] Creating ${IMG_SIZE_MIB} MiB sparse image..."
rm -f "${IMG_FILE}"
truncate -s "${IMG_SIZE_MIB}M" "${IMG_FILE}"

# 5. Partition disk image for Rockchip RK3588 (GPT)
# Sectors 0-32767 (first 16 MiB) reserved for U-Boot (idbloader.img @ 64, u-boot.itb @ 16384)
# Partition 1: 512 MiB ext4 /boot (starts at 16 MiB / sector 32768)
# Partition 2: remainder Btrfs root
echo "[2/7] Partitioning disk image with GPT..."
parted -s "${IMG_FILE}" mklabel gpt
parted -s "${IMG_FILE}" mkpart primary ext4 16MiB "$((16 + BOOT_SIZE_MIB))MiB"
parted -s "${IMG_FILE}" name 1 "BOOT"
parted -s "${IMG_FILE}" set 1 boot on
parted -s "${IMG_FILE}" mkpart primary btrfs "$((16 + BOOT_SIZE_MIB))MiB" 100%
parted -s "${IMG_FILE}" name 2 "ROOT"

# Attach loop device
echo "[3/7] Attaching loop device..."
LOOP_DEV=$(losetup -Pf --show "${IMG_FILE}")
echo "Attached loop device: ${LOOP_DEV}"
sleep 1
if [[ ! -b "${LOOP_DEV}p1" || ! -b "${LOOP_DEV}p2" ]]; then
  partx -u "${LOOP_DEV}"
  sleep 1
fi

# Flash U-Boot loader and ITB into raw sectors
echo "[4/7] Flashing Rockchip U-Boot loader into raw sectors..."
dd if="${BSP_DIR}/u-boot/idbloader.img" of="${LOOP_DEV}" seek=64 conv=notrunc status=none
dd if="${BSP_DIR}/u-boot/u-boot.itb" of="${LOOP_DEV}" seek=16384 conv=notrunc status=none

# 6. Format filesystems
echo "[5/7] Formatting filesystems (ext4 for boot, Btrfs for root)..."
mkfs.ext4 -F -L "BOOT" "${LOOP_DEV}p1"
mkfs.btrfs -f -L "ROOT" "${LOOP_DEV}p2"

# Retrieve UUIDs
BOOT_UUID=$(blkid -s UUID -o value "${LOOP_DEV}p1")
ROOT_UUID=$(blkid -s UUID -o value "${LOOP_DEV}p2")
echo "BOOT UUID: ${BOOT_UUID}"
echo "ROOT UUID: ${ROOT_UUID}"

# Create Btrfs subvolumes
mkdir -p "${MNT_TMP}"
mount -t btrfs "${LOOP_DEV}p2" "${MNT_TMP}"
echo "Creating Btrfs subvolumes (@, @home, @snapshots, @var_log, @pkg)..."
btrfs subvolume create "${MNT_TMP}/@"
btrfs subvolume create "${MNT_TMP}/@home"
btrfs subvolume create "${MNT_TMP}/@snapshots"
btrfs subvolume create "${MNT_TMP}/@var_log"
btrfs subvolume create "${MNT_TMP}/@pkg"
sync
umount "${MNT_TMP}"

# Mount target directory structure
mkdir -p "${TARGET_DIR}"
mount -t btrfs -o subvol=@,compress=zstd:3,noatime,discard=async "${LOOP_DEV}p2" "${TARGET_DIR}"
mkdir -p "${TARGET_DIR}/home" "${TARGET_DIR}/.snapshots" "${TARGET_DIR}/var/log" "${TARGET_DIR}/var/cache/pacman/pkg" "${TARGET_DIR}/boot"
mount -t btrfs -o subvol=@home,compress=zstd:3,noatime,discard=async "${LOOP_DEV}p2" "${TARGET_DIR}/home"
mount -t btrfs -o subvol=@snapshots,compress=zstd:3,noatime,discard=async "${LOOP_DEV}p2" "${TARGET_DIR}/.snapshots"
mount -t btrfs -o subvol=@var_log,compress=zstd:3,noatime,discard=async "${LOOP_DEV}p2" "${TARGET_DIR}/var/log"
mount -t btrfs -o subvol=@pkg,noatime,nodatacow "${LOOP_DEV}p2" "${TARGET_DIR}/var/cache/pacman/pkg"
mount -t ext4 "${LOOP_DEV}p1" "${TARGET_DIR}/boot"

# 7. Extract Arch Linux ARM rootfs
echo "[6/7] Extracting Arch Linux ARM root filesystem..."
tar -xpf "${ROOTFS_TAR}" -C "${TARGET_DIR}"

# 8. Install Rockchip BSP (Kernel, DTB, U-Boot scripts, modules, firmware)
echo "[7/7] Installing Firefly ITX-3588J BSP and kernel..."
mkdir -p "${TARGET_DIR}/boot" "${TARGET_DIR}/lib/modules" "${TARGET_DIR}/lib/firmware"

# Copy boot assets (symlinks, DTB, boot scripts, kernel)
rsync -a "${BSP_DIR}/boot/" "${TARGET_DIR}/boot/"

# Ensure Image and uInitrd symlinks/files are valid
if [[ ! -e "${TARGET_DIR}/boot/Image" ]]; then
  KERNEL_BIN=$(ls -1 "${TARGET_DIR}"/boot/vmlinuz-6.1.* 2>/dev/null | head -n1 || true)
  if [[ -n "${KERNEL_BIN}" ]]; then
    ln -sf "$(basename "${KERNEL_BIN}")" "${TARGET_DIR}/boot/Image"
  fi
fi
if [[ ! -e "${TARGET_DIR}/boot/uInitrd" ]]; then
  INITRD_BIN=$(ls -1 "${TARGET_DIR}"/boot/uInitrd-6.1.* 2>/dev/null | head -n1 || true)
  if [[ -n "${INITRD_BIN}" ]]; then
    ln -sf "$(basename "${INITRD_BIN}")" "${TARGET_DIR}/boot/uInitrd"
  fi
fi
if [[ ! -e "${TARGET_DIR}/boot/dtb" ]]; then
  DTB_DIR=$(ls -d "${TARGET_DIR}"/boot/dtb-6.1.* 2>/dev/null | head -n1 || true)
  if [[ -n "${DTB_DIR}" ]]; then
    ln -sf "$(basename "${DTB_DIR}")" "${TARGET_DIR}/boot/dtb"
  fi
fi

# Configure armbianEnv.txt with exact UUID and Btrfs parameters
cat <<EOF > "${TARGET_DIR}/boot/armbianEnv.txt"
verbosity=1
bootlogo=false
console=both
extraargs=cma=256M
overlay_prefix=rockchip-rk3588
fdtfile=rockchip/rk3588-firefly-itx-3588j.dtb
rootdev=UUID=${ROOT_UUID}
rootfstype=btrfs
rootflags=subvol=@,compress=zstd:3
usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
EOF

# Copy modules & firmware
rsync -a "${BSP_DIR}/modules/" "${TARGET_DIR}/lib/modules/"
rsync -a "${BSP_DIR}/firmware/" "${TARGET_DIR}/lib/firmware/"

# Configure /etc/fstab
cat <<EOF > "${TARGET_DIR}/etc/fstab"
# <file system> <mount point> <type> <options> <dump> <pass>
UUID=${BOOT_UUID}  /boot                   ext4   defaults,noatime                                    0 2
UUID=${ROOT_UUID}  /                       btrfs  subvol=@,compress=zstd:3,noatime,discard=async       0 0
UUID=${ROOT_UUID}  /home                   btrfs  subvol=@home,compress=zstd:3,noatime,discard=async   0 0
UUID=${ROOT_UUID}  /.snapshots             btrfs  subvol=@snapshots,compress=zstd:3,noatime,discard=async 0 0
UUID=${ROOT_UUID}  /var/log                btrfs  subvol=@var_log,compress=zstd:3,noatime,discard=async 0 0
UUID=${ROOT_UUID}  /var/cache/pacman/pkg   btrfs  subvol=@pkg,noatime,nodatacow                       0 0
EOF

# Hostname and hosts
echo "omarchy-firefly" > "${TARGET_DIR}/etc/hostname"
cat <<EOF > "${TARGET_DIR}/etc/hosts"
127.0.0.1   localhost
::1         localhost
127.0.1.1   omarchy-firefly.local omarchy-firefly
EOF

# DNS stub
echo "nameserver 1.1.1.1" > "${TARGET_DIR}/etc/resolv.conf"
echo "nameserver 8.8.8.8" >> "${TARGET_DIR}/etc/resolv.conf"

# Pacman chroot configuration
if [[ -f "${CONFIG_DIR}/pacman-chroot.conf" ]]; then
  cp "${CONFIG_DIR}/pacman-chroot.conf" "${TARGET_DIR}/etc/pacman.conf"
fi

echo "=== Base Arch Linux ARM Image Built Successfully! ==="
echo "Output: ${IMG_FILE}"
