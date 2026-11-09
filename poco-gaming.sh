#!/usr/bin/env bash
# ==============================================================================
# OmniLink Mobile Engine (scrcpy)
# Universal Ultra-Low Latency Android Gaming & Desktop Suite
# Compatible with: Any Android Device & Any Linux Workstation (Wayland & X11)
# ==============================================================================

set -eo pipefail

# ------------------------------------------------------------------------------
# Global Variables and Defaults
# ------------------------------------------------------------------------------
APP_NAME="OmniLink Mobile Engine"
VERSION="2.0.0"

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
PERF_PROFILE="max" # max (1080p), eco (720p), mirror
VIDEO_CODEC="h265"
VIDEO_BITRATE="16M"
FORCE_ADB_FORWARD=1
CHOSEN_ENCODER=""
DISABLE_AUDIO=0
AUDIO_DUP=1
TURN_SCREEN_OFF=1
STAY_AWAKE=1

# Orientation Controls
WINDOW_ORIENTATION="auto" # auto, horizontal, vertical
FORCE_DEVICE_ROTATION="" # 0, 90, 180, 270 (if user explicitly requests hardware lock)
REQUESTED_ROTATION="" # backwards compatibility
ROTATION_NUM=3
LOCK_LAPTOP_ROTATION=0
ORIG_LAPTOP_LOCK=""

# Device Telemetry & Identification
DEVICE_SERIAL=""
DEVICE_BRAND="Android"
DEVICE_MODEL="Device"
DEVICE_MANUFACTURER=""
DEVICE_SOC="Generic"
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
DEX_LAUNCHER_ACTIVE=""

AUTO_INSTALL=0
RUN_MODE="normal" # normal, eco, dex, mirror, virtual, otg, daemon, reset, check, reset-launcher

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

on_error() {
    local line=$1
    local cmd=$2
    local code=$3
    log_error "Internal error at line ${line} (command: \"${cmd}\", exit code: ${code})"
}

trap 'on_error "$LINENO" "$BASH_COMMAND" "$?"' ERR

# ------------------------------------------------------------------------------
# Fail-Safe Cleanup Handler (POSIX Trap)
# ------------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM HUP ERR # Prevent recursive trap calls

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

    # Terminate any lingering scrcpy sessions
    pkill -f "scrcpy -d" 2>/dev/null || true

    # Execute State Restorations in reverse order
    restore_laptop_rotation
    restore_dex_mode
    restore_device_orientation
    restore_device_refresh_rate
    restore_screen_resolution

    if [ "$exit_code" -ne 0 ]; then
        log_warn "Session ended with return code ${exit_code}."
    fi
}

trap cleanup EXIT INT TERM HUP

# ------------------------------------------------------------------------------
# Module 1: Universal Dependency and System Verifier
# ------------------------------------------------------------------------------
detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_LIKE="${ID_LIKE:-$OS_ID}"
    else
        OS_ID="unknown"
        OS_LIKE="unknown"
    fi
    log_info "Detected OS: ${OS_ID} (${OS_LIKE})"
}

