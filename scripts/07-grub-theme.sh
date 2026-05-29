#!/bin/bash

# ==============================================================================
# 07-grub-theme.sh - GRUB Theming (Automated Version)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

echo "[$(date '+%H:%M:%S')] INFO: ==============================================="
echo "[$(date '+%H:%M:%S')] INFO: Phase 7 - GRUB Customization & Theming"
echo "[$(date '+%H:%M:%S')] INFO: ==============================================="

# --- 检查GRUB是否安装 ---
if ! command -v grub-mkconfig >/dev/null 2>&1; then
    echo "[$(date '+%H:%M:%S')] WARN: GRUB not found. Skipping GRUB theme installation."
    exit 0
fi

# --- 辅助函数 ---
set_grub_value() {
    local key="$1"
    local value="$2"
    local conf_file="/etc/default/grub"
    local escaped_value
    escaped_value=$(printf '%s\n' "$value" | sed 's,[\/&],\\&,g')
    
    if grep -q -E "^#\s*$key=" "$conf_file"; then
        sed -i -E "s,^#\s*$key=.*,$key=\"$escaped_value\"," "$conf_file"
    elif grep -q -E "^$key=" "$conf_file"; then
        sed -i -E "s,^$key=.*,$key=\"$escaped_value\"," "$conf_file"
    else
        echo "$key=\"$escaped_value\"" >> "$conf_file"
    fi
}

