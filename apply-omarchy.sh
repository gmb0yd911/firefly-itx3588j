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
  if [[ -f "${MNT_DIR}/usr/bin/iptables.orig" ]]; then
    mv -f "${MNT_DIR}/usr/bin/iptables.orig" "${MNT_DIR}/usr/bin/iptables"
  fi
  if [[ -f "${MNT_DIR}/usr/bin/ip6tables.orig" ]]; then
    mv -f "${MNT_DIR}/usr/bin/ip6tables.orig" "${MNT_DIR}/usr/bin/ip6tables"
  fi
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
BOOT_FSTYPE=$(blkid -s TYPE -o value "${LOOP_DEV}p1" || echo "auto")
mount -t "${BOOT_FSTYPE}" "${LOOP_DEV}p1" "${MNT_DIR}/boot"

# 2. Configure QEMU binfmt and pacman sandbox settings
echo "[2/8] Setting up binfmt and pacman sandbox overrides..."
if [[ -f /etc/binfmt.d/qemu-aarch64-static.conf ]]; then
  systemctl restart systemd-binfmt 2>/dev/null || true
fi

# Disable pacman sandboxing and space checking for user-mode chroot
sed -i '/DisableSandboxFilesystem/d' "${MNT_DIR}/etc/pacman.conf"
sed -i '/DisableSandboxSyscalls/d' "${MNT_DIR}/etc/pacman.conf"
sed -i '/CheckSpace/d' "${MNT_DIR}/etc/pacman.conf"
sed -i '/\[options\]/a DisableSandboxFilesystem\nDisableSandboxSyscalls' "${MNT_DIR}/etc/pacman.conf"

# Setup temporary DNS
rm -f "${MNT_DIR}/etc/resolv.conf"
echo "nameserver 1.1.1.1" > "${MNT_DIR}/etc/resolv.conf"
echo "nameserver 8.8.8.8" >> "${MNT_DIR}/etc/resolv.conf"

# 3. Keyring & Base build tools
echo "[3/8] Initializing keyring, locales, and base packages..."
echo "en_US.UTF-8 UTF-8" > "${MNT_DIR}/etc/locale.gen"
arch-chroot "${MNT_DIR}" locale-gen || true
echo "LANG=en_US.UTF-8" > "${MNT_DIR}/etc/locale.conf"

arch-chroot "${MNT_DIR}" pacman-key --init
arch-chroot "${MNT_DIR}" pacman-key --populate archlinuxarm
arch-chroot "${MNT_DIR}" pacman -Sy --noconfirm --needed --overwrite '*' base-devel git go sudo btrfs-progs

# 4. User and sudo setup
echo "[4/8] Configuring alarm user and yay non-interactive setup..."
for grp in wheel video render audio input seat storage docker; do
  arch-chroot "${MNT_DIR}" groupadd -f "$grp"
done

if ! grep -q "^alarm:" "${MNT_DIR}/etc/passwd"; then
  arch-chroot "${MNT_DIR}" useradd -m -G wheel,video,render,audio,input,seat,storage,docker -s /bin/bash alarm
else
  arch-chroot "${MNT_DIR}" usermod -aG wheel,video,render,audio,input,seat,storage,docker alarm
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
if ! arch-chroot "${MNT_DIR}" command -v yay &>/dev/null; then
  echo "Building and installing yay from source..."
  rm -rf "${MNT_DIR}/tmp/yay"
  arch-chroot "${MNT_DIR}" su - alarm -c "git clone --depth 1 https://aur.archlinux.org/yay.git /tmp/yay && cd /tmp/yay && makepkg -si --noconfirm"
  rm -rf "${MNT_DIR}/tmp/yay"
fi

# Wrap iptables and ip6tables for QEMU chroot execution
if [[ ! -f "${MNT_DIR}/usr/bin/iptables.orig" && -f "${MNT_DIR}/usr/bin/iptables" ]]; then
  mv "${MNT_DIR}/usr/bin/iptables" "${MNT_DIR}/usr/bin/iptables.orig"
  cat <<'EOF' > "${MNT_DIR}/usr/bin/iptables"
#!/bin/bash
if [[ "$*" =~ (-V|--version) ]]; then
  echo "iptables v1.8.13 (nf_tables)"
  exit 0
fi
exec -a iptables /usr/bin/iptables.orig "$@"
EOF
  chmod +x "${MNT_DIR}/usr/bin/iptables"
fi

if [[ ! -f "${MNT_DIR}/usr/bin/ip6tables.orig" && -f "${MNT_DIR}/usr/bin/ip6tables" ]]; then
  mv "${MNT_DIR}/usr/bin/ip6tables" "${MNT_DIR}/usr/bin/ip6tables.orig"
  cat <<'EOF' > "${MNT_DIR}/usr/bin/ip6tables"