check_and_install_deps() {
    log_step "Checking System Environment and Dependencies"
    detect_os

    local missing_deps=()
    local needs_scrcpy_upgrade=0

    # 1. ADB Check
    if ! command -v adb >/dev/null 2>&1; then
        missing_deps+=("adb")
        log_warn "adb is not installed."
    else
        log_success "ADB found: $(command -v adb)"
    fi

    # 2. scrcpy Version Check
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
            log_warn "Installed scrcpy version ($scrcpy_ver) is outdated (< 2.0). Modern codecs require v2.0+."
            needs_scrcpy_upgrade=1
        else
            log_success "scrcpy version is up-to-date: ${scrcpy_ver}"
        fi

        # Check snap confinement plugs (raw-usb, joystick)
        if command -v snap >/dev/null 2>&1 && snap list scrcpy >/dev/null 2>&1; then
            local snap_conns
            snap_conns=$(snap connections scrcpy 2>/dev/null || true)
            if echo "$snap_conns" | grep -qE '^joystick\s+scrcpy:joystick\s+-'; then
                log_warn "scrcpy joystick plug not connected (required for Gamepad mode)."
                needs_scrcpy_upgrade=1
            elif echo "$snap_conns" | grep -qE '^raw-usb\s+scrcpy:raw-usb\s+-'; then
                log_warn "scrcpy raw-usb plug not connected (required for low-latency direct USB)."
                needs_scrcpy_upgrade=1
            else
                log_success "scrcpy snap security plugs (raw-usb, joystick) verified."
            fi
        fi
    fi

    # 3. Android udev Rules Check
    local udev_rule="/etc/udev/rules.d/51-android.rules"
    local needs_udev=0
    if [ ! -f "$udev_rule" ]; then
        needs_udev=1
        log_warn "Android udev rules missing in ${udev_rule}."
    else
        log_success "Android udev rules verified."
    fi

    # 4. Hardware Decoders Check on Host
    if command -v vainfo >/dev/null 2>&1; then
        if vainfo 2>&1 | grep -qi "VAProfileHEVC"; then
            log_success "Hardware VA-API HEVC decoder verified on host GPU."
        else
            log_info "VA-API available; verifying driver profile..."
        fi
    fi

    if [ ${#missing_deps[@]} -eq 0 ] && [ "$needs_scrcpy_upgrade" -eq 0 ] && [ "$needs_udev" -eq 0 ]; then
        log_success "All system requirements and dependencies are already satisfied."
        return 0
    fi

    if [ "$RUN_MODE" = "check" ]; then
        log_warn "Environment setup is incomplete. Run with -y to auto-configure."
        return 0
    fi

    echo ""
    log_warn "Missing components detected. Auto-configuring system..."

    local do_install=0
    if [ "$AUTO_INSTALL" -eq 1 ]; then
        do_install=1
    else
        read -r -p "Do you want OmniLink to auto-configure this machine now? [Y/n] " yn
        case "${yn:-Y}" in
            [Yy]* ) do_install=1 ;;
            * )
                log_error "Installation cancelled. Required dependencies are missing."
                exit 1
                ;;
        esac
    fi

    if [ "$do_install" -eq 1 ]; then
        log_step "Auto-Configuring System (Zero-to-Function Installer)"
        log_info "Elevating privileges to install missing packages and configure udev..."

        if [ "$needs_udev" -eq 1 ]; then
            log_info "Configuring universal Android USB udev permissions..."
            cat << 'EOF' | sudo tee "$udev_rule" >/dev/null
# Universal Android USB Rules (Xiaomi, Samsung, Google, Motorola, OnePlus, Asus)
SUBSYSTEM=="usb", ATTR{idVendor}=="2717", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="22b8", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="2a70", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="0b05", MODE="0666", GROUP="plugdev"
EOF
            sudo udevadm control --reload-rules || true
            sudo udevadm trigger || true
            log_success "Universal udev rules configured successfully."
        fi

        if [ ${#missing_deps[@]} -gt 0 ] || [ "$needs_scrcpy_upgrade" -eq 1 ]; then
            case "$OS_LIKE" in
                *debian*|*ubuntu*)
                    sudo apt update -y
                    [ ${#missing_deps[@]} -gt 0 ] && sudo apt install -y "${missing_deps[@]}"
                    if [ "$needs_scrcpy_upgrade" -eq 1 ]; then
                        if command -v snap >/dev/null 2>&1; then
                            sudo snap install scrcpy --classic 2>/dev/null || sudo snap refresh scrcpy
                            sudo snap connect scrcpy:raw-usb 2>/dev/null || true
                            sudo snap connect scrcpy:joystick 2>/dev/null || true
                        fi
                    fi
                    ;;
                *fedora*|*rhel*)
                    sudo dnf install -y adb scrcpy
                    ;;
                *arch*)
                    sudo pacman -Sy --noconfirm android-tools scrcpy
                    ;;
            esac
        fi
        log_success "All system requirements and dependencies are now ready!"
    fi
}

# ------------------------------------------------------------------------------
# Module 2: Host Display Geometry & Refresh Rate Detection
# ------------------------------------------------------------------------------
detect_host_display() {
    log_step "Detecting Host Display Resolution and Aspect Ratio"

    local detected_res=""
    local detected_hz=60

    # 1. DRM Kernel sysfs detection
    for mode_file in /sys/class/drm/card*-eDP-*/modes /sys/class/drm/card*-HDMI-*/modes /sys/class/drm/card*-DP-*/modes; do
        if [ -f "$mode_file" ]; then
            detected_res=$(head -n1 "$mode_file" 2>/dev/null | tr -d '\r\n')
            if [ -n "$detected_res" ] && [[ "$detected_res" =~ ^[0-9]+x[0-9]+$ ]]; then
                log_info "Resolution detected from DRM kernel sysfs (${mode_file}): ${detected_res}"
                break
            fi
        fi
    done

    # 2. Wayland / Zorin OS / GNOME Display Query Fallback
    if [ -z "$detected_res" ] && command -v gnome-monitor-config >/dev/null 2>&1; then
        detected_res=$(gnome-monitor-config list 2>/dev/null | grep -E "MODE:" | head -n1 | awk '{print $2}' || true)
    fi

    # 3. xrandr Fallback
    if [ -z "$detected_res" ] && command -v xrandr >/dev/null 2>&1; then
        detected_res=$(xrandr --current 2>/dev/null | grep -E '\*' | head -n1 | awk '{print $1}' || true)
    fi

    if [ -n "$detected_res" ] && [[ "$detected_res" =~ ^[0-9]+x[0-9]+$ ]]; then
        HOST_W=$(echo "$detected_res" | cut -d'x' -f1)
        HOST_H=$(echo "$detected_res" | cut -d'x' -f2)
    else
        log_warn "Could not auto-detect display resolution. Defaulting to 1920x1280 (3:2)."
        HOST_W=1920
        HOST_H=1280
    fi

    # Detect Host Refresh Rate (Hz)
    for connector_status in /sys/class/drm/card*-eDP-*/status; do
        if [ -f "$connector_status" ] && grep -q "connected" "$connector_status" 2>/dev/null; then
            local edid_file
            edid_file="$(dirname "$connector_status")/edid"
            if [ -f "$edid_file" ] && command -v edid-decode >/dev/null 2>&1; then
                local edid_hz
                edid_hz=$(edid-decode "$edid_file" 2>/dev/null | grep -E -o '[0-9]+\.[0-9]+ Hz' | head -n1 | cut -d'.' -f1 || true)
                if [ -n "$edid_hz" ] && [ "$edid_hz" -gt 30 ]; then
                    detected_hz="$edid_hz"
                    break
                fi
            fi
        fi
    done

    HOST_HZ="${detected_hz:-60}"
    TARGET_FPS="$HOST_HZ"
    log_info "Host refresh rate detected: ${HOST_HZ} Hz"

    # Compute Aspect Ratio
    local ratio_val
    ratio_val=$(awk "BEGIN {printf \"%.2f\", ${HOST_W}/${HOST_H}}")
    if [ "$ratio_val" = "1.50" ]; then
        HOST_RATIO="3:2"
    elif [ "$ratio_val" = "1.78" ]; then
        HOST_RATIO="16:9"
    elif [ "$ratio_val" = "1.60" ]; then
        HOST_RATIO="16:10"
    elif [ "$ratio_val" = "2.33" ] || [ "$ratio_val" = "2.37" ]; then
        HOST_RATIO="21:9"
    else
        HOST_RATIO="${HOST_W}:${HOST_H}"
    fi

    log_success "Target Display: ${HOST_W}x${HOST_H} (Aspect Ratio: ${HOST_RATIO})"
}

# ------------------------------------------------------------------------------
# Module 3: Universal Device Profiler and Hardware Telemetry
# ------------------------------------------------------------------------------
profile_device() {
    log_step "Connecting to Android Device and Profiling Hardware"

    adb start-server >/dev/null 2>&1 || true

    log_info "Waiting for device via USB (ensure USB Debugging is ON)..."
    local timeout=25
    local count=0

    while true; do
        local state
        state=$(adb get-state 2>/dev/null || echo "disconnected")
        if [ "$state" = "device" ]; then
            break
        elif [ "$state" = "unauthorized" ]; then
            log_warn "Device detected but UNAUTHORIZED! Check your phone screen and authorize USB debugging."
        fi

        sleep 1
        count=$((count + 1))
        if [ "$count" -ge "$timeout" ]; then
            log_error "Connection timed out. No authorized Android device detected."
            exit 1
        fi
    done

    # Obtain exact Device Serial
    DEVICE_SERIAL=$(adb get-serialno 2>/dev/null | tr -d '\r\n')
    if [ -z "$DEVICE_SERIAL" ] || [ "$DEVICE_SERIAL" = "unknown" ]; then
        DEVICE_SERIAL=$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device" {print $1}' | head -n1)
    fi

    # Universal Device Properties
    DEVICE_MODEL=$(adb -s "$DEVICE_SERIAL" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    DEVICE_BRAND=$(adb -s "$DEVICE_SERIAL" shell getprop ro.product.brand 2>/dev/null | tr -d '\r')
    DEVICE_MANUFACTURER=$(adb -s "$DEVICE_SERIAL" shell getprop ro.product.manufacturer 2>/dev/null | tr -d '\r')
    local dev_platform dev_soc
    dev_platform=$(adb -s "$DEVICE_SERIAL" shell getprop ro.board.platform 2>/dev/null | tr -d '\r')
    dev_soc=$(adb -s "$DEVICE_SERIAL" shell getprop ro.soc.model 2>/dev/null | tr -d '\r')
    [ -z "$dev_soc" ] && dev_soc=$(adb -s "$DEVICE_SERIAL" shell getprop ro.hardware 2>/dev/null | tr -d '\r')
    DEVICE_SOC="${dev_soc:-$dev_platform}"

    log_success "Connected: ${DEVICE_MANUFACTURER} ${DEVICE_BRAND} ${DEVICE_MODEL} (Serial: ${DEVICE_SERIAL}) [SoC: ${DEVICE_SOC}]"

    # Read native dimensions and density
    local wm_size_output wm_density_output
    wm_size_output=$(adb -s "$DEVICE_SERIAL" shell wm size 2>/dev/null || true)
    wm_density_output=$(adb -s "$DEVICE_SERIAL" shell wm density 2>/dev/null || true)

    DEVICE_ORIG_SIZE=$(echo "$wm_size_output" | awk -F': ' '/Physical size/ {print $2}' | tr -d '\r')
    [ -z "$DEVICE_ORIG_SIZE" ] && DEVICE_ORIG_SIZE=$(echo "$wm_size_output" | head -n1 | awk -F': ' '{print $2}' | tr -d '\r')

    DEVICE_ORIG_DENSITY=$(echo "$wm_density_output" | awk -F': ' '/Physical density/ {print $2}' | tr -d '\r')
    [ -z "$DEVICE_ORIG_DENSITY" ] && DEVICE_ORIG_DENSITY=$(echo "$wm_density_output" | head -n1 | awk -F': ' '{print $2}' | tr -d '\r')

    # Compute baseline TARGET_DENSITY
    local orig_h
    orig_h=$(echo "$DEVICE_ORIG_SIZE" | cut -d'x' -f2)
    if [ -n "$orig_h" ] && [ "$orig_h" -gt 0 ] && [ -n "$DEVICE_ORIG_DENSITY" ] && [ "$DEVICE_ORIG_DENSITY" -gt 0 ]; then
        TARGET_DENSITY=$(( (DEVICE_ORIG_DENSITY * HOST_H) / orig_h ))
        [ "$TARGET_DENSITY" -lt 240 ] && TARGET_DENSITY=280
        [ "$TARGET_DENSITY" -gt 440 ] && TARGET_DENSITY=340
    else
        TARGET_DENSITY=280
    fi

    # Read and Backup Original Phone Refresh Rate Configuration
    DEVICE_ORIG_PEAK_REFRESH=$(adb -s "$DEVICE_SERIAL" shell settings get system peak_refresh_rate 2>/dev/null | tr -d '\r')
    DEVICE_ORIG_MIN_REFRESH=$(adb -s "$DEVICE_SERIAL" shell settings get system min_refresh_rate 2>/dev/null | tr -d '\r')
    DEVICE_ORIG_USER_REFRESH=$(adb -s "$DEVICE_SERIAL" shell settings get system user_refresh_rate 2>/dev/null | tr -d '\r')
    DEVICE_ORIG_MIUI_REFRESH=$(adb -s "$DEVICE_SERIAL" shell settings get system miui_refresh_rate 2>/dev/null | tr -d '\r')
    log_info "Device native refresh rate detected: ${DEVICE_ORIG_PEAK_REFRESH:-60} Hz"

    # Universal Hardware Encoder Selection
    VIDEO_CODEC="h265"
    if command -v scrcpy >/dev/null 2>&1; then
        local encoders_list
        encoders_list=$(SNAP_LAUNCHER_NOTICE_ENABLED="false" scrcpy -s "$DEVICE_SERIAL" --list-encoders 2>&1 || true)
        if echo "$encoders_list" | grep -qi 'c2.qti.hevc.encoder'; then
            CHOSEN_ENCODER="c2.qti.hevc.encoder"
            log_success "Hardware Encoder: Qualcomm Snapdragon Dedicated HEVC (c2.qti.hevc.encoder)"
        elif echo "$encoders_list" | grep -qi 'c2.mtk.hevc.encoder'; then
            CHOSEN_ENCODER="c2.mtk.hevc.encoder"
            log_success "Hardware Encoder: MediaTek Dedicated HEVC (c2.mtk.hevc.encoder)"
        elif echo "$encoders_list" | grep -qi 'c2.exynos.hevc.encoder'; then
            CHOSEN_ENCODER="c2.exynos.hevc.encoder"
            log_success "Hardware Encoder: Samsung Exynos Dedicated HEVC (c2.exynos.hevc.encoder)"
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
# Module 4.2: Phone Screen & Window Orientation Configuration
# ------------------------------------------------------------------------------
setup_device_orientation() {
    if [ -n "$FORCE_DEVICE_ROTATION" ]; then
        log_step "Locking Device Hardware Screen Orientation to ${FORCE_DEVICE_ROTATION}°"

        DEVICE_ORIG_ACCEL_ROTATION=$(adb -s "$DEVICE_SERIAL" shell settings get system accelerometer_rotation 2>/dev/null | tr -d '\r')
        DEVICE_ORIG_USER_ROTATION=$(adb -s "$DEVICE_SERIAL" shell settings get system user_rotation 2>/dev/null | tr -d '\r')

        case "$FORCE_DEVICE_ROTATION" in
            0)   ROTATION_NUM=0 ;;
            90)  ROTATION_NUM=1 ;;
            180) ROTATION_NUM=2 ;;
            270) ROTATION_NUM=3 ;;
            *)   ROTATION_NUM=3 ;;
        esac

        log_info "Applying hardware orientation lock (${FORCE_DEVICE_ROTATION}° / index ${ROTATION_NUM})..."
        adb -s "$DEVICE_SERIAL" shell wm set-ignore-orientation-request true 2>/dev/null || true
        adb -s "$DEVICE_SERIAL" shell wm user-rotation lock "$ROTATION_NUM" 2>/dev/null || true
        adb -s "$DEVICE_SERIAL" shell settings put system accelerometer_rotation 0 2>/dev/null || true
        adb -s "$DEVICE_SERIAL" shell settings put system user_rotation "$ROTATION_NUM" 2>/dev/null || true
        ROTATION_MODIFIED=1
        log_success "Device orientation locked to ${FORCE_DEVICE_ROTATION}° (ignores app rotation requests)."
    else
        # Ensure device accelerometer is active and unconstrained so Android and apps rotate naturally
        adb -s "$DEVICE_SERIAL" shell wm set-ignore-orientation-request reset 2>/dev/null || true
        adb -s "$DEVICE_SERIAL" shell wm user-rotation free 2>/dev/null || true
        adb -s "$DEVICE_SERIAL" shell settings put system accelerometer_rotation 1 2>/dev/null || true
    fi
}

