#!/bin/bash

export SHELL=$(command -v bash)

# ==============================================================================
# Shorin Arch Setup - Main Installer (Automated Version)
# ==============================================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
STATE_FILE="$BASE_DIR/.install_progress"

# --- Source Utility Functions ---
if [ -f "$SCRIPTS_DIR/00-utils.sh" ]; then
    source "$SCRIPTS_DIR/00-utils.sh"
else
    echo "[$(date '+%H:%M:%S')] ERROR: 00-utils.sh not found."
    exit 1
fi

# --- Global Cleanup on Exit ---
cleanup() {
    rm -f "/tmp/shorin_install_user"
}
trap cleanup EXIT

# --- Environment ---
export DEBUG=${DEBUG:-0}
export CN_MIRROR=${CN_MIRROR:-0}

check_root
chmod +x "$SCRIPTS_DIR"/*.sh

# ==============================================================================
# chroot检测
# ==============================================================================
detect_chroot() {
    if grep -q "chroot" /proc/1/cgroup 2>/dev/null || [ -f "/.chroot" ]; then
        export IN_CHROOT=true
        echo "[$(date '+%H:%M:%S')] INFO: Detected chroot environment"
    else
        export IN_CHROOT=false
    fi
}
detect_chroot

# ==============================================================================
# 读取配置文件
# ==============================================================================
echo "[$(date '+%H:%M:%S')] INFO: Reading configuration from /root/setup-config.json"
read_config "/root/setup-config.json"

# ==============================================================================
# 自动检测用户
# ==============================================================================
detect_target_user

# ==============================================================================
# 系统信息输出
# ==============================================================================
sys_dashboard() {
    echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
    echo "[$(date '+%H:%M:%S')] INFO: SYSTEM DIAGNOSTICS"
    echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
    echo "[$(date '+%H:%M:%S')] INFO: Kernel   : $(uname -r)"
    echo "[$(date '+%H:%M:%S')] INFO: User     : $(whoami)"
    echo "[$(date '+%H:%M:%S')] INFO: Target   : $TARGET_USER"
    echo "[$(date '+%H:%M:%S')] INFO: Desktop  : $DESKTOP_ENV"
    echo "[$(date '+%H:%M:%S')] INFO: Mirror   : $MIRROR_MODE"
    echo "[$(date '+%H:%M:%S')] INFO: Modules  : ${#OPTIONAL_MODULES[@]} optional module(s)"
    echo "[$(date '+%H:%M:%S')] INFO: Chroot   : $IN_CHROOT"
    
    if [ "$CN_MIRROR" == "1" ]; then
        echo "[$(date '+%H:%M:%S')] INFO: Network  : CN Optimized (Manual)"
    elif [ "$DEBUG" == "1" ]; then
        echo "[$(date '+%H:%M:%S')] INFO: Network  : DEBUG FORCE (CN Mode)"
    else
        echo "[$(date '+%H:%M:%S')] INFO: Network  : Global Default"
    fi
    
    if [ -f "$STATE_FILE" ]; then
        done_count=$(wc -l < "$STATE_FILE")
        echo "[$(date '+%H:%M:%S')] INFO: Progress : Resuming ($done_count steps recorded)"
    fi
    echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
}

# ==============================================================================
# 模块映射
# ==============================================================================
map_module() {
    local module_name="$1"
    
    case "$module_name" in
        iwd)          echo "01b-nm-backend.sh" ;;
        dualboot)     echo "02a-dualboot-fix.sh" ;;
        gpu)          echo "03b-gpu-driver.sh" ;;
        grub)         echo "07-grub-theme.sh" ;;
        apps)         echo "99-apps.sh" ;;
        *)            echo "" ;;
    esac
}

# ==============================================================================
# Main Execution
# ==============================================================================

sys_dashboard

MANDATORY_MODULES=(
    "00-btrfs-init.sh"
    "01a-base.sh"
    "02-musthave.sh"
    "03a-user.sh"
    "03c-snapshot-before-desktop.sh"
    "05-verify-desktop.sh"
)

ALL_MODULES=("${MANDATORY_MODULES[@]}")

# 添加可选模块
for module_name in "${OPTIONAL_MODULES[@]}"; do
    script_name=$(map_module "$module_name")
    if [ -n "$script_name" ]; then
        ALL_MODULES+=("$script_name")
        echo "[$(date '+%H:%M:%S')] INFO: Adding optional module: $module_name -> $script_name"
    fi
done

# 添加桌面环境模块
case "$DESKTOP_ENV" in
    shorinniri)    ALL_MODULES+=("04-niri-setup.sh") ;;
    minimalniri)   ALL_MODULES+=("04j-minimal-niri.sh") ;;
    kde)           ALL_MODULES+=("04b-kdeplasma-setup.sh") ;;
    end4)          ALL_MODULES+=("04e-illogical-impulse-end4-quickshell.sh") ;;
    dms)           ALL_MODULES+=("04c-dms-quickshell.sh") ;;
    inir)          ALL_MODULES+=("04m-inir-quickshell.sh") ;;
    shorindms)     ALL_MODULES+=("04h-shorindms-quickshell.sh"); export SHORIN_DMS_GIT=1 ;;
    hyprniri)      ALL_MODULES+=("04i-shorin-hyprniri-quickshell.sh") ;;
    shorinnocniri) ALL_MODULES+=("04k-shorin-noctalia-quickshell.sh") ;;
    caelestia)     ALL_MODULES+=("04g-caelestia-quickshell.sh") ;;
    gnome)         ALL_MODULES+=("04d-gnome.sh") ;;
    minimallabwc)  ALL_MODULES+=("04l-minimal-labwc.sh") ;;
    none)          echo "[$(date '+%H:%M:%S')] INFO: Skipping Desktop Environment installation." ;;
    *)             echo "[$(date '+%H:%M:%S')] WARN: Unknown desktop selection: $DESKTOP_ENV, skipping desktop setup." ;;
esac

mapfile -t MODULES < <(printf "%s\n" "${ALL_MODULES[@]}" | sort -u)

if [ ! -f "$STATE_FILE" ]; then touch "$STATE_FILE"; fi

TOTAL_STEPS=${#MODULES[@]}
CURRENT_STEP=0

echo "[$(date '+%H:%M:%S')] INFO: Initializing installer sequence..."

# ==============================================================================
# Reflector Mirror Update (State Aware)
# ==============================================================================
echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
echo "[$(date '+%H:%M:%S')] INFO: Pre-Flight - Mirrorlist Optimization"
echo "[$(date '+%H:%M:%S')] INFO: ==============================================="

if grep -q "^REFLECTOR_DONE$" "$STATE_FILE"; then
    echo "[$(date '+%H:%M:%S')] INFO: Mirrorlist previously optimized. Skipping."
else
    echo "[$(date '+%H:%M:%S')] INFO: Checking Reflector..."
    exe pacman -S --noconfirm --needed reflector
    
    CURRENT_TZ=$(readlink -f /etc/localtime)
    REFLECTOR_ARGS="--protocol https -a 12 -f 10 --sort rate --save /etc/pacman.d/mirrorlist --verbose"
    
    if [ "$MIRROR_MODE" == "cn" ] || [[ "$CURRENT_TZ" == *"Shanghai"* ]]; then
        echo "[$(date '+%H:%M:%S')] INFO: China environment detected. Running Reflector for China..."
        if exe reflector $REFLECTOR_ARGS -c China; then
            echo "[$(date '+%H:%M:%S')] OK: Mirrors updated."
        else
            echo "[$(date '+%H:%M:%S')] WARN: Reflector failed. Continuing with existing mirrors."
        fi
    else
        echo "[$(date '+%H:%M:%S')] INFO: Running global Reflector..."
        COUNTRY_CODE=$(curl -s --max-time 2 https://ipinfo.io/country)
        
        if [ -n "$COUNTRY_CODE" ]; then
            echo "[$(date '+%H:%M:%S')] INFO: Detected country: $COUNTRY_CODE"
            if ! exe reflector $REFLECTOR_ARGS -c "$COUNTRY_CODE"; then
                echo "[$(date '+%H:%M:%S')] WARN: Country specific refresh failed. Trying global..."
                exe reflector $REFLECTOR_ARGS
            fi
        else
            echo "[$(date '+%H:%M:%S')] WARN: Could not detect country. Running global speed test..."
            exe reflector $REFLECTOR_ARGS --latest 25
        fi
        echo "[$(date '+%H:%M:%S')] OK: Mirrorlist optimized."
    fi
    
    echo "REFLECTOR_DONE" >> "$STATE_FILE"
fi

# ---- update keyring ----
echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
echo "[$(date '+%H:%M:%S')] INFO: Pre-Flight - Update Keyring"
echo "[$(date '+%H:%M:%S')] INFO: ==============================================="

exe pacman -Sy
exe pacman -S --noconfirm archlinux-keyring

# --- Global Update ---
echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
echo "[$(date '+%H:%M:%S')] INFO: Pre-Flight - System update"
echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
echo "[$(date '+%H:%M:%S')] INFO: Ensuring system is up-to-date..."

if exe pacman -Syu --noconfirm; then
    echo "[$(date '+%H:%M:%S')] OK: System Updated."
else
    echo "[$(date '+%H:%M:%S')] ERROR: System update failed. Check your network."
    exit 1
fi

# --- Module Loop ---
echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
echo "[$(date '+%H:%M:%S')] INFO: Starting module execution ($TOTAL_STEPS steps)"
echo "[$(date '+%H:%M:%S')] INFO: ==============================================="

for module in "${MODULES[@]}"; do
    [[ -z "$module" ]] && continue
    
    CURRENT_STEP=$((CURRENT_STEP + 1))
    script_path="$SCRIPTS_DIR/$module"
    
    if [ ! -f "$script_path" ]; then
        echo "[$(date '+%H:%M:%S')] ERROR: Module not found: $module"
        continue
    fi
    
    if grep -q "^${module}$" "$STATE_FILE"; then
        echo "[$(date '+%H:%M:%S')] INFO: Module $module already completed. Skipping."
        continue
    fi
    
    echo "[$(date '+%H:%M:%S')] INFO: Step $CURRENT_STEP/$TOTAL_STEPS - Executing $module"
    
    bash "$script_path"
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo "$module" >> "$STATE_FILE"
        echo "[$(date '+%H:%M:%S')] OK: Module $module completed."
    elif [ $exit_code -eq 130 ]; then
        echo "[$(date '+%H:%M:%S')] WARN: Script interrupted by user (Ctrl+C)."
        echo "[$(date '+%H:%M:%S')] INFO: Exiting without rollback. You can resume later."
        exit 130
    else
        echo "[$(date '+%H:%M:%S')] ERROR: Module $module failed with exit code $exit_code"
        exit 1
    fi
done

# ==============================================================================
# Final Cleanup
# ==============================================================================
echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
echo "[$(date '+%H:%M:%S')] INFO: Completion - System Cleanup"
echo "[$(date '+%H:%M:%S')] INFO: ==============================================="

clean_intermediate_snapshots() {
    local config_name="$1"
    local start_marker="Before Shorin Setup"
    
    local KEEP_MARKERS=(
        "Before Desktop Environments"
        "Before Niri Setup"
    )
    
    if ! snapper -c "$config_name" list &>/dev/null; then
        return
    fi
    
    echo "[$(date '+%H:%M:%S')] INFO: Scanning junk snapshots in: $config_name..."
    
    local start_id
    start_id=$(snapper -c "$config_name" list --columns number,description | grep -F "$start_marker" | awk '{print $1}' | tail -n 1)
    
    if [ -z "$start_id" ]; then
        echo "[$(date '+%H:%M:%S')] WARN: Marker '$start_marker' not found in '$config_name'. Skipping cleanup."
        return
    fi
    
    local IDS_TO_KEEP=()
    for marker in "${KEEP_MARKERS[@]}"; do
        local found_id
        found_id=$(snapper -c "$config_name" list --columns number,description | grep -F "$marker" | awk '{print $1}' | tail -n 1)
        
        if [ -n "$found_id" ]; then
            IDS_TO_KEEP+=("$found_id")
        fi
    done
    
    local snapshots_to_delete=()
    
    while IFS= read -r line; do
        local id
        local type
        
        id=$(echo "$line" | awk '{print $1}')
        type=$(echo "$line" | awk '{print $3}')
        
        if [[ "$id" =~ ^[0-9]+$ ]]; then
            if [ "$id" -gt "$start_id" ]; then
                
                local skip=false
                for keep in "${IDS_TO_KEEP[@]}"; do
                    if [[ "$id" == "$keep" ]]; then
                        skip=true
                        break
                    fi
                done
                
                if [ "$skip" = true ]; then
                    continue
                fi
                
                if [[ "$type" == "pre" || "$type" == "post" ]]; then
                    snapshots_to_delete+=("$id")
                fi
            fi
        fi
    done < <(snapper -c "$config_name" list --columns number,type)
    
    if [ ${#snapshots_to_delete[@]} -gt 0 ]; then
        echo "[$(date '+%H:%M:%S')] INFO: Deleting ${#snapshots_to_delete[@]} junk snapshots..."
        exe snapper -c "$config_name" delete "${snapshots_to_delete[@]}"
    fi
}

echo "[$(date '+%H:%M:%S')] INFO: Cleaning Pacman cache..."
exe pacman -Sc --noconfirm

clean_intermediate_snapshots "root"
clean_intermediate_snapshots "home"

DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$TARGET_USER}"
HOME_DIR="/home/$TARGET_USER"

for dir in /var/cache/pacman/pkg/download-*/; do
    if [ -d "$dir" ]; then
        rm -rf "$dir"
    fi
