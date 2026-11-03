# Project State: OmniLink Mobile Engine

- **Target OS**: Universal Linux (Validated on Zorin OS 18.1 / Ubuntu 24.04 noble, Wayland & X11).
- **Architecture**: Universal across Qualcomm Snapdragon, MediaTek Dimensity, Samsung Exynos, and Google Tensor.
- **Components**:
  - Python 3 + GTK 4 + Libadwaita Desktop GUI (`omnilink-gui`, `app/main.py`, `app/ui/`, `app/backend/`)
  - Shell Master Engine (`omnilink.sh`, backwards-compatible `poco-gaming.sh`)
  - Desktop Entry (`omnilink.desktop`) installed to `~/.local/share/applications/` and `~/Área de trabalho/`
- **Key Modules Verified**:
  - Global Screen Off toggle (saves battery & heat in all modes) + `Alt+O` shortcut
  - Desktop DeX Mode: `--new-display` + `com.levelup.droiduplauncher` + freeform windows
  - Pure 1:1 Mirroring Mode: zero resolution modification, 0% icon scrambling
  - Hardware KVM Dock Mode: bound strictly to `-s "${DEVICE_SERIAL}"`
  - Automated Home Screen Icon Reload: `restore_launcher_layout`
  - Universal Hardware Matrix: `docs/HARDWARE_MATRIX.md`
