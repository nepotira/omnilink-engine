# Project State: OmniLink Mobile Engine

- **Project Name**: OmniLink Mobile Engine (formerly POCO Game Engine)
- **Version**: 2.0.0 (SemVer 2.0.0)
- **Status**: Production Ready / Universalized
- **Repository**: `nepotira/omnilink-engine` (GitHub)
- **Architecture**:
  - **GUI**: Python 3 + GTK 4 + Libadwaita (`app/main.py`, `app/ui/`, `app/backend/`)
  - **Engine Core**: Bash + scrcpy 5.0+ (`omnilink.sh`, backwards-compatible `poco-gaming.sh`)
  - **Packaging**: Freedesktop Desktop Entry (`omnilink.desktop`), SVG vector icon (`assets/omnilink.svg`)
- **Key Capabilities & Verified Modules**:
  1. **Universal SoC Hardware Detection**: Dynamic encoder selection across Qualcomm Snapdragon, MediaTek Dimensity, Samsung Exynos, and Google Tensor.
  2. **Universal Host GPU VA-API Acceleration**: Hardware decoding via Intel VA-API, AMD Mesa VA-API, and NVIDIA NVDEC.
  3. **Universal Aspect Ratio Fitting**: Dynamic DRM detection for 3:2, 16:9, 16:10, and 21:9 monitors.
  4. **Global Screen Off Control**: Dedicated UI toggle and runtime shortcut (`Alt+O`) across all modes.
  5. **Android Desktop DeX Mode**: Freeform multi-window environment with taskbar, start menu, and app drawer via `com.levelup.droiduplauncher`.
  6. **Pure 1:1 Mirroring Mode**: Zero resolution modification, preserving 100% of home screen icon layouts.
  7. **Hardware KVM Mode**: Direct USB HID control with strict device serial binding (`-s "$DEVICE_SERIAL"`), preventing webcam device collision.
  8. **Zero-to-Function Automated Installer**: Automatic udev configuration and dependency checks on first run.
