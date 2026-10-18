# Firefly ITX-3588J Hardware Notes

## GPU & Display Architecture

- **Display Subsystem**: In Linux 6.1 BSP, display scanout is handled by the Rockchip VOP2 DRM driver (`rockchip-drm` on `/dev/dri/card1`), driving the dual HDMI 2.1 and DP Type-C outputs.
- **GPU Driver Status**:
  - The onboard GPU is an ARM Mali-G610 MP4 (Valhall v10 with Command Stream Frontend / CSF).
  - On the **Linux 6.1 BSP kernel**, the kernel includes ARM's out-of-tree `mali_kbase.ko` (`/dev/mali0`). Standard upstream Mesa cannot communicate with `mali_kbase.ko` (upstream Panthor was only mainlined in Linux 6.10+).
  - Without an explicit driver override, upstream Mesa attempts hardware DRI2 on `rockchip-drm`, fails, falls back to Zink, and causes Wayland compositors (like Hyprland/Aquamarine) to crash with `EGL_NOT_INITIALIZED: DRI2: failed to create screen`.
  - **Resolution on 6.1 BSP**: Set `MESA_LOADER_DRIVER_OVERRIDE=kms_swrast`, `QT_QUICK_BACKEND=software`, and `OMARCHY_PATH=/usr/share/omarchy` in `/etc/environment`. Mesa pairs Rockchip VOP2 KMS with the multithreaded `llvmpipe` software rasterizer for the Wayland compositor, and Qt Quick 2D software rendering prevents LLVMpipe multi-threaded tile SEGV crashes in the Quickshell desktop shell.
  - **Full Hardware Acceleration (Panthor)**: Native kernel-level hardware acceleration with open-source Mesa Panfrost/PanVK requires a Linux 6.10+ mainline or backported Panthor kernel.

## Display Configuration

- **Dual HDMI 2.1**: The ITX-3588J board provides two full-sized HDMI 2.1 outputs capable of 8K@60Hz or 4K@120Hz.
- **DisplayPort over Type-C**: Supported via the front USB-C interface.
- **Frame Buffer Resolution**: The console and Plymouth splash automatically query EDID; tested and verified at 2560x1440p60.

## Audio & Peripherals

- **Audio Codec**: Realtek ALC5640 / ES8388 audio codecs on board. PipeWire manages all digital HDMI and analog audio sinks.
- **Serial Debugging**:
  Debug UART header is exposed at `ttyS2` with baud rate `1500000` (Rockchip default high-speed UART).
- **PCIe & SATA**:
  M.2 PCIe 3.0 x4 slot supports NVMe storage. Onboard SATA 3.0 controller supports four SATA 6Gbps drives.