restore_device_orientation() {
    if [ "$ROTATION_MODIFIED" -eq 1 ] || [ "$RUN_MODE" = "reset" ]; then
        log_info "Restoring device native orientation and accelerometer..."
        local state
        state=$(adb get-state 2>/dev/null || echo "disconnected")
        if [ "$state" = "device" ]; then
            adb -s "$DEVICE_SERIAL" shell wm set-ignore-orientation-request reset 2>/dev/null || true
            adb -s "$DEVICE_SERIAL" shell wm user-rotation free 2>/dev/null || true
            adb -s "$DEVICE_SERIAL" shell settings put system accelerometer_rotation "${DEVICE_ORIG_ACCEL_ROTATION:-1}" 2>/dev/null || true
            adb -s "$DEVICE_SERIAL" shell settings put system user_rotation "${DEVICE_ORIG_USER_ROTATION:-0}" 2>/dev/null || true
            ROTATION_MODIFIED=0
            log_success "Device accelerometer and orientation restored."
        fi
    fi
}

# ------------------------------------------------------------------------------
# Module 4.3: Android Desktop Mode (Freeform Multi-Window DeX Environment)
# ------------------------------------------------------------------------------
setup_dex_mode() {
    log_step "Configuring Android Desktop DeX Mode (Freeform Windows)"

    ORIG_FREEFORM=$(adb -s "$DEVICE_SERIAL" shell settings get global enable_freeform_support 2>/dev/null | tr -d '\r')
    ORIG_RESIZABLE=$(adb -s "$DEVICE_SERIAL" shell settings get global force_resizable_activities 2>/dev/null | tr -d '\r')

    log_info "Enabling Android Freeform windows and resizable activities..."
    adb -s "$DEVICE_SERIAL" shell settings put global enable_freeform_support 1 2>/dev/null || true
    adb -s "$DEVICE_SERIAL" shell settings put global force_resizable_activities 1 2>/dev/null || true
    adb -s "$DEVICE_SERIAL" shell settings put secure freeform_window_management 1 2>/dev/null || true
    adb -s "$DEVICE_SERIAL" shell settings put global force_desktop_mode_on_external_displays 0 2>/dev/null || true
    DEX_MODE_ACTIVE=1
    log_success "Android Freeform Desktop environment activated."

    # Detect or auto-install DroidUP Dex Launcher for full desktop UI (Taskbar, App drawer)
    local launcher_pkg="com.levelup.droiduplauncher"
    if ! adb -s "$DEVICE_SERIAL" shell pm path "$launcher_pkg" 2>/dev/null | grep -q "package:"; then
        local apk_path="${SCRIPT_DIR}/payload/DroidUP-Dex-Launcher.apk"
        if [ -f "$apk_path" ]; then
            log_info "Installing Desktop DeX Launcher (${launcher_pkg})..."
            adb -s "$DEVICE_SERIAL" install -r "$apk_path" 2>/dev/null || true
        fi
    fi

    if adb -s "$DEVICE_SERIAL" shell pm path "$launcher_pkg" 2>/dev/null | grep -q "package:"; then
        adb -s "$DEVICE_SERIAL" shell appops set "$launcher_pkg" SYSTEM_ALERT_WINDOW allow 2>/dev/null || true
        DEX_LAUNCHER_ACTIVE="$launcher_pkg"
        log_success "Desktop DeX Launcher ready: ${launcher_pkg}"
    else
        DEX_LAUNCHER_ACTIVE=""
        log_warn "DeX launcher app not found. Virtual display will run standard Android UI."
    fi
}

