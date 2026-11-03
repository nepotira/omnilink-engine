# ADR-0002: DeX Virtual Display and Freeform Multi-Window Management

## Status
Accepted

## Context
When running Android in desktop mode on a secondary virtual display (`scrcpy --new-display`), two major challenges arise:
1. Android displays without a designated launcher render as an empty, blank gray canvas with only a mouse cursor.
2. Passing `--no-vd-system-decorations` disables Android's native window captions, status bar, and navigation controls, trapping apps in borderless fullscreen without minimize or close buttons.
3. Mutating `wm size` on the phone's primary display scrambles the user's home screen icon arrangement and folders.

## Decision
1. **Secondary Virtual Display as DeX Foundation**: DeX mode utilizes `--new-display`, leaving the phone's primary display and native resolution 100% untouched.
2. **Dedicated Desktop Launcher**: Automatically detect or install `com.levelup.droiduplauncher` and launch it on the virtual display via `--start-app=com.levelup.droiduplauncher`.
3. **Freeform Window Management**: Enable `enable_freeform_support=1`, `force_resizable_activities=1`, and `freeform_window_management=1`. Remove `--no-vd-system-decorations` so navigation controls and window decorations render cleanly.
4. **Desktop Navigation Shortcuts**: Expose and document standard scrcpy/Android windowing keybindings (`Alt+H` for Home, `Alt+S` for Multitasking Overview, `Alt+B` for Back).

## Consequences
- Clean, functional desktop experience with floating resizable windows, taskbar, and app menu.
- Phone's native home screen launcher layout remains pristine.
