# Project State: POCO Zero-Latency Game & Desktop Engine

- **Target OS**: Zorin OS 18.1 (Ubuntu 24.04 noble, Wayland, Intel UHD CometLake).
- **Host Display**: 1920x1280 (3:2 Aspect Ratio @ 60 Hz).
- **Connected Device**: POCO / Redmi 25053RT47C [SoC: sun] (Snapdragon 8 Elite / 8 Gen).
- **Core Engine**: `poco-gaming.sh` (CLI) and `poco-gaming-gui` (Python 3 + GTK 4 + Libadwaita).
- **Capabilities & Verification**:
  - **Native GTK4/Libadwaita GUI**: Complete graphical interface replacing terminal commands (`app/main.py`, `app/ui/`, `app/backend/`).
  - **Real-Time Telemetry**: Live polling of battery percentage, charging state, battery temperature (°C), phone refresh rate (Hz), and host display geometry.
  - **Profiles in One Click**: Gamer Max (1920x1280 3:2 @ 16M), Esports Eco (1280x854 3:2 @ 8M), Desktop DeX Mode, and OTG Dock.
  - **Hardware Sensor & Screen Controls**: Phone forced orientation (270° Landscape, 0° Portrait), Zorin OS 2-in-1 touchscreen orientation lock toggle, dual audio routing, and phone screen power-off.
  - **Emergency Safe Reset**: One-click "Restaurar Padrões" button instantly restores phone resolution, DPI, Hz, rotation, and launcher.
  - **System Integration**: `.desktop` entry installed in `~/.local/share/applications/` with custom vector icon (`assets/poco-gaming.svg`).
  - **Fail-Safe Trap**: Subprocess terminates cleanly on window close or stop button, executing signal traps safely.
