# Development Journal

## 2026-11-01
- Initial fusion of `jogar_poco.sh` low-latency parameters and `DroidUP-Dex` desktop features.
- Implemented MediaCodec 0 latency priority options, Snapdragon HEVC encoder selection, and fail-safe signal traps.
- Discovered and fixed snap confinement notice dialogs (`SNAP_LAUNCHER_NOTICE_ENABLED="false"`) and `scrcpy:joystick` connection.

## 2026-11-03
- **GUI Architecture & Delivery**: Built modern Python 3 + GTK 4 + Libadwaita desktop application with native Zorin OS aesthetic.
- **Desktop Double-Click Integration**: Delivered `.desktop` launcher on the user's Desktop (`~/Área de trabalho/`) marked with `metadata::trusted true`.
- **Bugfix (CLI/GUI option mismatch)**: Aligned audio and power flags (`--audio-dual`, `--turn-screen-off`) between the python frontend and bash engine.
- **Bugfix (Debounce & Double-Click Bouncing)**: Added button debounce state lock to prevent second rapid click from triggering premature session termination.
- **Bugfix (Pillarbox & Inverted Orientation)**: Fixed `--capture-orientation=@270` collision when output framebuffer is already in landscape geometry.
- **Bugfix (DeX Virtual Display)**: Integrated `com.levelup.droiduplauncher` auto-launch and enabled freeform window decorations.
- **Bugfix (KVM/OTG Device Collision)**: Resolved raw USB collision with host webcam by binding strictly to `-s "${DEVICE_SERIAL}"`.
- **Universalization (v2.0.0)**: Rebranded engine to **OmniLink Mobile Engine**, removed device-specific hardcodes, added Pure 1:1 Mirroring mode, and implemented home screen launcher layout preservation.
