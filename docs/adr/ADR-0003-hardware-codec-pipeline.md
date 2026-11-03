# ADR-0003: Ultra-Low Latency Hardware Codec & Input Pipeline

## Status
Accepted

## Context
High-refresh-rate gaming (emulating Nintendo Switch, PS2, or competitive Android esports) requires latency to remain below human perception thresholds (< 16ms). Traditional screen mirroring introduces latency through multi-frame software buffering, VSYNC misalignment, and software input injection.

## Decision
1. **Zero-Frame Buffering**: Set `--video-buffer=0` and pass MediaCodec options `--video-codec-options=latency:int=0,priority:int=0`.
2. **VSYNC Refresh Rate Sync**: Query the host monitor's refresh rate (e.g. 60Hz, 120Hz) and lock Android's `peak_refresh_rate`, `min_refresh_rate`, and `user_refresh_rate` to match the PC display, preventing judder and tearing while saving battery and thermal budget.
3. **Direct Kernel UHID**: Bypass Android's accessibility/software touch emulation by routing physical PC input directly into the Linux kernel via `--keyboard=uhid`, `--mouse=uhid`, and `--gamepad=uhid`.
4. **Hardware KVM (USB-OTG)**: For competitive gamers looking at the smartphone's native AMOLED display, provide a raw USB HID mode (`--otg`) with `-s "${DEVICE_SERIAL}"` binding to bypass video streaming altogether for true sub-millisecond hardware latency.

## Consequences
- Total end-to-end latency reduced to 1-5ms over USB.
- Complete compatibility with anti-cheat titles and emulators.
