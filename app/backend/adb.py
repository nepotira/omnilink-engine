"""ADB Telemetry and Device Diagnostics Service."""

import glob
import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from typing import Optional


@dataclass
class DeviceInfo:
    serial: str
    model: str
    soc: str
    android_version: str
    battery_level: int
    battery_temp_c: float
    is_charging: bool
    native_res: str
    current_res: str
    current_density: int
    refresh_rate_hz: int
    is_connected: bool


@dataclass
class HostDisplayInfo:
    resolution: str
    aspect_ratio: str
    refresh_rate_hz: int


class ADBManager:
    """Manages ADB queries and system hardware telemetry."""

    @staticmethod
    def is_adb_installed() -> bool:
        return shutil.which("adb") is not None

    @staticmethod
    def is_scrcpy_installed() -> bool:
        return shutil.which("scrcpy") is not None

    @staticmethod
    def get_connected_device_serial() -> Optional[str]:
        """Returns the serial of the first connected USB device."""
        if not ADBManager.is_adb_installed():
            return None
        try:
            res = subprocess.run(
                ["adb", "devices"],
                capture_output=True,
                text=True,
                timeout=3,
                check=False,
            )
            for line in res.stdout.strip().splitlines()[1:]:
                parts = line.split()
                if len(parts) >= 2 and parts[1] == "device":
                    return parts[0]
        except Exception:
            pass
        return None

    @staticmethod
    def get_device_info() -> DeviceInfo:
        """Fetches full hardware and battery telemetry from connected device."""
        serial = ADBManager.get_connected_device_serial()
        if not serial:
            return DeviceInfo(
                serial="",
                model="Desconectado",
                soc="N/A",
                android_version="N/A",
                battery_level=0,
                battery_temp_c=0.0,
                is_charging=False,
                native_res="N/A",
                current_res="N/A",
                current_density=0,
                refresh_rate_hz=0,
                is_connected=False,
            )

        # 1. Properties
        model = "POCO / Redmi"
        soc = "Snapdragon"
        android_ver = "17"
        try:
            cmd = (
                "getprop ro.product.model; "
                "getprop ro.soc.model; "
                "getprop ro.board.platform; "
                "getprop ro.build.version.release"
            )
            res = subprocess.run(
                ["adb", "-s", serial, "shell", cmd],
                capture_output=True,
                text=True,
                timeout=3,
                check=False,
            )
            props = [p.strip() for p in res.stdout.splitlines() if p.strip()]
            if len(props) >= 1:
                model = props[0]
            if len(props) >= 3:
                soc_model = props[1]
                platform = props[2]
                soc = f"{soc_model} ({platform})"
            if len(props) >= 4:
                android_ver = props[3]
        except Exception:
            pass

        # 2. Battery
        bat_level = 0
        bat_temp = 0.0
        is_charging = False
        try:
            res = subprocess.run(
                ["adb", "-s", serial, "shell", "dumpsys", "battery"],
                capture_output=True,
                text=True,
                timeout=3,
                check=False,
            )
            for line in res.stdout.splitlines():
                line = line.strip()
                if line.startswith("level:"):
                    bat_level = int(line.split(":")[1].strip())
                elif line.startswith("temperature:"):
                    bat_temp = int(line.split(":")[1].strip()) / 10.0
                elif line.startswith("status:"):
                    is_charging = int(line.split(":")[1].strip()) == 2
        except Exception:
            pass

        # 3. Display info
        native_res = "1280x2772"
        current_res = "1280x2772"
        current_density = 520
        refresh_rate = 120
        try:
            # Physical size
            res_wm_size = subprocess.run(
                ["adb", "-s", serial, "shell", "wm", "size"],
                capture_output=True,
                text=True,
                timeout=3,
                check=False,
            )
            for line in res_wm_size.stdout.splitlines():
                if "Physical size:" in line:
                    native_res = line.split("Physical size:")[1].strip()
                    current_res = native_res
                elif "Override size:" in line:
                    current_res = line.split("Override size:")[1].strip()

            # Density
            res_wm_density = subprocess.run(
                ["adb", "-s", serial, "shell", "wm", "density"],
                capture_output=True,
                text=True,
                timeout=3,
                check=False,
            )
            for line in res_wm_density.stdout.splitlines():
                if "Physical density:" in line:
                    try:
                        current_density = int(line.split("Physical density:")[1].strip())
                    except ValueError:
                        pass
                elif "Override density:" in line:
                    try:
                        current_density = int(line.split("Override density:")[1].strip())
                    except ValueError:
                        pass

            # Refresh Rate
            res_disp = subprocess.run(
                ["adb", "-s", serial, "shell", "dumpsys", "display"],
                capture_output=True,
                text=True,
                timeout=4,
                check=False,
            )
            m = re.search(r"renderFrameRate\s+([\d\.]+)", res_disp.stdout)
            if m:
                refresh_rate = int(round(float(m.group(1))))
        except Exception:
            pass

        return DeviceInfo(
            serial=serial,
            model=model,
            soc=soc,
            android_version=android_ver,
            battery_level=bat_level,
            battery_temp_c=bat_temp,
            is_charging=is_charging,
            native_res=native_res,
            current_res=current_res,
            current_density=current_density,
            refresh_rate_hz=refresh_rate,
            is_connected=True,
        )

    @staticmethod
    def get_host_display_info() -> HostDisplayInfo:
        """Detects the host display resolution, aspect ratio and refresh rate."""
        res_str = "1920x1280"
        aspect_ratio = "3:2"
        hz = 60

        # Try DRM modes
        for mode_path in glob.glob("/sys/class/drm/card*-eDP-*/modes"):
            try:
                with open(mode_path, "r", encoding="utf-8") as f:
                    first_mode = f.readline().strip()
                    if first_mode and "x" in first_mode:
                        res_str = first_mode
                        break
            except Exception:
                pass

        if "x" in res_str:
            try:
                w, h = map(int, res_str.split("x"))
                if abs((w / h) - (3 / 2)) < 0.05:
                    aspect_ratio = "3:2"
                elif abs((w / h) - (16 / 9)) < 0.05:
                    aspect_ratio = "16:9"
                elif abs((w / h) - (16 / 10)) < 0.05:
                    aspect_ratio = "16:10"
                else:
                    aspect_ratio = f"{w}:{h}"
            except Exception:
                pass

        return HostDisplayInfo(
            resolution=res_str,
            aspect_ratio=aspect_ratio,
            refresh_rate_hz=hz,
        )
