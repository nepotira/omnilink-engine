#!/usr/bin/env bash
# ==============================================================================
# POCO Zero-Latency Game Engine (scrcpy)
# Target: Any Linux (Optimized for Zorin OS / Ubuntu / Wayland / Intel UHD)
# Author: Antigravity (Advanced Agentic Coding)
# ==============================================================================

set -eo pipefail

# ------------------------------------------------------------------------------
# Global Variables and Defaults
# ------------------------------------------------------------------------------
APP_NAME="POCO Zero-Latency Game Engine"
VERSION="1.0.0"

# Silence Snap launcher popups and confinement notices
export SNAP_LAUNCHER_NOTICE_ENABLED="false"

# Terminal Colors
C_RESET="\033[0m"
C_RED="\033[1;31m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_BLUE="\033[1;34m"
C_CYAN="\033[1;36m"
C_BOLD="\033[1m"

# State Flags
DISPLAY_MODIFIED=0
REFRESH_MODIFIED=0
ROTATION_MODIFIED=0
LAPTOP_LOCK_MODIFIED=0
DEX_MODE_ACTIVE=0
SCRCPY_PID=""

# Display & Geometry Defaults
HOST_W=1920
HOST_H=1280
HOST_HZ=60
HOST_RATIO="3:2"
TARGET_DENSITY=280
TARGET_FPS=60
MAX_SIZE=1920

# Performance & Codec Defaults
PERF_PROFILE="max" # max (1080p), eco (720p)
VIDEO_CODEC="h265"
VIDEO_BITRATE="16M"
FORCE_ADB_FORWARD=1
CHOSEN_ENCODER=""
DISABLE_AUDIO=0

# Orientation Controls
REQUESTED_ROTATION="" # 0, 90, 180, 270
ROTATION_NUM=3
LOCK_LAPTOP_ROTATION=0
ORIG_LAPTOP_LOCK=""

# Device Original Backups
DEVICE_ORIG_SIZE=""
DEVICE_ORIG_DENSITY=""
DEVICE_ORIG_PEAK_REFRESH=""
DEVICE_ORIG_MIN_REFRESH=""
DEVICE_ORIG_USER_REFRESH=""
DEVICE_ORIG_MIUI_REFRESH=""
DEVICE_ORIG_ACCEL_ROTATION=""
DEVICE_ORIG_USER_ROTATION=""
ORIG_FREEFORM=""
ORIG_RESIZABLE=""

AUTO_INSTALL=0
RUN_MODE="normal" # normal, eco, dex, virtual, otg, daemon, reset, check

# Optional Configuration File Override
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

# ------------------------------------------------------------------------------
# Logging Functions
# ------------------------------------------------------------------------------
log_info()    { echo -e "${C_CYAN}[INFO]${C_RESET} $*"; }
log_success() { echo -e "${C_GREEN}[OK]${C_RESET} $*"; }
log_warn()    { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
log_error()   { echo -e "${C_RED}[ERROR]${C_RESET} $*"; }
log_step()    { echo -e "\n${C_BOLD}${C_BLUE}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }

# ------------------------------------------------------------------------------
# Fail-Safe Cleanup Handler (POSIX Trap)
# ------------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM HUP # Prevent recursive trap calls

    # Terminate running scrcpy process immediately if active
    if [ -n "${SCRCPY_PID:-}" ] && kill -0 "$SCRCPY_PID" 2>/dev/null; then
        echo ""
        log_warn "Interruption detected. Stopping scrcpy process (PID: ${SCRCPY_PID})..."
        kill -TERM "$SCRCPY_PID" 2>/dev/null || true
        for _ in {1..15}; do
            if ! kill -0 "$SCRCPY_PID" 2>/dev/null; then break; fi
            sleep 0.1
        done
        kill -KILL "$SCRCPY_PID" 2>/dev/null || true
    fi

    # Kill any lingering scrcpy instances
    killall -q -9 scrcpy 2>/dev/null || true

    # 1. Restore Zorin OS laptop orientation lock if modified
    if [ "$LAPTOP_LOCK_MODIFIED" -eq 1 ]; then
        restore_laptop_rotation || true
    fi

    # 2. Restore Android Freeform / DeX global settings
    if [ "$DEX_MODE_ACTIVE" -eq 1 ]; then
        restore_dex_mode || true
    fi

    # 3. Restore POCO screen orientation and accelerometer
    if [ "$ROTATION_MODIFIED" -eq 1 ]; then
        restore_device_orientation || true
    fi

    # 4. Restore POCO native refresh rate
    if [ "$REFRESH_MODIFIED" -eq 1 ]; then
        echo ""
        log_warn "Restoring POCO native refresh rate..."
        restore_device_refresh_rate || true
    fi

    # 5. Restore POCO native resolution and density
    if [ "$DISPLAY_MODIFIED" -eq 1 ]; then
        echo ""
        log_warn "Restoring POCO native display resolution and density..."
        restore_screen_resolution || true
    fi
    exit $exit_code
}

trap cleanup EXIT INT TERM HUP

# ------------------------------------------------------------------------------
# Module 1: Dependency Verification & Automated Zero-Setup Provisioner
# ------------------------------------------------------------------------------
install_missing_dependencies() {
    local distro_id="$1"
    local needs_adb="$2"
    local needs_scrcpy="$3"
    local needs_udev="$4"
    local needs_vaapi="$5"

    log_step "Auto-Configuring System (Zero to Function Installer)"
    log_info "Elevating privileges to install missing packages and configure udev..."
    sudo -v || { log_error "Failed to acquire sudo privileges."; exit 1; }

    # 1. Distro Package Installation
    case "$distro_id" in
        ubuntu|debian|zorin|linuxmint|pop)
            local apt_pkgs=()
            [ "$needs_adb" -eq 1 ] && apt_pkgs+=("android-tools-adb")
            [ "$needs_vaapi" -eq 1 ] && apt_pkgs+=("intel-media-va-driver-non-free" "vainfo")

            if [ "${#apt_pkgs[@]}" -gt 0 ]; then
                log_info "Installing distro packages: ${apt_pkgs[*]}"
                sudo apt-get update -y
                sudo apt-get install -y "${apt_pkgs[@]}" || sudo apt-get install -y intel-media-va-driver "${apt_pkgs[@]}" || true
            fi

            if [ "$needs_scrcpy" -eq 1 ]; then
                log_info "Installing modern scrcpy (v3+/v5+) via Snap..."
                if ! command -v snap >/dev/null 2>&1; then
                    sudo apt-get update -y && sudo apt-get install -y snapd
                fi
                sudo snap install scrcpy --quiet
            fi
            ;;
        fedora)
            local dnf_pkgs=()
            [ "$needs_adb" -eq 1 ] && dnf_pkgs+=("android-tools")
            [ "$needs_scrcpy" -eq 1 ] && dnf_pkgs+=("scrcpy")
            [ "$needs_vaapi" -eq 1 ] && dnf_pkgs+=("libva-intel-media-driver")
            if [ "${#dnf_pkgs[@]}" -gt 0 ]; then
                log_info "Installing via dnf: ${dnf_pkgs[*]}"
                sudo dnf install -y "${dnf_pkgs[@]}"
            fi
            ;;
        arch|manjaro)
            local pac_pkgs=()
            [ "$needs_adb" -eq 1 ] && pac_pkgs+=("android-tools")
            [ "$needs_scrcpy" -eq 1 ] && pac_pkgs+=("scrcpy")
            [ "$needs_vaapi" -eq 1 ] && pac_pkgs+=("intel-media-driver")
            if [ "${#pac_pkgs[@]}" -gt 0 ]; then
                log_info "Installing via pacman: ${pac_pkgs[*]}"
                sudo pacman -S --needed --noconfirm "${pac_pkgs[@]}"
            fi
            ;;
        *)
            log_warn "Generic distro detected. Attempting snap install scrcpy..."
            if command -v snap >/dev/null 2>&1; then
                sudo snap install scrcpy --quiet
            else
                log_error "Please install adb and modern scrcpy (>= 2.0) manually on this distribution."
                exit 1
            fi
            ;;
    esac

    # 2. Connect Snap Confinement Plugs (raw-usb, joystick)
    if command -v snap >/dev/null 2>&1 && snap list scrcpy >/dev/null 2>&1; then
        log_info "Configuring scrcpy snap security confinement plugs (raw-usb, joystick)..."
        sudo snap connect scrcpy:raw-usb || true
        sudo snap connect scrcpy:joystick || true
        log_success "Snap plugs (raw-usb, joystick) connected successfully."
    fi

    # 3. Configure POCO/Xiaomi Udev Rules
    if [ "$needs_udev" -eq 1 ]; then
        log_info "Configuring Xiaomi/POCO USB permissions (Vendor ID 2717)..."
        local udev_file="/etc/udev/rules.d/51-android.rules"
        sudo mkdir -p /etc/udev/rules.d
        echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="2717", MODE="0666", GROUP="plugdev", TAG+="uaccess"' | sudo tee -a "$udev_file" >/dev/null

        # Ensure plugdev group exists and current user is added
        if ! getent group plugdev >/dev/null 2>&1; then
            sudo groupadd plugdev || true
        fi
        sudo usermod -aG plugdev "$USER" || true

        log_info "Reloading udev subsystem rules..."
        sudo udevadm control --reload-rules && sudo udevadm trigger || true
        log_success "Udev rules configured successfully."
    fi

    log_success "All system requirements and dependencies are now ready!"
}

