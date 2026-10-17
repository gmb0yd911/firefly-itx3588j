# Flashing & Deployment Guide

This guide covers flashing the generated Omarchy image onto a microSD card, USB drive, or internal M.2 SSD for the **Firefly ITX-3588J**.

---

## 1. Remote Direct Deployment (Over SSH)

If your Firefly ITX-3588J board is currently booted (e.g. running the factory Armbian or another OS on eMMC), you can stream the image directly to the internal M.2 SSD (`/dev/sda`):

```bash
# From this repository:
./deploy-remote.sh firefly flash-image /dev/sda
```

This decompresses the image on the fly and streams it over SSH with `dd` and `conv=fsync`.

---

## 2. Local Flashing (SD Card or USB to NVMe Adapter)

If you are flashing locally on your host workstation:

### Decompress the Image:
```bash
zstd -d -k output/archlinuxarm-firefly-itx3588j-btrfs.img.zst
```

### Identify the Block Device:
```bash
lsblk
```
> [!CAUTION]
> Verify the target device carefully (e.g., `/dev/sdX`). Writing to the wrong device will overwrite your workstation drives!

### Write the Image:
```bash
sudo dd if=output/archlinuxarm-firefly-itx3588j-btrfs.img of=/dev/sdX bs=4M status=progress oflag=sync
```

---

## 3. Post-Boot First-Time Setup

1. Connect HDMI display to HDMI output 1 (top HDMI port).
2. Attach Ethernet cable to ETH1 or ETH2.
3. Power on the system.
4. Omarchy will auto-login to the `alarm` user session and launch the **Omarchy First-Boot Setup Wizard** (`omarchy-provision-owner`), prompting for your permanent username, display name, and password.
5. SSH access is pre-configured and allowed through UFW on port 22:
   - User: `alarm` (password `alarm`)
   - Root: `root` (password `root`)
