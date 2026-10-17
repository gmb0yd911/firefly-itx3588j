#!/usr/bin/env bash
# ==============================================================================
# apply-omarchy.sh
# Provision Omarchy Desktop onto an Arch Linux ARM Firefly ITX-3588J Image
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}"
IMG_FILE="${1:-}"
MNT_DIR="${2:-/mnt/firefly_build}"
WITH_AUR="${3:-false}"

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (or with sudo)." >&2
  exit 1
fi

if [[ -z "${IMG_FILE}" || ! -f "${IMG_FILE}" ]]; then
  echo "Usage: sudo $0 <path-to-firefly-btrfs.img> [mount-dir] [--with-aur]" >&2
  exit 1
fi

echo "===================================================================="
echo " Omarchy Provisioner for Firefly ITX-3588J"
echo " Image:        ${IMG_FILE}"
echo " Mount:        ${MNT_DIR}"
echo " AUR Packages: ${WITH_AUR}"
echo "===================================================================="

LOOP_DEV=""

cleanup() {
  echo "=== Running unmount cleanup ==="
  sync
  set +e
  if mountpoint -q "${MNT_DIR}/boot" 2>/dev/null; then umount -f "${MNT_DIR}/boot"; fi
  if mountpoint -q "${MNT_DIR}/home" 2>/dev/null; then umount -f "${MNT_DIR}/home"; fi
  if mountpoint -q "${MNT_DIR}/.snapshots" 2>/dev/null; then umount -f "${MNT_DIR}/.snapshots"; fi
  if mountpoint -q "${MNT_DIR}/var/log" 2>/dev/null; then umount -f "${MNT_DIR}/var/log"; fi
  if mountpoint -q "${MNT_DIR}/var/cache/pacman/pkg" 2>/dev/null; then umount -f "${MNT_DIR}/var/cache/pacman/pkg"; fi
  if mountpoint -q "${MNT_DIR}" 2>/dev/null; then umount -Rf "${MNT_DIR}"; fi
  if [[ -n "${LOOP_DEV:-}" && -b "${LOOP_DEV}" ]]; then losetup -d "${LOOP_DEV}" 2>/dev/null || true; fi
  set -e
}
trap cleanup EXIT

# 1. Mount image
echo "[1/8] Setting up loop device and mounting subvolumes..."
LOOP_DEV=$(losetup -Pf --show "${IMG_FILE}")
echo "Attached loop: ${LOOP_DEV}"
sleep 1
if [[ ! -b "${LOOP_DEV}p1" || ! -b "${LOOP_DEV}p2" ]]; then
  partx -u "${LOOP_DEV}"
  sleep 1
fi

mkdir -p "${MNT_DIR}"
mount -t btrfs -o subvol=@,compress=zstd:3,noatime,discard=async "${LOOP_DEV}p2" "${MNT_DIR}"
mkdir -p "${MNT_DIR}/home" "${MNT_DIR}/.snapshots" "${MNT_DIR}/var/log" "${MNT_DIR}/var/cache/pacman/pkg" "${MNT_DIR}/boot"
mount -t btrfs -o subvol=@home,compress=zstd:3,noatime,discard=async "${LOOP_DEV}p2" "${MNT_DIR}/home"
mount -t btrfs -o subvol=@snapshots,compress=zstd:3,noatime,discard=async "${LOOP_DEV}p2" "${MNT_DIR}/.snapshots"
mount -t btrfs -o subvol=@var_log,compress=zstd:3,noatime,discard=async "${LOOP_DEV}p2" "${MNT_DIR}/var/log"
mount -t btrfs -o subvol=@pkg,noatime,nodatacow "${LOOP_DEV}p2" "${MNT_DIR}/var/cache/pacman/pkg"
mount -t vfat "${LOOP_DEV}p1" "${MNT_DIR}/boot"

# 2. Configure QEMU binfmt and pacman sandbox settings
echo "[2/8] Setting up binfmt and pacman sandbox overrides..."
if [[ -f /etc/binfmt.d/qemu-aarch64-static.conf ]]; then
  systemctl restart systemd-binfmt 2>/dev/null || true
fi