restore_dex_mode() {
    if [ "$DEX_MODE_ACTIVE" -eq 1 ] || [ "$RUN_MODE" = "reset" ]; then
        local state
        state=$(adb get-state 2>/dev/null || echo "disconnected")
        if [ "$state" = "device" ]; then
            log_info "Restoring Android window manager global settings..."
            if [ -n "$ORIG_FREEFORM" ] && [ "$ORIG_FREEFORM" != "null" ]; then
                adb -s "$DEVICE_SERIAL" shell settings put global enable_freeform_support "$ORIG_FREEFORM" 2>/dev/null || true
            else
                adb -s "$DEVICE_SERIAL" shell settings delete global enable_freeform_support 2>/dev/null || true
            fi

            if [ -n "$ORIG_RESIZABLE" ] && [ "$ORIG_RESIZABLE" != "null" ]; then
                adb -s "$DEVICE_SERIAL" shell settings put global force_resizable_activities "$ORIG_RESIZABLE" 2>/dev/null || true
            else
                adb -s "$DEVICE_SERIAL" shell settings delete global force_resizable_activities 2>/dev/null || true
            fi
            DEX_MODE_ACTIVE=0
            log_success "Desktop mode global settings restored."
        fi
    fi
}

sync_device_refresh_rate() {
    log_step "Synchronizing Refresh Rate to Host (${HOST_HZ} Hz)"
    log_info "Configuring Android system display pipeline to ${HOST_HZ} Hz..."

    adb -s "$DEVICE_SERIAL" shell settings put system peak_refresh_rate "${HOST_HZ}.0" 2>/dev/null || true
    adb -s "$DEVICE_SERIAL" shell settings put system min_refresh_rate "${HOST_HZ}.0" 2>/dev/null || true
    adb -s "$DEVICE_SERIAL" shell settings put system user_refresh_rate "$HOST_HZ" 2>/dev/null || true
    adb -s "$DEVICE_SERIAL" shell settings put system miui_refresh_rate "$HOST_HZ" 2>/dev/null || true
    REFRESH_MODIFIED=1
    log_success "System refresh rate locked to ${HOST_HZ} Hz (VSYNC aligned)."
}

