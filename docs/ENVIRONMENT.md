# Environment Specification

## Host Environment
- **Operating System**: Linux (Validated on Zorin OS 18.1 / Ubuntu 24.04 noble LTS)
- **Desktop Environment**: GNOME 46 / Wayland (also compatible with X11)
- **Host GPU**: Intel CometLake-U GT2 [UHD Graphics] (`i915` kernel driver, Mesa 25.2.8)
- **Primary Display**: 1920x1280 (3:2 Aspect Ratio @ 60 Hz)
- **Python Runtime**: Python 3.12 with PyGObject (`python3-gi`, GTK 4.0, Libadwaita 1)
- **Subsystem Video**: VA-API 1.20+ (`/usr/lib/x86_64-linux-gnu/dri/iHD_drv_video.so`)

## Mobile Target Hardware
- **Supported Platforms**: Qualcomm Snapdragon, MediaTek, Samsung Exynos, Google Tensor, Unisoc
- **Primary Test Device**: Xiaomi / Redmi 25053RT47C (`sun` - Snapdragon 8 Elite / SM8735, Android 17)
- **USB Interface**: USB-C 3.2 High-Speed / SuperSpeed
- **HID Interfaces**: Linux uhid kernel module (keyboard, mouse, gamepad)

## Package Requirements
- `adb` (Android Debug Bridge)
- `scrcpy` (v2.0+, recommended v3.0+ or v5.0+)
- `python3-gi`, `gir1.2-gtk-4.0`, `gir1.2-adw-1`
- `udev` rules in `/etc/udev/rules.d/51-android.rules`
