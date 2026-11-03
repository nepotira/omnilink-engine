# ADR-0001: Universal Multi-Vendor Architecture

## Status
Accepted

## Context
The project initially targeted the Xiaomi POCO / Redmi device series under the name "POCO Game Engine". However, the low-latency MediaCodec optimizations, aspect ratio fitting algorithms, and freeform desktop mechanics are mathematically and architecturally universal across the Android and Linux ecosystems. Hardcoding device names, vendor IDs, or specific SoC models hindered adoption on other devices (Samsung Galaxy, Google Pixel, Motorola, Asus ROG, etc.).

## Decision
We renamed the engine to **OmniLink Mobile Engine** and decoupled all device and host identification from static strings into dynamic, runtime hardware probing:
- Smartphone brand, model, and SoC family are queried via Android `getprop` on connect.
- Host GPU, driver, and display geometry are queried via Linux DRM sysfs and VA-API introspection.
- Profiles adapt automatically: when a Qualcomm Snapdragon is detected, dedicated QTI low-latency flags are applied; when an Exynos or MediaTek is detected, corresponding dedicated vendor encoders are prioritized.

## Consequences
- Single universal codebase runs out-of-the-box on any Android device and any Linux workstation.
- Users see their exact hardware branded dynamically in the GUI.
- Maintained backwards compatibility via symlinks (`poco-gaming.sh` -> `omnilink.sh`).
