# Omarchy Firefly ITX-3588J (`firefly-itx3588j`)

[![Platform](https://img.shields.io/badge/Architecture-aarch64%20%2F%20ARM64-blue.svg)](https://archlinuxarm.org)
[![Target](https://img.shields.io/badge/Hardware-Firefly%20ITX--3588J-red.svg)](https://en.t-firefly.com/product/industry/itx3588j)
[![SoC](https://img.shields.io/badge/SoC-Rockchip%20RK3588-orange.svg)](https://www.rock-chips.com)
[![Desktop](https://img.shields.io/badge/Compositor-Hyprland%20Wayland-green.svg)](https://hyprland.org)
[![Filesystem](https://img.shields.io/badge/Filesystem-Btrfs%20Subvolumes-yellow.svg)](https://btrfs.readthedocs.io/)

Turnkey image generation and provisioning pipeline for **Omarchy Linux** on the **Firefly ITX-3588J** (Rockchip RK3588).

This repository generates bootable, production-ready Arch Linux ARM images with **Hyprland**, **Btrfs snapshotting**, **Mesa/Panfrost GPU acceleration**, **SDDM**, and the full **Omarchy Desktop Suite**.

---

## Features

- **Rockchip RK3588 Octa-Core Power**: 4x Cortex-A76 + 4x Cortex-A55 cores with full vendor 6.1 BSP kernel and device tree (`rk3588-firefly-itx-3588j.dtb`).
- **Mali-G610 MP4 Hardware Acceleration**: Mesa Panfrost OpenGL & Vulkan drivers driving smooth 60/120 FPS Wayland compositing at 1440p / 4K.
- **Enterprise Btrfs Storage**: Configured with subvolumes (`@`, `@home`, `@snapshots`, `@var_log`, `@pkg`) and transparent zstd:3 compression.
- **Omarchy Desktop Suite**: Complete pre-configured desktop featuring Hyprland, Waybar, SDDM, Foot, Alacritty, PipeWire audio, and First-Boot User Wizard.
- **Offline QEMU Chroot Engine**: Completely unattended image building on x86_64 host using QEMU aarch64 user-mode emulation with Landlock bypass.
- **Remote Hardware Deployment**: Built-in script (`deploy-remote.sh`) to stream and flash images directly to the connected Firefly board over SSH.

---

## Directory Layout

```text
firefly-itx3588j/
├── README.md               # Quickstart and overview
├── build.sh                # End-to-end master build pipeline
├── build-base-image.sh     # Base Arch Linux ARM Btrfs image builder
├── apply-omarchy.sh        # Provision Omarchy desktop suite onto image
├── deploy-remote.sh        # Flash or provision live hardware over SSH
├── scripts/
│   ├── extract-kernel-from-firefly.sh  # Pulls kernel, modules, U-Boot from live board
│   ├── mount-img.sh        # Mounts Btrfs subvolumes to /mnt/firefly_build
│   ├── umount-img.sh       # Safely flushes buffers and detaches loop devices
│   └── chroot-img.sh       # Drops into interactive QEMU aarch64 chroot
├── config/
│   ├── armbianEnv.txt      # U-Boot boot environment with Btrfs root flags
│   ├── boot.cmd            # U-Boot boot script source
│   ├── pacman-chroot.conf  # ALPM sandbox configuration for QEMU chroot
│   ├── yay-config.json     # Non-interactive yay configuration
│   └── qemu-aarch64-static.conf # Binfmt definition with :FPC credentials flag
├── docs/
│   ├── architecture.md     # Partition layout and U-Boot offsets
│   ├── flashing-guide.md   # Local & remote flashing instructions
│   └── hardware-notes.md   # GPU, display, audio, and peripheral details
├── cache/                  # Downloaded rootfs, BSP kernels, modules, U-Boot
└── output/                 # Built .img and .img.zst images
```

---

## Quick Start

### Host Prerequisites
Ensure host system has the required utilities installed (Arch Linux):
```bash
sudo pacman -S --needed qemu-user-static qemu-user-static-binfmt btrfs-progs dosfstools parted zstd rsync
```

### 1. Build the Complete Omarchy Image
To build the complete image (base rootfs + Rockchip U-Boot & kernel + Omarchy desktop):
```bash
sudo ./build.sh
```

### 2. Deploy to Live Firefly Hardware
Deploy the built image directly to the Firefly board's internal SSD (`/dev/sda`) over SSH:
```bash
./deploy-remote.sh firefly flash-image /dev/sda
```

### 3. Inspect or Customize Inside Chroot
```bash
# Mount subvolumes
sudo ./scripts/mount-img.sh archlinuxarm-firefly-itx3588j-btrfs.img

# Enter chroot
sudo ./scripts/chroot-img.sh

# Unmount cleanly
sudo ./scripts/umount-img.sh
```

---

## Default Credentials

| Account | Username | Password | Sudo Access |
|---|---|---|---|
| First-Boot User | `alarm` | `alarm` | Full (`NOPASSWD: ALL` / wheel) |
| Root | `root` | `root` | Full |

*(On first graphical boot, the Omarchy Setup Wizard will prompt you to create your own permanent user).*

---

## Related

- [fedora-firefly-uefi](https://github.com/gmb0yd911/fedora-firefly-uefi): Fedora Cinnamon with a Btrfs root on the same board, booting through
  EDK2 UEFI with Fedora's mainline kernel and device tree.