#!/bin/bash
if [[ "$*" =~ (-V|--version) ]]; then
  echo "ip6tables v1.8.13 (nf_tables)"
  exit 0
fi
exec -a ip6tables /usr/bin/ip6tables.orig "$@"
EOF
  chmod +x "${MNT_DIR}/usr/bin/ip6tables"
fi

# 6. Deploy and execute Omarchy ARM installer
echo "[6/8] Deploying Omarchy arm64 repository and executing installer..."
mkdir -p "${MNT_DIR}/home/alarm/omarchy-arm"
if [[ -d "/home/gmb0yd911/Work/omarchy-arm" ]]; then
  rsync -a --exclude='.git' /home/gmb0yd911/Work/omarchy-arm/ "${MNT_DIR}/home/alarm/omarchy-arm/"
fi
arch-chroot "${MNT_DIR}" chown -R alarm:alarm /home/alarm/omarchy-arm

echo "Running Omarchy ARM installer inside chroot (resolving packages, system, and user setup)..."
arch-chroot "${MNT_DIR}" su - alarm -c "cd /home/alarm/omarchy-arm && ./install.sh -y"

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

if ! grep -q "OMARCHY_PATH" "${MNT_DIR}/etc/environment" 2>/dev/null; then
  echo "OMARCHY_PATH=/usr/share/omarchy" >> "${MNT_DIR}/etc/environment"
fi

# Install EDID firmware override for Dell P2720DC QHD monitor
if [[ -f "${WORK_DIR}/config/edid/dell_p2720dc.bin" ]]; then
  echo "Installing EDID firmware for Dell P2720DC..."
  install -Dm644 "${WORK_DIR}/config/edid/dell_p2720dc.bin" "${MNT_DIR}/usr/lib/firmware/edid/dell_p2720dc.bin"
fi

# Default monitor scale to 1 (prevent 2x scaling down on 1080p/1440p displays)
if [[ -f "${MNT_DIR}/usr/share/omarchy/config/hypr/monitors.lua" ]]; then
  sed -i 's/local omarchy_monitor_scale = "auto"/local omarchy_monitor_scale = 1/' "${MNT_DIR}/usr/share/omarchy/config/hypr/monitors.lua"
  sed -i 's/local omarchy_gdk_scale = 2/local omarchy_gdk_scale = 1/' "${MNT_DIR}/usr/share/omarchy/config/hypr/monitors.lua"
fi
if [[ -f "${MNT_DIR}/etc/skel/.config/hypr/monitors.lua" ]]; then
  sed -i 's/local omarchy_monitor_scale = "auto"/local omarchy_monitor_scale = 1/' "${MNT_DIR}/etc/skel/.config/hypr/monitors.lua"
  sed -i 's/local omarchy_gdk_scale = 2/local omarchy_gdk_scale = 1/' "${MNT_DIR}/etc/skel/.config/hypr/monitors.lua"
fi

# Transparent scrims for software backend (prevents Wayland layer-surface opaque black overlay)
if [[ -f "${MNT_DIR}/usr/share/omarchy/shell/Commons/Color.qml" ]]; then
  sed -i 's/property color scrim: root.composed("menu.scrim", "menu.scrim-alpha", root.background, 0.5)/property color scrim: "transparent"/' "${MNT_DIR}/usr/share/omarchy/shell/Commons/Color.qml"
  sed -i 's/property color scrim: root.composed("polkit.scrim", "polkit.scrim-alpha", root.background, 0.5)/property color scrim: "transparent"/' "${MNT_DIR}/usr/share/omarchy/shell/Commons/Color.qml"
  sed -i 's/property color scrim: root.composed("image-picker.scrim", "image-picker.scrim-alpha", root.background, 0.5)/property color scrim: "transparent"/' "${MNT_DIR}/usr/share/omarchy/shell/Commons/Color.qml"
fi
if [[ -f "${MNT_DIR}/usr/share/omarchy/shell/plugins/menu/Menu.qml" ]]; then
  sed -i 's/property color scrim: Color.menu.scrim/property color scrim: "transparent"/' "${MNT_DIR}/usr/share/omarchy/shell/plugins/menu/Menu.qml"
fi

# Pin QtQuick imports to 6.0 across all shell QML files to avoid Qt 6.12+ Color singleton conflict
if [[ -d "${MNT_DIR}/usr/share/omarchy/shell" ]]; then
  echo "Pinning QtQuick imports to 6.0 to avoid Qt 6.12+ Color singleton shadowing..."
  find "${MNT_DIR}/usr/share/omarchy/shell" -name '*.qml' -exec sed -i 's/^import QtQuick$/import QtQuick 6.0/' {} +
fi

# Performance and input tuning for Firefly (RK3588 with Mali-G610 Panthor GPU acceleration)
if [[ -f "${MNT_DIR}/usr/share/omarchy/default/hypr/platform/firefly.lua" ]]; then
  echo "Tuning Firefly Hyprland platform profile..."
  cat <<'EOF' > "${MNT_DIR}/usr/share/omarchy/default/hypr/platform/firefly.lua"