restore_device_refresh_rate() {
    if [ "$REFRESH_MODIFIED" -eq 1 ] || [ "$RUN_MODE" = "reset" ]; then
        local state
        state=$(adb get-state 2>/dev/null || echo "disconnected")
        if [ "$state" = "device" ]; then
            log_info "Restoring native refresh rate..."
            if [ -n "$DEVICE_ORIG_PEAK_REFRESH" ] && [ "$DEVICE_ORIG_PEAK_REFRESH" != "null" ]; then
                adb -s "$DEVICE_SERIAL" shell settings put system peak_refresh_rate "$DEVICE_ORIG_PEAK_REFRESH" 2>/dev/null || true
            else
                adb -s "$DEVICE_SERIAL" shell settings put system peak_refresh_rate 120.0 2>/dev/null || true
            fi

            if [ -n "$DEVICE_ORIG_MIN_REFRESH" ] && [ "$DEVICE_ORIG_MIN_REFRESH" != "null" ]; then
                adb -s "$DEVICE_SERIAL" shell settings put system min_refresh_rate "$DEVICE_ORIG_MIN_REFRESH" 2>/dev/null || true
            else
                adb -s "$DEVICE_SERIAL" shell settings delete system min_refresh_rate 2>/dev/null || true
            fi

            if [ -n "$DEVICE_ORIG_USER_REFRESH" ] && [ "$DEVICE_ORIG_USER_REFRESH" != "null" ]; then
                adb -s "$DEVICE_SERIAL" shell settings put system user_refresh_rate "$DEVICE_ORIG_USER_REFRESH" 2>/dev/null || true
            else
                adb -s "$DEVICE_SERIAL" shell settings put system user_refresh_rate 120 2>/dev/null || true
            fi

            if [ -n "$DEVICE_ORIG_MIUI_REFRESH" ] && [ "$DEVICE_ORIG_MIUI_REFRESH" != "null" ]; then
                adb -s "$DEVICE_SERIAL" shell settings put system miui_refresh_rate "$DEVICE_ORIG_MIUI_REFRESH" 2>/dev/null || true
            else
                adb -s "$DEVICE_SERIAL" shell settings put system miui_refresh_rate 120 2>/dev/null || true
            fi

            REFRESH_MODIFIED=0
            log_success "Refresh rate restored to original state."
        fi
    fi
}

