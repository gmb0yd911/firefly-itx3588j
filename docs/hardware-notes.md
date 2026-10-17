# Firefly ITX-3588J Hardware Notes

## GPU Acceleration: ARM Mali-G610 MP4

- **Driver Architecture**: In Linux 6.1 BSP, the display subsystem is handled by Rockchip VOP2 DRM (`rockchip-drm`), and 3D graphics are driven by ARM Mali CSF (Command Stream Frontend) kernel base (`mali_kbase.ko`) combined with Panfrost/Mesa.
- **Render Nodes**:
  - `/dev/dri/card0` / `/dev/dri/renderD128`: Display controller & hardware render node
  - `/dev/dri/card1` / `/dev/dri/renderD129`: Auxiliary render node
- **Wayland / Hyprland Compositing**:
  Unlike lower-tier SBC GPUs (such as VideoCore on Raspberry Pi), the Mali-G610 MP4 has 4 shader cores providing ~450 GFLOPS of performance. All Omarchy animations, rounded borders, and dynamic UI effects run at full 60 FPS / 120 FPS without dropped frames.

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
