# Project State: POCO Zero-Latency Game & Desktop Engine

- **Target OS**: Zorin OS 18.1 (Ubuntu 24.04 noble, Wayland, Intel UHD CometLake).
- **Host Display**: 1920x1280 (3:2 Aspect Ratio @ 60 Hz).
- **Connected Device**: POCO / Redmi 25053RT47C [SoC: sun] (Snapdragon 8 Elite / 8 Gen).
- **Core Script**: `poco-gaming.sh`
- **Capabilities & Verification**:
  - Unified Fusion Engine: Fully incorporated all best features from `jogar_poco.sh` and `DroidUP-Dex`.
  - MediaCodec 0 Latency: `--video-codec-options=latency:int=0,priority:int=0` and `--force-adb-forward`.
  - Dual Performance Profiles: `--max` (1920x1280 @ 16M) vs `--eco` / `--720p` (1280x854 @ 8M low heat).
  - Phone Forced Rotation: `--landscape` (270°), `--portrait` (0°), `--rotate <deg>` with hardware override and clean restoration.
  - Laptop Auto-Rotation Lock: `--lock-laptop` locks Zorin OS touchscreen orientation via GSettings, preventing 2-in-1 sensor rotation while gaming.
  - Android Desktop DeX Mode: `--dex` / `--desktop` enables freeform floating windows + clean virtual display (`--no-vd-system-decorations`), leaving phone screen untouched.
  - Fail-Safe Trap: Tested and verified (`poco-gaming.sh --reset` restores laptop lock, DeX mode, orientation, Hz, and display size).