check_and_install_deps() {
    log_step "Checking System Environment and Dependencies"

    # Identify Linux Distribution
    local distro_id="unknown"
    local distro_like=""
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        distro_id=$(grep -E '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
        distro_like=$(grep -E '^ID_LIKE=' /etc/os-release | cut -d'=' -f2 | tr -d '"' || true)
    fi
    log_info "Detected OS: ${distro_id} (${distro_like:-standalone})"

    local missing_pkgs=()
    local needs_adb=0
    local needs_scrcpy_upgrade=0

    # 1. Check ADB
    if ! command -v adb >/dev/null 2>&1; then
        missing_pkgs+=("adb")
        needs_adb=1
    else
        log_success "ADB found: $(command -v adb)"
    fi

    # 2. Check scrcpy version and snap confinement plugs
    local needs_snap_plugs=0
    if ! command -v scrcpy >/dev/null 2>&1; then
        needs_scrcpy_upgrade=1
        log_warn "scrcpy is not installed."
    else
        local scrcpy_ver
        scrcpy_ver=$(SNAP_LAUNCHER_NOTICE_ENABLED="false" scrcpy --version 2>&1 | grep -E '^scrcpy ' | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || echo "0.0")
        log_info "Current scrcpy version: ${scrcpy_ver}"
        local major_ver
        major_ver=$(echo "$scrcpy_ver" | cut -d'.' -f1)
        if [ "$major_ver" -lt 2 ]; then
            log_warn "Installed scrcpy version ($scrcpy_ver) is outdated (< 2.0). Modern codecs and audio require v2.0+."
            needs_scrcpy_upgrade=1
        else
            log_success "scrcpy version is up-to-date: ${scrcpy_ver}"
        fi

        # Check snap confinement plugs (raw-usb, joystick)
        if command -v snap >/dev/null 2>&1 && snap list scrcpy >/dev/null 2>&1; then
            local snap_conns
            snap_conns=$(snap connections scrcpy 2>/dev/null || true)
            if echo "$snap_conns" | grep -qE '^joystick\s+scrcpy:joystick\s+-'; then
                needs_snap_plugs=1
                log_warn "scrcpy joystick plug not connected (required for Gamepad mode)."
            fi
            if echo "$snap_conns" | grep -qE '^raw-usb\s+scrcpy:raw-usb\s+-'; then
                needs_snap_plugs=1
                log_warn "scrcpy raw-usb plug not connected (required for low-latency USB)."
            fi
            if [ "$needs_snap_plugs" -eq 0 ]; then
                log_success "scrcpy snap security plugs (raw-usb, joystick) verified."
            fi
        fi
    fi

    # 3. Check Xiaomi / POCO Udev Rules (Vendor ID 2717)
    local udev_file="/etc/udev/rules.d/51-android.rules"
    local needs_udev=0
    if [ ! -f "$udev_file" ] || ! grep -q "2717" "$udev_file" 2>/dev/null; then
        needs_udev=1
        log_warn "Xiaomi/POCO udev rules missing in ${udev_file}."
    else
        log_success "Android udev rules verified (Vendor ID 2717)."
    fi

    # 4. Check VA-API hardware decoding driver for Intel
    local needs_vaapi=0
    if lspci 2>/dev/null | grep -qi 'Intel.*Graphics'; then
        if [ ! -f /usr/lib/x86_64-linux-gnu/dri/iHD_drv_video.so ] && [ ! -f /usr/lib64/dri/iHD_drv_video.so ]; then
            needs_vaapi=1
            log_warn "Intel VA-API driver (intel-media-va-driver) recommended for hardware video decoding."
        else
            log_success "Intel VA-API driver found."
        fi
    fi

    # Summary and Automated Resolution
    if [ "$needs_adb" -eq 1 ] || [ "$needs_scrcpy_upgrade" -eq 1 ] || [ "$needs_snap_plugs" -eq 1 ] || [ "$needs_udev" -eq 1 ] || [ "$needs_vaapi" -eq 1 ]; then
        if [ "$RUN_MODE" = "check" ]; then
            echo ""
            log_warn "Environment setup is incomplete. Run without --check or with -y to auto-configure."
            return 0
        fi

        echo ""
        log_warn "Fresh environment detected: missing components need to be installed to achieve 'Zero to Function'."
        
        local do_install=0
        if [ "$AUTO_INSTALL" -eq 1 ]; then
            do_install=1
        else
            read -r -p "Do you want poco-gaming to auto-configure this machine now? [Y/n] " yn
            case "${yn:-Y}" in
                [Yy]* ) do_install=1 ;;
                * ) log_warn "Skipping auto-installation. Will attempt to run with current environment..." ;;
            esac
        fi

        if [ "$do_install" -eq 1 ]; then
            install_missing_dependencies "$distro_id" "$needs_adb" "$needs_scrcpy_upgrade" "$needs_udev" "$needs_vaapi"
        fi
    else
        log_success "All system requirements and dependencies are already satisfied."
    fi
}