# Disable pacman sandboxing for user-mode chroot
sed -i '/DisableSandboxFilesystem/d' "${MNT_DIR}/etc/pacman.conf"
sed -i '/DisableSandboxSyscalls/d' "${MNT_DIR}/etc/pacman.conf"
sed -i '/\[options\]/a DisableSandboxFilesystem\nDisableSandboxSyscalls' "${MNT_DIR}/etc/pacman.conf"

# Setup temporary DNS
rm -f "${MNT_DIR}/etc/resolv.conf"
echo "nameserver 1.1.1.1" > "${MNT_DIR}/etc/resolv.conf"
echo "nameserver 8.8.8.8" >> "${MNT_DIR}/etc/resolv.conf"

# 3. Keyring & Base build tools
echo "[3/8] Initializing keyring and base packages..."
arch-chroot "${MNT_DIR}" pacman-key --init
arch-chroot "${MNT_DIR}" pacman-key --populate archlinuxarm
arch-chroot "${MNT_DIR}" pacman -Sy --noconfirm --needed --overwrite '*' base-devel git sudo btrfs-progs

# 4. User and sudo setup
echo "[4/8] Configuring alarm user and yay non-interactive setup..."
if ! id -u -R "${MNT_DIR}" alarm &>/dev/null; then
  arch-chroot "${MNT_DIR}" useradd -m -G wheel,video,render,audio,input,seat,storage -s /bin/bash alarm
else
  arch-chroot "${MNT_DIR}" usermod -aG wheel,video,render,audio,input,seat,storage alarm
fi
echo "alarm:alarm" | arch-chroot "${MNT_DIR}" chpasswd
echo "root:root" | arch-chroot "${MNT_DIR}" chpasswd
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > "${MNT_DIR}/etc/sudoers.d/wheel"
chmod 0440 "${MNT_DIR}/etc/sudoers.d/wheel"

# Copy yay non-interactive configuration
mkdir -p "${MNT_DIR}/home/alarm/.config/yay"
if [[ -f "${WORK_DIR}/config/yay-config.json" ]]; then
  cp "${WORK_DIR}/config/yay-config.json" "${MNT_DIR}/home/alarm/.config/yay/config.json"
fi
chown -R 1000:1000 "${MNT_DIR}/home/alarm"

# 5. Install yay if not present
if ! arch-chroot "${MNT_DIR}" which yay &>/dev/null; then
  echo "Building and installing yay from source..."
  arch-chroot "${MNT_DIR}" su - alarm -c "git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin 2>/dev/null || git clone https://aur.archlinux.org/yay.git /tmp/yay"
  if [[ -d "${MNT_DIR}/tmp/yay-bin" ]]; then
    arch-chroot "${MNT_DIR}" su - alarm -c "cd /tmp/yay-bin && makepkg -si --noconfirm"
  else
    arch-chroot "${MNT_DIR}" su - alarm -c "cd /tmp/yay && makepkg -si --noconfirm"
  fi
  rm -rf "${MNT_DIR}/tmp/yay"*
fi

# 6. Deploy Omarchy ARM
echo "[5/8] Deploying Omarchy arm64 repository..."
mkdir -p "${MNT_DIR}/usr/share/omarchy"
if [[ -d "/home/gmb0yd911/Work/omarchy-arm" ]]; then
  rsync -a --exclude='.git' /home/gmb0yd911/Work/omarchy-arm/ "${MNT_DIR}/usr/share/omarchy/"
fi