# ------------------------------------------------------------------------------
# Module 4.4: Resolution Scaling & Launcher Preservation
# ------------------------------------------------------------------------------
setup_screen_resolution() {
    # If window orientation is automatic or vertical, do NOT force landscape resolution on phone
    if [ "$WINDOW_ORIENTATION" != "horizontal" ]; then
        log_info "Window orientation is ${WINDOW_ORIENTATION}: preserving native phone resolution to allow seamless dynamic rotation."
        return 0
    fi

    log_step "Adapting Screen Resolution to Match Host (${HOST_W}x${HOST_H} ${HOST_RATIO})"

    if [ "$PERF_PROFILE" = "eco" ] || [ "$PERF_PROFILE" = "720p" ]; then
        HOST_W=1280
        HOST_H=854
        TARGET_DENSITY=280
        VIDEO_BITRATE="8M"
        MAX_SIZE=1280
        log_info "Profile [ESPORTS ECO]: 1280x854 (3:2) @ 8M Bitrate (Cooling & Battery Saver)"
    else
        MAX_SIZE=1920
        log_info "Profile [MAX QUALITY]: ${HOST_W}x${HOST_H} (3:2) @ ${VIDEO_BITRATE} Bitrate"
    fi

    log_info "Applying temporary gaming profile -> ${HOST_W}x${HOST_H} @ ${TARGET_DENSITY} DPI"
    adb -s "$DEVICE_SERIAL" shell wm size "${HOST_W}x${HOST_H}"
    adb -s "$DEVICE_SERIAL" shell wm density "${TARGET_DENSITY}"
    DISPLAY_MODIFIED=1
    log_success "Phone resolution aligned to 100% fullscreen host display."
}

restore_launcher_layout() {
    log_info "Reloading home screen launcher layout to preserve clean icon arrangement..."
    local launchers=(
        "com.miui.home"
        "com.mi.android.globallauncher"
        "com.google.android.apps.nexuslauncher"
        "com.sec.android.app.launcher"
        "com.motorola.launcher3"
        "com.oppo.launcher"
        "com.huawei.android.launcher"
    )
    for pkg in "${launchers[@]}"; do
        adb -s "$DEVICE_SERIAL" shell am force-stop "$pkg" 2>/dev/null || true
    done
    log_success "Home screen launcher reloaded."
}

restore_screen_resolution() {
    if [ "$DISPLAY_MODIFIED" -eq 1 ] || [ "$RUN_MODE" = "reset" ]; then
        local state
        state=$(adb get-state 2>/dev/null || echo "disconnected")
        if [ "$state" != "device" ]; then
            log_warn "Device disconnected. Waiting up to 10s for reconnect to restore display settings..."
            for _ in {1..10}; do
                sleep 1
                state=$(adb get-state 2>/dev/null || echo "disconnected")
                if [ "$state" = "device" ]; then break; fi
            done
        fi

        if [ "$state" = "device" ]; then
            log_info "Resetting device display size and density to factory defaults..."
            adb -s "$DEVICE_SERIAL" shell wm size reset 2>/dev/null || true
            adb -s "$DEVICE_SERIAL" shell wm density reset 2>/dev/null || true
            restore_launcher_layout
            DISPLAY_MODIFIED=0
            log_success "Native display settings restored."
        else
            log_warn "Device unreachable. Native resolution will restore automatically on next USB connect."
        fi
    fi
}

