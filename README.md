# OmniLink Mobile Engine

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux%20(Wayland%20%26%20X11)-blue.svg)](https://www.kernel.org)
[![Android: 9-17+](https://img.shields.io/badge/Android-9%20to%2017%2B-green.svg)](https://www.android.com)

**OmniLink Mobile Engine** is a universal, ultra-low latency gaming and desktop automation suite for Android smartphones and Linux workstations. Engineered with native **GTK 4 / Libadwaita** and optimized for any display geometry (3:2, 16:9, 16:10, 21:9), it delivers sub-frame input response and full desktop multi-window multitasking.

---

## Key Features

- **Universal SoC & Hardware Acceleration**:
  - Automatically identifies silicon architecture (**Qualcomm Snapdragon**, **MediaTek Dimensity**, **Samsung Exynos**, **Google Tensor**) and locks dedicated hardware HEVC/AVC encoders.
  - Zero-copy hardware decoding on Linux via Intel VA-API, AMD Mesa VA-API, and NVIDIA NVDEC.
- **Aspect Ratio Fitting (Zero Black Borders)**:
  - Dynamically calculates proportional DPI and matches device framebuffer geometry to host monitors (e.g. 1920x1280 3:2, 1920x1080 16:9, 2560x1600 16:10).
- **Android Desktop DeX Mode**:
  - Launches a secondary virtual display with floating resizable windows, taskbar, start menu, and full multi-window multitasking via `com.levelup.droiduplauncher`.
- **Pure 1:1 Mirroring Mode**:
  - Native mirror without altering physical resolution or DPI, preserving 100% of your home screen icon arrangements.
- **Hardware KVM Dock Mode (USB-OTG)**:
  - Connects your PC physical keyboard and mouse directly to Android via USB HID with sub-millisecond hardware latency (bypassing ADB and software layers).
- **Dynamic Refresh Rate Sync**:
  - Matches the Android display pipeline to the host monitor's native refresh rate (60 Hz, 120 Hz, 144 Hz) for judder-free VSYNC alignment and reduced battery heating.
- **Direct Kernel UHID**:
  - Zero-latency game controller passthrough via Linux UHID kernel module.
- **Global Screen Power Toggle**:
  - Turn physical phone screen off during sessions to eliminate thermal throttling, with live toggle (`Alt+O`).
- **Fail-Safe Restoration Trap**:
  - Guaranteed automatic restoration of screen resolution, density, refresh rate, orientation, and laptop sensor locks upon exit or cable disconnect.

---

## Quick Start

### Graphical User Interface (GUI)
Double-click the **OmniLink Mobile Engine** icon on your Linux Desktop or run from terminal:

```bash
cd omnilink-engine
./omnilink-gui
```

### Command Line Interface (CLI)
OmniLink is completely self-contained ("Zero to Function"). It automatically checks dependencies and configures universal udev rules on first run:

```bash
# Fullscreen Gaming Mode (Auto Aspect Ratio Adaptation)
./omnilink.sh

# Android Desktop DeX Mode
./omnilink.sh --dex

# Pure 1:1 Mirroring (Preserves Icon Layouts)
./omnilink.sh --mirror

# Hardware KVM Dock Mode
./omnilink.sh --otg

# Emergency Recovery (Restores factory display settings)
./omnilink.sh --reset
```

---

## Operational Profiles

| Mode | Target Resolution | Bitrate | Buffer | Best For |
| :--- | :--- | :--- | :--- | :--- |
| **Gamer Max** | Host Native (e.g. 1920x1280 3:2) | 16 Mbps | 0 ms | Competitive mobile gaming, emulators (Switch, PS2) |
| **Esports Eco** | Optimized (e.g. 1280x854 3:2) | 8 Mbps | 0 ms | Extended gaming sessions, lower thermal budget |
| **Desktop DeX** | Virtual Display (1920x1280) | 16 Mbps | 0 ms | Multi-window productivity, floating windows, office apps |
| **Pure Mirror** | Device Native (1:1 Unscaled) | 16 Mbps | 0 ms | Quick screen mirroring, zero icon scrambling |
| **KVM Dock** | Direct Hardware USB HID | N/A | 0 ms | Controlling phone directly using PC keyboard/mouse |

---

## Architecture & Documentation

- [Hardware Compatibility Matrix](docs/HARDWARE_MATRIX.md)
- [Project State & Engineering Roadmap](docs/PROJECT_STATE.md)
- [Environment & Dependencies Specification](docs/ENVIRONMENT.md)
- [Development Journal](docs/JOURNAL.md)
- [Architectural Decision Records (ADRs)](docs/adr/)

---

## License

OmniLink Mobile Engine is released under the [MIT License](LICENSE).