# Link all commands
for cmd in "${MNT_DIR}"/usr/share/omarchy/bin/*; do
  cmd_name="$(basename "$cmd")"
  ln -sf "/usr/share/omarchy/bin/${cmd_name}" "${MNT_DIR}/usr/bin/${cmd_name}"
done

echo "[6/8] Executing Omarchy settings, system, and user provisioning..."
arch-chroot "${MNT_DIR}" bash /usr/share/omarchy/install/arm/settings.sh
arch-chroot "${MNT_DIR}" omarchy-apply-system --install-user alarm --first-install
arch-chroot "${MNT_DIR}" su - alarm -c "omarchy-provision-user --force"

# Ensure SDDM autologin, state, and wayland session symlink
install -d -m 0755 "${MNT_DIR}/var/lib/sddm"
cat <<'EOF' > "${MNT_DIR}/var/lib/sddm/state.conf"
[Last]
Session=/usr/local/share/wayland-sessions/omarchy.desktop
User=alarm
EOF
arch-chroot "${MNT_DIR}" chown -R sddm:sddm /var/lib/sddm

mkdir -p "${MNT_DIR}/etc/sddm.conf.d"
cat <<'EOF' > "${MNT_DIR}/etc/sddm.conf.d/autologin.conf"
[Autologin]
User=alarm
Session=omarchy.desktop
EOF

cat <<'EOF' > "${MNT_DIR}/etc/sddm.conf.d/99-omarchy-login.conf"
[Theme]
Current=omarchy

[Users]
RememberLastUser=true
RememberLastSession=true
EOF

mkdir -p "${MNT_DIR}/usr/share/wayland-sessions"
ln -sf /usr/local/share/wayland-sessions/omarchy.desktop "${MNT_DIR}/usr/share/wayland-sessions/omarchy.desktop"

# Arm Omarchy First-Boot Setup Wizard (omarchy-provision-owner)
echo "Arming Omarchy First-Boot Setup Wizard..."
install -Dm644 "${MNT_DIR}/usr/share/omarchy/install/provisioning/omarchy-provision-owner.service" \
  "${MNT_DIR}/etc/systemd/system/omarchy-provision-owner.service"
mkdir -p "${MNT_DIR}/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/omarchy-provision-owner.service \
  "${MNT_DIR}/etc/systemd/system/multi-user.target.wants/omarchy-provision-owner.service"

mkdir -p "${MNT_DIR}/var/lib/omarchy/provisioning"
touch "${MNT_DIR}/var/lib/omarchy/provisioning/pending"
rm -f "${MNT_DIR}/var/lib/omarchy/provisioning/setup-user" "${MNT_DIR}/var/lib/omarchy/provisioning/wipe-pending"

cat <<'EOF' > "${MNT_DIR}/var/lib/omarchy/provisioning/groups"
wheel
video
render
audio
input
seat
storage
docker
EOF

# Allow SSH in UFW
if [[ -f "${MNT_DIR}/etc/ufw/user.rules" ]]; then
  if ! grep -q "dport 22" "${MNT_DIR}/etc/ufw/user.rules"; then
    sed -i '/### END RULES ###/i ### tuple ### allow tcp 22 0.0.0.0\/0 any 0.0.0.0\/0 in\n-A ufw-user-input -p tcp --dport 22 -j ACCEPT\n' "${MNT_DIR}/etc/ufw/user.rules"
  fi
fi
if [[ -f "${MNT_DIR}/etc/ufw/user6.rules" ]]; then
  if ! grep -q "dport 22" "${MNT_DIR}/etc/ufw/user6.rules"; then
    sed -i '/### END RULES ###/i ### tuple ### allow tcp 22 ::\/0 any ::\/0 in\n-A ufw6-user-input -p tcp --dport 22 -j ACCEPT\n' "${MNT_DIR}/etc/ufw/user6.rules"
  fi
fi

# 7. AUR packages if requested
if [[ "${WITH_AUR}" == "--with-aur" || "${WITH_AUR}" == "true" ]]; then
  echo "[7/8] Installing selected desktop AUR packages..."
  for pkg in tzupdate ttf-ia-writer yaru-icon-theme cliamp aether; do
    echo "Processing AUR package: ${pkg}"
    arch-chroot "${MNT_DIR}" su - alarm -c "omarchy-pkg-aur-add ${pkg}" || true
  done
fi

# 8. Cleanup and restore
echo "[8/8] Cleaning package caches and restoring DNS stub..."
arch-chroot "${MNT_DIR}" pacman -Scc --noconfirm || true
rm -rf "${MNT_DIR}/home/alarm/.cache/yay/*" "${MNT_DIR}/home/alarm/.cargo" 2>/dev/null || true
rm -f "${MNT_DIR}/etc/resolv.conf"
ln -sf /run/systemd/resolve/stub-resolv.conf "${MNT_DIR}/etc/resolv.conf"

echo "=== Omarchy Firefly ITX-3588J Provisioning Complete! ==="