manage_kernel_param() {
    local action="$1"
    local param="$2"
    local conf_file="/etc/default/grub"
    
    local line=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$conf_file" || true)
    local params=$(echo "$line" | sed -e 's/GRUB_CMDLINE_LINUX_DEFAULT=//' -e 's/"//g')
    local param_key
    if [[ "$param" == *"="* ]]; then param_key="${param%%=*}"; else param_key="$param"; fi
    params=$(echo "$params" | sed -E "s/\b${param_key}(=[^ ]*)?\b//g")
    
    if [ "$action" == "add" ]; then params="$params $param"; fi
    
    params=$(echo "$params" | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    sed -i "s,^GRUB_CMDLINE_LINUX_DEFAULT=.*,GRUB_CMDLINE_LINUX_DEFAULT=\"$params\"," "$conf_file"
}

cleanup_minegrub() {
    local minegrub_found=false
    
    if [ -f "/etc/grub.d/05_twomenus" ] || [ -f "/boot/grub/mainmenu.cfg" ]; then
        minegrub_found=true
        echo "[$(date '+%H:%M:%S')] INFO: Cleaning Minegrub artifacts..."
        [ -f "/etc/grub.d/05_twomenus" ] && rm -f /etc/grub.d/05_twomenus
        [ -f "/boot/grub/mainmenu.cfg" ] && rm -f /boot/grub/mainmenu.cfg
    fi
    
    if command -v grub-editenv >/dev/null 2>&1; then
        if grub-editenv - list 2>/dev/null | grep -q "^config_file="; then
            minegrub_found=true
            echo "[$(date '+%H:%M:%S')] INFO: Unsetting Minegrub GRUB environment variable..."
            grub-editenv - unset config_file
        fi
    fi
    
    if [ "$minegrub_found" == "true" ]; then
        echo "[$(date '+%H:%M:%S')] OK: Minegrub configuration removed"
    fi
}

# --- Step 1: 通用GRUB配置 ---
echo "[$(date '+%H:%M:%S')] INFO: Step 1/4 - General GRUB Settings"

if [ -L "/boot/grub" ]; then
    LINK_TARGET=$(readlink -f "/boot/grub" || true)
    
    if [[ "$LINK_TARGET" == "/efi/grub" ]] || [[ "$LINK_TARGET" == "/boot/efi/grub" ]]; then
        echo "[$(date '+%H:%M:%S')] INFO: Enabling GRUB savedefault..."
        set_grub_value "GRUB_DEFAULT" "saved"
        set_grub_value "GRUB_SAVEDEFAULT" "true"
    fi
fi

echo "[$(date '+%H:%M:%S')] INFO: Configuring kernel boot parameters..."
manage_kernel_param "remove" "quiet"
manage_kernel_param "remove" "splash"
manage_kernel_param "add" "loglevel=5"
manage_kernel_param "add" "nowatchdog"

CPU_VENDOR=$(LC_ALL=C lscpu 2>/dev/null | awk '/Vendor ID:/ {print $3}' || true)
if [ "${CPU_VENDOR:-}" == "GenuineIntel" ]; then
    echo "[$(date '+%H:%M:%S')] INFO: Intel CPU detected. Disabling iTCO_wdt watchdog."
    manage_kernel_param "add" "modprobe.blacklist=iTCO_wdt"
elif [ "${CPU_VENDOR:-}" == "AuthenticAMD" ]; then
    echo "[$(date '+%H:%M:%S')] INFO: AMD CPU detected. Disabling sp5100_tco watchdog."
    manage_kernel_param "add" "modprobe.blacklist=sp5100_tco"
fi

echo "[$(date '+%H:%M:%S')] OK: Kernel parameters updated"

# --- Step 2: 同步主题到系统目录 ---
echo "[$(date '+%H:%M:%S')] INFO: Step 2/4 - Sync Themes to System Directory"

SOURCE_BASE="$PARENT_DIR/grub-themes"
DEST_DIR="/usr/share/grub/themes"

if [ ! -d "$DEST_DIR" ]; then
    mkdir -p "$DEST_DIR"
fi

if [ -d "$SOURCE_BASE" ]; then
    echo "[$(date '+%H:%M:%S')] INFO: Syncing repository themes to $DEST_DIR..."
    for dir in "$SOURCE_BASE"/*; do
        if [ -d "$dir" ] && [ -f "$dir/theme.txt" ]; then
            THEME_BASENAME=$(basename "$dir")
            if [ ! -d "$DEST_DIR/$THEME_BASENAME" ]; then
                echo "[$(date '+%H:%M:%S')] INFO: Installing $THEME_BASENAME to system..."
                cp -r "$dir" "$DEST_DIR/"
            fi
        fi
    done
    echo "[$(date '+%H:%M:%S')] OK: Local themes installed"
else
    echo "[$(date '+%H:%M:%S')] WARN: Directory 'grub-themes' not found"
fi

# --- Step 3: 主题配置 ---
echo "[$(date '+%H:%M:%S')] INFO: Step 3/4 - Theme Configuration"

GRUB_CONF="/etc/default/grub"

if [ -z "$GRUB_THEME" ] || [ "$GRUB_THEME" == "none" ]; then
    echo "[$(date '+%H:%M:%S')] INFO: No GRUB theme specified, clearing existing theme..."
    cleanup_minegrub
    
    if [ -f "$GRUB_CONF" ]; then
        if grep -q "^GRUB_THEME=" "$GRUB_CONF"; then
            sed -i 's|^GRUB_THEME=|#GRUB_THEME=|' "$GRUB_CONF"
            echo "[$(date '+%H:%M:%S')] OK: Disabled existing GRUB_THEME"
        fi
    fi
else
    cleanup_minegrub
    
    THEME_PATH="$DEST_DIR/$GRUB_THEME/theme.txt"
    
    if [ -f "$THEME_PATH" ]; then
        if [ -f "$GRUB_CONF" ]; then
            if grep -q "^GRUB_THEME=" "$GRUB_CONF"; then
                sed -i "s|^GRUB_THEME=.*|GRUB_THEME=\"$THEME_PATH\"|" "$GRUB_CONF"
            elif grep -q "^#GRUB_THEME=" "$GRUB_CONF"; then
                sed -i "s|^#GRUB_THEME=.*|GRUB_THEME=\"$THEME_PATH\"|" "$GRUB_CONF"
            else
                echo "GRUB_THEME=\"$THEME_PATH\"" >> "$GRUB_CONF"
            fi
            
            if grep -q "^GRUB_TERMINAL_OUTPUT=\"console\"" "$GRUB_CONF"; then
                sed -i 's/^GRUB_TERMINAL_OUTPUT="console"/#GRUB_TERMINAL_OUTPUT="console"/' "$GRUB_CONF"
            fi
            
            if ! grep -q "^GRUB_GFXMODE=" "$GRUB_CONF"; then
                echo 'GRUB_GFXMODE=auto' >> "$GRUB_CONF"
            fi
            echo "[$(date '+%H:%M:%S')] OK: Configured GRUB to use theme: $GRUB_THEME"
        else
            echo "[$(date '+%H:%M:%S')] ERROR: $GRUB_CONF not found"
            exit 1
        fi
    else
        echo "[$(date '+%H:%M:%S')] WARN: Theme $GRUB_THEME not found. Skipping theme configuration."
    fi
fi

# --- Step 4: 添加关机/重启菜单 ---
echo "[$(date '+%H:%M:%S')] INFO: Step 4/4 - Menu Entries"

cp /etc/grub.d/40_custom /etc/grub.d/99_custom
echo 'menuentry "Reboot" --class restart {reboot}' >> /etc/grub.d/99_custom
echo 'menuentry "Shutdown" --class shutdown {halt}' >> /etc/grub.d/99_custom

echo "[$(date '+%H:%M:%S')] OK: Added power options to GRUB menu"

# --- 应用更改 ---
echo "[$(date '+%H:%M:%S')] INFO: Applying changes..."
if grub-mkconfig -o /boot/grub/grub.cfg; then
    echo "[$(date '+%H:%M:%S')] OK: GRUB updated successfully"
else
    echo "[$(date '+%H:%M:%S')] ERROR: Failed to update GRUB"
    echo "[$(date '+%H:%M:%S')] WARN: You may need to run 'grub-mkconfig' manually"
fi

echo "[$(date '+%H:%M:%S')] INFO: Module 07 completed"