# ------------------------------------------------------------------------------
# Module 2: Host Display Resolution and Aspect Ratio Sensor
# ------------------------------------------------------------------------------
detect_host_display() {
    log_step "Detecting Host Display Resolution and Aspect Ratio"

    local detected_res=""

    if [ -n "${CUSTOM_HOST_W:-}" ] && [ -n "${CUSTOM_HOST_H:-}" ]; then
        detected_res="${CUSTOM_HOST_W}x${CUSTOM_HOST_H}"
        log_info "Using custom resolution override from config.env: ${detected_res}"
    fi

    # Method 1: Read directly from /sys/class/drm (Wayland/X11 agnostic)
    if [ -z "$detected_res" ]; then
        for mode_file in /sys/class/drm/card*-eDP-*/modes /sys/class/drm/card*-*/modes; do
            if [ -f "$mode_file" ]; then
                detected_res=$(head -n1 "$mode_file" 2>/dev/null || true)
                if [ -n "$detected_res" ]; then
                    log_info "Resolution detected from DRM kernel sysfs ($mode_file): ${detected_res}"
                    break
                fi
            fi
        done
    fi

    # Method 2: Fallback to xrandr
    if [ -z "$detected_res" ] && command -v xrandr >/dev/null 2>&1; then
        detected_res=$(xrandr --current 2>/dev/null | grep -E '\*' | head -n1 | awk '{print $1}' || true)
        if [ -n "$detected_res" ]; then
            log_info "Resolution detected from xrandr: ${detected_res}"
        fi
    fi

    # Method 3: Fallback default (Zorin / Surface / Jinlon standard)
    if [ -z "$detected_res" ]; then
        detected_res="1920x1280"
        log_warn "Could not auto-detect display. Using default profile: ${detected_res}"
    fi

    HOST_W=$(echo "$detected_res" | cut -d'x' -f1)
    HOST_H=$(echo "$detected_res" | cut -d'x' -f2)

    # Detect Host Display Refresh Rate (Hz)
    local raw_hz=""
    if command -v xrandr >/dev/null 2>&1; then
        raw_hz=$(xrandr 2>/dev/null | grep -E '\*' | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1 || echo "")
    fi

    if [ -n "$raw_hz" ]; then
        local int_hz
        int_hz=$(echo "$raw_hz" | cut -d'.' -f1)
        if [ "$int_hz" -ge 135 ]; then HOST_HZ=144
        elif [ "$int_hz" -ge 110 ]; then HOST_HZ=120
        elif [ "$int_hz" -ge 85 ]; then HOST_HZ=90
        elif [ "$int_hz" -ge 55 ]; then HOST_HZ=60
        else HOST_HZ="$int_hz"
        fi
        log_info "Host refresh rate detected: ${HOST_HZ} Hz (${raw_hz} Hz raw)"
    else
        HOST_HZ=60
        log_info "Defaulting host refresh rate: 60 Hz"
    fi

    TARGET_FPS="$HOST_HZ"

    # Calculate Aspect Ratio
    if [ "$HOST_W" -eq 1920 ] && [ "$HOST_H" -eq 1280 ]; then
        HOST_RATIO="3:2"
    elif [ "$HOST_W" -eq 1920 ] && [ "$HOST_H" -eq 1080 ]; then
        HOST_RATIO="16:9"
    elif [ "$HOST_W" -eq 2560 ] && [ "$HOST_H" -eq 1600 ]; then
        HOST_RATIO="16:10"
    elif [ "$HOST_W" -eq 2560 ] && [ "$HOST_H" -eq 1440 ]; then
        HOST_RATIO="16:9"
    else
        HOST_RATIO="${HOST_W}:${HOST_H}"
    fi

    log_success "Target Display: ${HOST_W}x${HOST_H} (Aspect Ratio: ${HOST_RATIO})"
}

