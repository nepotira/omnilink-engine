# Lessons Learned

## 2026-11-01: Zero to Function Scripts must be Self-Contained Installers
- **Context**: The user asked for a "Zero to Function" automatic script for any Linux to prepare an unconfigured PC and run scrcpy with POCO.
- **Correction**: Do not execute manual terminal setup commands (like `sudo apt/snap`) on behalf of the user to configure the PC manually. The script itself must detect missing components, prompt/handle privilege elevation (`sudo`), configure udev rules, install dependencies across distros, and transition seamlessly into running the game without external manual intervention.

## 2026-11-01: Scrcpy Snap Confinement and Launcher Notice Suppression
- **Context**: When scrcpy is installed via Snap, running `--gamepad=uhid` requires the `joystick` interface (`sudo snap connect scrcpy:joystick`), otherwise it blocks execution, triggers a graphical popup ('Unofficial snap notice'), and emits escape codes (`^A` and carriage returns) that garble the terminal output.
- **Correction**: Always export `SNAP_LAUNCHER_NOTICE_ENABLED="false"`, auto-connect both `scrcpy:raw-usb` and `scrcpy:joystick`, and use `--quiet` on snap package operations to keep terminal output clean.

## 2026-11-01: Process Trapping with Snap Wrappers, Disconnect Handling and Audio Buffering
- **Context**: The Snap launcher for scrcpy runs in a subshell without `exec`, so pressing Ctrl+C in terminal does not kill the child `scrcpy` binary, leaving the session and resolution override active. If the USB cable is unplugged, `adb shell wm size reset` fails unless it handles reconnection. Additionally, `--audio-buffer=20` is too low for PipeWire on Ubuntu/Zorin (causing audio underrun/silence), and HyperOS can mute media if audio routing isn't duplicated or specified.
- **Correction**: Track `SCRCPY_PID` and explicitly terminate child processes in `cleanup()`; add a reconnection wait loop in `restore_screen_resolution`; add self-healing resolution reset check at startup; use a stable 50ms audio buffer and `--audio-dup` with `--audio-source=playback`.
