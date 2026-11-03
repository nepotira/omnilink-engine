# POCO Zero-Latency Game & Desktop Engine for Linux

High-performance, zero-latency gaming and desktop automation bridge for POCO / Xiaomi smartphones and Linux workstations (optimized for **Zorin OS 18.1 / Ubuntu 24.04 LTS / Wayland / Intel UHD Graphics** with a native **3:2 (1920x1280)** display).

---

## Key Features

- **True Fullscreen Aspect Ratio Adaptation (3:2 Fitting)**: Matches the POCO's rendering resolution and proportional DPI (`wm size` / `wm density`) directly to the host's screen geometry without black letterbox borders.
- **Dynamic Refresh Rate Matching (Host Hz Sync)**: Detects host display refresh rate (e.g. 60Hz, 120Hz) and locks Android's `peak_refresh_rate`, `min_refresh_rate`, and `user_refresh_rate` to match the PC monitor, aligning VSYNC and saving GPU/battery.
- **Hardware-Level MediaCodec Low Latency**: Injects `--video-codec-options=latency:int=0,priority:int=0` directly into Qualcomm Snapdragon and MediaTek video encoders for instantaneous 0-frame queueing.
- **Hardware Acceleration**: Auto-selects Snapdragon dedicated hardware HEVC encoder (`c2.qti.hevc.encoder`) with Linux VA-API hardware decoding on Intel UHD Graphics.
- **Forced Orientation Locking**: Hardware locks screen rotation (e.g. 270° Landscape for Nintendo Switch and PS2 emulators) using `wm set-ignore-orientation-request true` and restores auto-rotation cleanly on exit.
- **Laptop Auto-Rotation Lock (Zorin OS / GNOME Wayland)**: Automatically locks 2-in-1 convertible laptop screen rotation via GSettings so moving the laptop does not trigger unintentional screen orientation shifts.
- **Android Desktop DeX Mode**: Activates Android Freeform window support (`enable_freeform_support=1` and `force_resizable_activities=1`) on a secondary virtual display with `--no-vd-system-decorations` (leaving phone screen and home launcher icons 100% untouched).
- **Dual Performance Profiles**:
  - **Max Fidelity (1080p 3:2)**: 1920x1280 @ 16M Bitrate.
  - **Esports Eco (720p 3:2)**: 1280x854 @ 8M Bitrate (drastically cuts phone thermals during demanding emulation).
- **Direct Kernel HID Input**: Bypasses Android software input layers using `--keyboard=uhid`, `--mouse=uhid`, and `--gamepad=uhid`.
- **Fail-Safe Restoration Trap**: POSIX signal handler ensures phone resolution, DPI, refresh rate, orientation, and laptop lock are instantly reset on exit (`Ctrl+C`, `Alt+F4`, `Super+Q`), interruption, or cable disconnect.

---

## Phone Configuration (POCO / Xiaomi / MIUI / HyperOS)

To allow scrcpy to control the device and inject low-latency hardware input:

1. Go to **Settings** > **About Phone**.
2. Tap **OS Version / MIUI Version** 7 times to unlock Developer Options.
3. Go to **Settings** > **Additional Settings** > **Developer Options**.
4. Enable the following toggles:
   - **USB Debugging** (Required)
   - **Install via USB** (Optional)
   - **USB Debugging (Security settings)** (CRITICAL for mouse/keyboard/gamepad input on Xiaomi devices; requires Xiaomi account login)
5. Connect your phone via USB-C and select **"Always allow from this computer"** when prompted.

---

## Quick Start

### Graphical User Interface (Recommended)
You can launch the native modern GUI app directly from the terminal or open it from the Zorin OS Application Menu under **Games / Utilities**:

```bash
cd /home/nepo/.gemini/antigravity/scratch/poco-game-engine
./poco-gaming-gui
```

The GUI provides real-time battery and thermal telemetry, one-click profile switching (Gamer Max, Esports Eco, DeX, OTG Dock), instant rotation lock, and an emergency reset button.

---

### Command Line Interface (CLI)

The script is completely self-contained ("Zero to Function") — it auto-detects missing dependencies and configures udev rules automatically on first run:

```bash
cd /home/nepo/.gemini/antigravity/scratch/poco-game-engine

# Standard Fullscreen Gaming (1080p 3:2 + Latency Zero)
./poco-gaming.sh

# Esports Eco Gaming (720p 3:2 - Low Heat) with Landscape 270° and Laptop Lock
./poco-gaming.sh --eco -l --lock-laptop

# Android Desktop DeX Mode (Freeform Floating Windows, untouched phone screen)
./poco-gaming.sh --dex
```

---

## Command-Line Options

```text
Usage: poco-gaming.sh [OPTIONS]

Operational Modes:
  (no args)               Standard Fullscreen Zero-Latency Game Mode (Auto 3:2 adaptation)
  --eco, --720p           Esports Eco Mode (1280x854 3:2 @ 8M - Low Heat & Battery Saver)
  --max, --1080p          Maximum Quality Mode (1920x1280 3:2 @ 16M Bitrate)
  --dex, --desktop        Android Desktop DeX Mode (Freeform windows + No-decorations Virtual Display)
  --virtual               Secondary Virtual Display Mode (keeps phone screen free & untouched)
  --otg                   Pure Hardware Dock Mode (KVM mouse & keyboard control via USB)
  --daemon                Background daemon mode: Auto-launches session whenever POCO is plugged in

Screen Orientation & Display Controls:
  --landscape, -l         Force POCO screen to Landscape mode (270° standard for emulators)
  --portrait, -p          Force POCO screen to Portrait mode (0° vertical)
  --rotate <0|90|180|270> Force arbitrary hardware screen rotation angle
  --lock-laptop           Lock laptop screen rotation in Zorin OS (prevents 2-in-1 auto-rotation)

Audio Controls:
  --no-audio              Disable audio streaming (lowest processing latency, audio on phone)
  --audio-dup             Stream audio to PC and keep playing on phone speakers (default)

System & Recovery:
  -y, --yes               Auto-install missing dependencies non-interactively
  --install               Force run dependency and udev installer
  --check                 Verify dependencies and environment only (no launch)
  --reset                 Emergency reset: Restores resolution, density, Hz, rotation, and laptop lock
  -h, --help              Show this help message
```

---

## Configuration (`config.env`)

You can customize parameters by creating or editing `config.env`:

```bash
# Performance Profile ("max" or "eco")
PERF_PROFILE="max"

# Video Settings
VIDEO_CODEC="h265"
VIDEO_BITRATE="16M"
VIDEO_BUFFER=0
FORCE_ADB_FORWARD=1

# Audio Settings
AUDIO_BUFFER=50
AUDIO_SOURCE="playback"
AUDIO_DUP=1

# Orientation & Hardware Lock
REQUESTED_ROTATION=""        # "270", "0", etc.
LOCK_LAPTOP_ROTATION=0       # Set 1 to always lock 2-in-1 laptop rotation
```