# ------------------------------------------------------------------------------
# Module 3: POCO Device Profiler and Hardware Telemetry
# ------------------------------------------------------------------------------
profile_device() {
    log_step "Connecting to POCO Device and Profiling Hardware"

    # Start adb server
    adb start-server >/dev/null 2>&1

    log_info "Waiting for device via USB (ensure USB Debugging is ON)..."
    local timeout=25
    local count=0

    while true; do
        local state
        state=$(adb get-state 2>/dev/null || echo "disconnected")
        if [ "$state" = "device" ]; then
            break
        elif [ "$state" = "unauthorized" ]; then
            log_warn "Device detected but UNAUTHORIZED! Check your POCO screen and authorize USB debugging."
        fi

        sleep 1
        count=$((count + 1))
        if [ "$count" -ge "$timeout" ]; then
            log_error "Connection timed out. No authorized Android device detected."
            log_info "Troubleshooting checklist:"
            echo "  1. Reconnect the USB-C cable."
            echo "  2. Unlock POCO screen and accept the 'Allow USB debugging' prompt."
            echo "  3. Xiaomi Settings -> Additional Settings -> Developer Options:"
            echo "     - Enable 'USB debugging'"
            echo "     - Enable 'USB debugging (Security settings)'"
            exit 1
        fi
    done

    # Collect Device Telemetry
    local dev_model dev_platform dev_soc dev_brand
    dev_model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    dev_brand=$(adb shell getprop ro.product.brand 2>/dev/null | tr -d '\r')
    dev_platform=$(adb shell getprop ro.board.platform 2>/dev/null | tr -d '\r')
    dev_soc=$(adb shell getprop ro.soc.model 2>/dev/null | tr -d '\r')
    [ -z "$dev_soc" ] && dev_soc=$(adb shell getprop ro.hardware 2>/dev/null | tr -d '\r')

    log_success "Connected: ${dev_brand} ${dev_model} [SoC: ${dev_platform:-$dev_soc}]"

    # Read and Backup Original Phone Refresh Rate Configuration
    DEVICE_ORIG_PEAK_REFRESH=$(adb shell settings get system peak_refresh_rate 2>/dev/null | tr -d '\r')
    DEVICE_ORIG_MIN_REFRESH=$(adb shell settings get system min_refresh_rate 2>/dev/null | tr -d '\r')
    DEVICE_ORIG_USER_REFRESH=$(adb shell settings get system user_refresh_rate 2>/dev/null | tr -d '\r')
    DEVICE_ORIG_MIUI_REFRESH=$(adb shell settings get system miui_refresh_rate 2>/dev/null | tr -d '\r')
    log_info "POCO original refresh rate detected: ${DEVICE_ORIG_PEAK_REFRESH:-120} Hz"

    # Hardware Encoder Selection
    VIDEO_CODEC="h265"
    if command -v scrcpy >/dev/null 2>&1; then
        local encoders_list
        encoders_list=$(SNAP_LAUNCHER_NOTICE_ENABLED="false" scrcpy --list-encoders 2>&1 || true)
        if echo "$encoders_list" | grep -qi 'c2.qti.hevc.encoder'; then
            CHOSEN_ENCODER="c2.qti.hevc.encoder"
            log_success "Hardware Encoder: Qualcomm Snapdragon Dedicated HEVC (c2.qti.hevc.encoder)"
        elif echo "$encoders_list" | grep -qi 'c2.mtk.hevc.encoder'; then
            CHOSEN_ENCODER="c2.mtk.hevc.encoder"
            log_success "Hardware Encoder: MediaTek Dedicated HEVC (c2.mtk.hevc.encoder)"
        elif echo "$encoders_list" | grep -qi 'c2.android.hevc.encoder\|OMX.qcom.video.encoder.hevc'; then
            VIDEO_CODEC="h265"
            log_success "Hardware Encoder: H.265 (HEVC)"
        else
            VIDEO_CODEC="h264"
            log_info "Falling back to standard H.264 encoder"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Module 4: Resolution Scaling & Fail-Safe Restoration
# ------------------------------------------------------------------------------
setup_screen_resolution() {
    log_step "Adapting Screen Resolution to Match Host (${HOST_W}x${HOST_H} ${HOST_RATIO})"

    # Read native dimensions and density
    local wm_size_output wm_density_output
    wm_size_output=$(adb shell wm size 2>/dev/null || true)
    wm_density_output=$(adb shell wm density 2>/dev/null || true)

    DEVICE_ORIG_SIZE=$(echo "$wm_size_output" | awk -F': ' '/Physical size/ {print $2}' | tr -d '\r')
    [ -z "$DEVICE_ORIG_SIZE" ] && DEVICE_ORIG_SIZE=$(echo "$wm_size_output" | head -n1 | awk -F': ' '{print $2}' | tr -d '\r')

    DEVICE_ORIG_DENSITY=$(echo "$wm_density_output" | awk -F': ' '/Physical density/ {print $2}' | tr -d '\r')
    [ -z "$DEVICE_ORIG_DENSITY" ] && DEVICE_ORIG_DENSITY=$(echo "$wm_density_output" | head -n1 | awk -F': ' '{print $2}' | tr -d '\r')

    log_info "POCO Native Resolution: ${DEVICE_ORIG_SIZE} | Density: ${DEVICE_ORIG_DENSITY} DPI"

    if [ "$PERF_PROFILE" = "eco" ] || [ "$PERF_PROFILE" = "720p" ]; then
        HOST_W=1280
        HOST_H=854
        TARGET_DENSITY=280
        VIDEO_BITRATE="8M"
        MAX_SIZE=1280
        log_info "Profile [ESPORTS ECO]: 1280x854 (3:2) @ 8M Bitrate (Cooling & Battery Saver)"
    else
        # Calculate proportional DPI for host aspect ratio
        local orig_h
        orig_h=$(echo "$DEVICE_ORIG_SIZE" | cut -d'x' -f2)
        if [ -n "$orig_h" ] && [ "$orig_h" -gt 0 ] && [ -n "$DEVICE_ORIG_DENSITY" ] && [ "$DEVICE_ORIG_DENSITY" -gt 0 ]; then
            TARGET_DENSITY=$(( (DEVICE_ORIG_DENSITY * HOST_H) / orig_h ))
            # Clamp density within functional UI range (260 to 420)
            [ "$TARGET_DENSITY" -lt 260 ] && TARGET_DENSITY=280
            [ "$TARGET_DENSITY" -gt 440 ] && TARGET_DENSITY=340
        else
            TARGET_DENSITY=280
        fi
        MAX_SIZE=1920
        log_info "Profile [MAX QUALITY]: ${HOST_W}x${HOST_H} (3:2) @ ${VIDEO_BITRATE} Bitrate"
    fi

    log_info "Applying temporary gaming profile -> ${HOST_W}x${HOST_H} @ ${TARGET_DENSITY} DPI"
    adb shell wm size "${HOST_W}x${HOST_H}"
    adb shell wm density "${TARGET_DENSITY}"
    DISPLAY_MODIFIED=1
    log_success "Phone resolution aligned to 100% fullscreen host display."
}

restore_screen_resolution() {
    if [ "$DISPLAY_MODIFIED" -eq 1 ] || [ "$RUN_MODE" = "reset" ]; then
        log_info "Restoring POCO display size and density to factory defaults..."

        # If disconnected (e.g. user pulled the USB-C cable), wait for reconnection
        local state
        state=$(adb get-state 2>/dev/null || echo "disconnected")
        if [ "$state" != "device" ]; then
            log_warn "POCO device is currently disconnected! Reconnect USB-C cable to restore original display."
            log_info "Waiting up to 15 seconds for device reconnection..."
            local count=0
            while [ "$count" -lt 15 ]; do
                state=$(adb get-state 2>/dev/null || echo "disconnected")
                if [ "$state" = "device" ]; then
                    log_success "POCO reconnected!"
                    break
                fi
                sleep 1
                count=$((count + 1))
            done
        fi

        adb shell wm size reset 2>/dev/null || true
        adb shell wm density reset 2>/dev/null || true

        # Cleanly reload launcher grid in native geometry
        adb shell am force-stop com.miui.home 2>/dev/null || true
        adb shell am force-stop com.mi.android.globallauncher 2>/dev/null || true

        DISPLAY_MODIFIED=0
        log_success "Native display settings restored."
    fi
}

# ------------------------------------------------------------------------------
# Module 4.1: Laptop Screen Rotation Lock (Zorin OS / GNOME Wayland)
# ------------------------------------------------------------------------------
lock_laptop_rotation() {
    if command -v gsettings >/dev/null 2>&1; then
        if gsettings list-keys org.gnome.settings-daemon.peripherals.touchscreen 2>/dev/null | grep -q "orientation-lock"; then
            ORIG_LAPTOP_LOCK=$(gsettings get org.gnome.settings-daemon.peripherals.touchscreen orientation-lock 2>/dev/null || echo "false")
            if [ "$ORIG_LAPTOP_LOCK" != "true" ]; then
                log_step "Locking Laptop Auto-Rotation in Zorin OS"
                gsettings set org.gnome.settings-daemon.peripherals.touchscreen orientation-lock true 2>/dev/null || true
                LAPTOP_LOCK_MODIFIED=1
                log_success "Laptop screen locked to current orientation (won't rotate when moved)."
            else
                log_info "Laptop screen rotation was already locked."
            fi
        fi
    fi
}

restore_laptop_rotation() {
    if [ "$LAPTOP_LOCK_MODIFIED" -eq 1 ] || [ "$RUN_MODE" = "reset" ]; then
        if command -v gsettings >/dev/null 2>&1; then
            if gsettings list-keys org.gnome.settings-daemon.peripherals.touchscreen 2>/dev/null | grep -q "orientation-lock"; then
                log_info "Restoring laptop orientation-lock state (${ORIG_LAPTOP_LOCK:-false})..."
                gsettings set org.gnome.settings-daemon.peripherals.touchscreen orientation-lock "${ORIG_LAPTOP_LOCK:-false}" 2>/dev/null || true
                LAPTOP_LOCK_MODIFIED=0
                log_success "Laptop rotation settings restored."
            fi
        fi
    fi
}

# ------------------------------------------------------------------------------
# Module 4.2: Phone Forced Screen Orientation Lock
# ------------------------------------------------------------------------------
setup_device_orientation() {
    if [ -n "$REQUESTED_ROTATION" ]; then
        log_step "Locking POCO Screen Orientation to ${REQUESTED_ROTATION}°"

        DEVICE_ORIG_ACCEL_ROTATION=$(adb shell settings get system accelerometer_rotation 2>/dev/null | tr -d '\r')
        DEVICE_ORIG_USER_ROTATION=$(adb shell settings get system user_rotation 2>/dev/null | tr -d '\r')

        case "$REQUESTED_ROTATION" in
            0)   ROTATION_NUM=0 ;;
            90)  ROTATION_NUM=1 ;;
            180) ROTATION_NUM=2 ;;
            270) ROTATION_NUM=3 ;;
            *)   ROTATION_NUM=3 ;;
        esac

        log_info "Applying hardware orientation lock (${REQUESTED_ROTATION}° / index ${ROTATION_NUM})..."
        adb shell wm set-ignore-orientation-request true 2>/dev/null || true
        adb shell wm user-rotation lock "$ROTATION_NUM" 2>/dev/null || true
        adb shell settings put system accelerometer_rotation 0 2>/dev/null || true
        adb shell settings put system user_rotation "$ROTATION_NUM" 2>/dev/null || true
        ROTATION_MODIFIED=1
        log_success "POCO orientation locked to ${REQUESTED_ROTATION}° (ignores app rotation requests)."
    fi
}

