# Firefly ITX-3588J: EDK2 UEFI BIOS & Omarchy Guide

This guide details how to use **EDK2 UEFI BIOS** (`edk2-rk3588`) with Omarchy ARM on the **Firefly ITX-3588J** motherboard.

---

## 1. Overview & Advantages

The standard Rockchip boot process uses Rockchip U-Boot with raw partition offsets (sector 64 and 16384) and proprietary distro-boot scripts (`armbianEnv.txt` / `boot.scr`).

By installing **EDK2 UEFI** (TianoCore) to the Firefly board's eMMC or onboard SPI NOR flash:
- **True PC-Like UEFI Experience**: A standard BIOS setup screen (accessible via `ESC` or `F2`) and boot selection menu (`F12`).
- **Standard EFI System Partition (ESP)**: The OS drive uses a standard GPT layout with a 512 MiB **FAT32** partition flagged as `boot, esp`, containing standard `\EFI\BOOT\BOOTAA64.EFI`.
- **Plug-and-Play Drive Booting**: Any SATA SSD, PCIe NVMe M.2 SSD, or USB drive can be booted directly by EDK2 without needing U-Boot flashing or eMMC redirect scripts.
- **Native systemd-boot**: Boots the Linux kernel directly via its ARM64 EFI stub (`CONFIG_EFI_STUB=y`) with device tree integration.

---

## 2. Disk Layout Comparison

```
Traditional Rockchip U-Boot Image:
[Raw Sectors 0-32767: U-Boot SPL & ITB]
├── Partition 1: 512 MiB ext4 (/boot with boot.scr / armbianEnv.txt)
└── Partition 2: Remainder Btrfs root (@, @home, @snapshots, etc.)

EDK2 UEFI Image (Standard PC Layout):
[Standard Protective MBR / GPT Header]
├── Partition 1: 512 MiB FAT32 EFI System Partition (/boot)
│   ├── EFI/BOOT/BOOTAA64.EFI (systemd-boot ARM64)
│   ├── EFI/systemd/systemd-bootaa64.efi
│   ├── loader/
│   │   ├── loader.conf
│   │   └── entries/omarchy.conf
│   ├── dtb/rockchip/rk3588-firefly-itx-3588j.dtb
│   ├── vmlinuz-6.1.115-vendor-rk35xx
│   └── initrd.img-6.1.115-vendor-rk35xx
└── Partition 2: Remainder Btrfs root (@, @home, @snapshots, etc.)
```

---

## 3. Building the UEFI Omarchy Image

In this repository, build the UEFI base image and provision Omarchy onto it:

```bash
# 1. Build the base UEFI GPT image with FAT32 ESP + Btrfs subvolumes:
sudo ./build-uefi-image.sh

# 2. Provision the full Omarchy desktop (Hyprland, SDDM, apps, themes):
sudo ./apply-omarchy.sh archlinuxarm-firefly-itx3588j-uefi-btrfs.img
```

The resulting image (`archlinuxarm-firefly-itx3588j-uefi-btrfs.img`) is a standard UEFI disk image.

---

## 4. Flashing EDK2 UEFI to the Hardware

The official pre-compiled firmware image `itx-3588j_UEFI_Release_v1.1.img` (from `edk2-porting/edk2-rk3588`) is cached in `cache/edk2/`.

### Flashing over SSH to eMMC:
```bash
./scripts/flash-edk2.sh firefly /dev/mmcblk0
```

> [!WARNING]
> Flashing EDK2 to `/dev/mmcblk0` will replace the existing bootloader on eMMC. Make sure any important data on the eMMC has been backed up.

---

## 5. Required EDK2 BIOS Settings

When booting with EDK2 for the first time:

1. Attach an HDMI display to **HDMI Output 1** (top port) and connect a USB keyboard.
2. Power on the Firefly board.
3. Tap **ESC** or **F2** repeatedly as soon as power is applied to enter the **EDK2 Setup Utility**.
4. Navigate to:
   ```
   Device Manager -> Rockchip Platform Configuration
   ```
5. Set **Config Table Mode** to **Device Tree (FDT)** (do *not* leave on ACPI).
   > [!IMPORTANT]
   > Linux 6.1 with Panfrost Mali-G610 GPU acceleration, VOP2 HDMI 2.1 display controller, sound, and NPU requires the Rockchip Device Tree (`rk3588-firefly-itx-3588j.dtb`). ACPI mode only supports basic generic peripherals.
6. Press **F10** to save settings, then **ESC** to exit and reboot.

---

## 6. Flashing & Deploying the UEFI Image

You can flash the provisioned UEFI image to your SATA SSD (`/dev/sda`), NVMe SSD, or USB drive:

```bash
./deploy-remote.sh firefly flash-image /dev/sda
```

EDK2 will detect the drive's EFI System Partition and boot directly into Omarchy!
