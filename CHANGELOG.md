# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2026-11-08

### Added
- **PC Window Orientation Controls**: Introduced tri-state window orientation in the GTK4/Libadwaita GUI (`Orientação da Janela no Computador`) and CLI flags (`--window-auto`, `--window-horizontal`, `--window-vertical`).
- **Dynamic Real-Time Window Rotation**: When set to Automatic, the computer window automatically flips between portrait and landscape following the phone's physical or in-app rotation.
- **Forced Horizontal and Vertical Window Views**: Added dedicated locked capture orientation options (`--capture-orientation=@270` for Landscape and `--capture-orientation=@0` for Portrait) without altering physical phone hardware settings.

### Fixed
- **Device Accelerometer Interference**: Eliminated invasive `wm user-rotation lock` and `accelerometer_rotation 0` calls, ensuring the Android device's internal rotation sensor remains fully active and unconstrained.
- **Resolution Scaling Overrides**: Prevented forced 1920x1280 landscape display overrides when running in Automatic or Vertical window modes, preserving seamless dynamic rotation.

## [2.0.0] - 2026-11-03

### Added
- **Universal Engine Rebranding**: Transitioned from "POCO Game Engine" to **OmniLink Mobile Engine** with dynamic SoC, GPU, and vendor detection.
- **Pure 1:1 Mirroring Mode**: Added dedicated mirror profile preserving native phone resolution and 100% of home screen icon layouts.
- **Global Screen Power Toggle**: Added universal switch to keep phone screen on or off across all operational modes, with `Alt+O` runtime shortcut support.
- **DeX Multi-Window Environment**: Integrated automatic launch of `com.levelup.droiduplauncher` on secondary virtual display with window decorations and navigation controls.
- **Home Screen Layout Recovery**: Added quick-action button and CLI flag (`--reset-launcher`) to reload native launchers after resolution changes.
- **Hardware Compatibility Matrix**: Published comprehensive hardware mapping in `docs/HARDWARE_MATRIX.md` covering Qualcomm, MediaTek, Exynos, Tensor, Intel, AMD, and NVIDIA.
- **Architectural Decision Records**: Added ADR-0001, ADR-0002, and ADR-0003 in `docs/adr/`.

### Fixed
- **KVM / OTG Device Collision**: Bound scrcpy strictly to `-s "${DEVICE_SERIAL}"` in raw USB mode, preventing conflicts with internal webcams.
- **Pillarbox & Aspect Ratio Inversion**: Removed redundant `--capture-orientation=@270` when the output display is already horizontal (1920x1280 3:2).
- **Double-Click Button Bouncing**: Implemented debounce state lock and 2.5s grace period on the UI launch button to prevent accidental immediate termination.
- **CLI/GUI Option Alignment**: Added aliases for `--audio-dual`, `--audio-pc`, `--turn-screen-off`, and `--dock`.

## [1.0.0] - 2026-11-01

### Added
- Initial release of low-latency scrcpy gaming bridge for Linux.
- Aspect ratio matching for 3:2 displays (1920x1280) and dynamic DPI calculation.
- MediaCodec 0 latency priority options and Snapdragon HEVC hardware encoder selection.
- POSIX signal trap fail-safe resolution and density recovery.