restore_device_orientation() {
    if [ "$ROTATION_MODIFIED" -eq 1 ] || [ "$RUN_MODE" = "reset" ]; then
        log_info "Restoring POCO native orientation and accelerometer..."
        local state
        state=$(adb get-state 2>/dev/null || echo "disconnected")
        if [ "$state" = "device" ]; then
            adb shell wm set-ignore-orientation-request reset 2>/dev/null || true
            adb shell wm user-rotation free 2>/dev/null || true
            adb shell settings put system accelerometer_rotation "${DEVICE_ORIG_ACCEL_ROTATION:-1}" 2>/dev/null || true
            adb shell settings put system user_rotation "${DEVICE_ORIG_USER_ROTATION:-0}" 2>/dev/null || true
            ROTATION_MODIFIED=0
            log_success "POCO accelerometer and orientation restored."
        fi
    fi
}

# ------------------------------------------------------------------------------
# Module 4.3: Android Desktop Mode (Freeform Windows inspired by DroidUP-Dex)
# ------------------------------------------------------------------------------
setup_dex_mode() {
    log_step "Configuring Android Desktop DeX Mode (Freeform Windows)"

    ORIG_FREEFORM=$(adb shell settings get global enable_freeform_support 2>/dev/null | tr -d '\r')
    ORIG_RESIZABLE=$(adb shell settings get global force_resizable_activities 2>/dev/null | tr -d '\r')

    log_info "Enabling Android Freeform windows and resizable activities..."
    adb shell settings put global enable_freeform_support 1 2>/dev/null || true
    adb shell settings put global force_resizable_activities 1 2>/dev/null || true
    adb shell settings put global force_desktop_mode_on_external_displays 0 2>/dev/null || true
    DEX_MODE_ACTIVE=1
    log_success "Android Freeform Desktop environment activated."
}