# ------------------------------------------------------------------------------
# Module 5: Ultra-Low Latency scrcpy Runner
# ------------------------------------------------------------------------------
launch_scrcpy() {
    log_step "Launching Low-Latency Game Session"

    local scrcpy_cmd=("scrcpy")

    # In OTG mode, scrcpy uses raw USB; bind strictly to device serial to prevent webcam conflicts
    if [ "$RUN_MODE" = "otg" ]; then
        scrcpy_cmd+=("-s" "${DEVICE_SERIAL}")
        scrcpy_cmd+=("--otg")
        log_info "Running in Pure Hardware KVM Docking Mode (--otg -s ${DEVICE_SERIAL})"
        log_info "Executing: ${scrcpy_cmd[*]}"
        echo -e "${C_GREEN}${C_BOLD}>>> KVM MODE ACTIVE! <<<${C_RESET}"
        echo -e "  Your PC keyboard and mouse are now directly connected to your phone via USB HID."
        echo -e "  To exit cleanly: Press ${C_BOLD}Ctrl+C${C_RESET}\n"

        "${scrcpy_cmd[@]}" &
        SCRCPY_PID=$!
        wait "$SCRCPY_PID" 2>/dev/null || true
        SCRCPY_PID=""
        return 0
    fi

    # Standard video streaming modes
    scrcpy_cmd+=("-s" "${DEVICE_SERIAL}")

    if [ "${FORCE_ADB_FORWARD:-1}" -eq 1 ]; then
        scrcpy_cmd+=("--force-adb-forward")
    fi

    # Apply PC Window Orientation (Horizontal, Vertical, or Automatic)
    case "$WINDOW_ORIENTATION" in
        horizontal)
            log_info "Locking PC window orientation to Horizontal / Landscape (@270)"
            scrcpy_cmd+=("--capture-orientation=@270")
            ;;
        vertical)
            log_info "Locking PC window orientation to Vertical / Portrait (@0)"
            scrcpy_cmd+=("--capture-orientation=@0")
            ;;
        auto|*)
            log_info "Window orientation set to Automatic (follows device rotation dynamically)"
            # Dynamic orientation: no @ lock, allowing window to follow phone orientation in real-time
            ;;
    esac

    case "$RUN_MODE" in
        dex)
            log_info "Running in Android Desktop DeX Mode (Freeform Windows + Virtual Display)"
            scrcpy_cmd+=("--new-display=${HOST_W}x${HOST_H}/${TARGET_DENSITY}")
            scrcpy_cmd+=("-f")
            scrcpy_cmd+=("--video-codec=${VIDEO_CODEC:-h265}")
            scrcpy_cmd+=("--video-buffer=${VIDEO_BUFFER:-0}")
            scrcpy_cmd+=("--video-codec-options=latency:int=0,priority:int=0")
            scrcpy_cmd+=("--video-bit-rate=${VIDEO_BITRATE:-16M}")
            scrcpy_cmd+=("--max-fps=${TARGET_FPS}")

            if [ -n "${DEX_LAUNCHER_ACTIVE:-}" ]; then
                scrcpy_cmd+=("--start-app=${DEX_LAUNCHER_ACTIVE}")
            fi

            [ "${TURN_SCREEN_OFF:-1}" -eq 1 ] && scrcpy_cmd+=("--turn-screen-off")
            [ "${STAY_AWAKE:-1}" -eq 1 ] && scrcpy_cmd+=("--stay-awake")
            [ "${ENABLE_UHID_KEYBOARD:-1}" -eq 1 ] && scrcpy_cmd+=("--keyboard=uhid")
            [ "${ENABLE_UHID_MOUSE:-1}" -eq 1 ] && scrcpy_cmd+=("--mouse=uhid")
            [ "${ENABLE_UHID_GAMEPAD:-1}" -eq 1 ] && scrcpy_cmd+=("--gamepad=uhid")

            if [ -n "$CHOSEN_ENCODER" ]; then
                scrcpy_cmd+=("--video-encoder=${CHOSEN_ENCODER}")
            fi
            ;;
        mirror)
            log_info "Running in Pure Native 1:1 Mirroring Mode (No display resizing)"
            scrcpy_cmd+=("--video-codec=${VIDEO_CODEC:-h265}")
            scrcpy_cmd+=("--video-buffer=${VIDEO_BUFFER:-0}")
            scrcpy_cmd+=("--video-codec-options=latency:int=0,priority:int=0")
            scrcpy_cmd+=("--video-bit-rate=${VIDEO_BITRATE:-16M}")
            scrcpy_cmd+=("--max-fps=${TARGET_FPS}")

            [ "${TURN_SCREEN_OFF:-1}" -eq 1 ] && scrcpy_cmd+=("--turn-screen-off")
            [ "${STAY_AWAKE:-1}" -eq 1 ] && scrcpy_cmd+=("--stay-awake")
            [ "${ENABLE_UHID_KEYBOARD:-1}" -eq 1 ] && scrcpy_cmd+=("--keyboard=uhid")
            [ "${ENABLE_UHID_MOUSE:-1}" -eq 1 ] && scrcpy_cmd+=("--mouse=uhid")
            [ "${ENABLE_UHID_GAMEPAD:-1}" -eq 1 ] && scrcpy_cmd+=("--gamepad=uhid")

            if [ -n "$CHOSEN_ENCODER" ]; then
                scrcpy_cmd+=("--video-encoder=${CHOSEN_ENCODER}")
            fi
            ;;
        virtual)
            log_info "Running in Secondary Virtual Display Mode (--new-display)"
            scrcpy_cmd+=("--new-display=${HOST_W}x${HOST_H}/${TARGET_DENSITY}")
            scrcpy_cmd+=("-f")
            scrcpy_cmd+=("--video-codec=${VIDEO_CODEC:-h265}")
            scrcpy_cmd+=("--video-buffer=${VIDEO_BUFFER:-0}")
            scrcpy_cmd+=("--video-codec-options=latency:int=0,priority:int=0")
            scrcpy_cmd+=("--video-bit-rate=${VIDEO_BITRATE:-16M}")
            scrcpy_cmd+=("--max-fps=${TARGET_FPS}")

            [ "${TURN_SCREEN_OFF:-1}" -eq 1 ] && scrcpy_cmd+=("--turn-screen-off")
            [ "${STAY_AWAKE:-1}" -eq 1 ] && scrcpy_cmd+=("--stay-awake")
            [ "${ENABLE_UHID_KEYBOARD:-1}" -eq 1 ] && scrcpy_cmd+=("--keyboard=uhid")
            [ "${ENABLE_UHID_MOUSE:-1}" -eq 1 ] && scrcpy_cmd+=("--mouse=uhid")
            [ "${ENABLE_UHID_GAMEPAD:-1}" -eq 1 ] && scrcpy_cmd+=("--gamepad=uhid")

            if [ -n "$CHOSEN_ENCODER" ]; then
                scrcpy_cmd+=("--video-encoder=${CHOSEN_ENCODER}")
            fi
            ;;
        normal|daemon)
            log_info "Applying Fullscreen Low-Latency Pipeline (${PERF_PROFILE:-max} profile)"
            scrcpy_cmd+=("-f")
            scrcpy_cmd+=("--video-buffer=${VIDEO_BUFFER:-0}")
            scrcpy_cmd+=("--video-codec-options=latency:int=0,priority:int=0")
            scrcpy_cmd+=("--video-codec=${VIDEO_CODEC:-h265}")
            scrcpy_cmd+=("--video-bit-rate=${VIDEO_BITRATE:-16M}")
            scrcpy_cmd+=("--max-size=${MAX_SIZE:-1920}")
            scrcpy_cmd+=("--max-fps=${TARGET_FPS}")

            [ "${TURN_SCREEN_OFF:-1}" -eq 1 ] && scrcpy_cmd+=("--turn-screen-off")
            [ "${STAY_AWAKE:-1}" -eq 1 ] && scrcpy_cmd+=("--stay-awake")
            [ "${ENABLE_UHID_KEYBOARD:-1}" -eq 1 ] && scrcpy_cmd+=("--keyboard=uhid")
            [ "${ENABLE_UHID_MOUSE:-1}" -eq 1 ] && scrcpy_cmd+=("--mouse=uhid")
            [ "${ENABLE_UHID_GAMEPAD:-1}" -eq 1 ] && scrcpy_cmd+=("--gamepad=uhid")

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
        [ "${AUDIO_DUP:-1}" -eq 1 ] && scrcpy_cmd+=("--audio-dup")
        [ -n "${AUDIO_CODEC:-}" ] && scrcpy_cmd+=("--audio-codec=${AUDIO_CODEC}")
    fi

    log_info "Executing: ${scrcpy_cmd[*]}"
    echo -e "${C_GREEN}${C_BOLD}>>> SESSION READY! <<<${C_RESET}"
    echo -e "  To exit cleanly: Press ${C_BOLD}Alt+F4${C_RESET} or ${C_BOLD}Super+Q${C_RESET} (or Ctrl+C in terminal)"
    echo -e "  Toggle Phone Screen on/off anytime: Press ${C_BOLD}Alt+O${C_RESET}\n"

    # Run scrcpy in background and track PID to guarantee clean SIGINT termination
    "${scrcpy_cmd[@]}" &
    SCRCPY_PID=$!
    wait "$SCRCPY_PID" 2>/dev/null || true
    SCRCPY_PID=""
}

