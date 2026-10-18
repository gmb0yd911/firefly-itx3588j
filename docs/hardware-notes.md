# Firefly ITX-3588J Hardware Notes

## GPU & Display Architecture

- **Display Subsystem**: In Linux 6.1 BSP, display scanout is handled by the Rockchip VOP2 DRM driver (`rockchip-drm` on `/dev/dri/card1`), driving the dual HDMI 2.1 and DP Type-C outputs.
- **GPU Driver Status**:
  - The onboard GPU is an ARM Mali-G610 MP4 (Valhall v10 with Command Stream Frontend / CSF).
  - The Linux 6.1 BSP kernel includes the backported open-source **`panthor.ko`** driver (`/dev/dri/card2` / `/dev/dri/renderD130`) and CSF firmware (`arm/mali/arch10.8/mali_csffw.bin`).
  - **Full Hardware Acceleration (Panthor)**: Enabled by setting `overlays=panthor-gpu` in `/boot/armbianEnv.txt` and updating the Device Tree to flip `gpu` (`mali_kbase`) to `disabled` and `gpu_panthor` to `okay` with `mali-supply = <&vdd_gpu_s0>`. Upstream Mesa automatically binds via `panthor_dri.so` / `vulkan-panfrost` as **Mali-G610 MC4 (Panfrost)**, delivering native hardware OpenGL ES 3.1 and Vulkan acceleration with zero CPU rasterization overhead.

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