restore_dex_mode() {
    if [ "$DEX_MODE_ACTIVE" -eq 1 ] || [ "$RUN_MODE" = "reset" ]; then
        local state
        state=$(adb get-state 2>/dev/null || echo "disconnected")
        if [ "$state" = "device" ]; then
            log_info "Restoring Android window manager global settings..."
            if [ -n "$ORIG_FREEFORM" ] && [ "$ORIG_FREEFORM" != "null" ]; then
                adb shell settings put global enable_freeform_support "$ORIG_FREEFORM" 2>/dev/null || true
            else
                adb shell settings delete global enable_freeform_support 2>/dev/null || true
            fi

            if [ -n "$ORIG_RESIZABLE" ] && [ "$ORIG_RESIZABLE" != "null" ]; then
                adb shell settings put global force_resizable_activities "$ORIG_RESIZABLE" 2>/dev/null || true
            else
                adb shell settings delete global force_resizable_activities 2>/dev/null || true
            fi
            DEX_MODE_ACTIVE=0
            log_success "Desktop mode global settings restored."
        fi
    fi
}

sync_device_refresh_rate() {
    log_step "Synchronizing POCO Refresh Rate to Host (${HOST_HZ} Hz)"
    log_info "Configuring Android system display pipeline to ${HOST_HZ} Hz..."

    adb shell settings put system peak_refresh_rate "${HOST_HZ}.0" 2>/dev/null || true
    adb shell settings put system min_refresh_rate "${HOST_HZ}.0" 2>/dev/null || true
    adb shell settings put system user_refresh_rate "$HOST_HZ" 2>/dev/null || true
    adb shell settings put system miui_refresh_rate "$HOST_HZ" 2>/dev/null || true
    REFRESH_MODIFIED=1
    log_success "POCO system refresh rate locked to ${HOST_HZ} Hz (VSYNC aligned)."
}

