"""OmniLink Mobile Engine - Universal ADB Telemetry and Device Diagnostics Service."""

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
    brand: str
    model: str
    manufacturer: str
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
    gpu_vendor: str


class ADBManager:
    """Manages universal ADB queries and system hardware telemetry."""

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
        """Fetches full universal hardware and battery telemetry from connected device."""
        serial = ADBManager.get_connected_device_serial()
        if not serial:
            return DeviceInfo(
                serial="",
                brand="Android",
                model="Desconectado",
                manufacturer="",
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

        # 1. Universal Device Properties
        brand = "Android"
        model = "Device"
        manufacturer = ""
        soc = "Generic SoC"
        android_ver = "15+"
        try:
            cmd = (
                "getprop ro.product.brand; "
                "getprop ro.product.model; "
                "getprop ro.product.manufacturer; "
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
            if len(props) >= 1 and props[0]:
                brand = props[0].capitalize()
            if len(props) >= 2 and props[1]:
                model = props[1]
            if len(props) >= 3 and props[2]:
                manufacturer = props[2].capitalize()
            if len(props) >= 5 and (props[3] or props[4]):
                soc_model = props[3] if props[3] else props[4]
                platform = props[4] if props[4] else ""
                soc = f"{soc_model} ({platform})" if platform and platform != soc_model else soc_model
            if len(props) >= 6 and props[5]:
                android_ver = props[5]
        except Exception:
            pass

        # 2. Battery Telemetry
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
        native_res = "1920x1080"
        current_res = "1920x1080"
        current_density = 320
        refresh_rate = 60
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
            brand=brand,
            model=model,
            manufacturer=manufacturer,
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
        """Detects the host display resolution, aspect ratio, refresh rate, and GPU vendor."""
        res_str = "1920x1080"
        aspect_ratio = "16:9"
        hz = 60
        gpu_vendor = "Intel / Mesa"

        # DRM modes
        for mode_path in glob.glob("/sys/class/drm/card*-eDP-*/modes") + glob.glob("/sys/class/drm/card*-HDMI-*/modes"):
            try:
                with open(mode_path, "r", encoding="utf-8") as f:
                    first_mode = f.readline().strip()
                    if first_mode and "x" in first_mode:
                        res_str = first_mode
                        break
            except Exception:
                pass

        # Detect GPU vendor
        try:
            gl_res = subprocess.run(
                ["glxinfo", "-B"],
                capture_output=True,
                text=True,
                timeout=2,
                check=False,
            )
            for line in gl_res.stdout.splitlines():
                if "OpenGL vendor string:" in line:
                    gpu_vendor = line.split(":", 1)[1].strip()
                    break
        except Exception:
            for card in glob.glob("/sys/class/drm/card*"):
                if "card0" in card or "card1" in card:
                    device_path = os.path.realpath(f"{card}/device")
                    if "8086" in device_path or "i915" in device_path:
                        gpu_vendor = "Intel Graphics"
                    elif "1002" in device_path or "amdgpu" in device_path:
                        gpu_vendor = "AMD Radeon"
                    elif "10de" in device_path or "nvidia" in device_path:
                        gpu_vendor = "NVIDIA GeForce"

        if "x" in res_str:
            try:
                w, h = map(int, res_str.split("x"))
                r = w / h
                if abs(r - (3 / 2)) < 0.05:
                    aspect_ratio = "3:2"
                elif abs(r - (16 / 9)) < 0.05:
                    aspect_ratio = "16:9"
                elif abs(r - (16 / 10)) < 0.05:
                    aspect_ratio = "16:10"
                elif abs(r - (21 / 9)) < 0.1:
                    aspect_ratio = "21:9"
                else:
                    aspect_ratio = f"{w}:{h}"
            except Exception:
                pass

        return HostDisplayInfo(
            resolution=res_str,
            aspect_ratio=aspect_ratio,
            refresh_rate_hz=hz,
            gpu_vendor=gpu_vendor,
        )