# ------------------------------------------------------------------------------
# Module 6: Background Daemon Mode
# ------------------------------------------------------------------------------
run_daemon_mode() {
    log_step "Starting Background Daemon Mode"
    log_info "Monitoring for connected devices... (Press Ctrl+C to stop)"

    while true; do
        local state
        state=$(adb get-state 2>/dev/null || echo "disconnected")
        if [ "$state" = "device" ]; then
            log_success "Device connection detected! Launching session..."
            detect_host_display
            profile_device
            setup_screen_resolution
            sync_device_refresh_rate
            launch_scrcpy
            log_info "Session finished. Resuming background monitor..."
        fi
        sleep 2
    done
}

# ------------------------------------------------------------------------------
# Help Dialog
# ------------------------------------------------------------------------------
show_help() {
    echo -e "${C_BOLD}${APP_NAME} v${VERSION}${C_RESET}

Usage: $(basename "$0") [OPTIONS]

Operational Modes:
  (no args)               Standard Fullscreen Zero-Latency Game Mode (Auto Host Aspect Adaptation)
  --eco, --720p           Esports Eco Mode (1280x854 @ 8M - Low Heat & Battery Saver)
  --max, --1080p          Maximum Quality Mode (1920x1280 @ 16M Bitrate)
  --mirror                Pure Native 1:1 Mirroring Mode (No display resizing, zero layout scramble)
  --dex, --desktop        Android Desktop DeX Mode (Freeform Multi-Window Desktop on Virtual Display)
  --virtual               Secondary Virtual Display Mode (Keeps phone screen free & untouched)
  --otg, --dock           Hardware KVM Dock Mode (PC keyboard & mouse directly via USB HID)
  --daemon                Background daemon mode: Auto-launches session whenever phone is connected

Screen & Controls:
  --window-auto, --auto   Automatic window orientation: Dynamically rotates PC window as phone rotates (default)
  --window-horizontal, --horizontal, -l Force PC window to Horizontal / Landscape orientation (@270)
  --window-vertical, --vertical, -p   Force PC window to Vertical / Portrait orientation (@0)
  --landscape             Alias for --window-horizontal
  --portrait              Alias for --window-vertical
  --force-device-rotate <0|90|180|270> Force arbitrary hardware screen rotation on Android device
  --lock-laptop           Lock laptop screen rotation in Zorin OS (prevents 2-in-1 auto-rotation)
  --turn-screen-off, -S   Turn phone screen off during session (saves battery and heat)
  --keep-screen-on        Keep phone screen on during session

Audio Controls:
  --no-audio, --audio-off Disable audio streaming (lowest processing latency, audio on phone)
  --audio-dual, --audio-dup Stream audio to PC and keep playing on phone speakers (default)
  --audio-pc              Stream audio to PC only (mute phone)

System & Recovery:
  -y, --yes               Auto-install missing dependencies non-interactively
  --install               Force run dependency and udev installer
  --check                 Verify dependencies and environment only (no launch)
  --reset                 Emergency reset: Restores resolution, density, Hz, rotation, and laptop lock
  --reset-launcher        Force reload home screen launcher layout to fix icon arrangement
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
            --reset-launcher)
                profile_device
                restore_launcher_layout
                exit 0
                ;;
            --window-auto|--auto)
                WINDOW_ORIENTATION="auto"
                ;;
            --window-horizontal|--horizontal|--landscape|-l)
                WINDOW_ORIENTATION="horizontal"
                ;;
            --window-vertical|--vertical|--portrait|-p)
                WINDOW_ORIENTATION="vertical"
                ;;
            --rotate|--force-device-rotate)
                shift
                FORCE_DEVICE_ROTATION="${1:-270}"
                ;;
            --lock-laptop)
                LOCK_LAPTOP_ROTATION=1
                ;;
            --turn-screen-off|-S)
                TURN_SCREEN_OFF=1
                ;;
            --keep-screen-on|--no-turn-screen-off)
                TURN_SCREEN_OFF=0
                ;;
            --no-audio|--audio-off)
                DISABLE_AUDIO=1
                ;;
            --audio-dup|--audio-dual)
                DISABLE_AUDIO=0
                AUDIO_DUP=1
                ;;
            --audio-pc)
                DISABLE_AUDIO=0
                AUDIO_DUP=0
                ;;
            --eco|--720p)
                PERF_PROFILE="eco"
                ;;
            --max|--1080p)
                PERF_PROFILE="max"
                ;;
            --mirror)
                RUN_MODE="mirror"
                ;;
            --dex|--desktop)
                RUN_MODE="dex"
                ;;
            --virtual)
                RUN_MODE="virtual"
                ;;
            --otg|--dock)
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
            mirror)
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