done

VERIFY_LIST="/tmp/shorin_install_verify.list"
rm -f "$VERIFY_LIST"

echo "[$(date '+%H:%M:%S')] INFO: Regenerating final GRUB configuration..."
exe env LANG=en_US.UTF-8 grub-mkconfig -o /boot/grub/grub.cfg

# --- Completion ---
echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
echo "[$(date '+%H:%M:%S')] OK: INSTALLATION COMPLETE"
echo "[$(date '+%H:%M:%S')] INFO: ==============================================="

if [ -f "$STATE_FILE" ]; then rm "$STATE_FILE"; fi

echo "[$(date '+%H:%M:%S')] INFO: Archiving log..."
if [ -f "/tmp/shorin_install_user" ]; then
    FINAL_USER=$(cat /tmp/shorin_install_user)
else
    FINAL_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
fi

if [ -n "$FINAL_USER" ]; then
    FINAL_DOCS="/home/$FINAL_USER/Documents"
    mkdir -p "$FINAL_DOCS"
    if [ -f "${TEMP_LOG_FILE:-/tmp/shorin.log}" ]; then
        cp "${TEMP_LOG_FILE:-/tmp/shorin.log}" "$FINAL_DOCS/log-shorin-arch-setup.txt"
        chown -R "$FINAL_USER:$FINAL_USER" "$FINAL_DOCS"
        echo "[$(date '+%H:%M:%S')] INFO: Log saved to: $FINAL_DOCS/log-shorin-arch-setup.txt"
    fi
fi

echo "[$(date '+%H:%M:%S')] INFO: System requires a REBOOT."
echo "[$(date '+%H:%M:%S')] INFO: Rebooting in 5 seconds..."
sleep 5
systemctl reboot