restore_device_refresh_rate() {
    if [ "$REFRESH_MODIFIED" -eq 1 ] || [ "$RUN_MODE" = "reset" ]; then
        log_info "Restoring POCO refresh rate to original settings (${DEVICE_ORIG_PEAK_REFRESH:-120} Hz)..."

        local state
        state=$(adb get-state 2>/dev/null || echo "disconnected")
        if [ "$state" = "device" ]; then
            if [ -n "$DEVICE_ORIG_PEAK_REFRESH" ] && [ "$DEVICE_ORIG_PEAK_REFRESH" != "null" ]; then
                adb shell settings put system peak_refresh_rate "$DEVICE_ORIG_PEAK_REFRESH" 2>/dev/null || true
            else
                adb shell settings put system peak_refresh_rate 120.0 2>/dev/null || true
            fi

            if [ -n "$DEVICE_ORIG_MIN_REFRESH" ] && [ "$DEVICE_ORIG_MIN_REFRESH" != "null" ]; then
                adb shell settings put system min_refresh_rate "$DEVICE_ORIG_MIN_REFRESH" 2>/dev/null || true
            else
                adb shell settings delete system min_refresh_rate 2>/dev/null || true
            fi

            if [ -n "$DEVICE_ORIG_USER_REFRESH" ] && [ "$DEVICE_ORIG_USER_REFRESH" != "null" ]; then
                adb shell settings put system user_refresh_rate "$DEVICE_ORIG_USER_REFRESH" 2>/dev/null || true
            else
                adb shell settings put system user_refresh_rate 120 2>/dev/null || true
            fi

            if [ -n "$DEVICE_ORIG_MIUI_REFRESH" ] && [ "$DEVICE_ORIG_MIUI_REFRESH" != "null" ]; then
                adb shell settings put system miui_refresh_rate "$DEVICE_ORIG_MIUI_REFRESH" 2>/dev/null || true
            else
                adb shell settings put system miui_refresh_rate 120 2>/dev/null || true
            fi

            REFRESH_MODIFIED=0
            log_success "POCO refresh rate restored to original state."
        fi
    fi
}

# ------------------------------------------------------------------------------
# Module 5: Ultra-Low Latency scrcpy Runner
# ------------------------------------------------------------------------------
launch_scrcpy() {
    log_step "Launching Low-Latency Game Session"

    local scrcpy_cmd=("scrcpy" "-d")

    # Force ADB forward for maximum connection stability (from jogar_poco.sh)
    if [ "${FORCE_ADB_FORWARD:-1}" -eq 1 ]; then
        scrcpy_cmd+=("--force-adb-forward")
    fi

    # Forced orientation in scrcpy capture if requested
    if [ -n "$REQUESTED_ROTATION" ]; then
        scrcpy_cmd+=("--capture-orientation=@${REQUESTED_ROTATION}")
    fi

    case "$RUN_MODE" in
        dex)
            log_info "Running in Android Desktop DeX Mode (Freeform Windows + Virtual Display)"
            scrcpy_cmd+=("--new-display=${HOST_W}x${HOST_H}/${TARGET_DENSITY}")
            scrcpy_cmd+=("--no-vd-system-decorations")
            scrcpy_cmd+=("-f")
            scrcpy_cmd+=("--video-codec=${VIDEO_CODEC:-h265}")
            scrcpy_cmd+=("--video-buffer=${VIDEO_BUFFER:-0}")
            scrcpy_cmd+=("--video-codec-options=latency:int=0,priority:int=0")
            scrcpy_cmd+=("--video-bit-rate=${VIDEO_BITRATE:-16M}")
            scrcpy_cmd+=("--max-fps=${TARGET_FPS}")
            ;;
        virtual)
            log_info "Running in Secondary Virtual Display Mode (--new-display)"
            scrcpy_cmd+=("--new-display=${HOST_W}x${HOST_H}/${TARGET_DENSITY}")
            scrcpy_cmd+=("--no-vd-system-decorations")
            scrcpy_cmd+=("-f")
            scrcpy_cmd+=("--video-codec=${VIDEO_CODEC:-h265}")
            scrcpy_cmd+=("--video-buffer=${VIDEO_BUFFER:-0}")
            scrcpy_cmd+=("--video-codec-options=latency:int=0,priority:int=0")
            scrcpy_cmd+=("--video-bit-rate=${VIDEO_BITRATE:-16M}")
            scrcpy_cmd+=("--max-fps=${TARGET_FPS}")
            ;;
        otg)
            log_info "Running in Pure Hardware Docking Mode (--otg)"
            scrcpy_cmd+=("--otg")
            ;;
        normal|daemon)
            log_info "Applying Fullscreen Low-Latency Pipeline (${PERF_PROFILE:-max} profile)"
            scrcpy_cmd+=("-f")                                                # Fullscreen
            scrcpy_cmd+=("--video-buffer=${VIDEO_BUFFER:-0}")                 # 0ms pipeline video buffer
            scrcpy_cmd+=("--video-codec-options=latency:int=0,priority:int=0") # Realtime 0 latency queue
            scrcpy_cmd+=("--video-codec=${VIDEO_CODEC:-h265}")                # Fast H.265 / HEVC
            scrcpy_cmd+=("--video-bit-rate=${VIDEO_BITRATE:-16M}")            # Bitrate
            scrcpy_cmd+=("--max-size=${MAX_SIZE:-1920}")                      # Max frame dimension
            scrcpy_cmd+=("--max-fps=${TARGET_FPS}")                           # Matched refresh rate

            [ "${TURN_SCREEN_OFF:-1}" -eq 1 ] && scrcpy_cmd+=("--turn-screen-off") # Prevent phone heating
            [ "${STAY_AWAKE:-1}" -eq 1 ] && scrcpy_cmd+=("--stay-awake")           # Prevent OS sleep
            [ "${ENABLE_UHID_KEYBOARD:-1}" -eq 1 ] && scrcpy_cmd+=("--keyboard=uhid") # Direct kernel HID input
            [ "${ENABLE_UHID_MOUSE:-1}" -eq 1 ] && scrcpy_cmd+=("--mouse=uhid")       # Direct kernel HID mouse
            [ "${ENABLE_UHID_GAMEPAD:-1}" -eq 1 ] && scrcpy_cmd+=("--gamepad=uhid")   # Pass physical PC controller as Android gamepad

            if [ -n "$CHOSEN_ENCODER" ]; then
                scrcpy_cmd+=("--video-encoder=${CHOSEN_ENCODER}")
            fi
            ;;
    esac

    # Audio forwarding configuration
    if [ "$DISABLE_AUDIO" -eq 1 ]; then
        log_info "Audio forwarding disabled (--no-audio active)"
        scrcpy_cmd+=("--no-audio")
    else
        scrcpy_cmd+=("--audio-buffer=${AUDIO_BUFFER:-50}")
        scrcpy_cmd+=("--audio-source=${AUDIO_SOURCE:-playback}")
        [ "${AUDIO_DUP:-1}" -eq 1 ] && scrcpy_cmd+=("--audio-dup")       # Play on PC + Phone simultaneously
        [ -n "${AUDIO_CODEC:-}" ] && scrcpy_cmd+=("--audio-codec=${AUDIO_CODEC}")
    fi

    log_info "Executing: ${scrcpy_cmd[*]}"
    echo -e "${C_GREEN}${C_BOLD}>>> GAME ON! <<<${C_RESET}"
    echo -e "  To exit cleanly: Press ${C_BOLD}Alt+F4${C_RESET} or ${C_BOLD}Super+Q${C_RESET} (or Ctrl+C in terminal)\n"

    # Run scrcpy in background and track PID to guarantee clean SIGINT termination
    "${scrcpy_cmd[@]}" &
    SCRCPY_PID=$!
    wait "$SCRCPY_PID" 2>/dev/null || true
    SCRCPY_PID=""

    # Complete restoration sequence
    restore_laptop_rotation
    restore_dex_mode
    restore_device_orientation
    restore_device_refresh_rate
    restore_screen_resolution
}

