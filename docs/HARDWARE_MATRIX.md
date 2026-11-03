# Universal Hardware & Adaptability Matrix

**Project**: OmniLink Mobile Engine  
**Version**: 2.0.0  
**Scope**: Universal compatibility across all Android SoCs, Host Linux GPUs, Display Geometries, and Network/USB Interfaces.

---

## 1. Android Mobile Platforms (SoCs & Video Encoders)

OmniLink dynamically queries the connected device's MediaCodec subsystem (`scrcpy --list-encoders`) and selects the highest-priority hardware encoder available on the silicon:

| SoC Architecture / Vendor | Primary Hardware Encoder (HEVC / H.265) | Secondary Fallback (AVC / H.264) | Latency Profile | Features & Optimizations |
| :--- | :--- | :--- | :--- | :--- |
| **Qualcomm Snapdragon**<br>*(8 Elite, 8 Gen 1-3, 7+, 888)* | `c2.qti.hevc.encoder`<br>`OMX.qcom.video.encoder.hevc` | `c2.qti.avc.encoder`<br>`OMX.qcom.video.encoder.avc` | **Ultra-Low (< 2ms)** | Injected `--video-codec-options=latency:int=0,priority:int=0`. 10-bit HDR support, zero frame buffering. |
| **MediaTek Dimensity / Helio**<br>*(9400, 9300, 8300, G99)* | `c2.mtk.hevc.encoder`<br>`OMX.MTK.VIDEO.ENCODER.HEVC` | `c2.mtk.avc.encoder`<br>`OMX.MTK.VIDEO.ENCODER.AVC` | **Low (< 4ms)** | Hardware MediaTek MiraVision low-latency pipeline. Power-efficient encoding. |
| **Samsung Exynos**<br>*(2400, 2200, 2100, 1380)* | `c2.exynos.hevc.encoder`<br>`OMX.Exynos.HEVC.Encoder` | `c2.exynos.avc.encoder`<br>`OMX.Exynos.AVC.Encoder` | **Low (< 4ms)** | Samsung MFC (Multi-Format Codec) dedicated silicon acceleration. |
| **Google Tensor**<br>*(G1, G2, G3, G4)* | `c2.android.hevc.encoder` (Hardware accelerated) | `c2.android.avc.encoder` | **Low (< 5ms)** | ARM Mali / Immortalis GPU hardware coordination. |
| **Budget / Legacy SoCs**<br>*(Unisoc, Allwinner, Rockchip)* | `c2.android.hevc.encoder` | `c2.android.avc.encoder` | **Adaptive (8-15ms)** | Dynamic bitrate downscaling (6-8 Mbps), baseline profile fallback. |

---

## 2. Linux Host Workstations (GPU Decoders & Display Drivers)

OmniLink detects the host's GPU vendor via DRM sysfs (`/sys/class/drm/card*`) and queries VA-API/NVDEC capabilities:

| Host GPU Architecture | Kernel Driver | Userspace Acceleration API | scrcpy Pipeline Configuration | Fallback Behavior |
| :--- | :--- | :--- | :--- | :--- |
| **Intel Graphics**<br>*(UHD, Iris Xe, Intel Arc)* | `i915` / `xe` | **VA-API** (`intel-media-va-driver`) | `--video-codec=h265`, Zero-copy OpenGL/VA-API texture streaming. | VA-API H.264 profile or Mesa software rasterizer. |
| **AMD Radeon**<br>*(RDNA 1-3, Vega, Polaris)* | `amdgpu` | **Mesa VA-API** (`radeonsi`) | Direct VA-API hardware decoding through Mesa radeonsi. | VDPAU or Mesa llvmpipe. |
| **NVIDIA GeForce**<br>*(RTX 20/30/40, GTX 16xx)* | `nvidia` (Proprietary) | **NVDEC** via `nvidia-vaapi-driver` or VDPAU | Native NVDEC decoding; hardware VSYNC synchronization. | Multi-threaded CPU decoding via `libavcodec`. |
| **Virtual Machines / Headless**<br>*(QEMU, KVM, VirtualBox)* | `virtio-gpu` / `llvmpipe` | **Mesa Software OpenGL** | Adaptive software rendering with 15ms buffer to avoid audio/video desync. | 720p 30/60 FPS ceiling. |

---

## 3. Display Aspect Ratios & Geometry Adaptation

OmniLink computes the host monitor's geometry and applies proportional density scaling:

$$\text{Proportional DPI} = \text{clamp}\left(\frac{\text{Native Device DPI} \times \text{Host Height}}{\text{Native Device Height}},\, 240,\, 420\right)$$

| Host Aspect Ratio | Sample Resolutions | Adaptation Strategy | Target DPI Clamp | Mode Compatibility |
| :--- | :--- | :--- | :--- | :--- |
| **3:2** (Productivity / Tablet) | 1920x1280, 2256x1504, 3000x2000 | 100% Fullscreen fit, zero black letterboxing. | 260 - 320 DPI | Gamer Max, Eco, DeX, Virtual |
| **16:9** (Standard Desktop/TV) | 1920x1080, 2560x1440, 3840x2160 | Native 16:9 widescreen match. | 240 - 280 DPI | All Modes |
| **16:10** (Modern Laptops/Macs) | 1920x1200, 2560x1600, 2880x1800 | Exact 16:10 proportional rendering. | 260 - 300 DPI | All Modes |
| **21:9** (Ultrawide Gaming) | 2560x1080, 3440x1440, 5120x2160 | Expanded horizontal FOV for supported Android games. | 280 - 340 DPI | Gamer Max, DeX |
| **Native Device Ratio** | 9:19.5, 9:20 (e.g. 1280x2772) | **Pure 1:1 Mirroring Mode**: Zero resolution mutation; natural pillarbox on host. | Native (e.g. 520) | Espelhamento Simples |

---

## 4. Connectivity, Latency, and Buffer Profiles

| Interface Channel | Bandwidth Ceiling | Jitter Profile | Video Buffer | Audio Buffer | Target Bitrate | Ideal Use-Case |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **USB 3.0 / 3.2 Gen 1/2** | 5.0 - 10 Gbps | Ultra-Low (< 0.1ms) | `0 ms` | `30 ms` | 20 Mbps (HEVC) | Competitive Esports, Switch/PS2 Emulation |
| **USB 2.0 (High Speed)** | 480 Mbps | Low (< 0.5ms) | `0 ms` | `50 ms` | 16 Mbps (HEVC) | Universal standard USB connection |
| **Hardware KVM (USB-OTG)** | Direct USB HID | Instantaneous (< 0.01ms) | N/A (No Video) | N/A | N/A | Zero-latency mouse/keyboard without PC screen |
| **Wi-Fi 6 / 6E (802.11ax)** | 600 - 2400 Mbps | Low (1-3ms) | `5 ms` | `60 ms` | 12 Mbps (HEVC) | Wireless Desktop & Gaming |
| **Wi-Fi 5 (802.11ac 5GHz)** | 200 - 450 Mbps | Medium (4-8ms) | `10 ms` | `80 ms` | 10 Mbps (H.264/HEVC) | Wireless Productivity |
| **Wi-Fi 2.4 GHz (Legacy)** | 30 - 72 Mbps | High (10-30ms) | `25 ms` | `120 ms` | 6 Mbps (H.264) | Emergency fallback |