-- Firefly ITX-3588J (Rockchip RK3588) defaults.
-- Native hardware acceleration enabled via Panthor + Mesa Panfrost (Mali-G610 MC4).
-- Comfortable keyboard repeat thresholds and responsive pointer profile.

hl.config({
  cursor = {
    no_hardware_cursors = false,
  },
  input = {
    repeat_delay = 600,
    repeat_rate = 25,
    sensitivity = 0.5,
    accel_profile = "adaptive",
  },
})
EOF
fi

if [[ -f "${MNT_DIR}/etc/skel/.config/hypr/input.lua" ]]; then
  cat <<'EOF' > "${MNT_DIR}/etc/skel/.config/hypr/input.lua"
-- Keep only your personal input overrides here.

hl.config({
  input = {
    repeat_delay = 600,
    repeat_rate = 25,
    sensitivity = 0.5,
    accel_profile = "adaptive",
  },
})
EOF
fi

# Prevent unrecoverable DPMS blanking on desktop SBC with external HDMI/DP monitors
if [[ -f "${MNT_DIR}/usr/share/omarchy/bin/omarchy-brightness-display" ]]; then
  echo "Patching omarchy-brightness-display to protect external displays from DPMS disconnects..."
  python3 -c "
import re
path = '${MNT_DIR}/usr/share/omarchy/bin/omarchy-brightness-display'
with open(path, 'r') as f:
    text = f.read()
repl = '''if [[ \$step == \"off\" ]]; then
  # On desktop SBC hardware with external displays, disable DPMS power-off to avoid
  # dropping HDMI/DP VOP2 pipeline links and unrecoverable sleep states.
  if omarchy-hw-laptop; then
    hyprctl dispatch \'hl.dsp.dpms({ action = \"disable\" })\' >/dev/null 2>&1
  fi
  exit 0'''
text = re.sub(r'if \[\[ \\\$step == \"off\" \]\]; then.*?exit 0', repl, text, flags=re.DOTALL)
with open(path, 'w') as f:
    f.write(text)
"
fi

# Suppress /sys/class/dmi/id/chassis_type error on Device Tree ARM boards
if [[ -f "${MNT_DIR}/usr/share/omarchy/bin/omarchy-hw-laptop" ]]; then
  echo "Patching omarchy-hw-laptop for non-DMI Device Tree systems..."
  cat <<'EOF' > "${MNT_DIR}/usr/share/omarchy/bin/omarchy-hw-laptop"
#!/bin/bash

# omarchy:summary=Returns true when running on a laptop (has a lid or laptop chassis).

# A lid switch is the definitive signal for clamshell-capable hardware.
for state in /proc/acpi/button/lid/*/state; do
  [[ -e $state ]] && exit 0
done

# Fall back to the DMI chassis type for laptops that don't expose an ACPI lid
# button. 8=Portable 9=Laptop 10=Notebook 14=Sub Notebook 30=Tablet
# 31=Convertible 32=Detachable.
if [[ -f /sys/class/dmi/id/chassis_type ]]; then
  case $(< /sys/class/dmi/id/chassis_type 2>/dev/null) in
  8 | 9 | 10 | 14 | 30 | 31 | 32) exit 0 ;;
  esac
fi

exit 1
EOF
  chmod 755 "${MNT_DIR}/usr/share/omarchy/bin/omarchy-hw-laptop"
fi

# Configure relaxed desktop idle timeouts (15m screensaver, 30m lock)
mkdir -p "${MNT_DIR}/etc/skel/.config/omarchy"
cat <<'EOF' > "${MNT_DIR}/etc/skel/.config/omarchy/shell.json"
{
  "version": 1,
  "idle": {
    "screensaver": 900,
    "lock": 1800
  }
}
EOF

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
if [[ -f "${MNT_DIR}/usr/bin/iptables.orig" ]]; then
  mv -f "${MNT_DIR}/usr/bin/iptables.orig" "${MNT_DIR}/usr/bin/iptables"
fi
if [[ -f "${MNT_DIR}/usr/bin/ip6tables.orig" ]]; then
  mv -f "${MNT_DIR}/usr/bin/ip6tables.orig" "${MNT_DIR}/usr/bin/ip6tables"
fi
arch-chroot "${MNT_DIR}" pacman -Scc --noconfirm || true
rm -rf "${MNT_DIR}/home/alarm/.cache/yay/*" "${MNT_DIR}/home/alarm/.cargo" 2>/dev/null || true
rm -f "${MNT_DIR}/etc/resolv.conf"
ln -sf /run/systemd/resolve/stub-resolv.conf "${MNT_DIR}/etc/resolv.conf"

echo "=== Omarchy Firefly ITX-3588J Provisioning Complete! ==="