# ------------------------------------------------------------------------------
# Module 6: Daemon Plug-and-Play Mode
# ------------------------------------------------------------------------------
run_daemon_mode() {
    log_step "Starting Plug-and-Play Daemon Mode"
    log_info "Watching for POCO connection via USB... (Press Ctrl+C to stop)"

    while true; do
        local state
        state=$(adb get-state 2>/dev/null || echo "disconnected")
        if [ "$state" = "device" ]; then
            log_success "POCO connected! Initializing gaming environment..."
            detect_host_display
            profile_device
            [ "$LOCK_LAPTOP_ROTATION" -eq 1 ] && lock_laptop_rotation
            setup_screen_resolution
            sync_device_refresh_rate
            setup_device_orientation
            launch_scrcpy
            log_info "Session finished. Waiting for next device connection..."
        fi
        sleep 2
    done
}

# ------------------------------------------------------------------------------
# Help and Usage
# ------------------------------------------------------------------------------
show_help() {
    echo -e "${C_BOLD}${APP_NAME} v${VERSION}${C_RESET}

Usage: $(basename "$0") [OPTIONS]

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
"
}

# ------------------------------------------------------------------------------
# Main Entry Point
# ------------------------------------------------------------------------------
main() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -y|--yes)
                AUTO_INSTALL=1
                ;;
            --install)
                AUTO_INSTALL=1
                check_and_install_deps
                exit 0
                ;;
            --check)
                RUN_MODE="check"
                ;;
            --reset)
                RUN_MODE="reset"
                restore_laptop_rotation
                restore_dex_mode
                restore_device_orientation
                restore_device_refresh_rate
                restore_screen_resolution
                exit 0
                ;;
            --landscape|-l)
                REQUESTED_ROTATION="270"
                ;;
            --portrait|-p)
                REQUESTED_ROTATION="0"
                ;;
            --rotate)
                shift
                REQUESTED_ROTATION="${1:-270}"
                ;;
            --lock-laptop)
                LOCK_LAPTOP_ROTATION=1
                ;;
            --no-audio)
                DISABLE_AUDIO=1
                ;;
            --audio-dup)
                DISABLE_AUDIO=0
                AUDIO_DUP=1
                ;;
            --eco|--720p)
                PERF_PROFILE="eco"
                ;;
            --max|--1080p)
                PERF_PROFILE="max"
                ;;
            --dex|--desktop)
                RUN_MODE="dex"
                ;;
            --virtual)
                RUN_MODE="virtual"
                ;;
            --otg)
                RUN_MODE="otg"
                ;;
            --daemon)
                RUN_MODE="daemon"
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done

    check_and_install_deps

    if [ "$RUN_MODE" = "check" ]; then
        exit 0
    fi

    # Self-healing check: reset leftover display overrides from any previous session
    if [ "$RUN_MODE" != "reset" ] && command -v adb >/dev/null 2>&1; then
        if [ "$(adb get-state 2>/dev/null || echo '')" = "device" ]; then
            if adb shell wm size 2>/dev/null | grep -q "Override size"; then
                log_warn "Leftover display override detected from previous session. Auto-resetting to native..."
                adb shell wm size reset 2>/dev/null || true
                adb shell wm density reset 2>/dev/null || true
            fi
        fi
    fi

    if [ "$RUN_MODE" = "daemon" ]; then
        run_daemon_mode
    else
        detect_host_display
        profile_device

        # Lock laptop auto-rotation if enabled
        if [ "$LOCK_LAPTOP_ROTATION" -eq 1 ]; then
            lock_laptop_rotation
        fi

        case "$RUN_MODE" in
            dex)
                setup_dex_mode
                sync_device_refresh_rate
                ;;
            virtual)
                sync_device_refresh_rate
                ;;
            normal)
                setup_screen_resolution
                sync_device_refresh_rate
                setup_device_orientation
                ;;
        esac

        launch_scrcpy
    fi
}

main "$@"
